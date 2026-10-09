<#
.SYNOPSIS
    Exports ARM templates for every resource in every resource group and uploads
    them to Azure Blob Storage.
.DESCRIPTION
    Can run either locally or as an Azure Automation runbook using Managed Identity.
#>

param(
    [string]$SubscriptionId,
    [string]$StorageAccountName,
    [string]$ContainerName     = "resourceexports",
    [string]$ResourceExportPath = "ResourceExports"
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }

# Authentication logic: Managed Identity in Automation, or existing Azure context
if ($env:AUTOMATION_VARIABLE_AZURE_SUBSCRIPTION_ID) {
    Connect-AzAccount -Identity | Out-Null
} elseif (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
}

Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not $StorageAccountName) {
    $StorageAccountName = Read-Host "Enter Target Storage Account Name for blob backup"
}

# Resolve storage account context
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName }
if (-not $storageAccount) {
    Write-Error "Storage account '$StorageAccountName' not found in subscription $SubscriptionId."
    exit 1
}

$storageContext = $storageAccount.Context

# Ensure container exists
$container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container) {
    New-AzStorageContainer -Name $ContainerName -Context $storageContext -Permission Off | Out-Null
    Write-Host "Created container: $ContainerName" -ForegroundColor Green
}

$baseOutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "ResourceExports_$(Get-Random)"
if (-not (Test-Path -Path $baseOutputDirectory)) {
    New-Item -ItemType Directory -Path $baseOutputDirectory -Force | Out-Null
}

$resourceGroups = Get-AzResourceGroup

foreach ($rg in $resourceGroups) {
    $resourceGroupName = $rg.ResourceGroupName
    $rgOutputDirectory = Join-Path -Path $baseOutputDirectory -ChildPath $resourceGroupName
    New-Item -ItemType Directory -Path $rgOutputDirectory -Force | Out-Null

    $resources = Get-AzResource -ResourceGroupName $resourceGroupName

    foreach ($resource in $resources) {
        $safeName = ($resource.Name -replace '[^a-zA-Z0-9_\-\.]', '_')
        $outputFile = Join-Path -Path $rgOutputDirectory -ChildPath "$safeName.json"

        try {
            Export-AzResourceGroup `
                -ResourceGroupName $resourceGroupName `
                -Resource $resource.ResourceId `
                -Path $outputFile -Force -ErrorAction Stop

            $blobPath = "$ResourceExportPath/$resourceGroupName/$safeName.json"

            Set-AzStorageBlobContent `
                -File $outputFile `
                -Container $ContainerName `
                -Blob $blobPath `
                -Context $storageContext `
                -Force | Out-Null

            Write-Host "  Uploaded $safeName to $blobPath" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to export or upload $($resource.Name): $_" -ForegroundColor Red
        }
    }
}

Remove-Item -Path $baseOutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "All resources exported and uploaded successfully to $StorageAccountName/$ContainerName" -ForegroundColor Green
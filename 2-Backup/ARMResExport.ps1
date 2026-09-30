<#
.SYNOPSIS
    Exports ARM templates for every individual resource in every resource group
    to a structured local directory, organised by Resource Group name.
.DESCRIPTION
    Skips resources already exported so the script is safe to rerun if interrupted.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$BaseOutputDirectory = (Join-Path $backupRootDir "ARMExports/Resources")
)

Write-Host "=== Exporting Individual ARM Resource Templates ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $BaseOutputDirectory)) {
    New-Item -ItemType Directory -Path $BaseOutputDirectory -Force | Out-Null
}

$resourceGroups = Get-AzResourceGroup -ErrorAction Stop

foreach ($rg in $resourceGroups) {
    $resourceGroupName = $rg.ResourceGroupName
    $rgOutputDirectory = Join-Path -Path $BaseOutputDirectory -ChildPath $resourceGroupName

    if (-not (Test-Path -Path $rgOutputDirectory)) {
        New-Item -ItemType Directory -Path $rgOutputDirectory -Force | Out-Null
    }

    $resources = Get-AzResource -ResourceGroupName $resourceGroupName

    foreach ($resource in $resources) {
        $safeName = ($resource.Name -replace '[^a-zA-Z0-9_\-\.]', '_')
        $outputFile = Join-Path -Path $rgOutputDirectory -ChildPath "$safeName.json"

        if (Test-Path -Path $outputFile) {
            Write-Host "  [SKIP] File already exists for $($resource.Name)" -ForegroundColor Gray
            continue
        }

        try {
            Export-AzResourceGroup `
                -ResourceGroupName $resourceGroupName `
                -Resource $resource.ResourceId `
                -Path $outputFile -Force -ErrorAction Stop

            Write-Host "  [EXPORT] $($resource.Name) -> $outputFile" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to export $($resource.Name): $_" -ForegroundColor Red
        }
    }
}

Write-Host "`nResource export complete. Output directory: $BaseOutputDirectory" -ForegroundColor Green

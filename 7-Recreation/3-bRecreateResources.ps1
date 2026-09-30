<#
.SYNOPSIS
    Deploys an ARM template to a Resource Group in the destination subscription.
.DESCRIPTION
    Used to recreate unmovable resources (e.g., WAF policies, network components)
    from ARM template files exported in Phase 2.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$TemplateFile,
    [string]$ParametersFile,
    [string]$DeploymentName = "RecreateResource_$(Get-Date -Format 'yyyyMMddHHmmss')"
)

Write-Host "=== Deploying ARM Resource Template ===" -ForegroundColor Cyan
Write-Host "Destination Subscription: $SubscriptionId"
Write-Host "Resource Group          : $ResourceGroupName"
Write-Host "Template File           : $TemplateFile"

Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $TemplateFile)) {
    Write-Error "Template file not found at: $TemplateFile"
    exit 1
}

$deployParams = @{
    Name              = $DeploymentName
    ResourceGroupName = $ResourceGroupName
    TemplateFile      = $TemplateFile
    Mode              = "Incremental"
}

if ($ParametersFile -and (Test-Path $ParametersFile)) {
    Write-Host "Using Parameters File: $ParametersFile" -ForegroundColor Cyan
    $deployParams["TemplateParameterFile"] = $ParametersFile
}

try {
    New-AzResourceGroupDeployment @deployParams -ErrorAction Stop | Out-Null
    Write-Host "✅ ARM Template deployment '$DeploymentName' completed successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ ARM Template deployment failed: $_" -ForegroundColor Red
    exit 1
}
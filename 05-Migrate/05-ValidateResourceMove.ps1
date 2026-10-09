<#
.SYNOPSIS
    Validates resource move readiness using the ARM validateMoveResources API.
.DESCRIPTION
    Validates either a specific list of resources or an entire Resource Group
    before moving resources across resource groups or subscriptions.
#>

param(
    [Parameter(Mandatory=$true)][string]$SourceResourceGroup,
    [string]$DestinationResourceGroup,
    [string]$TargetSubscriptionId,
    [string[]]$ResourceNames          = @()
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('DestinationResourceGroup')) { $DestinationResourceGroup = $SourceResourceGroup }
if (-not $PSBoundParameters.ContainsKey('TargetSubscriptionId')) { $TargetSubscriptionId = $destinationSubscriptionId }

Write-Host "=== Validating Resource Move ===" -ForegroundColor Cyan
Write-Host "Source RG: $SourceResourceGroup"
Write-Host "Target RG: $DestinationResourceGroup (Sub: $TargetSubscriptionId)"

Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null

$srcRG = Get-AzResourceGroup -Name $SourceResourceGroup -ErrorAction Stop

if ($ResourceNames.Count -gt 0) {
    $resources = Get-AzResource -ResourceGroupName $SourceResourceGroup | Where-Object { $_.Name -in $ResourceNames }
} else {
    $resources = Get-AzResource -ResourceGroupName $SourceResourceGroup
}

if (-not $resources -or $resources.Count -eq 0) {
    Write-Host "No resources found to validate." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($resources.Count) resource(s) to validate." -ForegroundColor Cyan

$destinationRGId = "/subscriptions/$TargetSubscriptionId/resourceGroups/$DestinationResourceGroup"

try {
    Write-Host "Invoking validateMoveResources (this may take 30-60 seconds)..." -ForegroundColor Cyan
    $result = Invoke-AzResourceAction `
        -Action "validateMoveResources" `
        -ResourceId $srcRG.ResourceId `
        -Parameters @{
            resources           = [string[]]$resources.ResourceId
            targetResourceGroup = $destinationRGId
        } `
        -Force `
        -ErrorAction Stop

    Write-Host "`n✅ Validation PASSED! Resources are ready to move." -ForegroundColor Green
} catch {
    Write-Host "`n❌ Validation FAILED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($_.ErrorDetails.Message) {
        Write-Host "`nARM Error Details:" -ForegroundColor Yellow
        try {
            $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $_.ErrorDetails.Message
        }
    }
    exit 1
}
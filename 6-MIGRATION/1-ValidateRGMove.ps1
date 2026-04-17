## DESCRIPTION: Validates whether all resources in a resource group can be moved to
##              the destination subscription. Uses the ARM validateMoveResources API.
##              Run this before executing the migration to surface blockers early.
## USAGE:       1. Set $resourceGroupName to the RG you want to validate.
##              2. Source and destination subscriptions are loaded from migration-params.ps1.
##              3. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

$resourceGroupName = "REPLACE_WITH_RG_NAME"

# ── Resolve destination RG (must exist in destination sub before move) ─────────
$destinationRGId = "/subscriptions/$destinationSubscriptionId/resourceGroups/$resourceGroupName"

Write-Host "=== RG Move Validation ===" -ForegroundColor Cyan
Write-Host "Source subscription : $sourceSubscriptionId"
Write-Host "Destination sub     : $destinationSubscriptionId"
Write-Host "Resource group      : $resourceGroupName"
Write-Host ""

try {
    Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "Context set to source subscription." -ForegroundColor Green

    $sourceRG = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
    $resources = Get-AzResource -ResourceGroupName $resourceGroupName -ErrorAction Stop

    if ($resources.Count -eq 0) {
        Write-Host "WARNING: No resources found in '$resourceGroupName'. Nothing to validate." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Found $($resources.Count) resource(s) to validate." -ForegroundColor Green

    Write-Host ""
    Write-Host "Calling validateMoveResources — this can take 15-30 seconds..." -ForegroundColor Cyan

    $result = Invoke-AzResourceAction `
        -Action "validateMoveResources" `
        -ResourceId $sourceRG.ResourceId `
        -Parameters @{
            resources           = $resources.ResourceId
            targetResourceGroup = $destinationRGId
        } `
        -Force `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "Validation PASSED — all resources can be moved." -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "Validation FAILED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    # Surface the inner ARM error detail if available
    if ($_.ErrorDetails.Message) {
        Write-Host ""
        Write-Host "ARM detail:" -ForegroundColor Yellow
        $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
    }

    exit 1
}

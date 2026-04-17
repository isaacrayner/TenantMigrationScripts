## DESCRIPTION: Moves all resources in a resource group from the source subscription
##              to the destination subscription (cross-tenant supported via separate
##              az login contexts). Uses the Azure CLI `az resource move` command so
##              errors surface directly in the terminal with full ARM detail.
## USAGE:       1. Set $resourceGroupName to the RG you want to move.
##              2. Run 1-ValidateRGMove.ps1 first and confirm it passes.
##              3. For cross-tenant moves: log in to both tenants before running
##                 (az login --tenant <sourceTenantId> / az login --tenant <destTenantId>).
##              4. Run in PowerShell with the Az module + Azure CLI installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

$resourceGroupName = "REPLACE_WITH_RG_NAME"

# ── Cross-tenant flag ──────────────────────────────────────────────────────────
# Set to $true when source and destination are in different Azure AD tenants.
# This instructs the move API to allow cross-tenant resource transfer.
$isCrossTenant = if ($destinationTenantId -and $destinationTenantId -ne $sourceTenantId) { $true } else { $false }

Write-Host "=== RG Migration ===" -ForegroundColor Cyan
Write-Host "Source subscription : $sourceSubscriptionId"
Write-Host "Destination sub     : $destinationSubscriptionId"
Write-Host "Resource group      : $resourceGroupName"
Write-Host "Cross-tenant move   : $isCrossTenant"
Write-Host ""

# ── Confirm before proceeding ──────────────────────────────────────────────────
$confirm = Read-Host "Type YES to proceed with the migration"
if ($confirm -ne "YES") {
    Write-Host "Migration cancelled." -ForegroundColor Yellow
    exit 0
}

try {
    # Set context to source to enumerate resources
    Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null

    $resources = Get-AzResource -ResourceGroupName $resourceGroupName -ErrorAction Stop

    if ($resources.Count -eq 0) {
        Write-Host "No resources found in '$resourceGroupName'. Exiting." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Moving $($resources.Count) resource(s)..." -ForegroundColor Cyan

    # Build space-separated list of resource IDs for the CLI
    $resourceIds = ($resources.ResourceId) -join " "

    $destinationRGId = "/subscriptions/$destinationSubscriptionId/resourceGroups/$resourceGroupName"

    # Ensure destination RG exists
    Write-Host "Ensuring destination resource group exists..." -ForegroundColor Cyan
    az group create `
        --name $resourceGroupName `
        --location $resources[0].Location `
        --subscription $destinationSubscriptionId `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create/confirm destination resource group." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    # Perform the move via Azure CLI (errors print directly to terminal)
    Write-Host ""
    Write-Host "Starting resource move — this may take several minutes..." -ForegroundColor Cyan

    if ($isCrossTenant) {
        az resource move `
            --ids $resourceIds `
            --destination-group $resourceGroupName `
            --destination-subscription-id $destinationSubscriptionId `
            --cross-tenant
    } else {
        az resource move `
            --ids $resourceIds `
            --destination-group $resourceGroupName `
            --destination-subscription-id $destinationSubscriptionId
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Resource move failed. See ARM error above." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host ""
    Write-Host "Migration COMPLETE — '$resourceGroupName' moved to subscription $destinationSubscriptionId." -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.ErrorDetails.Message) {
        Write-Host ""
        Write-Host "ARM detail:" -ForegroundColor Yellow
        $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
    }

    exit 1
}

<#
.SYNOPSIS
    Guides and executes the transfer of an Azure Subscription to a new Microsoft Entra ID Tenant.
.DESCRIPTION
    Use this script when performing a Tenant-to-Tenant migration by changing the
    directory of the subscription.
    CRITICAL WARNING:
    Transferring a subscription to a new tenant permanently deletes all RBAC role assignments,
    deletes all system-assigned managed identities, and requires updating Key Vault tenant IDs.
    Ensure the Phase 3 backups are 100% complete before running this script!
#>

param(
    [string]$SubscriptionId,
    [string]$TargetTenantId
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('TargetTenantId')) { $TargetTenantId = $destinationTenantId }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      AZURE SUBSCRIPTION TENANT DIRECTORY TRANSFER        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Subscription ID : $SubscriptionId" -ForegroundColor Yellow
Write-Host "Target Tenant ID: $TargetTenantId" -ForegroundColor Yellow

if (-not $TargetTenantId) {
    $TargetTenantId = Read-Host "Enter the Destination Microsoft Entra ID Tenant ID"
}

# Pre-transfer safety checklist
Write-Host "`nPRE-TRANSFER VERIFICATION CHECKLIST:" -ForegroundColor Yellow
Write-Host "1. Have you run 03-Backup/01-BackupResourceLocks.ps1? (Locks block transfer)"
Write-Host "2. Have you run 03-Backup/03-BackupRoleAssignments.ps1? (RBAC is wiped on transfer)"
Write-Host "3. Have you run 03-Backup/04-BackupManagedIdentities.ps1? (MIs are wiped on transfer)"
Write-Host "4. Have you run 03-Backup/11-BackupKeyVaultAccess.sh? (Key Vaults need tenant update)"
Write-Host "5. Does your account have Owner permissions in the target tenant?"

$confirm = Read-Host "`nType 'TRANSFER' to proceed with subscription directory change"
if ($confirm -ne "TRANSFER") {
    Write-Host "Directory transfer aborted." -ForegroundColor Green
    exit 0
}

Write-Host "`nExecuting tenant directory change..." -ForegroundColor Cyan

# Check if az CLI is available
if (Get-Command "az" -ErrorAction SilentlyContinue) {
    Write-Host "Invoking Azure CLI tenant-change..." -ForegroundColor Cyan
    & az account tenant-change --subscription $SubscriptionId --target-tenant $TargetTenantId

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Tenant directory change submitted successfully!" -ForegroundColor Green
        Write-Host "Wait 10-15 minutes for directory propagation, then re-authenticate to the destination tenant:" -ForegroundColor Cyan
        Write-Host "  az login --tenant $TargetTenantId" -ForegroundColor White
        Write-Host "  Connect-AzAccount -TenantId $TargetTenantId" -ForegroundColor White
        Write-Host "`nThen proceed directly to Phase 6 (06-Restore scripts)." -ForegroundColor Green
    } else {
        Write-Host "`n❌ Directory transfer command failed. Check error above or complete via Azure Portal:" -ForegroundColor Red
        Write-Host "Portal: Subscriptions -> $SubscriptionId -> 'Change directory'" -ForegroundColor Cyan
    }
} else {
    Write-Host "Azure CLI not found. Complete transfer via Azure Portal:" -ForegroundColor Yellow
    Write-Host "1. Open https://portal.azure.com"
    Write-Host "2. Go to Subscriptions -> $SubscriptionId"
    Write-Host "3. Click 'Change directory' in the toolbar and select Tenant $TargetTenantId"
}

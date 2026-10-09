<#
.SYNOPSIS
    Re-enables VM backup protection in the destination subscription from the CSV backup.
.DESCRIPTION
    Sets vault context and re-protects VMs under the specified backup policies.
#>

param(
    [string]$SubscriptionId,
    [string]$BackupConfigFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $destinationSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('BackupConfigFile')) { $BackupConfigFile = (Join-Path $backupRootDir "BackupSettings/VMBackupConfig.csv") }

Write-Host "=== Re-enabling VM Backup Protection ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $BackupConfigFile)) {
    Write-Host "Backup config file not found: $BackupConfigFile. Skipping." -ForegroundColor Yellow
    exit 0
}

$backupConfigs = Import-Csv -Path $BackupConfigFile

if (-not $backupConfigs -or $backupConfigs.Count -eq 0) {
    Write-Host "No backup configurations in file." -ForegroundColor Green
    exit 0
}

Write-Host "Processing $($backupConfigs.Count) VM backup configuration(s)..." -ForegroundColor Cyan

foreach ($config in $backupConfigs) {
    $vmName    = $config.VMName
    $rgName    = $config.ResourceGroupName
    $vaultName = $config.VaultName
    $policyName = $config.PolicyName

    Write-Host "Restoring backup for VM '$vmName' in Vault '$vaultName'..." -ForegroundColor Yellow

    # Get vault in destination subscription
    $vault = Get-AzRecoveryServicesVault -Name $vaultName -ErrorAction SilentlyContinue
    if (-not $vault) {
        Write-Host "  ⚠️ Vault '$vaultName' not found in destination subscription. Ensure vault is created or moved." -ForegroundColor Red
        continue
    }

    # Set vault context (required before calling backup cmdlets)
    Set-AzRecoveryServicesVaultContext -Vault $vault

    # Get policy
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy | Where-Object { $_.Name -eq $policyName }
    if (-not $policy) {
        Write-Host "  ⚠️ Backup Policy '$policyName' not found in vault '$vaultName'. Skipping." -ForegroundColor Red
        continue
    }

    try {
        Enable-AzRecoveryServicesBackupProtection `
            -ResourceGroupName $rgName `
            -Name $vmName `
            -Policy $policy `
            -ErrorAction Stop | Out-Null

        Write-Host "  ✅ Backup re-enabled for VM: $vmName" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Failed to re-enable backup for ${vmName}: $_" -ForegroundColor Red
    }
}

Write-Host "`nVM backup restoration complete." -ForegroundColor Green

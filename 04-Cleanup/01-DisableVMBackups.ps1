<#
.SYNOPSIS
    Stops VM backup protection (retaining all recovery points) and removes Instant
    Restore Point Collections prior to resource migration.
.DESCRIPTION
    Recovery points are kept in the vault. Instant Restore Point Collections block
    VM migration and must be deleted.
#>

param(
    [string]$SubscriptionId,
    [string]$BackupConfigFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('BackupConfigFile')) { $BackupConfigFile = (Join-Path $backupRootDir "BackupSettings/VMBackupConfig.csv") }

Write-Host "=== Disabling VM Backups & Cleaning Restore Point Collections ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $BackupConfigFile)) {
    Write-Host "Backup config file not found: $BackupConfigFile. Run 03-Backup/12-BackupVMBackupSettings.ps1 first." -ForegroundColor Yellow
    exit 0
}

$backupConfigs = Import-Csv -Path $BackupConfigFile

foreach ($config in $backupConfigs) {
    Write-Host "Checking backup for VM '$($config.VMName)' in Vault '$($config.VaultName)'..." -ForegroundColor Cyan

    $vault = Get-AzRecoveryServicesVault -Name $config.VaultName -ResourceGroupName $config.VaultResourceGroup -ErrorAction SilentlyContinue
    if (-not $vault) {
        $vault = Get-AzRecoveryServicesVault -Name $config.VaultName -ErrorAction SilentlyContinue
    }

    if (-not $vault) {
        Write-Host "  ⚠️ Vault '$($config.VaultName)' not found. Skipping." -ForegroundColor Yellow
        continue
    }

    Set-AzRecoveryServicesVaultContext -Vault $vault

    $container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType "AzureVM" | Where-Object { $_.FriendlyName -eq $config.VMName }

    if (-not $container) {
        Write-Host "  No active container for VM: $($config.VMName)" -ForegroundColor Gray
        continue
    }

    $backupItems = Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -Container $container -WorkloadType "AzureVM"
    $vmBackupItem = $backupItems | Where-Object { $_.SourceResourceId -eq $config.ResourceId }

    if ($vmBackupItem) {
        Write-Host "  Stopping backup protection (retaining recovery points) for: $($config.VMName)..." -ForegroundColor Yellow
        Disable-AzRecoveryServicesBackupProtection -Item $vmBackupItem -RetainRecoveryData -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✅ Backup stopped (data retained) for: $($config.VMName)" -ForegroundColor Green
    }
}

Write-Host "`n=== Cleaning Instant Restore Point Collections ===" -ForegroundColor Cyan
$restorePointCollections = Get-AzResource -ResourceType "Microsoft.Compute/restorePointCollections" -ErrorAction SilentlyContinue

if ($restorePointCollections -and $restorePointCollections.Count -gt 0) {
    Write-Host "Found $($restorePointCollections.Count) Restore Point Collection(s) to remove..." -ForegroundColor Yellow
    foreach ($collection in $restorePointCollections) {
        Write-Host "  Deleting RPC: $($collection.Name)..." -ForegroundColor Cyan
        Remove-AzResource -ResourceId $collection.ResourceId -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✅ Deleted: $($collection.Name)" -ForegroundColor Green
    }
} else {
    Write-Host "No Instant Restore Point Collections found." -ForegroundColor Green
}

Write-Host "`nBackup disable and cleanup completed successfully." -ForegroundColor Green

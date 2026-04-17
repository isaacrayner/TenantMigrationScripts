## DESCRIPTION: Restores VM backup protection in the destination subscription using the backup
##              configuration CSV produced by 13-BackupVMBackupSettings.ps1.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Ensure C:\temp\AzureBackupSettingsBackup\BackupConfig.csv exists.
##              3. Ensure Recovery Services Vaults and backup policies exist in the destination.
##              4. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

##### Restore the Backup Policy on all VMs (from backup restore file) #####

# Set Subscription (loaded from migration-params.ps1)
$subscriptionId = $destinationSubscriptionId
Set-AzContext -SubscriptionId $subscriptionId

# Load backup configuration
$backupConfigFile = "C:\temp\AzureBackupSettingsBackup\BackupConfig.csv"
$backupConfigs = Import-Csv -Path $backupConfigFile

foreach ($config in $backupConfigs) {
    Write-Host "🔄 Restoring backup for VM: $($config.VMName)"

    # Get the vault in the new subscription
    $vault = Get-AzRecoveryServicesVault -Name $config.VaultName

    # Get the backup policy in the new vault
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.ID | Where-Object { $_.Name -eq $config.PolicyName }

    if (-not $policy) {
        Write-Host "⚠ WARNING: Policy not found for VM: $($config.VMName). Skipping..."
        continue
    }

    # Re-enable backup using FullBackupName (to match Azure Backup exactly)
    Enable-AzRecoveryServicesBackupProtection -VaultId $vault.ID -Policy $policy -Name $config.FullBackupName -ResourceType "AzureVM"

    Write-Host "✅ Backup re-enabled for: $($config.VMName)"
}

Write-Host "🔹 Backup configuration restored successfully."

## DESCRIPTION: Backs up VM backup configurations (vault name, policy name, VM name) from all
##              Recovery Services Vaults to a CSV file. Used by the disable and restore scripts.
##              NOTE: Remove soft delete on Recovery Services Vaults before running.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Update $backupFolder to your desired output directory.
##              3. Run in PowerShell with the Az module installed.
##              4. Output CSV is used by 5-DisableBackups.ps1 and 8-VMBackups.ps1.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

##### Create the backup of backups :-) #####
##### remember to REMOVE SOFT DELETE ON THE RECOVERY SERVICES VAULTS #####

# Set Subscription (loaded from migration-params.ps1)
$subscriptionId = $sourceSubscriptionId
Set-AzContext -SubscriptionId $subscriptionId

# Set output file
$backupFolder = "C:\temp\AzureBackupSettingsBackup"
$backupConfigFile = "$backupFolder\BackupConfig.csv"
$errorLogFile = "$backupFolder\BackupErrorLog.txt"

# Ensure the directory exists
if (!(Test-Path -Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

# Clear error log file
"" | Set-Content -Path $errorLogFile

$backupConfigs = @()

# Get all Recovery Services Vaults
$vaults = Get-AzRecoveryServicesVault

foreach ($vault in $vaults) {
    Write-Output "Checking Recovery Services Vault: $($vault.Name)"

    # Get all backup containers
    try {
        $containers = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType "AzureVM"
    } catch {
        Write-Output "❌ ERROR: Could not get backup containers for vault: $($vault.Name) - $_" | Out-File -Append -FilePath $errorLogFile
        continue
    }

    if (-not $containers -or $containers.Count -eq 0) {
        Write-Output "⚠ No backup containers found in vault: $($vault.Name). Skipping..."
        continue
    }

    # Get all VMs protected in this vault
    $protectedVMs = @()
    foreach ($container in $containers) {
        try {
            $protectedVMs += Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -Container $container -WorkloadType "AzureVM"
        } catch {
            Write-Output "❌ ERROR: Could not get backup items for vault: $($vault.Name) - $_" | Out-File -Append -FilePath $errorLogFile
        }
    }

    if (-not $protectedVMs -or $protectedVMs.Count -eq 0) {
        Write-Output "⚠ No protected VMs found in vault: $($vault.Name). Skipping..."
        continue
    }

    foreach ($vm in $protectedVMs) {
        try {
            # Ensure VM name is valid
            if (-not $vm.Name) {
                Write-Output "❌ ERROR: VM Name is missing for an entry in vault: $($vault.Name). Skipping..." | Out-File -Append -FilePath $errorLogFile
                continue
            }

            # Store both the full backup name and the clean VM name
            $fullBackupName = $vm.Name
            $cleanVmName = ($vm.Name -split ";")[-1]

            Write-Output "Saving backup configuration for VM: $cleanVmName"

            # Ensure the VM has a policy before looking it up
            if (-not $vm.PolicyId) {
                Write-Output "⚠ WARNING: VM $cleanVmName has no associated policy. Skipping..."
                continue
            }

            # Find the exact backup policy using PolicyId
            $policy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.ID | Where-Object { $_.ID -eq $vm.PolicyId }

            if (-not $policy) {
                Write-Output "⚠ WARNING: Could not find matching backup policy for VM: $cleanVmName. Skipping..."
                continue
            }

            # Store backup details
            $backupConfigs += [PSCustomObject]@{
                VMName            = $cleanVmName
                FullBackupName    = $fullBackupName
                ResourceId        = $vm.SourceResourceId
                VaultName         = $vault.Name
                VaultId           = $vault.ID
                PolicyName        = $policy.Name
                PolicyId          = $policy.ID
            }

        } catch {
            Write-Output "❌ ERROR: Issue processing VM $cleanVmName - $_" | Out-File -Append -FilePath $errorLogFile
        }
    }
}

# Export backup configuration to CSV
try {
    if ($backupConfigs.Count -gt 0) {
        $backupConfigs | Export-Csv -Path $backupConfigFile -NoTypeInformation
        Write-Output "✅ Backup configuration saved to: $backupConfigFile"
    } else {
        Write-Output "⚠ No backup configurations were found. Nothing saved."
    }
} catch {
    Write-Output "❌ ERROR: Could not save CSV file - $_" | Out-File -Append -FilePath $errorLogFile
}

Write-Output "🔹 Backup details collected. You can now review before disabling backup."

# Show any errors captured in the log
if ((Test-Path $errorLogFile) -and ((Get-Content -Path $errorLogFile | Measure-Object -Line).Lines -gt 0)) {
    Write-Output "⚠ Some errors occurred. Check the log file at: $errorLogFile"
}



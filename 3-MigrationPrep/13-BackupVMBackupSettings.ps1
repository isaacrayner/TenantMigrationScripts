<#
.SYNOPSIS
    Backs up Azure VM backup configurations across all Recovery Services Vaults.
.DESCRIPTION
    Exports VM Name, ResourceId, ResourceGroup, VaultName, and PolicyName to CSV/JSON.
    Used by 4-Deletions/5-DisableBackups.ps1 and 7-Recreation/8-VMBackups.ps1.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$BackupFolder   = (Join-Path $backupRootDir "BackupSettings")
)

Write-Host "=== Backing up Azure VM Backup Configurations ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $BackupFolder)) {
    New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
}

$backupConfigFile = Join-Path $BackupFolder "VMBackupConfig.csv"
$errorLogFile     = Join-Path $logRootDir "VMBackupErrorLog.txt"

$vaults = Get-AzRecoveryServicesVault -ErrorAction Stop
if (-not $vaults -or $vaults.Count -eq 0) {
    Write-Host "No Recovery Services Vaults found in subscription." -ForegroundColor Green
    exit 0
}

$backupConfigs = @()

foreach ($vault in $vaults) {
    Write-Host "Checking Vault: $($vault.Name) (RG: $($vault.ResourceGroupName))..." -ForegroundColor Cyan
    Set-AzRecoveryServicesVaultContext -Vault $vault -ErrorAction Stop | Out-Null

    try {
        $containers = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType "AzureVM" -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  ❌ Failed to get backup containers for $($vault.Name): $_" -ForegroundColor Red
        continue
    }

    if (-not $containers -or $containers.Count -eq 0) {
        Write-Host "  No VM backup containers in vault $($vault.Name)." -ForegroundColor Gray
        continue
    }

    $protectedVMs = @()
    foreach ($container in $containers) {
        try {
            $protectedVMs += Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -Container $container -WorkloadType "AzureVM" -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  ❌ Error retrieving backup items: $_" -ForegroundColor Red
        }
    }

    foreach ($vm in $protectedVMs) {
        $cleanVmName = ($vm.Name -split ";")[-1]
        $vmRg = ($vm.SourceResourceId -split "/")[4]

        # Get policy name
        $policyName = "DefaultPolicy"
        if ($vm.PolicyId) {
            $policy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.ID | Where-Object { $_.ID -eq $vm.PolicyId }
            if ($policy) { $policyName = $policy.Name }
        }

        Write-Host "  Saving backup configuration for VM: $cleanVmName (Policy: $policyName)" -ForegroundColor Green

        $backupConfigs += [PSCustomObject]@{
            VMName            = $cleanVmName
            FullBackupName    = $vm.Name
            ResourceId        = $vm.SourceResourceId
            ResourceGroupName = $vmRg
            VaultName         = $vault.Name
            VaultResourceGroup= $vault.ResourceGroupName
            VaultId           = $vault.ID
            PolicyName        = $policyName
            PolicyId          = $vm.PolicyId
        }
    }
}

if ($backupConfigs.Count -gt 0) {
    $backupConfigs | Export-Csv -Path $backupConfigFile -NoTypeInformation -Encoding utf8
    $jsonFile = $backupConfigFile -replace "\.csv$", ".json"
    $backupConfigs | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonFile -Encoding utf8
    Write-Host "`n✅ VM Backup configurations saved to: $backupConfigFile" -ForegroundColor Green
} else {
    Write-Host "`nNo protected VMs found across any vaults." -ForegroundColor Yellow
}

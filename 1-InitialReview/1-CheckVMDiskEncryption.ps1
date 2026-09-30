<#
.SYNOPSIS
    Queries and audits Virtual Machines and Disks for Azure Disk Encryption (ADE)
    and Customer-Managed Keys (CMK) which block subscription/tenant migration.
.DESCRIPTION
    BitLocker/ADE must be disabled and decrypted before cross-subscription or cross-tenant moves.
    Disks using Disk Encryption Sets (DES) must have target vault permissions.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId
)

Write-Host "=== Auditing VM & Disk Encryption Status ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId | Out-Null

$outputReport = Join-Path $backupRootDir "DiskEncryption_Audit.json"

Write-Host "Checking for Azure Resource Graph module..." -ForegroundColor Gray
$hasArg = Get-Module -ListAvailable -Name "Az.ResourceGraph"

$vmEncryptionResults = @()
$diskEncryptionResults = @()

if ($hasArg) {
    Write-Host "Running Resource Graph query on VMs..." -ForegroundColor Cyan
    $vmQuery = @"
Resources
| where type == "microsoft.compute/virtualmachines"
| extend osDisk = properties.storageProfile.osDisk
| project name, resourceGroup, location, osType = tostring(osDisk.osType),
          diskEncryptionSetId = tostring(osDisk.managedDisk.diskEncryptionSet.id),
          encryptionSettings = osDisk.encryptionSettingsCollection,
          securityProfile = properties.securityProfile
"@
    $vmEncryptionResults = (Search-AzGraph -Query $vmQuery -Subscription $SubscriptionId).data

    Write-Host "Running Resource Graph query on Disks..." -ForegroundColor Cyan
    $diskQuery = @"
Resources
| where type == "microsoft.compute/disks"
| project name, resourceGroup, location, encryptionType = tostring(properties.encryption.type),
          diskEncryptionSetId = tostring(properties.encryptionSettingsCollection.encryptionSettings)
"@
    $diskEncryptionResults = (Search-AzGraph -Query $diskQuery -Subscription $SubscriptionId).data
} else {
    Write-Host "Resource Graph not available; querying VMs via Az.Compute..." -ForegroundColor Yellow
    $vms = Get-AzVM
    foreach ($vm in $vms) {
        $vmEncryptionResults += [PSCustomObject]@{
            name                = $vm.Name
            resourceGroup       = $vm.ResourceGroupName
            location            = $vm.Location
            osType              = $vm.StorageProfile.OsDisk.OsType
            diskEncryptionSetId = $vm.StorageProfile.OsDisk.ManagedDisk.DiskEncryptionSet.Id
            encryptionSettings  = $vm.StorageProfile.OsDisk.EncryptionSettings
        }
    }
}

$blockers = @()

foreach ($vm in $vmEncryptionResults) {
    $hasAde = $null -ne $vm.encryptionSettings -and $vm.encryptionSettings.enabled -eq $true
    $hasDes = [string]::IsNullOrEmpty($vm.diskEncryptionSetId) -eq $false

    if ($hasAde) {
        $blockers += [PSCustomObject]@{
            Resource = $vm.name
            Type     = "VirtualMachine"
            RG       = $vm.resourceGroup
            Issue    = "Azure Disk Encryption (ADE/BitLocker) enabled - MUST be disabled before move"
            Severity = "BLOCKER"
        }
    }

    if ($hasDes) {
        $blockers += [PSCustomObject]@{
            Resource = $vm.name
            Type     = "VirtualMachine"
            RG       = $vm.resourceGroup
            Issue    = "Uses Customer-Managed Key (DiskEncryptionSet) - Key Vault permissions must exist in target"
            Severity = "WARNING"
        }
    }
}

$report = @{
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    SubscriptionId = $SubscriptionId
    VMCount = $vmEncryptionResults.Count
    DiskCount = $diskEncryptionResults.Count
    Blockers = $blockers
    VMDetails = $vmEncryptionResults
}

$report | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputReport -Encoding utf8
Write-Host "Audit report saved to: $outputReport" -ForegroundColor Green

if ($blockers.Count -gt 0) {
    Write-Host "`n⚠️ ENCRYPTION BLOCKERS / WARNINGS DETECTED (${blockers.Count}):" -ForegroundColor Red
    $blockers | Format-Table -AutoSize
} else {
    Write-Host "`n✅ No ADE/BitLocker blockers detected on VMs." -ForegroundColor Green
}

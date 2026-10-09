<#
.SYNOPSIS
    Comprehensive Pre-Migration Readiness and Blocker Assessment.
.DESCRIPTION
    Scans the source subscription for all known Azure Resource Manager (ARM)
    migration blockers before initiating migration tasks.
#>

param(
    [string]$SubscriptionId
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   AZURE TENANT/SUBSCRIPTION MIGRATION BLOCKER SCANNER    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Source Subscription: $SubscriptionId" -ForegroundColor Yellow

Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

$scanReportPath = Join-Path $backupRootDir "PreMigration_Blocker_Report.json"
$blockers = @()
$warnings = @()

# 1. Check Resource Locks
Write-Host "[1/8] Checking for Resource Locks..." -ForegroundColor Cyan
$locks = Get-AzResourceLock -ErrorAction SilentlyContinue
if ($locks -and $locks.Count -gt 0) {
    foreach ($lock in $locks) {
        $blockers += [PSCustomObject]@{
            Category = "Resource Lock"
            Resource = $lock.Name
            Scope    = $lock.ResourceId
            Level    = $lock.LockLevel
            Action   = "Resource Lock MUST be removed before moving resources or deleting dependencies."
        }
    }
    Write-Host "  Found $($locks.Count) lock(s) - BLOCKER" -ForegroundColor Red
} else {
    Write-Host "  No resource locks found. (PASS)" -ForegroundColor Green
}

# 2. Check VNet Peerings
Write-Host "[2/8] Checking for Virtual Network Peerings..." -ForegroundColor Cyan
$vnets = Get-AzVirtualNetwork -ErrorAction SilentlyContinue
$peeringCount = 0
foreach ($vnet in $vnets) {
    if ($vnet.VirtualNetworkPeerings -and $vnet.VirtualNetworkPeerings.Count -gt 0) {
        foreach ($p in $vnet.VirtualNetworkPeerings) {
            $peeringCount++
            $blockers += [PSCustomObject]@{
                Category = "VNet Peering"
                Resource = "$($vnet.Name)::$($p.Name)"
                Scope    = $vnet.Id
                Level    = "High"
                Action   = "VNet peering must be deleted before subscription transfer and recreated after."
            }
        }
    }
}
if ($peeringCount -gt 0) {
    Write-Host "  Found $peeringCount peering(s) - BLOCKER" -ForegroundColor Red
} else {
    Write-Host "  No VNet peerings found. (PASS)" -ForegroundColor Green
}

# 3. Check Private Endpoints
Write-Host "[3/8] Checking for Private Endpoints..." -ForegroundColor Cyan
$pes = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue
if ($pes -and $pes.Count -gt 0) {
    foreach ($pe in $pes) {
        $blockers += [PSCustomObject]@{
            Category = "Private Endpoint"
            Resource = $pe.Name
            Scope    = $pe.Id
            Level    = "High"
            Action   = "Private Endpoint cannot move across subscriptions. Must be backed up, deleted, and recreated."
        }
    }
    Write-Host "  Found $($pes.Count) Private Endpoint(s) - BLOCKER" -ForegroundColor Red
} else {
    Write-Host "  No Private Endpoints found. (PASS)" -ForegroundColor Green
}

# 4. Check System-Assigned Managed Identities
Write-Host "[4/8] Checking for System-Assigned Managed Identities..." -ForegroundColor Cyan
$allResources = Get-AzResource -ExpandProperties -ErrorAction SilentlyContinue
$miCount = 0
foreach ($r in $allResources) {
    if ($r.Identity -and $r.Identity.Type -match "SystemAssigned") {
        $miCount++
        $warnings += [PSCustomObject]@{
            Category = "System Managed Identity"
            Resource = $r.Name
            Scope    = $r.ResourceId
            Level    = "Medium"
            Action   = "System-assigned MI will be deleted on move/tenant-change. Must record role assignments and recreate post-move."
        }
    }
}
if ($miCount -gt 0) {
    Write-Host "  Found $miCount resource(s) with System-Assigned Managed Identities - ACTION REQUIRED" -ForegroundColor Yellow
} else {
    Write-Host "  No System-Assigned Managed Identities found. (PASS)" -ForegroundColor Green
}

# 5. Check Backup & Instant Restore Points
Write-Host "[5/8] Checking for Backup Vaults and Instant Restore Point Collections..." -ForegroundColor Cyan
$rsvs = Get-AzRecoveryServicesVault -ErrorAction SilentlyContinue
$rsvCount = if ($rsvs) { $rsvs.Count } else { 0 }
$rpcs = Get-AzResource -ResourceType "Microsoft.Compute/restorePointCollections" -ErrorAction SilentlyContinue
$rpcCount = if ($rpcs) { $rpcs.Count } else { 0 }
if ($rpcCount -gt 0) {
    foreach ($rpc in $rpcs) {
        $blockers += [PSCustomObject]@{
            Category = "Restore Point Collection"
            Resource = $rpc.Name
            Scope    = $rpc.ResourceId
            Level    = "High"
            Action   = "Instant Restore Point Collections block VM move and must be deleted."
        }
    }
    Write-Host "  Found $rpcCount restorePointCollection(s) - BLOCKER" -ForegroundColor Red
} else {
    Write-Host "  No restorePointCollections found. (PASS)" -ForegroundColor Green
}
if ($rsvCount -gt 0) {
    $warnings += [PSCustomObject]@{
        Category = "Recovery Services Vault"
        Resource = "$rsvCount vault(s) present"
        Scope    = "Subscription"
        Level    = "Medium"
        Action   = "RSVs require stopping protection (retain data) and manual migration or recreation in destination."
    }
    Write-Host "  Found $rsvCount Recovery Services Vault(s) - ACTION REQUIRED" -ForegroundColor Yellow
}

# 6. Check App Service SSL Bindings & Certificates
Write-Host "[6/8] Checking for App Services with Custom Domains / SSL Bindings..." -ForegroundColor Cyan
$webApps = Get-AzWebApp -ErrorAction SilentlyContinue
$certCount = 0
foreach ($app in $webApps) {
    if ($app.HostNameSslStates -and ($app.HostNameSslStates | Where-Object { $_.SslState -ne "Disabled" })) {
        $certCount++
        $warnings += [PSCustomObject]@{
            Category = "App Service SSL Binding"
            Resource = $app.Name
            Scope    = $app.Id
            Level    = "Medium"
            Action   = "Custom domain SSL bindings and App Service Managed Certificates must be unbinded/deleted before move."
        }
    }
}
if ($certCount -gt 0) {
    Write-Host "  Found $certCount App Service(s) with active SSL bindings - ACTION REQUIRED" -ForegroundColor Yellow
} else {
    Write-Host "  No active App Service SSL bindings detected. (PASS)" -ForegroundColor Green
}

# 7. Check Public IP SKUs
Write-Host "[7/8] Checking Public IP Addresses..." -ForegroundColor Cyan
$pips = Get-AzPublicIpAddress -ErrorAction SilentlyContinue
$basicPipCount = 0
if ($pips) {
    foreach ($pip in $pips) {
        if ($pip.Sku.Name -eq "Basic") {
            $basicPipCount++
            $warnings += [PSCustomObject]@{
                Category = "Basic Public IP"
                Resource = $pip.Name
                Scope    = $pip.Id
                Level    = "Medium"
                Action   = "Basic SKU Public IPs should be upgraded to Standard SKU before move or recreated."
            }
        }
    }
}
if ($basicPipCount -gt 0) {
    Write-Host "  Found $basicPipCount Basic SKU Public IP(s) - UPGRADE RECOMMENDED" -ForegroundColor Yellow
} else {
    Write-Host "  Public IP SKUs checked. (PASS)" -ForegroundColor Green
}

# 8. Check Disk Encryption
Write-Host "[8/8] Checking VM Disk Encryption..." -ForegroundColor Cyan
$vms = Get-AzVM -ErrorAction SilentlyContinue
$adeCount = 0
if ($vms) {
    foreach ($vm in $vms) {
        if ($vm.StorageProfile.OsDisk.EncryptionSettings -and $vm.StorageProfile.OsDisk.EncryptionSettings.Enabled) {
            $adeCount++
            $blockers += [PSCustomObject]@{
                Category = "Azure Disk Encryption"
                Resource = $vm.Name
                Scope    = $vm.Id
                Level    = "High"
                Action   = "BitLocker / ADE must be disabled and decrypted before moving VMs."
            }
        }
    }
}
if ($adeCount -gt 0) {
    Write-Host "  Found $adeCount VM(s) with ADE/BitLocker enabled - BLOCKER" -ForegroundColor Red
} else {
    Write-Host "  No ADE/BitLocker detected on VMs. (PASS)" -ForegroundColor Green
}

# Summary Report
$fullReport = @{
    Timestamp      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    SubscriptionId = $SubscriptionId
    TotalBlockers  = $blockers.Count
    TotalWarnings  = $warnings.Count
    Blockers       = $blockers
    Warnings       = $warnings
}

$fullReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $scanReportPath -Encoding utf8

Write-Host "`n================== SCAN SUMMARY ==================" -ForegroundColor Cyan
Write-Host "Total Hard Blockers : $($blockers.Count)" -ForegroundColor $(if ($blockers.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Total Warnings      : $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "Full Report Saved To: $scanReportPath" -ForegroundColor Cyan

if ($blockers.Count -gt 0) {
    Write-Host "`nCRITICAL BLOCKERS DETECTED:" -ForegroundColor Red
    $blockers | Format-Table Category, Resource, Action -AutoSize
}

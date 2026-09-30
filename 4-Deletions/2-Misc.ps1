<#
.SYNOPSIS
    Cleans up miscellaneous resources that block subscription or tenant migration.
.DESCRIPTION
    Sections can be executed selectively via parameters:
    - Snapshots: Disk snapshots block VM moves.
    - NatGateways: Must be disassociated from subnets before deletion.
    - VpnGateways: Virtual Network Gateways and connections.
    - AppGateways: Application Gateways (ensure backup was run first).
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [switch]$Snapshots,
    [switch]$NatGateways,
    [switch]$VpnGateways,
    [switch]$AppGateways,
    [switch]$All
)

Write-Host "=== Miscellaneous Migration Deletions & Cleanups ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not ($Snapshots -or $NatGateways -or $VpnGateways -or $AppGateways -or $All)) {
    Write-Host "No cleanup flags specified." -ForegroundColor Yellow
    Write-Host "Usage: .\2-Misc.ps1 -Snapshots [-NatGateways] [-VpnGateways] [-AppGateways] [-All]" -ForegroundColor Cyan
    $prompt = Read-Host "Choose what to clean up: [1] Snapshots [2] NAT Gateways [3] VPN Gateways [4] App Gateways [5] All"
    switch ($prompt) {
        "1" { $Snapshots = $true }
        "2" { $NatGateways = $true }
        "3" { $VpnGateways = $true }
        "4" { $AppGateways = $true }
        "5" { $All = $true }
        Default { Write-Host "Cancelled."; exit 0 }
    }
}

# 1. Snapshots
if ($Snapshots -or $All) {
    Write-Host "`n--- Cleaning Disk Snapshots ---" -ForegroundColor Cyan
    $snapshots = Get-AzSnapshot -ErrorAction SilentlyContinue
    if (-not $snapshots -or $snapshots.Count -eq 0) {
        Write-Host "No disk snapshots found." -ForegroundColor Green
    } else {
        foreach ($snap in $snapshots) {
            Write-Host "Deleting Snapshot '$($snap.Name)' in RG '$($snap.ResourceGroupName)'..." -ForegroundColor Yellow
            Remove-AzSnapshot -ResourceGroupName $snap.ResourceGroupName -SnapshotName $snap.Name -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  ✅ Deleted: $($snap.Name)" -ForegroundColor Green
        }
    }
}

# 2. NAT Gateways
if ($NatGateways -or $All) {
    Write-Host "`n--- Cleaning NAT Gateways ---" -ForegroundColor Cyan
    # First disassociate from any subnets
    $subnetsWithNat = Get-AzVirtualNetwork | ForEach-Object { $_.Subnets } | Where-Object { $_.NatGateway -ne $null }
    foreach ($subnet in $subnetsWithNat) {
        Write-Host "Disassociating NAT Gateway from subnet: $($subnet.Name)..." -ForegroundColor Yellow
        $vnet = Get-AzVirtualNetwork -ResourceGroupName ($subnet.Id -split "/")[4] -Name ($subnet.Id -split "/")[8]
        $subObj = $vnet.Subnets | Where-Object { $_.Name -eq $subnet.Name }
        $subObj.NatGateway = $null
        $vnet | Set-AzVirtualNetwork -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✅ Disassociated NAT Gateway from $($subnet.Name)" -ForegroundColor Green
    }

    $natGateways = Get-AzNatGateway -ErrorAction SilentlyContinue
    foreach ($nat in $natGateways) {
        Write-Host "Deleting NAT Gateway '$($nat.Name)' in RG '$($nat.ResourceGroupName)'..." -ForegroundColor Yellow
        Remove-AzNatGateway -ResourceGroupName $nat.ResourceGroupName -NatGatewayName $nat.Name -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✅ Deleted: $($nat.Name)" -ForegroundColor Green
    }
}

# 3. VPN Gateways
if ($VpnGateways -or $All) {
    Write-Host "`n--- Cleaning VPN Gateway Connections & Gateways ---" -ForegroundColor Cyan
    $connections = Get-AzVirtualNetworkGatewayConnection -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        Write-Host "Deleting VPN Connection '$($conn.Name)' in RG '$($conn.ResourceGroupName)'..." -ForegroundColor Yellow
        Remove-AzVirtualNetworkGatewayConnection -ResourceGroupName $conn.ResourceGroupName -Name $conn.Name -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✅ Deleted Connection: $($conn.Name)" -ForegroundColor Green
    }

    $vnetGateways = Get-AzVirtualNetworkGateway -ErrorAction SilentlyContinue
    foreach ($gw in $vnetGateways) {
        Write-Host "Deleting Virtual Network Gateway '$($gw.Name)' in RG '$($gw.ResourceGroupName)'..." -ForegroundColor Yellow
        Remove-AzVirtualNetworkGateway -ResourceGroupName $gw.ResourceGroupName -Name $gw.Name -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✅ Deleted Gateway: $($gw.Name)" -ForegroundColor Green
    }
}

# 4. Application Gateways
if ($AppGateways -or $All) {
    Write-Host "`n--- Cleaning Application Gateways ---" -ForegroundColor Cyan
    $appGateways = Get-AzApplicationGateway -ErrorAction SilentlyContinue
    foreach ($appGw in $appGateways) {
        Write-Host "Deleting Application Gateway '$($appGw.Name)' in RG '$($appGw.ResourceGroupName)'..." -ForegroundColor Yellow
        Remove-AzApplicationGateway -ResourceGroupName $appGw.ResourceGroupName -Name $appGw.Name -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✅ Deleted App Gateway: $($appGw.Name)" -ForegroundColor Green
    }
}

Write-Host "`nSelected cleanup operations completed." -ForegroundColor Green

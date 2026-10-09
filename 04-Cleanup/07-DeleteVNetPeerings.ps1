<#
.SYNOPSIS
    Removes all Virtual Network Peerings in the source subscription.
.DESCRIPTION
    VNet peerings block subscription transfers and cross-subscription resource moves.
    Run this after backing up peerings via 03-Backup/16-BackupVNetPeerings.ps1.
#>

param(
    [string]$SubscriptionId
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }

Write-Host "=== Deleting Virtual Network Peerings in Source Subscription ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

$vNets = Get-AzVirtualNetwork -ErrorAction Stop
$deletedCount = 0

foreach ($vNet in $vNets) {
    if (-not $vNet.VirtualNetworkPeerings -or $vNet.VirtualNetworkPeerings.Count -eq 0) { continue }

    foreach ($peering in $vNet.VirtualNetworkPeerings) {
        Write-Host "Deleting Peering: '$($peering.Name)' on VNet '$($vNet.Name)' (RG: $($vNet.ResourceGroupName))..." -ForegroundColor Yellow
        try {
            Remove-AzVirtualNetworkPeering -VirtualNetworkName $vNet.Name -ResourceGroupName $vNet.ResourceGroupName -Name $peering.Name -Force -ErrorAction Stop
            Write-Host "  ✅ Deleted Peering: $($peering.Name)" -ForegroundColor Green
            $deletedCount++
        } catch {
            Write-Host "  ❌ Failed to delete Peering '$($peering.Name)': $_" -ForegroundColor Red
        }
    }
}

Write-Host "`nAll VNet peerings processed. Total deleted: $deletedCount" -ForegroundColor Green
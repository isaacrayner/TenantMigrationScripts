<#
.SYNOPSIS
    Exports all Virtual Network Peering configurations across the source subscription.
.DESCRIPTION
    Captures LocalVNet, LocalResourceGroup, PeeringName, RemoteVNetId, AllowVnetAccess,
    AllowForwardedTraffic, AllowGatewayTransit, and UseRemoteGateways.
    Saves to migration-data/VNETs/NetPeeringsBackup.csv and .json.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$OutputDir      = (Join-Path $backupRootDir "VNETs")
)

Write-Host "=== Backing up Virtual Network Peerings ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$vNets = Get-AzVirtualNetwork -ErrorAction Stop
$peeringList = @()

foreach ($vNet in $vNets) {
    if (-not $vNet.VirtualNetworkPeerings) { continue }

    foreach ($peering in $vNet.VirtualNetworkPeerings) {
        $peeringList += [PSCustomObject]@{
            LocalVNetName         = $vNet.Name
            LocalResourceGroup    = $vNet.ResourceGroupName
            PeeringName           = $peering.Name
            RemoteVNetId          = $peering.RemoteVirtualNetwork.Id
            AllowVirtualNetworkAccess = $peering.AllowVirtualNetworkAccess
            AllowForwardedTraffic = $peering.AllowForwardedTraffic
            AllowGatewayTransit   = $peering.AllowGatewayTransit
            UseRemoteGateways     = $peering.UseRemoteGateways
        }
    }
}

$csvPath = Join-Path $OutputDir "NetPeeringsBackup.csv"
$jsonPath = Join-Path $OutputDir "NetPeeringsBackup.json"

$peeringList | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
$peeringList | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8

Write-Host "✅ Exported $($peeringList.Count) VNet peering(s) to:" -ForegroundColor Green
Write-Host "  CSV : $csvPath" -ForegroundColor Cyan
Write-Host "  JSON: $jsonPath" -ForegroundColor Cyan
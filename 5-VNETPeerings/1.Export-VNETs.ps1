## DESCRIPTION: Exports all VNet peering configurations across the subscription to a CSV file.
##              Run this before deleting peerings so they can be recreated post-migration.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Update the CSV output path.
##              3. Run in PowerShell with the Az module installed.
##              4. Output CSV is used by 3.RecreatePeerings.ps1.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

#Export all VNET Peerings and save to CSV

# Connect to Azure
Connect-AzAccount -TenantId $sourceTenantId
Set-AzContext -Subscription $sourceSubscriptionId

# Set the Subscription
$subscriptionId = $sourceSubscriptionId
Select-AzSubscription -SubscriptionId $subscriptionId

# Get all Virtual Networks
$vNets = Get-AzVirtualNetwork

# Create an array to store peering details
$peeringList = @()

# Loop through each VNet and collect peering details
foreach ($vNet in $vNets) {
    $peerings = $vNet.VirtualNetworkPeerings
    foreach ($peering in $peerings) {
        $peeringList += [PSCustomObject]@{
            LocalVNetName      = $vNet.Name
            LocalResourceGroup = $vNet.ResourceGroupName
            PeeringName        = $peering.Name
            RemoteVNetId       = $peering.RemoteVirtualNetwork.Id
            AllowVnetAccess    = $peering.AllowVirtualNetworkAccess
            AllowForwardedTraffic = $peering.AllowForwardedTraffic
            AllowGatewayTransit = $peering.AllowGatewayTransit
            UseRemoteGateways  = $peering.UseRemoteGateways
        }
    }
}

# Export to CSV
$peeringList | Export-Csv -Path C:\CSPARMExports\Boxlight\vnets\NetPeeringsBackup.csv -NoTypeInformation

Write-Output "Exported all VNet peerings to VNetPeeringsBackup.csv"
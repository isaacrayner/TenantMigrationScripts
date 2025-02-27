#Export all VNET Peerings and save to CSV

# Connect to Azure
Connect-AzAccount -Tenant '00000000-0000-0000-0000-000000000000'
Set-AzContext -Subscription '00000000-0000-0000-0000-000000000000'

# Set the Subscription
$subscriptionId = '00000000-0000-0000-0000-000000000000'
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
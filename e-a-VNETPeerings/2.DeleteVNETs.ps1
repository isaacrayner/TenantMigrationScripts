# Connect to Azure
Connect-AzAccount

# Set the Subscription
$subscriptionId = '00000000-0000-0000-0000-000000000000'
Select-AzSubscription -SubscriptionId $subscriptionId

# Get all Virtual Networks
$vNets = Get-AzVirtualNetwork

# Loop through each VNet and remove peerings
foreach ($vNet in $vNets) {
    $peerings = $vNet.VirtualNetworkPeerings
    foreach ($peering in $peerings) {
        Remove-AzVirtualNetworkPeering -VirtualNetworkName $vNet.Name -ResourceGroupName $vNet.ResourceGroupName -Name $peering.Name -Force
        Write-Output "Deleted Peering: $($peering.Name) from VNet: $($vNet.Name)"
    }
}

Write-Output "All VNet peerings have been removed successfully!"
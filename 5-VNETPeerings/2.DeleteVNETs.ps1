## DESCRIPTION: Removes all VNet peerings in the subscription. VNet peerings must be deleted
##              before VNets can be migrated across tenants.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Run 1.Export-VNETs.ps1 first to back up peering configurations.
##              3. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Connect to Azure
Connect-AzAccount

# Set the Subscription (loaded from migration-params.ps1)
$subscriptionId = $sourceSubscriptionId
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
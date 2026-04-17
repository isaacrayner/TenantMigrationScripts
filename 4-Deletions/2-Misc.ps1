## DESCRIPTION: Deletes miscellaneous resources that must be removed before tenant migration:
##              disk snapshots, VPN gateway connections/gateways/local gateways, NAT gateways,
##              and Application Gateways. Run each section selectively as needed.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Review and update resource group names and resource names in each section.
##              3. Run sections individually in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

#########
# Set the Context
#########

Set-AzContext -Subscription $sourceSubscriptionId

#########
# Delete All Snapshots
#########

# Set your subscription (if you have multiple)
Set-AzContext -SubscriptionId "<Your-Subscription-ID>"

# Get all snapshots in the subscription
$snapshots = Get-AzSnapshot

if ($snapshots.Count -eq 0) {
    Write-Output "No snapshots found in the subscription."
} else {
    foreach ($snapshot in $snapshots) {
        try {
            Write-Output "Deleting snapshot: $($snapshot.Name) in resource group: $($snapshot.ResourceGroupName)"
            Remove-AzSnapshot -ResourceGroupName $snapshot.ResourceGroupName -SnapshotName $snapshot.Name -Force
            Write-Output "Deleted snapshot: $($snapshot.Name)"
        } catch {
            Write-Output "Failed to delete snapshot: $($snapshot.Name). Error: $_"
        }
    }

    Write-Output "All snapshots have been processed."
}

#########
# Delete VPN Gateway
#########

# Define variables
$resourceGroupName = "vpn-gateway"
$vpnGatewayName = "boxlight-vpn-gw"
$localGatewayName = "<Your-Local-Network-Gateway-Name>"

# Step 1: Delete VPN Connections
$connections = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $resourceGroupName
foreach ($connection in $connections) {
    Write-Output "Deleting VPN Connection: $($connection.Name)"
    Remove-AzVirtualNetworkGatewayConnection -ResourceGroupName $resourceGroupName -Name $connection.Name -Force
    Write-Output "Deleted VPN Connection: $($connection.Name)"
}

# Step 2: Delete VPN Gateway
Write-Output "Deleting VPN Gateway: $vpnGatewayName"
Remove-AzVirtualNetworkGateway -ResourceGroupName $resourceGroupName -Name $vpnGatewayName -Force
Write-Output "VPN Gateway $vpnGatewayName deleted successfully."

# Step 3: Delete Local Network Gateway (Optional)
if ($localGatewayName -ne "") {
    Write-Output "Deleting Local Network Gateway: $localGatewayName"
    Remove-AzLocalNetworkGateway -ResourceGroupName $resourceGroupName -Name $localGatewayName -Force
    Write-Output "Local Network Gateway $localGatewayName deleted successfully."
}

Write-Output "All VPN resources have been deleted."

#########
# Delete NAT Gateway
#########
# Get all NAT Gateways in the subscription
$natGateways = Get-AzNatGateway

if ($natGateways.Count -eq 0) {
    Write-Output "No NAT Gateways found in the subscription."
} else {
    foreach ($natGateway in $natGateways) {
        try {
            Write-Output "Deleting NAT Gateway: $($natGateway.Name) in resource group: $($natGateway.ResourceGroupName)"
            Remove-AzNatGateway -ResourceGroupName $natGateway.ResourceGroupName -NatGatewayName $natGateway.Name -Force
            Write-Output "Deleted NAT Gateway: $($natGateway.Name)"
        } catch {
            Write-Output "Failed to delete NAT Gateway: $($natGateway.Name). Error: $_"
        }
    }

    Write-Output "All NAT Gateways have been processed."
}


#########
# Delete Application Gateways
#########
# Get all Application Gateways in the subscription
$appGateways = Get-AzApplicationGateway

if ($appGateways.Count -eq 0) {
    Write-Output "No Application Gateways found in the subscription."
} else {
    foreach ($appGateway in $appGateways) {
        try {
            Write-Output "Deleting Application Gateway: $($appGateway.Name) in resource group: $($appGateway.ResourceGroupName)"
            Remove-AzApplicationGateway -ResourceGroupName $appGateway.ResourceGroupName -Name $appGateway.Name -Force
            Write-Output "Deleted Application Gateway: $($appGateway.Name)"
        } catch {
            Write-Output "Failed to delete Application Gateway: $($appGateway.Name). Error: $_"
        }
    }

    Write-Output "All Application Gateways have been processed."
}



# Script to create Azure VNet peerings from CSV
# Save this as a .ps1 file and run it

# Set the Subscription
$subscriptionId = '00000000-0000-0000-0000-000000000000'
Select-AzSubscription -SubscriptionId $subscriptionId

# Import the CSV file
$peeringData = Import-Csv -Path 'C:\CSPARMExports\Boxlight\vnets\NetPeeringsBackup.csv'

# Create a log file instead of relying on console output
$logFile = "VNetPeering_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
"VNet Peering Creation Log - $(Get-Date)" | Out-File -FilePath $logFile

# Get the Az module version for debugging
$azVersion = (Get-Module Az.Network -ListAvailable).Version
"Using Az.Network module version: $azVersion" | Out-File -FilePath $logFile -Append

foreach ($peering in $peeringData) {
    # Log peering creation start
    "Creating peering: $($peering.PeeringName)" | Out-File -FilePath $logFile -Append
    
    try {
        # Extract subscription ID from RemoteVNetId
        $remoteVNetIdParts = $peering.RemoteVNetId -split '/'
        $subscriptionId = $remoteVNetIdParts[2]
        
        # Set the correct subscription context
        Set-AzContext -SubscriptionId $subscriptionId | Out-Null
        
        # Get the virtual network object
        $vnet = Get-AzVirtualNetwork -Name $peering.LocalVNetName -ResourceGroupName $peering.LocalResourceGroup
        
        # Check if peering already exists
        $existingPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $peering.LocalVNetName -ResourceGroupName $peering.LocalResourceGroup -Name $peering.PeeringName -ErrorAction SilentlyContinue
        
        if ($existingPeering) {
            "  INFO: Peering $($peering.PeeringName) already exists. Skipping." | Out-File -FilePath $logFile -Append
            continue
        }
        
        # Use a different approach: Add the peering directly to the VNet object
        $peeringConfig = Add-AzVirtualNetworkPeering `
            -Name $peering.PeeringName `
            -VirtualNetwork $vnet `
            -RemoteVirtualNetworkId $peering.RemoteVNetId
            
        # After creating the basic peering, update the additional properties
        if ([System.Convert]::ToBoolean($peering.AllowForwardedTraffic)) {
            $peeringConfig.AllowForwardedTraffic = $true
        }
        
        if ([System.Convert]::ToBoolean($peering.AllowGatewayTransit)) {
            $peeringConfig.AllowGatewayTransit = $true
        }
        
        if ([System.Convert]::ToBoolean($peering.UseRemoteGateways)) {
            $peeringConfig.UseRemoteGateways = $true
        }
        
        # Apply the configuration
        $vnet | Set-AzVirtualNetwork | Out-Null
        
        "  SUCCESS: Created peering: $($peering.PeeringName)" | Out-File -FilePath $logFile -Append
    }
    catch {
        "  ERROR: Failed to create peering: $($peering.PeeringName)" | Out-File -FilePath $logFile -Append
        "  ERROR Details: $_" | Out-File -FilePath $logFile -Append
    }
}

"All peerings creation completed at $(Get-Date)" | Out-File -FilePath $logFile -Append

# Display a simple completion message with minimal console output
Write-Host "VNet Peering creation completed. See log file for details: $logFile"
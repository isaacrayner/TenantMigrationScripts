## DESCRIPTION: Recreates VNet peerings in the destination subscription from the CSV exported
##              by 1.Export-VNETs.ps1. Skips peerings that already exist. Writes a timestamped
##              log file for review.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Update the CSV path to match the export from 1.Export-VNETs.ps1.
##              3. Run in PowerShell with the Az module installed.
##              4. Review the generated VNetPeering_Log_*.txt for results.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Script to create Azure VNet peerings from CSV
# Save this as a .ps1 file and run it

# Set the Subscription (loaded from migration-params.ps1)
$subscriptionId = $destinationSubscriptionId
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
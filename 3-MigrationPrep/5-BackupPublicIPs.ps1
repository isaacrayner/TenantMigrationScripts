## DESCRIPTION: Exports all Public IP address details from the source subscription to a CSV file.
##              Optionally recreates those Public IPs in the destination subscription.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Run in PowerShell with the Az module installed.
##              3. Answer Y at the prompt to also recreate IPs in the destination subscription.
##              4. Review C:\temp\PublicIP_Migration.log for results.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Define log file
$logFile = "C:\temp\PublicIP_Migration.log"

# Function to log messages
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    
    # Output to console
    Write-Host $logMessage  
    
    # Append to log file
    Add-Content -Path $logFile -Value $logMessage
}

# Set export file path
$csvFile = "C:\temp\PublicIP_Export.csv"
$subscriptionId    = $sourceSubscriptionId
$newSubscriptionId = $destinationSubscriptionId

# Step 2: Set Subscription Context
try {
    Write-Log "Setting context to source subscription: $subscriptionId"
    Set-AzContext -SubscriptionId $subscriptionId
    Write-Log "Subscription context set successfully."
} catch {
    Write-Log "ERROR: Failed to set subscription context. $_"
    exit
}

# Step 3: Retrieve and Export Public IPs
try {
    Write-Log "Retrieving Public IPs from subscription: $subscriptionId..."
    $publicIPs = Get-AzPublicIpAddress

    if ($publicIPs.Count -eq 0) {
        Write-Log "No Public IPs found in the subscription."
    } else {
        # Export Public IP details to CSV (Ensure correct field names & default values)
        $publicIPs | Select-Object `
            Name, `
            ResourceGroupName, `
            @{Name="Sku"; Expression={if ($_.Sku.Name) { $_.Sku.Name } else { "Standard" }}}, `
            @{Name="AllocationMethod"; Expression={if ($_.PublicIpAllocationMethod) { $_.PublicIpAllocationMethod } else { "Static" }}}, `
            @{Name="IpAddressVersion"; Expression={if ($_.IpConfiguration -eq $null) {"IPv4"} else {$_.IpConfiguration.PrivateIpAddressVersion}}}, `
            Location, `
            @{Name="Zone"; Expression={if ($_.Zones.Count -gt 0) { $_.Zones -join "," } else { "1,2,3" }}}, `
            @{Name="DomainNameLabel"; Expression={$_.DnsSettings.DomainNameLabel}} |
            Export-Csv -Path $csvFile -NoTypeInformation

        Write-Log "Public IP details exported to $csvFile"
    }
} catch {
    Write-Log "ERROR: Failed to retrieve Public IPs. $_"
    exit
}

# Step 4: Prompt for Recreating Public IPs in New Subscription
$restoreIPs = Read-Host "Do you want to recreate Public IPs in the new subscription? (Y/N)"

if ($restoreIPs -eq "Y" -or $restoreIPs -eq "y") {
    # Step 5: Log in to the new subscription
    try {
        Write-Log "Setting context to new subscription: $newSubscriptionId"
        Set-AzContext -SubscriptionId $newSubscriptionId
        Write-Log "Context switched to new subscription."
    } catch {
        Write-Log "ERROR: Failed to log in to new subscription or set context. $_"
        exit
    }

    # Step 6: Read CSV and Recreate Public IPs
    try {
        Write-Log "Reading Public IP details from $csvFile..."
        $publicIPs = Import-Csv -Path $csvFile

        Write-Log "Recreating Public IPs in the new subscription..."
        foreach ($ip in $publicIPs) {
            try {
                # Set defaults if missing
                $sku = if ($ip.Sku -and $ip.Sku -ne "") { $ip.Sku } else { "Standard" }
                $ipVersion = if ($ip.IpAddressVersion -and $ip.IpAddressVersion -ne "") { $ip.IpAddressVersion } else { "IPv4" }
                $allocationMethod = if ($ip.AllocationMethod -and $ip.AllocationMethod -ne "") { $ip.AllocationMethod } else { "Static" }
                $zone = if ($ip.Zone -and $ip.Zone -ne "") { $ip.Zone } else { "1,2,3" } # Default zone for Standard SKU

                Write-Log "Creating Public IP: $($ip.Name) in Resource Group: $($ip.ResourceGroupName) at Location: $($ip.Location) with SKU: $sku, IP Version: $ipVersion, Allocation Method: $allocationMethod, and Zones: $zone"

                # Create Public IP
                New-AzPublicIpAddress -Name $ip.Name `
                    -ResourceGroupName $ip.ResourceGroupName `
                    -Location $ip.Location `
                    -Sku $sku `
                    -AllocationMethod $allocationMethod `
                    -IpAddressVersion $ipVersion `
                    -Zone ($zone -split ",") `
                    -DomainNameLabel $ip.DomainNameLabel

                Write-Log "Successfully created Public IP: $($ip.Name) with SKU: $sku, IP Version: $ipVersion, Allocation Method: $allocationMethod, and Zones: $zone"
            } catch {
                Write-Log "ERROR: Failed to create Public IP: $($ip.Name). Error: $_"
            }
        }
        Write-Log "Public IP migration completed successfully."
    } catch {
        Write-Log "ERROR: Failed to read Public IP details from CSV. $_"
        exit
    }
}

Write-Log "Public IP migration process completed."

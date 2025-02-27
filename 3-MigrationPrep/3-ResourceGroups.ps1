# Define log file
$logFile = "C:\temp\AzureResourceGroupMigration.log"

# Function to log messages
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Define source and destination subscriptions
$sourceSubscription = "00000000-0000-0000-0000-000000000000"
$destinationSubscription = "00000000-0000-0000-0000-000000000000"

try {
    # Log in to Azure
    Write-Log "Logging in to Azure..."
    #Connect-AzAccount
    Write-Log "Azure login successful."

    # Step 1: Set context to the source subscription
    Write-Log "Setting context to source subscription: $sourceSubscription"
    Set-AzContext -Subscription $sourceSubscription

    # Retrieve all resource groups from the source subscription
    Write-Log "Retrieving resource groups from the source subscription..."
    $SourceResourceGroups = Get-AzResourceGroup

    if ($SourceResourceGroups.Count -eq 0) {
        Write-Log "No resource groups found in the source subscription."
    } else {
        Write-Log "Found $($SourceResourceGroups.Count) resource groups."
    }

    # Set context to the destination subscription
    Write-Log "Setting context to destination subscription: $destinationSubscription"
    Set-AzContext -Subscription $destinationSubscription

    # Recreate resource groups in the target subscription
    Write-Log "Creating resource groups in the target subscription..."
    foreach ($ResourceGroup in $SourceResourceGroups) {
        try {
            $ResourceGroupName = $ResourceGroup.ResourceGroupName
            $Location = $ResourceGroup.Location
            $Tags = $ResourceGroup.Tags

            Write-Log "Creating Resource Group: $ResourceGroupName in $Location..."
            New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags
            Write-Log "Successfully created Resource Group: $ResourceGroupName"
        } catch {
            Write-Log "ERROR: Failed to create Resource Group: $ResourceGroupName. Error: $_"
        }
    }

    Write-Log "Resource group migration completed successfully."
} catch {
    Write-Log "ERROR: An unexpected error occurred. Details: $_"
}

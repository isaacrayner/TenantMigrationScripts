## DESCRIPTION: Exports all RBAC role assignments from the source subscription to JSON and CSV.
##              Run this during migration prep. To restore assignments in the destination,
##              use 7-Recreation/5-RestoreRoleAssignments.ps1.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Run in PowerShell with the Az module installed.
##              3. Review C:\temp\RBAC_Migration.log for results.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Subscription IDs (loaded from migration-params.ps1)
$subscriptionId    = $sourceSubscriptionId
$newSubscriptionId = $destinationSubscriptionId

# Define log file
$logFile = "C:\temp\RBAC_Migration.log"

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

# Set file paths for export
$jsonFile = "C:\temp\RBAC_Assignments.json"
$csvFile = "C:\temp\RBAC_Assignments.csv"


# Step 1: Log in to Azure
try {
    Write-Log "Logging in to Azure..."
    Connect-AzAccount
    Write-Log "Azure login successful."
} catch {
    Write-Log "ERROR: Azure login failed. $_"
    exit
}

# Step 2: Set Subscription Context

try {
    Write-Log "Setting context to subscription: $subscriptionId"
    Set-AzContext -SubscriptionId $subscriptionId
    Write-Log "Subscription context set successfully."
} catch {
    Write-Log "ERROR: Failed to set subscription context. $_"
    exit
}

# Step 3: Retrieve and Export RBAC Assignments
try {
    Write-Log "Retrieving all RBAC assignments for subscription: $subscriptionId..."
    $rbacAssignments = Get-AzRoleAssignment

    if ($rbacAssignments.Count -eq 0) {
        Write-Log "No RBAC assignments found."
    } else {
        # Export to JSON
        $rbacAssignments | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Log "RBAC assignments exported to $jsonFile"

        # Export to CSV
        $rbacAssignments | Select-Object ObjectId, DisplayName, RoleDefinitionName, Scope | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Log "RBAC assignments exported to $csvFile"
    }
} catch {
    Write-Log "ERROR: Failed to retrieve RBAC assignments. $_"
    exit
}

Write-Log "Export complete. To restore assignments in the destination subscription, run 7-Recreation/5-RestoreRoleAssignments.ps1."

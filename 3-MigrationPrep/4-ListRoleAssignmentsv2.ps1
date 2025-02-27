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

$subscriptionId = "00000000-0000-0000-0000-000000000000"
$newSubscriptionId = "00000000-0000-0000-0000-000000000000"


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

# Step 4: Prompt for Reassignment after Subscription Migration
$restoreRBAC = Read-Host "Do you want to reapply RBAC roles in the new subscription? (Y/N)"

if ($restoreRBAC -eq "Y" -or $restoreRBAC -eq "y") {
    # Step 5: Log in to new tenant and set subscription context
    try {
        Write-Log "Logging into the new tenant..."
        Connect-AzAccount
        Write-Log "Azure login successful in new tenant."
        
        Write-Log "Setting context to new subscription: $newSubscriptionId"
        Set-AzContext -SubscriptionId $newSubscriptionId
        Write-Log "Context switched to new subscription."
    } catch {
        Write-Log "ERROR: Failed to log in to new tenant or set subscription context. $_"
        exit
    }

    # Step 6: Read and Reapply RBAC Assignments
    try {
        Write-Log "Reading RBAC assignments from $jsonFile..."
        $rbacAssignments = Get-Content -Path $jsonFile | ConvertFrom-Json

        Write-Log "Reapplying RBAC assignments in the new subscription..."
        foreach ($assignment in $rbacAssignments) {
            try {
                Write-Log "Assigning role: $($assignment.RoleDefinitionName) to $($assignment.DisplayName) at scope $($assignment.Scope)"
                New-AzRoleAssignment -ObjectId $assignment.ObjectId -RoleDefinitionName $assignment.RoleDefinitionName -Scope $assignment.Scope
                Write-Log "Successfully assigned role to $($assignment.DisplayName)"
            } catch {
                Write-Log "ERROR: Failed to assign role to $($assignment.DisplayName). Error: $_"
            }
        }
        Write-Log "RBAC reassignment completed successfully."
    } catch {
        Write-Log "ERROR: Failed to read RBAC assignments from file. $_"
        exit
    }
}

Write-Log "RBAC migration process completed."

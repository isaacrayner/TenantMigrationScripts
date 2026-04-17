

## DESCRIPTION: Inventories all managed identities (system-assigned and user-assigned) across
##              VMs, App Services, Application Gateways, Function Apps, and SQL Servers.
##              Exports resource identity details and RBAC assignments to CSV files.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Run in PowerShell with the Az module installed.
##              3. Output CSVs are used by 4-DisableMIdentities.ps1 and 4-A-RecreateMIdentities.ps1.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Set Subscription (loaded from migration-params.ps1)
$subscriptionId = $sourceSubscriptionId
Set-AzContext -SubscriptionId $subscriptionId

# Initialize arrays
$resourcesWithMI = @()
$rbacAssignments = @()

# Function to Get RBAC Assignments for a Resource
function Get-RBACAssignments {
    param ($resourceId)

    $assignments = Get-AzRoleAssignment -Scope $resourceId
    foreach ($assignment in $assignments) {
        [PSCustomObject]@{
            ResourceId      = $resourceId
            PrincipalName   = $assignment.DisplayName
            PrincipalId     = $assignment.ObjectId
            RoleDefinition  = $assignment.RoleDefinitionName
            RoleDefinitionId = $assignment.RoleDefinitionId
            AssignmentScope = $assignment.Scope
            AssignmentType  = if ($assignment.SignInName) { "User/Group" } else { "Service Principal" }
        }
    }
}

# Query Virtual Machines (Ensuring Managed Identity is Captured)
$vmList = Get-AzVM
foreach ($vm in $vmList) {
    if ($vm.Identity -and $vm.Identity.Type -ne "None") {
        $resourcesWithMI += [PSCustomObject]@{
            ResourceName = $vm.Name
            ResourceId = $vm.Id
            ResourceType = "VirtualMachine"
            IdentityType = $vm.Identity.Type
            UserAssignedIdentities = ($vm.Identity.UserAssignedIdentities | ConvertTo-Json -Depth 1)
        }
        $rbacAssignments += Get-RBACAssignments -resourceId $vm.Id
    }
}

# Query App Services
$appList = Get-AzWebApp
foreach ($app in $appList) {
    if ($app.Identity -and $app.Identity.Type -ne "None") {
        $resourcesWithMI += [PSCustomObject]@{
            ResourceName = $app.Name
            ResourceId = $app.Id
            ResourceType = "AppService"
            IdentityType = $app.Identity.Type
            UserAssignedIdentities = ($app.Identity.UserAssignedIdentities | ConvertTo-Json -Depth 1)
        }
        $rbacAssignments += Get-RBACAssignments -resourceId $app.Id
    }
}

# Query Application Gateways
$appGwList = Get-AzApplicationGateway
foreach ($appGw in $appGwList) {
    if ($appGw.Identity -and $appGw.Identity.Type -ne "None") {
        $resourcesWithMI += [PSCustomObject]@{
            ResourceName = $appGw.Name
            ResourceId = $appGw.Id
            ResourceType = "ApplicationGateway"
            IdentityType = $appGw.Identity.Type
            UserAssignedIdentities = ($appGw.Identity.UserAssignedIdentities | ConvertTo-Json -Depth 1)
        }
        $rbacAssignments += Get-RBACAssignments -resourceId $appGw.Id
    }
}

# Query Azure Functions
$funcList = Get-AzFunctionApp
foreach ($func in $funcList) {
    if ($func.Identity -and $func.Identity.Type -ne "None") {
        $resourcesWithMI += [PSCustomObject]@{
            ResourceName = $func.Name
            ResourceId = $func.Id
            ResourceType = "FunctionApp"
            IdentityType = $func.Identity.Type
            UserAssignedIdentities = ($func.Identity.UserAssignedIdentities | ConvertTo-Json -Depth 1)
        }
        $rbacAssignments += Get-RBACAssignments -resourceId $func.Id
    }
}

# Query Managed Identity-enabled Azure SQL Servers
$sqlServers = Get-AzSqlServer
foreach ($sql in $sqlServers) {
    if ($sql.Identity -and $sql.Identity.Type -ne "None") {
        $resourcesWithMI += [PSCustomObject]@{
            ResourceName = $sql.ServerName
            ResourceId = $sql.Id
            ResourceType = "SQLServer"
            IdentityType = $sql.Identity.Type
            UserAssignedIdentities = ($sql.Identity.UserAssignedIdentities | ConvertTo-Json -Depth 1)
        }
        $rbacAssignments += Get-RBACAssignments -resourceId $sql.Id
    }
}

# Export Managed Identity Details
$resourcesWithMI | Export-Csv -Path "C:\temp\AzureMIdentityBackup\ManagedIdentityResources.csv" -NoTypeInformation

# Export RBAC Assignments
$rbacAssignments | Export-Csv -Path "C:\temp\AzureMIdentityBackup\RBACAssignments.csv" -NoTypeInformation

# Display Summary
Write-Host "✅ Exported Managed Identities to ManagedIdentityResources.csv"
Write-Host "✅ Exported RBAC Assignments to RBACAssignments.csv"

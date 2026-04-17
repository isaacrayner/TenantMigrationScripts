## DESCRIPTION: Exports all RBAC role assignments, managed identities, service principals, and
##              user principals from the source subscription to CSV files. Also includes notes
##              on recreating service principals in the destination tenant.
## USAGE:       1. Replace <source-tenant-id> and <source-subscription-id> with correct values.
##              2. Update file paths as needed.
##              3. Run each section in sequence in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")


#Download Role Assignments
#https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-list-portal#list-role-assignments-at-a-scope
#You can download role assignments at a scope in CSV or JSON formats. This can be helpful if you need to inspect the list in a spreadsheet or take an inventory when migrating a subscription.

#STEP ONE: LIST ALL ROLE ASSIGNMENTS
Connect-AzAccount -TenantId $sourceTenantId
$SubscriptionId = $sourceSubscriptionId
Select-AzSubscription -SubscriptionId $SubscriptionId
$RoleAssignments = Get-AzRoleAssignment

$RoleAssignments | Select-Object RoleDefinitionName, PrincipalName, PrincipalType, Scope | Export-Csv -Path "C:\Temp\RoleAssignments.csv" -NoTypeInformation

#STE ONE B: EXPORT ALL CUSTOM ROLES


<# STEP 2: Map Identities:
Identify which identities in the source tenant have equivalents in the destination tenant.
If an identity doesn't exist, you'll need to create it in the destination tenant (e.g., a new user, group, or service principal).
Resolve Conflicts:
Some roles might not make sense in the new tenant (e.g., if tied to resources that don’t exist in the destination).
#>

#list managed identities
Get-AzUserAssignedIdentity | Select-Object Name, ResourceGroupName, Location, ClientId, PrincipalId |
Export-Csv -Path "C:\Temp\UserAssignedIdentities.csv" -NoTypeInformation

OR This
az resource list --query "[?identity.type=='SystemAssigned'].{Name:name,  principalId:identity.principalId}" --output table

#Get Service Principals
Get-AzADServicePrincipal | Select-Object DisplayName, AppId, ObjectId | Export-Csv -Path "C:\Temp\ServicePrincipals.csv" -NoTypeInformation

#document user principals
Get-AzADUser | Select-Object DisplayName, UserPrincipalName, ObjectId | Export-Csv -Path "C:\Temp\UserPrincipals.csv" -NoTypeInformation



############

#Recreate Service Principals
New-AzADServicePrincipal -DisplayName "<ServicePrincipalName>" -AppId "<ApplicationId>"

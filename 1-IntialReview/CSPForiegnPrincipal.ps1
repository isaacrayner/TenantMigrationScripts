## DESCRIPTION: Retrieves the CSP Foreign Principal ObjectID from the source tenant and grants it
##              Owner permissions on the customer subscription. Run this before any migration work
##              to ensure the CSP partner account has the required access.
## USAGE:       1. Replace 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' with the customer Azure AD Tenant ID.
##              2. Replace 'PARTNER NAME' with your CSP Partner Name.
##              3. Replace '{ObjectId from previous step}' and 'XXXXX' with the retrieved ObjectId
##                 and the target subscription ID.
##              4. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot ".\..\migration-params.ps1")

## Connect to Customer AAD Tenant:
Connect-AzAccount -TenantId $sourceTenantId

## Get CSP Foreign Principal ID - Change 'PARTNER NAME' to whatever your CSP Partner Name is:
Get-AZRoleAssignment | where DisplayName -like "Foreign Principal for 'PARTNER NAME'*" | fl DisplayName, ObjectID

## Example Command Output:
DisplayName : Foreign Principal for 'CSP PARTNER NAME' in Role 'TenantAdmins' (CUSTOMER NAME)
ObjectId    : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## Set CSP Foreign Principal With Permissions Over Required Subscriptions - Insert correct ObjectID of CSP Foreign Principal & Customer Subscription ID:
New-AZRoleAssignment -ObjectId '{ObjectId from previous step}' -RoleDefinitionName Owner -Scope /subscriptions/XXXXX
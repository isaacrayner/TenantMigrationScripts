## Connect to Customer AAD Tenant - Change 'xxxx' to the Azure AD Tenant ID which the subscriptions are linked to:
Connect-AzAccount -TenantId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## Get CSP Foreign Principal ID - Change 'PARTNER NAME' to whatever your CSP Partner Name is:
Get-AZRoleAssignment | where DisplayName -like "Foreign Principal for 'PARTNER NAME'*" | fl DisplayName, ObjectID

## Example Command Output:
DisplayName : Foreign Principal for 'CSP PARTNER NAME' in Role 'TenantAdmins' (CUSTOMER NAME)
ObjectId    : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## Set CSP Foreign Principal With Permissions Over Required Subscriptions - Insert correct ObjectID of CSP Foreign Principal & Customer Subscription ID:
New-AZRoleAssignment -ObjectId '{ObjectId from previous step}' -RoleDefinitionName Owner -Scope /subscriptions/XXXXX
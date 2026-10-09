<#
.SYNOPSIS
    Retrieves the CSP Foreign Principal ObjectID from the source tenant and assigns Owner
    permissions on the target subscription.
.DESCRIPTION
    Run this before migration work to ensure the CSP partner account has required access.
    Automatically queries the Foreign Principal service principal in the tenant.
#>

param(
    [string]$PartnerName,
    [string]$SubscriptionId
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }

# Connect to Customer Entra ID (Azure AD) Tenant
if (-not (Get-AzContext) -or (Get-AzContext).Tenant.Id -ne $sourceTenantId) {
    Write-Host "Connecting to Source Tenant: $sourceTenantId" -ForegroundColor Cyan
    Connect-AzAccount -TenantId $sourceTenantId
}

if (-not $SubscriptionId) {
    $SubscriptionId = Read-Host "Enter the Subscription ID to grant access to"
}

if (-not $PartnerName) {
    $PartnerName = Read-Host "Enter the CSP Partner Name (or part of it)"
}

Write-Host "Searching for Foreign Principal matching '$PartnerName'..." -ForegroundColor Cyan
$foreignPrincipals = Get-AzRoleAssignment | Where-Object { $_.DisplayName -like "Foreign Principal for *$PartnerName*" } | Select-Object -Property DisplayName, ObjectId -Unique

if (-not $foreignPrincipals -or $foreignPrincipals.Count -eq 0) {
    Write-Host "No Foreign Principal found matching '$PartnerName'. Listing all Foreign Principals:" -ForegroundColor Yellow
    Get-AzRoleAssignment | Where-Object { $_.DisplayName -like "Foreign Principal*" } | Select-Object -Property DisplayName, ObjectId -Unique | Format-Table -AutoSize
    $selectedObjectId = Read-Host "Enter the ObjectId of the Foreign Principal to assign"
} else {
    $foreignPrincipals | Format-Table -AutoSize
    $selectedObjectId = $foreignPrincipals[0].ObjectId
}

if ($selectedObjectId) {
    $scope = "/subscriptions/$SubscriptionId"
    Write-Host "Assigning Owner role to Foreign Principal ($selectedObjectId) at scope: $scope..." -ForegroundColor Cyan
    
    $existing = Get-AzRoleAssignment -ObjectId $selectedObjectId -RoleDefinitionName "Owner" -Scope $scope -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Foreign Principal already has Owner role on subscription $SubscriptionId." -ForegroundColor Green
    } else {
        New-AzRoleAssignment -ObjectId $selectedObjectId -RoleDefinitionName "Owner" -Scope $scope
        Write-Host "Successfully assigned Owner role to CSP Foreign Principal." -ForegroundColor Green
    }
}
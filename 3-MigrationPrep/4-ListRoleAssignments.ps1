<#
.SYNOPSIS
    Inventories Azure AD (Entra ID) Users, Groups, and Service Principals associated
    with the source subscription.
.DESCRIPTION
    Exports principal details to CSV files in the centralized migration-data folder.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$OutputDir      = (Join-Path $backupRootDir "Identities")
)

Write-Host "=== Entra ID Identity Inventory ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 1. Export Role Assignments using v2 script
Write-Host "Exporting RBAC Role Assignments..." -ForegroundColor Cyan
$v2Script = Join-Path $PSScriptRoot "4-ListRoleAssignmentsv2.ps1"
if (Test-Path $v2Script) {
    & $v2Script -SubscriptionId $SubscriptionId
}

# 2. Export User-Assigned Managed Identities
Write-Host "Exporting User-Assigned Managed Identities..." -ForegroundColor Cyan
try {
    $userAssigned = Get-AzUserAssignedIdentity
    $uaFile = Join-Path $OutputDir "UserAssignedIdentities.csv"
    $userAssigned | Select-Object Name, ResourceGroupName, Location, ClientId, PrincipalId, Id |
        Export-Csv -Path $uaFile -NoTypeInformation
    Write-Host "  ✅ Saved to $uaFile" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ Could not export User-Assigned Identities: $_" -ForegroundColor Yellow
}

# 3. Export Service Principals
Write-Host "Exporting Entra ID Service Principals..." -ForegroundColor Cyan
try {
    $spFile = Join-Path $OutputDir "ServicePrincipals.csv"
    Get-AzADServicePrincipal | Select-Object DisplayName, AppId, Id |
        Export-Csv -Path $spFile -NoTypeInformation
    Write-Host "  ✅ Saved to $spFile" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ Could not export Service Principals: $_" -ForegroundColor Yellow
}

# 4. Export Users
Write-Host "Exporting Entra ID Users..." -ForegroundColor Cyan
try {
    $userFile = Join-Path $OutputDir "UserPrincipals.csv"
    Get-AzADUser | Select-Object DisplayName, UserPrincipalName, Id |
        Export-Csv -Path $userFile -NoTypeInformation
    Write-Host "  ✅ Saved to $userFile" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ Could not export Users: $_" -ForegroundColor Yellow
}

Write-Host "`nIdentity inventory complete. Data saved in $OutputDir" -ForegroundColor Green

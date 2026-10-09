<#
.SYNOPSIS
    Planning Stage: Generates an Identity & Permission Mapping Planning Template.
.DESCRIPTION
    Extracts all unique principals (Users, Groups, Service Principals, Managed Identities)
    that hold permissions on the subscription, and builds an Identity_Mapping_Plan.csv
    to prepare for reapplying permissions in the destination tenant.
#>

param(
    [string]$InputJson,
    [string]$OutputFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('InputJson')) { $InputJson = (Join-Path $backupRootDir "Planning/Master_RBAC_Assignments.json") }
if (-not $PSBoundParameters.ContainsKey('OutputFile')) { $OutputFile = (Join-Path $backupRootDir "Planning/Identity_Mapping_Plan.csv") }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      PLANNING STAGE: GENERATE IDENTITY MAPPING PLAN      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $InputJson)) {
    Write-Host "RBAC assignments file not found. Running 00-Planning/01-ExportAllPermissions.ps1 first..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "00-Planning/01-ExportAllPermissions.ps1")
}

$assignments = Get-Content $InputJson -Raw | ConvertFrom-Json

# Group unique principals
$uniquePrincipals = $assignments | Group-Object -Property ObjectId

Write-Host "Discovered $($uniquePrincipals.Count) unique principal(s) with role assignments." -ForegroundColor Cyan

$plan = @()

foreach ($group in $uniquePrincipals) {
    $first = $group.Group[0]
    $rolesHeld = ($group.Group | ForEach-Object { "$($_.RoleDefinitionName)@$($_.ScopeLevel)" }) -join "; "
    $pType = $first.ObjectType

    $targetAction = switch ($pType) {
        "User"             { if ($destinationTenantId) { "Map to Target Tenant UPN" } else { "Preserve Same-Tenant ObjectId" } }
        "Group"            { if ($destinationTenantId) { "Map to Target Tenant Group" } else { "Preserve Same-Tenant ObjectId" } }
        "ServicePrincipal" { if ($destinationTenantId) { "Recreate / Map in Target Tenant" } else { "Preserve Same-Tenant ObjectId" } }
        Default            { "Review" }
    }

    $plan += [PSCustomObject]@{
        PrincipalType        = $pType
        SourceDisplayName    = $first.DisplayName
        SourceSignInName     = $first.SignInName
        SourceObjectId       = $first.ObjectId
        RolesCount           = $group.Count
        RolesAndScopes       = $rolesHeld
        TargetSignInName     = if ($destinationTenantId) { "" } else { $first.SignInName }
        TargetObjectId       = if ($destinationTenantId) { "" } else { $first.ObjectId }
        MappingStatus        = if ($destinationTenantId) { "PENDING_MAPPING" } else { "READY" }
        ActionRequired       = $targetAction
    }
}

$plan | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding utf8
Write-Host "`n✅ Identity Mapping Plan generated successfully!" -ForegroundColor Green
Write-Host "File saved to: $OutputFile" -ForegroundColor Yellow
Write-Host "`nHow to use this file:" -ForegroundColor White
Write-Host "1. Open $OutputFile in Excel or a CSV editor."
Write-Host "2. For cross-tenant moves: fill in TargetSignInName / TargetObjectId for your target tenant users/groups."
Write-Host "3. Run 00-Planning/03-ResolveTargetIdentities.ps1 to automatically lookup TargetObjectIds in the destination tenant."

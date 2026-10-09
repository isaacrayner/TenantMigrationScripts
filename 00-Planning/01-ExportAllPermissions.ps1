<#
.SYNOPSIS
    Planning Stage: Comprehensive Permission & Access Exporter.
.DESCRIPTION
    Scans and exports all layers of access across the source subscription:
    1. Subscription, Resource Group, and Resource level RBAC role assignments.
    2. Custom RBAC role definitions.
    3. Key Vault Access Policies and Key Vault RBAC mode status.
    4. Permissions held by Managed Identities.
    5. Azure SQL Server Entra ID Administrators.
    Outputs a consolidated permissions inventory to migration-data/Planning/.
#>

param(
    [string]$SubscriptionId,
    [string]$OutputDir
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('OutputDir')) { $OutputDir = (Join-Path $backupRootDir "Planning") }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     PLANNING STAGE: MASTER PERMISSION EXPORTER           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Source Subscription: $SubscriptionId" -ForegroundColor Yellow

Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# 1. Export All RBAC Assignments
Write-Host "`n[1/5] Exporting All RBAC Role Assignments (Subscription & Resource Scopes)..." -ForegroundColor Cyan
$allRoleAssignments = Get-AzRoleAssignment -ErrorAction Stop

$rbacSummary = @()
foreach ($ra in $allRoleAssignments) {
    $scopeLevel = if ($ra.Scope -eq "/subscriptions/$SubscriptionId") {
        "Subscription"
    } elseif ($ra.Scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+$") {
        "ResourceGroup"
    } else {
        "Resource"
    }

    $rbacSummary += [PSCustomObject]@{
        DisplayName        = $ra.DisplayName
        SignInName         = $ra.SignInName
        ObjectId           = $ra.ObjectId
        ObjectType         = $ra.ObjectType
        RoleDefinitionName = $ra.RoleDefinitionName
        RoleDefinitionId   = $ra.RoleDefinitionId
        ScopeLevel         = $scopeLevel
        Scope              = $ra.Scope
    }
}
$rbacJson = Join-Path $OutputDir "Master_RBAC_Assignments.json"
$rbacCsv  = Join-Path $OutputDir "Master_RBAC_Assignments.csv"
$rbacSummary | ConvertTo-Json -Depth 10 | Out-File -FilePath $rbacJson -Encoding utf8
$rbacSummary | Export-Csv -Path $rbacCsv -NoTypeInformation -Encoding utf8
Write-Host "  ✅ Exported $($rbacSummary.Count) RBAC assignment(s) -> $rbacCsv" -ForegroundColor Green

# 2. Export Custom Roles
Write-Host "`n[2/5] Exporting Custom RBAC Role Definitions..." -ForegroundColor Cyan
$customRoles = Get-AzRoleDefinition | Where-Object { $_.IsCustom -eq $true }
$customRolesExport = @()
if ($customRoles -and $customRoles.Count -gt 0) {
    foreach ($cr in $customRoles) {
        $customRolesExport += [PSCustomObject]@{
            RoleName         = $cr.Name
            Description      = $cr.Description
            Actions          = ($cr.Actions -join "; ")
            NotActions       = ($cr.NotActions -join "; ")
            DataActions      = ($cr.DataActions -join "; ")
            AssignableScopes = ($cr.AssignableScopes -join "; ")
        }
    }
    $crCsv = Join-Path $OutputDir "Custom_Role_Definitions.csv"
    $customRolesExport | Export-Csv -Path $crCsv -NoTypeInformation -Encoding utf8
    Write-Host "  ✅ Exported $($customRoles.Count) custom role definition(s) -> $crCsv" -ForegroundColor Green
} else {
    Write-Host "  No custom roles found in subscription." -ForegroundColor Gray
}

# 3. Export Key Vault Access Policies & Auth Modes
Write-Host "`n[3/5] Exporting Key Vault Access Policies & Auth Modes..." -ForegroundColor Cyan
$keyVaults = Get-AzKeyVault -ErrorAction SilentlyContinue
$kvPermissions = @()
if ($keyVaults) {
    foreach ($kv in $keyVaults) {
        $vaultObj = Get-AzKeyVault -VaultName $kv.VaultName -ResourceGroupName $kv.ResourceGroupName
        $rbacEnabled = $vaultObj.EnableRbacAuthorization -eq $true

        if ($rbacEnabled) {
            $kvPermissions += [PSCustomObject]@{
                VaultName       = $kv.VaultName
                ResourceGroup   = $kv.ResourceGroupName
                AuthModel       = "Azure RBAC"
                PrincipalId     = "Managed via Subscription/Vault RBAC"
                KeyPerms        = "RBAC"
                SecretPerms     = "RBAC"
                CertPerms       = "RBAC"
            }
        } else {
            foreach ($policy in $vaultObj.AccessPolicies) {
                $kvPermissions += [PSCustomObject]@{
                    VaultName       = $kv.VaultName
                    ResourceGroup   = $kv.ResourceGroupName
                    AuthModel       = "Access Policy"
                    PrincipalId     = $policy.ObjectId
                    KeyPerms        = ($policy.PermissionsToKeys -join "; ")
                    SecretPerms     = ($policy.PermissionsToSecrets -join "; ")
                    CertPerms       = ($policy.PermissionsToCertificates -join "; ")
                }
            }
        }
    }
    $kvCsv = Join-Path $OutputDir "KeyVault_Access_Policies.csv"
    $kvPermissions | Export-Csv -Path $kvCsv -NoTypeInformation -Encoding utf8
    Write-Host "  ✅ Exported $($kvPermissions.Count) Key Vault access policy entry/entries -> $kvCsv" -ForegroundColor Green
} else {
    Write-Host "  No Key Vaults found in subscription." -ForegroundColor Gray
}

# 4. Export Managed Identity Permissions
Write-Host "`n[4/5] Scanning Managed Identities & Held Permissions..." -ForegroundColor Cyan
$allResources = Get-AzResource -ExpandProperties -ErrorAction SilentlyContinue
$miPermissions = @()
foreach ($r in $allResources) {
    if ($r.Identity -and $r.Identity.PrincipalId) {
        $principalId = $r.Identity.PrincipalId
        $heldAssignments = Get-AzRoleAssignment -ObjectId $principalId -ErrorAction SilentlyContinue
        if ($heldAssignments) {
            foreach ($ha in $heldAssignments) {
                $miPermissions += [PSCustomObject]@{
                    ResourceName       = $r.Name
                    ResourceType       = $r.ResourceType
                    ResourceGroup      = $r.ResourceGroupName
                    PrincipalId        = $principalId
                    IdentityType       = $r.Identity.Type
                    RoleDefinitionName = $ha.RoleDefinitionName
                    Scope              = $ha.Scope
                }
            }
        }
    }
}
if ($miPermissions.Count -gt 0) {
    $miCsv = Join-Path $OutputDir "Managed_Identity_Permissions.csv"
    $miPermissions | Export-Csv -Path $miCsv -NoTypeInformation -Encoding utf8
    Write-Host "  ✅ Exported $($miPermissions.Count) role assignment(s) held by Managed Identities -> $miCsv" -ForegroundColor Green
} else {
    Write-Host "  No Managed Identity permissions discovered." -ForegroundColor Gray
}

# 5. Export Azure SQL Entra ID Administrators
Write-Host "`n[5/5] Checking Azure SQL Server Entra ID Administrators..." -ForegroundColor Cyan
$sqlServers = Get-AzSqlServer -ErrorAction SilentlyContinue
$sqlAdmins = @()
if ($sqlServers) {
    foreach ($server in $sqlServers) {
        try {
            $admin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.ServerName -ErrorAction SilentlyContinue
            if ($admin) {
                $sqlAdmins += [PSCustomObject]@{
                    ServerName    = $server.ServerName
                    ResourceGroup = $server.ResourceGroupName
                    DisplayName   = $admin.DisplayName
                    ObjectId      = $admin.ObjectId
                    SignInName    = $admin.Login
                }
            }
        } catch {}
    }
    if ($sqlAdmins.Count -gt 0) {
        $sqlCsv = Join-Path $OutputDir "SQL_EntraID_Admins.csv"
        $sqlAdmins | Export-Csv -Path $sqlCsv -NoTypeInformation -Encoding utf8
        Write-Host "  ✅ Exported $($sqlAdmins.Count) SQL Entra ID Admin(s) -> $sqlCsv" -ForegroundColor Green
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "All permission exports successfully generated in:" -ForegroundColor Green
Write-Host "  $OutputDir" -ForegroundColor Yellow
Write-Host "Next Step: Run 00-Planning/02-GenerateIdentityMappingTemplate.ps1" -ForegroundColor Cyan

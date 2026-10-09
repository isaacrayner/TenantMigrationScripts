<#
.SYNOPSIS
    Inventories all Managed Identities (System-Assigned & User-Assigned) and exports
    the RBAC permissions held BY those identities across the subscription.
.DESCRIPTION
    Captures ResourceId, IdentityType, PrincipalId, and all role assignments where
    the Managed Identity is the Assignee. Used by 4-DisableMIdentities, 4-A-RecreateMIdentities,
    and 5-RestoreRoleAssignments to automatically remap permissions after migration.
#>

param(
    [string]$SubscriptionId,
    [string]$OutputDir
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('OutputDir')) { $OutputDir = (Join-Path $backupRootDir "ManagedIdentities") }

Write-Host "=== Backing up Managed Identities & Permissions ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$resourcesWithMI = @()
$identityRoleAssignments = @()

Write-Host "Scanning all resources for Managed Identities..." -ForegroundColor Cyan
$allResources = Get-AzResource -ExpandProperties -ErrorAction Stop

foreach ($res in $allResources) {
    if ($res.Identity -and $res.Identity.Type -and $res.Identity.Type -ne "None") {
        $identType = $res.Identity.Type
        $principalId = $res.Identity.PrincipalId
        $tenantId = $res.Identity.TenantId

        # Parse user assigned identities dictionary
        $userAssignedIds = @()
        if ($res.Identity.UserAssignedIdentities) {
            $userAssignedIds = $res.Identity.UserAssignedIdentities.Keys
        }

        $miEntry = [PSCustomObject]@{
            ResourceName           = $res.Name
            ResourceId             = $res.ResourceId
            ResourceType           = $res.ResourceType
            ResourceGroupName      = $res.ResourceGroupName
            IdentityType           = $identType
            PrincipalId            = $principalId
            TenantId               = $tenantId
            UserAssignedIdentities = ($userAssignedIds -join ";")
        }

        $resourcesWithMI += $miEntry
        Write-Host "  Found [$identType] on $($res.ResourceType): $($res.Name) (PrincipalId: $principalId)" -ForegroundColor Green

        # Query all RBAC role assignments granted TO this identity (as assignee)
        if ($principalId) {
            try {
                $assignments = Get-AzRoleAssignment -ObjectId $principalId -ErrorAction SilentlyContinue
                if ($assignments) {
                    foreach ($a in $assignments) {
                        $identityRoleAssignments += [PSCustomObject]@{
                            ResourceName       = $res.Name
                            ResourceId         = $res.ResourceId
                            PrincipalId        = $principalId
                            RoleDefinitionName = $a.RoleDefinitionName
                            RoleDefinitionId   = $a.RoleDefinitionId
                            Scope              = $a.Scope
                            DisplayName        = $a.DisplayName
                        }
                    }
                }
            } catch {
                Write-Host "    ⚠️ Could not query role assignments for principal ${principalId}: $_" -ForegroundColor Yellow
            }
        }
    }
}

# Export resources
$resJson = Join-Path $OutputDir "ManagedIdentityResources.json"
$resCsv  = Join-Path $OutputDir "ManagedIdentityResources.csv"
$resourcesWithMI | ConvertTo-Json -Depth 5 | Out-File -FilePath $resJson -Encoding utf8
$resourcesWithMI | Export-Csv -Path $resCsv -NoTypeInformation -Encoding utf8

# Export permissions
$rolesJson = Join-Path $OutputDir "ManagedIdentityRoleAssignments.json"
$rolesCsv  = Join-Path $OutputDir "ManagedIdentityRoleAssignments.csv"
$identityRoleAssignments | ConvertTo-Json -Depth 5 | Out-File -FilePath $rolesJson -Encoding utf8
$identityRoleAssignments | Export-Csv -Path $rolesCsv -NoTypeInformation -Encoding utf8

Write-Host "`n✅ Managed Identity inventory completed!" -ForegroundColor Green
Write-Host "Total Resources with Managed Identities: $($resourcesWithMI.Count)" -ForegroundColor Cyan
Write-Host "Total Role Assignments held by MIs     : $($identityRoleAssignments.Count)" -ForegroundColor Cyan
Write-Host "Files saved in: $OutputDir" -ForegroundColor Cyan

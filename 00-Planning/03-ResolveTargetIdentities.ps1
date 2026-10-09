<#
.SYNOPSIS
    Planning Stage: Resolves and validates target identities in the Destination Tenant.
.DESCRIPTION
    Connects to the destination Microsoft Entra ID tenant, reads Identity_Mapping_Plan.csv,
    and automatically queries Entra ID to populate TargetObjectIds for users, groups,
    and service principals. Flags any missing accounts that must be created or invited.
#>

param(
    [string]$TargetTenantId,
    [string]$PlanCsv
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('TargetTenantId')) { $TargetTenantId = $destinationTenantId }
if (-not $PSBoundParameters.ContainsKey('PlanCsv')) { $PlanCsv = (Join-Path $backupRootDir "Planning/Identity_Mapping_Plan.csv") }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    PLANNING STAGE: RESOLVE DESTINATION TENANT IDENTITIES " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $PlanCsv)) {
    Write-Host "Plan CSV not found at $PlanCsv. Run 00-Planning/02-GenerateIdentityMappingTemplate.ps1 first." -ForegroundColor Red
    exit 1
}

if (-not $TargetTenantId) {
    Write-Host "Destination tenant ID not set. For same-tenant moves, identities resolve automatically." -ForegroundColor Green
    exit 0
}

Write-Host "Connecting to Destination Tenant: $TargetTenantId..." -ForegroundColor Cyan
Connect-AzAccount -TenantId $TargetTenantId | Out-Null

$plan = Import-Csv -Path $PlanCsv
$resolvedCount = 0
$missingCount = 0

foreach ($row in $plan) {
    # If already has a target ID, verify existence
    $lookupName = if ($row.TargetSignInName) { $row.TargetSignInName } else { $row.SourceSignInName }

    Write-Host "Validating $($row.PrincipalType): '$lookupName'..." -ForegroundColor Yellow

    try {
        switch ($row.PrincipalType) {
            "User" {
                $user = Get-AzADUser -UserPrincipalName $lookupName -ErrorAction SilentlyContinue
                if (-not $user) {
                    $user = Get-AzADUser -Mail $lookupName -ErrorAction SilentlyContinue
                }
                if ($user) {
                    $row.TargetObjectId = $user.Id
                    $row.MappingStatus  = "RESOLVED"
                    Write-Host "  ✅ Found User: $($user.DisplayName) (Id: $($user.Id))" -ForegroundColor Green
                    $resolvedCount++
                } else {
                    $row.MappingStatus = "NOT_FOUND_IN_TARGET"
                    Write-Host "  ❌ User not found in destination tenant: $lookupName" -ForegroundColor Red
                    $missingCount++
                }
            }
            "Group" {
                $group = Get-AzADGroup -DisplayName $row.SourceDisplayName -ErrorAction SilentlyContinue
                if ($group) {
                    $row.TargetObjectId = $group.Id
                    $row.MappingStatus  = "RESOLVED"
                    Write-Host "  ✅ Found Group: $($group.DisplayName) (Id: $($group.Id))" -ForegroundColor Green
                    $resolvedCount++
                } else {
                    $row.MappingStatus = "NOT_FOUND_IN_TARGET"
                    Write-Host "  ❌ Group not found in destination tenant: $($row.SourceDisplayName)" -ForegroundColor Red
                    $missingCount++
                }
            }
            "ServicePrincipal" {
                $sp = Get-AzADServicePrincipal -DisplayName $row.SourceDisplayName -ErrorAction SilentlyContinue
                if ($sp) {
                    $row.TargetObjectId = $sp.Id
                    $row.MappingStatus  = "RESOLVED"
                    Write-Host "  ✅ Found Service Principal: $($sp.DisplayName) (Id: $($sp.Id))" -ForegroundColor Green
                    $resolvedCount++
                } else {
                    $row.MappingStatus = "NOT_FOUND_IN_TARGET"
                    Write-Host "  ❌ Service Principal not found: $($row.SourceDisplayName)" -ForegroundColor Red
                    $missingCount++
                }
            }
            Default {
                $row.MappingStatus = "MANUAL_REVIEW"
            }
        }
    } catch {
        Write-Host "  ⚠️ Error resolving ${lookupName}: $_" -ForegroundColor Red
        $row.MappingStatus = "ERROR"
    }
}

$plan | Export-Csv -Path $PlanCsv -NoTypeInformation -Encoding utf8

Write-Host "`n=================== RESOLUTION SUMMARY ===================" -ForegroundColor Cyan
Write-Host "Successfully Resolved in Target Tenant : $resolvedCount" -ForegroundColor Green
Write-Host "Missing / Action Required in Target    : $missingCount" -ForegroundColor $(if ($missingCount -gt 0) { "Red" } else { "Green" })
Write-Host "Updated Plan CSV Saved To              : $PlanCsv" -ForegroundColor Yellow

if ($missingCount -gt 0) {
    Write-Host "`n⚠️ Before migration, invite or create the missing users/groups in the destination tenant." -ForegroundColor Yellow
}

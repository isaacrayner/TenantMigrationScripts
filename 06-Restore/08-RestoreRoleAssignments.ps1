<#
.SYNOPSIS
    Restores RBAC role assignments in the destination subscription from the JSON backup.
.DESCRIPTION
    1. Rewrites scope paths to the destination subscription ID.
    2. Translates Old System-Assigned Managed Identity IDs to New IDs using NewManagedIdentitiesMapping.json.
    3. Translates Old User/Group/ServicePrincipal IDs to Target Tenant IDs using Identity_Mapping_Plan.csv (for cross-tenant moves).
    4. Applies role assignments idempotently in the destination subscription.
#>

param(
    [string]$SubscriptionId,
    [string]$BackupJson,
    [string]$MappingFile,
    [string]$IdentityPlanCsv
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $destinationSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('BackupJson')) { $BackupJson = (Join-Path $backupRootDir "RBAC_Assignments.json") }
if (-not $PSBoundParameters.ContainsKey('MappingFile')) { $MappingFile = (Join-Path $backupRootDir "ManagedIdentities/NewManagedIdentitiesMapping.json") }
if (-not $PSBoundParameters.ContainsKey('IdentityPlanCsv')) { $IdentityPlanCsv = (Join-Path $backupRootDir "Planning/Identity_Mapping_Plan.csv") }

$logFile = Join-Path $logRootDir "RBAC_Restore.log"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$level] $message"
    Write-Host $line -ForegroundColor $(if ($level -eq "ERROR") { "Red" } elseif ($level -eq "WARN") { "Yellow" } else { "Cyan" })
    Add-Content -Path $logFile -Value $line
}

if (-not (Test-Path $BackupJson)) {
    # Check alternate planning path
    $altJson = Join-Path $backupRootDir "Planning/Master_RBAC_Assignments.json"
    if (Test-Path $altJson) {
        $BackupJson = $altJson
    } else {
        Write-Log "Backup file not found: $BackupJson. Run 03-Backup/03-BackupRoleAssignments.ps1 or 00-Planning/01-ExportAllPermissions.ps1 first." "ERROR"
        exit 1
    }
}

Write-Log "=== Restoring RBAC Role Assignments ==="
Write-Log "Source Subscription     : $sourceSubscriptionId"
Write-Log "Destination Subscription: $SubscriptionId"

# Master translation mapping
$idMap = @{}

# 1. Load System Managed Identity translation
if (Test-Path $MappingFile) {
    $mappings = Get-Content $MappingFile -Raw | ConvertFrom-Json
    foreach ($m in $mappings) {
        if ($m.OldPrincipalId -and $m.NewPrincipalId) {
            $idMap[$m.OldPrincipalId] = $m.NewPrincipalId
        }
    }
    Write-Log "Loaded $($mappings.Count) Managed Identity PrincipalId translation mappings." "SUCCESS"
}

# 2. Load Cross-Tenant Identity Plan mapping (Users, Groups, SPs)
if (Test-Path $IdentityPlanCsv) {
    $planEntries = Import-Csv -Path $IdentityPlanCsv
    $planCount = 0
    foreach ($p in $planEntries) {
        if ($p.SourceObjectId -and $p.TargetObjectId -and $p.TargetObjectId -ne $p.SourceObjectId) {
            $idMap[$p.SourceObjectId] = $p.TargetObjectId
            $planCount++
        }
    }
    if ($planCount -gt 0) {
        Write-Log "Loaded $planCount Cross-Tenant PrincipalId translation mappings from Identity Planning Plan." "SUCCESS"
    }
}

# Set context to destination
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

$assignments = Get-Content $BackupJson -Raw | ConvertFrom-Json
$counts = @{ Total = 0; Skipped = 0; Applied = 0; Failed = 0; Remapped = 0 }

foreach ($a in $assignments) {
    $counts.Total++
    $originalScope = $a.Scope
    $role          = $a.RoleDefinitionName
    $displayName   = $a.DisplayName
    $objectId      = $a.ObjectId
    $principalType = $a.ObjectType

    # Rewrite scope: swap old sub ID for new sub ID
    $newScope = $originalScope -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId

    # Skip scopes outside subscription
    if ($newScope -notmatch "^/subscriptions/$destinationSubscriptionId") {
        Write-Log "SKIP [$role] '$displayName' — scope outside target subscription: $originalScope" "WARN"
        $counts.Skipped++
        continue
    }

    # Check if ObjectId should be translated via Managed Identity mapping or Identity Plan
    if ($idMap.ContainsKey($objectId)) {
        $translatedId = $idMap[$objectId]
        Write-Log "REMAPPING: Principal '$displayName' ($objectId -> $translatedId)" "INFO"
        $objectId = $translatedId
        $counts.Remapped++
    }

    # Apply assignment
    try {
        $existing = Get-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName $role -Scope $newScope -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "SKIP [$role] '$displayName' at '$newScope' — already exists." "WARN"
            $counts.Skipped++
            continue
        }

        New-AzRoleAssignment `
            -ObjectId           $objectId `
            -RoleDefinitionName $role `
            -Scope              $newScope `
            -ErrorAction        Stop | Out-Null

        Write-Log "OK   [$role] '$displayName' ($principalType) at '$newScope'" "SUCCESS"
        $counts.Applied++

    } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match "PrincipalNotFound") {
            Write-Log "FAIL [$role] '$displayName' ($objectId) — PrincipalNotFound. If this is a cross-tenant move, ensure target principal exists and is mapped in 0-Planning/Identity_Mapping_Plan.csv." "ERROR"
        } elseif ($errMsg -match "RoleAssignmentExists") {
            Write-Log "SKIP [$role] '$displayName' — already exists." "WARN"
            $counts.Skipped++
        } else {
            Write-Log "FAIL [$role] '$displayName' at '$newScope' — $errMsg" "ERROR"
        }
        $counts.Failed++
    }
}

Write-Log "`n=== Restore Summary ==="
Write-Log "Total in backup : $($counts.Total)"
Write-Log "Applied         : $($counts.Applied)"
Write-Log "Remapped (Auto) : $($counts.Remapped)"
Write-Log "Skipped         : $($counts.Skipped)"
Write-Log "Failed          : $($counts.Failed)"
Write-Log "Log file        : $logFile"

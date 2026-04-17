## DESCRIPTION: Restores RBAC role assignments in the destination subscription from the JSON
##              backup produced by 3-MigrationPrep/4-ListRoleAssignmentsv2.ps1.
##              Rewrites all scope paths to the destination subscription ID.
##              Skips assignments that cannot be recreated (managed identity system principals,
##              out-of-subscription scopes, and principals that no longer exist).
## USAGE:       1. Run 3-MigrationPrep/4-ListRoleAssignmentsv2.ps1 first to produce the backup.
##              2. For cross-tenant migrations: ensure you are logged in to the destination
##                 tenant before running (Connect-AzAccount -TenantId <destTenantId>).
##              3. Managed identities get new ObjectIds after recreation — run
##                 7-Recreation/4-A-RecreateMIdentities.ps1 first, then reassign their roles
##                 manually using the CSV from 3-MigrationPrep/11-BackupIdentities.ps1.
##              4. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

$backupJson = "C:\temp\RBAC_Assignments.json"
$logFile    = "C:\temp\RBAC_Restore.log"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$level] $message"
    Write-Host $line -ForegroundColor $(if ($level -eq "ERROR") { "Red" } elseif ($level -eq "WARN") { "Yellow" } else { "Cyan" })
    Add-Content -Path $logFile -Value $line
}

# ── Validate backup file ───────────────────────────────────────────────────────
if (-not (Test-Path $backupJson)) {
    Write-Log "Backup file not found: $backupJson" "ERROR"
    Write-Log "Run 3-MigrationPrep/4-ListRoleAssignmentsv2.ps1 first." "ERROR"
    exit 1
}

Write-Log "=== RBAC Role Assignment Restore ==="
Write-Log "Source subscription : $sourceSubscriptionId"
Write-Log "Destination sub     : $destinationSubscriptionId"
Write-Log "Backup file         : $backupJson"

Write-Log "NOTE: System-assigned managed identity role assignments will fail with PrincipalNotFound — this is expected." "WARN"
Write-Log "      After running 7-Recreation/4-A-RecreateMIdentities.ps1, reassign those roles manually using" "WARN"
Write-Log "      the ObjectIds shown in the new subscription (Get-AzVM | Select Name, Identity)." "WARN"

# ── Set context to destination ─────────────────────────────────────────────────
try {
    Set-AzContext -Subscription $destinationSubscriptionId -ErrorAction Stop | Out-Null
    Write-Log "Context set to destination subscription."
} catch {
    Write-Log "Failed to set subscription context: $_" "ERROR"
    exit 1
}

# ── Load and process backup ────────────────────────────────────────────────────
$assignments = Get-Content $backupJson -Raw | ConvertFrom-Json

$counts = @{ Total = 0; Skipped = 0; Applied = 0; Failed = 0 }

foreach ($a in $assignments) {
    $counts.Total++

    $originalScope = $a.Scope
    $role          = $a.RoleDefinitionName
    $displayName   = $a.DisplayName
    $objectId      = $a.ObjectId
    $principalType = $a.ObjectType   # User, Group, ServicePrincipal

    # ── Rewrite scope: swap old sub ID for new sub ID ─────────────────────────
    $newScope = $originalScope -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId

    # ── Skip: scope is outside the subscription (management group, tenant root) ─
    if ($newScope -notmatch "^/subscriptions/$destinationSubscriptionId") {
        Write-Log "SKIP [$role] '$displayName' — scope outside target subscription: $originalScope" "WARN"
        $counts.Skipped++
        continue
    }

    # ── Apply the assignment ───────────────────────────────────────────────────
    try {
        # Idempotency check — skip if assignment already exists
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

        Write-Log "OK   [$role] '$displayName' ($principalType) at '$newScope'"
        $counts.Applied++

    } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match "PrincipalNotFound") {
            Write-Log "FAIL [$role] '$displayName' ($objectId) — principal not found. If this is a system-assigned managed identity, its ObjectId changed after recreation. Reassign manually once MIs are re-enabled." "ERROR"
        } elseif ($errMsg -match "RoleAssignmentExists") {
            Write-Log "SKIP [$role] '$displayName' — assignment already exists." "WARN"
            $counts.Skipped++
            $counts.Failed--   # don't count as failure
        } else {
            Write-Log "FAIL [$role] '$displayName' at '$newScope' — $errMsg" "ERROR"
        }
        $counts.Failed++
    }
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Log ""
Write-Log "=== Restore Summary ==="
Write-Log "Total assignments in backup : $($counts.Total)"
Write-Log "Applied                     : $($counts.Applied)"
Write-Log "Skipped                     : $($counts.Skipped)"
Write-Log "Failed                      : $($counts.Failed)"
Write-Log "Log file                    : $logFile"

if ($counts.Failed -gt 0) {
    Write-Log "Some assignments failed. Review the log and reassign manually." "WARN"
    exit 1
}

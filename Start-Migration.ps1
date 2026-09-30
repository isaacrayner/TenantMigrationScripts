<#
.SYNOPSIS
    Interactive Orchestrator for Azure Subscription & Tenant Migration.
.DESCRIPTION
    Provides a guided, state-aware workflow that automatically inspects
    migration-data to detect completed phases and suggest the next recommended action.
#>

$paramsPath = Join-Path $PSScriptRoot "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

function Get-PhaseState {
    $state = @{
        PhaseP = "PENDING"
        Phase0 = "PENDING"
        Phase1 = "PENDING"
        Phase2 = "PENDING"
        Phase3 = "PENDING"
        Phase4 = "PENDING"
        Phase5 = "PENDING"
        Next   = "P"
    }

    # Phase P check
    if (Test-Path (Join-Path $backupRootDir "Planning/Master_RBAC_Assignments.json")) {
        $state.PhaseP = "DONE"
        $state.Next = "0"
    }

    # Phase 0 check
    if (Test-Path (Join-Path $backupRootDir "PreMigration_Blocker_Report.json")) {
        $state.Phase0 = "DONE"
        if ($state.Next -eq "0") { $state.Next = "1" }
    }

    # Phase 2 Backup check
    if ((Test-Path (Join-Path $backupRootDir "RBAC_Assignments.json")) -and 
        (Test-Path (Join-Path $backupRootDir "ResourceLocks_Backup.json"))) {
        $state.Phase2 = "DONE"
        if ($state.Phase1 -eq "PENDING") { $state.Phase1 = "DONE" }
        if ($state.Next -eq "1" -or $state.Next -eq "2") { $state.Next = "3" }
    }

    # Phase 3 Cleanup check
    if (Test-Path (Join-Path $backupRootDir "public_ips_associations.json")) {
        $state.Phase3 = "DONE"
        if ($state.Next -eq "3") { $state.Next = "4" }
    }

    # Phase 5 Restore check
    if (Test-Path (Join-Path $backupRootDir "ManagedIdentities/NewManagedIdentitiesMapping.json")) {
        $state.Phase4 = "DONE"
        $state.Phase5 = "IN_PROGRESS"
        $state.Next = "5"
    }

    return $state
}

function Show-Header {
    param($state)
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "         AZURE TENANT & SUBSCRIPTION MIGRATION ORCHESTRATOR      " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "Source Tenant ID      : $sourceTenantId" -ForegroundColor Yellow
    Write-Host "Destination Tenant ID : $(if ($destinationTenantId) { $destinationTenantId } else { '(Same Tenant Move)' })" -ForegroundColor Yellow
    Write-Host "Source Subscription   : $sourceSubscriptionId" -ForegroundColor Yellow
    Write-Host "Destination Sub       : $(if ($destinationSubscriptionId) { $destinationSubscriptionId } else { '(Not Set)' })" -ForegroundColor Yellow
    Write-Host "Data Directory        : $backupRootDir" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

    # Display Next Recommended Step
    $nextLabel = switch ($state.Next) {
        "P" { "[P] Planning Stage: Export Permissions & Identity Mapping" }
        "0" { "[0] Pre-Flight: Blocker Discovery Scanner" }
        "1" { "[1] Phase 1: Prepare Destination Subscription" }
        "2" { "[2] Phase 2: Full Backup of Source Subscription" }
        "3" { "[3] Phase 3: Pre-Migration Cleanup & Disassociations" }
        "4" { "[4] Phase 4: Validate & Execute Migration" }
        "5" { "[5] Phase 5: Recreate & Restore Destination Environment" }
        Default { "Review Logs & Verification" }
    }
    Write-Host ">>> NEXT RECOMMENDED STEP: $nextLabel" -ForegroundColor Green
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
}

function Open-Dashboard {
    $dashFile = Join-Path $PSScriptRoot "dashboard.html"
    Write-Host "Opening Migration Dashboard in browser: $dashFile..." -ForegroundColor Cyan
    if ($IsWindows -or ($env:OS -match "Windows")) {
        Start-Process $dashFile
    } elseif ($IsMacOS) {
        Start-Process "open" -ArgumentList $dashFile
    } else {
        Start-Process "xdg-open" -ArgumentList $dashFile -ErrorAction SilentlyContinue
    }
}

function Format-Tag($status) {
    switch ($status) {
        "DONE"        { return "[COMPLETED]  " }
        "IN_PROGRESS" { return "[IN PROGRESS]" }
        Default       { return "[PENDING]    " }
    }
}

function Color-Tag($status) {
    switch ($status) {
        "DONE"        { return "Green" }
        "IN_PROGRESS" { return "Yellow" }
        Default       { return "Gray" }
    }
}

function Run-PhasePlanning {
    Write-Host "`n>>> Running Phase 0: Planning & Permission Assessment..." -ForegroundColor Cyan
    Write-Host "Select Planning Action:" -ForegroundColor Yellow
    Write-Host "  [1] Export ALL Permissions (RBAC, Custom Roles, Key Vault, MIs, SQL)"
    Write-Host "  [2] Generate Identity Mapping Plan (Template for target tenant)"
    Write-Host "  [3] Resolve & Validate Target Tenant Identities (Entra ID lookup)"
    Write-Host "  [4] Compare Compute Quotas (vCPU core limits vs destination)"
    Write-Host "  [5] Run All Planning Steps"
    $opt = Read-Host "Choice"
    switch ($opt) {
        "1" { & (Join-Path $PSScriptRoot "0-Planning/1-ExportAllPermissions.ps1") }
        "2" { & (Join-Path $PSScriptRoot "0-Planning/2-GenerateIdentityMappingTemplate.ps1") }
        "3" { & (Join-Path $PSScriptRoot "0-Planning/3-ResolveTargetIdentities.ps1") }
        "4" { & (Join-Path $PSScriptRoot "0-Planning/4-CompareSubscriptionQuotas.ps1") }
        "5" {
            & (Join-Path $PSScriptRoot "0-Planning/1-ExportAllPermissions.ps1")
            & (Join-Path $PSScriptRoot "0-Planning/2-GenerateIdentityMappingTemplate.ps1")
            if ($destinationTenantId) {
                & (Join-Path $PSScriptRoot "0-Planning/3-ResolveTargetIdentities.ps1")
            }
            if ($destinationSubscriptionId) {
                & (Join-Path $PSScriptRoot "0-Planning/4-CompareSubscriptionQuotas.ps1")
            }
        }
    }
}

function Run-PhaseBlockers {
    Write-Host "`n>>> Running Pre-Flight Blocker Discovery..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "1-InitialReview/2-CheckMigrationBlockers.ps1")
    & (Join-Path $PSScriptRoot "1-InitialReview/1-CheckVMDiskEncryption.ps1")
}

function Run-Phase1 {
    Write-Host "`n>>> Running Phase 1: Prepare Destination Subscription..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "3-MigrationPrep/2-RegisterResources.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/3-ResourceGroups.ps1")
}

function Run-Phase2 {
    Write-Host "`n>>> Running Phase 2: Full Backup of Source Subscription..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "3-MigrationPrep/0-BackupAndRemoveResourceLocks.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/4-BackupCustomRoles.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/4-ListRoleAssignmentsv2.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/11-BackupIdentities.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/5-BackupPublicIPs.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/6-BackupActionGroups.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/9-BackupDiagSettings.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/13-BackupVMBackupSettings.ps1")
    & (Join-Path $PSScriptRoot "3-MigrationPrep/16-BackupAppGateways.ps1")
    & (Join-Path $PSScriptRoot "5-VNETPeerings/1.Export-VNETs.ps1")
    if (Get-Command "bash" -ErrorAction SilentlyContinue) {
        bash (Join-Path $PSScriptRoot "3-MigrationPrep/10-BackupPrivateEndpoints.azcli")
        bash (Join-Path $PSScriptRoot "3-MigrationPrep/12-BackupAccessPolicies.azcli")
        bash (Join-Path $PSScriptRoot "3-MigrationPrep/14-BackupSABackupSettings.azcli")
        bash (Join-Path $PSScriptRoot "3-MigrationPrep/15-BackupNATsettings.azcli")
        bash (Join-Path $PSScriptRoot "3-MigrationPrep/7-ExportSSHKeys.azcli")
        bash (Join-Path $PSScriptRoot "3-MigrationPrep/8-BackupMetricAlerts.azcli")
    }
    Write-Host "`n✅ Phase 2 Backup Complete! Data stored in $backupRootDir" -ForegroundColor Green
}

function Run-Phase3 {
    Write-Host "`n>>> Running Phase 3: Pre-Migration Deletions & Disassociations..." -ForegroundColor Cyan
    Write-Host "WARNING: This will disable backups, identities, and disconnect peerings." -ForegroundColor Red
    $conf = Read-Host "Type YES to proceed with Phase 3"
    if ($conf -ne "YES") { return }

    & (Join-Path $PSScriptRoot "4-Deletions/5-DisableBackups.ps1")
    & (Join-Path $PSScriptRoot "4-Deletions/4-DisableMIdentities.ps1")
    & (Join-Path $PSScriptRoot "4-Deletions/7-UnbindAppServiceCertificates.ps1")
    & (Join-Path $PSScriptRoot "5-VNETPeerings/2.DeleteVNETs.ps1")
    if (Get-Command "bash" -ErrorAction SilentlyContinue) {
        bash (Join-Path $PSScriptRoot "4-Deletions/1-PublicIPdiss.azcli")
        bash (Join-Path $PSScriptRoot "4-Deletions/3-PrivateEndpoints.azcli")
        bash (Join-Path $PSScriptRoot "4-Deletions/6-DisableSABackups.azcli")
    }
    Write-Host "`n✅ Phase 3 Cleanup Complete! Resources are now in a moveable state." -ForegroundColor Green
}

function Run-Phase4 {
    Write-Host "`n>>> Running Phase 4: Migration Execution..." -ForegroundColor Cyan
    Write-Host "Select Migration Method:" -ForegroundColor Yellow
    Write-Host "  [1] Validate Resource Group Move (Same Tenant Sub-to-Sub)"
    Write-Host "  [2] Move Resource Group (Same Tenant Sub-to-Sub)"
    Write-Host "  [3] Transfer Entire Subscription to New Tenant Directory"
    $m = Read-Host "Choice"
    switch ($m) {
        "1" { & (Join-Path $PSScriptRoot "6-MIGRATION/1-ValidateRGMove.ps1") -AllResourceGroups }
        "2" { & (Join-Path $PSScriptRoot "6-MIGRATION/2-MigrateRG.ps1") }
        "3" { & (Join-Path $PSScriptRoot "6-MIGRATION/4-TransferSubscriptionDirectory.ps1") }
    }
}

function Run-Phase5 {
    Write-Host "`n>>> Running Phase 5: Recreate & Restore Destination Environment..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "5-VNETPeerings/3.RecreatePeerings.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/5-RestoreCustomRoles.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/4-A-RecreateMIdentities.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/4-B-RestoreKeyVaultAccess.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/5-RestoreRoleAssignments.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/7-RestoreActionGroups.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/8-VMBackups.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/10-RestoreDiagSettings.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/11-RestoreAppGateways.ps1")
    & (Join-Path $PSScriptRoot "7-Recreation/0-RestoreResourceLocks.ps1")
    if (Get-Command "bash" -ErrorAction SilentlyContinue) {
        bash (Join-Path $PSScriptRoot "7-Recreation/1-PublicIPass.azcli")
        bash (Join-Path $PSScriptRoot "7-Recreation/2-KeyVault.azcli")
        bash (Join-Path $PSScriptRoot "7-Recreation/3-PrivateEndpoints.azcli")
        bash (Join-Path $PSScriptRoot "7-Recreation/6-NATGateway.azcli")
        bash (Join-Path $PSScriptRoot "7-Recreation/7-RestoreSSHKeys.sh")
        bash (Join-Path $PSScriptRoot "7-Recreation/9-SABackups.azcli")
        bash (Join-Path $PSScriptRoot "7-Recreation/MetricAlerts.azcli")
    }
    Write-Host "`n✅ Phase 5 Restoration Complete!" -ForegroundColor Green
}

while ($true) {
    $st = Get-PhaseState
    Show-Header -state $st

    Write-Host "MIGRATION PHASES (State-Aware):" -ForegroundColor White
    Write-Host "  $(Format-Tag $st.PhaseP) [P] Planning Stage: Export Permissions & Identity Mapping" -ForegroundColor $(Color-Tag $st.PhaseP)
    Write-Host "  $(Format-Tag $st.Phase0) [0] Pre-Flight: Blocker Discovery & Disk Encryption Scanner" -ForegroundColor $(Color-Tag $st.Phase0)
    Write-Host "  $(Format-Tag $st.Phase1) [1] Phase 1 - Prepare Destination Subscription" -ForegroundColor $(Color-Tag $st.Phase1)
    Write-Host "  $(Format-Tag $st.Phase2) [2] Phase 2 - Back Up Everything (Source Subscription)" -ForegroundColor $(Color-Tag $st.Phase2)
    Write-Host "  $(Format-Tag $st.Phase3) [3] Phase 3 - Pre-Migration Cleanup (Disassociations & Deletions)" -ForegroundColor $(Color-Tag $st.Phase3)
    Write-Host "  $(Format-Tag $st.Phase4) [4] Phase 4 - Validate & Execute Migration" -ForegroundColor $(Color-Tag $st.Phase4)
    Write-Host "  $(Format-Tag $st.Phase5) [5] Phase 5 - Recreate & Restore (Destination Subscription)" -ForegroundColor $(Color-Tag $st.Phase5)
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  [G] Open Visual Web Dashboard (GUI in browser)" -ForegroundColor Cyan
    Write-Host "  [Q] Quit"
    Write-Host ""
    $choice = Read-Host "Select an option (Press Enter for recommended: $($st.Next))"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $st.Next
    }

    switch ($choice.ToUpper()) {
        "P" { Run-PhasePlanning; Pause }
        "0" { Run-PhaseBlockers; Pause }
        "1" { Run-Phase1; Pause }
        "2" { Run-Phase2; Pause }
        "3" { Run-Phase3; Pause }
        "4" { Run-Phase4; Pause }
        "5" { Run-Phase5; Pause }
        "G" { Open-Dashboard; Pause }
        "Q" { Write-Host "Exiting."; exit 0 }
        Default { Write-Host "Invalid option." -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}

<#
.SYNOPSIS
    Interactive, state-aware orchestrator for an Azure subscription / tenant migration.
.DESCRIPTION
    Phases map 1:1 to the numbered folders in this repository (00-Planning ... 06-Restore).
    The menu inspects ./migration-data to work out which phases are complete and recommends
    the next one. Pressing Enter runs the recommended phase; choosing a phase runs every
    default script in that folder in numeric order, or lets you pick a single script.
.PARAMETER Phase
    Run one phase non-interactively (0-6) and exit. Destructive phases still ask for YES
    unless -Force is given.
.PARAMETER Setup
    Create the untracked migration-params.local.ps1 / .sh files, then exit.
.PARAMETER Force
    Skip the YES confirmation on destructive phases (4 - Cleanup, 5 - Migrate).
.EXAMPLE
    ./Start-Migration.ps1                 # interactive menu
.EXAMPLE
    ./Start-Migration.ps1 -Phase 3        # run every default Backup script
#>
[CmdletBinding()]
param(
    [ValidateRange(-1, 6)][int]$Phase = -1,
    [switch]$Setup,
    [switch]$Force
)

$paramsPath = Join-Path $PSScriptRoot "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

$ZeroGuid = "00000000-0000-0000-0000-000000000000"

# ── Phase catalogue ───────────────────────────────────────────────────────────
# Mode  All  : Enter runs every default script in order.
#       Pick : scripts are alternatives (e.g. same-tenant move vs directory transfer), choose one.
# Optional scripts are skipped by "run all" but can still be picked individually.
# Requires: a script that only makes sense when a config value is set.
$Phases = @(
    @{ Id = 0; Folder = "00-Planning";           Mode = "All";  Destructive = $false
       Title = "Planning: export permissions, map identities, compare quotas"
       Optional = @("05-ExportPrincipalInventory.ps1")
       Requires = @{ "03-ResolveTargetIdentities.ps1" = { $destinationTenantId }
                     "04-CompareSubscriptionQuotas.ps1" = { $destinationSubscriptionId } } },
    @{ Id = 1; Folder = "01-Preflight";          Mode = "All";  Destructive = $false
       Title = "Pre-flight: find migration blockers and encrypted disks"
       Optional = @("03-GrantCspForeignPrincipal.ps1") },
    @{ Id = 2; Folder = "02-PrepareDestination"; Mode = "All";  Destructive = $false
       Title = "Prepare destination: sync resource providers, create resource groups"
       Requires = @{ "01-SyncResourceProviders.ps1" = { $destinationSubscriptionId }
                     "02-CreateResourceGroups.ps1"  = { $destinationSubscriptionId } } },
    @{ Id = 3; Folder = "03-Backup";             Mode = "All";  Destructive = $false
       Title = "Backup: snapshot RBAC, identities, networking, backups, alerts, ARM templates"
       Optional = @("18-ExportArmTemplatesByResource.ps1", "19-UploadArmTemplatesToBlob.ps1") },
    @{ Id = 4; Folder = "04-Cleanup";            Mode = "All";  Destructive = $true
       Title = "Cleanup: disable backups, detach identities, delete peerings and endpoints"
       Optional = @("08-DeleteBlockingResources.ps1") },
    @{ Id = 5; Folder = "05-Migrate";            Mode = "Pick"; Destructive = $true
       Title = "Migrate: validate and move resource groups, or transfer the directory" },
    @{ Id = 6; Folder = "06-Restore";            Mode = "All";  Destructive = $false
       Title = "Restore: recreate everything in the destination, remapping identities"
       Optional = @("19-DeployArmTemplate.ps1") }
)

# ── State ─────────────────────────────────────────────────────────────────────
function Get-PhaseState {
    $has = { param($rel) Test-Path (Join-Path $backupRootDir $rel) }
    $backedUp = (& $has "RBAC_Assignments.json") -and (& $has "ResourceLocks_Backup.json")
    $status = @{
        0 = if (& $has "Planning/Master_RBAC_Assignments.json") { "DONE" } else { "PENDING" }
        1 = if (& $has "PreMigration_Blocker_Report.json")      { "DONE" } else { "PENDING" }
        2 = if ($backedUp)                                       { "DONE" } else { "PENDING" }
        3 = if ($backedUp)                                       { "DONE" } else { "PENDING" }
        4 = if (& $has "public_ips_associations.json")           { "DONE" } else { "PENDING" }
        5 = "PENDING"
        6 = "PENDING"
    }
    if (& $has "ManagedIdentities/NewManagedIdentitiesMapping.json") {
        $status[5] = "DONE"
        $status[6] = "IN_PROGRESS"
    }
    $next = 0..6 | Where-Object { $status[$_] -ne "DONE" } | Select-Object -First 1
    [pscustomobject]@{ Status = $status; Next = $next }
}

function Test-IsPlaceholder($value) { [string]::IsNullOrWhiteSpace($value) -or $value -eq $ZeroGuid }

# ── First-run setup ───────────────────────────────────────────────────────────
function Invoke-Setup {
    Write-Host "`nFirst-run setup: values are written to untracked local files (git-ignored)." -ForegroundColor Cyan
    $st = Read-Host "Source tenant ID"
    $ss = Read-Host "Source subscription ID"
    $dt = Read-Host "Destination tenant ID (Enter = same tenant)"
    $ds = Read-Host "Destination subscription ID (Enter = decide later)"

    @(
        "# Local overrides - untracked. Generated by Start-Migration.ps1 -Setup",
        "`$sourceTenantId            = `"$st`"",
        "`$destinationTenantId       = `"$dt`"",
        "`$sourceSubscriptionId      = `"$ss`"",
        "`$destinationSubscriptionId = `"$ds`""
    ) | Set-Content -Path (Join-Path $PSScriptRoot "migration-params.local.ps1") -Encoding utf8

    @(
        "# Local overrides - untracked. Generated by Start-Migration.ps1 -Setup",
        "SOURCE_TENANT_ID=`"$st`"",
        "DESTINATION_TENANT_ID=`"$dt`"",
        "SOURCE_SUBSCRIPTION_ID=`"$ss`"",
        "DESTINATION_SUBSCRIPTION_ID=`"$ds`""
    ) | Set-Content -Path (Join-Path $PSScriptRoot "migration-params.local.sh") -Encoding utf8NoBOM

    . $paramsPath
    Write-Host "Saved migration-params.local.ps1 and migration-params.local.sh" -ForegroundColor Green
}

function Test-Prerequisites {
    $missing = @()
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { $missing += "Az PowerShell module  (Install-Module Az -Scope CurrentUser)" }
    if (-not (Get-Command az   -ErrorAction SilentlyContinue)) { $missing += "Azure CLI 'az'        (https://aka.ms/installazurecli)" }
    if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { $missing += "bash                  (needed for the .sh scripts; use WSL on Windows)" }
    if (-not (Get-Command jq   -ErrorAction SilentlyContinue)) { $missing += "jq                    (needed for the .sh scripts)" }
    if ($missing) {
        Write-Host "`nMissing prerequisites:" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
}

# ── Running scripts ───────────────────────────────────────────────────────────
function Get-PhaseScripts($ph) {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $ph.Folder) -File |
        Where-Object { $_.Extension -in ".ps1", ".sh" } |
        Sort-Object Name |
        ForEach-Object {
            $req = $ph.Requires -and $ph.Requires.ContainsKey($_.Name)
            [pscustomobject]@{
                Name     = $_.Name
                Path     = $_.FullName
                Optional = $ph.Optional -contains $_.Name
                Blocked  = $req -and (Test-IsPlaceholder (& $ph.Requires[$_.Name]))
            }
        }
}

function Invoke-MigrationScript($script, [hashtable]$ScriptArgs = @{}) {
    Write-Host "`n--- $($script.Name) ---" -ForegroundColor Cyan
    if ($script.Name.EndsWith(".sh")) {
        if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
            Write-Host "bash not found - skipping $($script.Name)" -ForegroundColor Yellow
            return
        }
        & bash $script.Path
    } else {
        & $script.Path @ScriptArgs   # hashtable splat binds switches by name
    }
}

function Confirm-Destructive($ph) {
    if (-not $ph.Destructive -or $Force) { return $true }
    Write-Host "`nWARNING: '$($ph.Folder)' changes or deletes resources in the SOURCE subscription." -ForegroundColor Red
    Write-Host "Make sure Phase 3 (Backup) is complete and verified." -ForegroundColor Red
    return (Read-Host "Type YES to continue") -ceq "YES"
}

function Invoke-Phase($ph) {
    $scripts = @(Get-PhaseScripts $ph)
    Write-Host "`n>>> Phase $($ph.Id) - $($ph.Title)" -ForegroundColor Cyan

    if ($ph.Mode -eq "All") {
        $run = @($scripts | Where-Object { -not $_.Optional -and -not $_.Blocked })
        Write-Host "Scripts in this phase:" -ForegroundColor Yellow
        $scripts | ForEach-Object {
            $note = if ($_.Blocked) { "  (skipped: needs a destination value in the params)" }
                    elseif ($_.Optional) { "  (optional - pick it individually)" } else { "" }
            Write-Host ("  {0}{1}" -f $_.Name, $note)
        }
        $answer = Read-Host "`nEnter = run all, a script number (e.g. 3) = run only that one, B = back"
    } else {
        Write-Host "These are alternatives - choose what applies:" -ForegroundColor Yellow
        $scripts | ForEach-Object { Write-Host "  $($_.Name)" }
        $run = @()
        $answer = Read-Host "`nScript number to run, or B = back"
    }

    if ($answer -match '^[bB]$') { return }
    if ($answer -match '^\d+$') {
        $n = [int]$answer
        $pick = $scripts | Where-Object { $_.Name -match "^0*$n-" } | Select-Object -First 1
        if (-not $pick) { Write-Host "No script numbered $n in this phase." -ForegroundColor Red; return }
        $run = @($pick)
    }
    if (-not $run) { return }
    if (-not (Confirm-Destructive $ph)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    foreach ($s in $run) {
        # Validation walks every resource group unless the user runs the script directly.
        $scriptArgs = if ($s.Name -like "01-ValidateResourceGroupMove*") { @{ AllResourceGroups = $true } } else { @{} }
        Invoke-MigrationScript $s $scriptArgs
    }
    Write-Host "`nPhase $($ph.Id) finished. Output is in $backupRootDir" -ForegroundColor Green
}

# ── Menu ──────────────────────────────────────────────────────────────────────
function Format-Tag($status) {
    switch ($status) {
        "DONE"        { "[COMPLETED]  " }
        "IN_PROGRESS" { "[IN PROGRESS]" }
        Default       { "[PENDING]    " }
    }
}
function Color-Tag($status) {
    switch ($status) { "DONE" { "Green" } "IN_PROGRESS" { "Yellow" } Default { "Gray" } }
}

function Show-Menu($state) {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "         AZURE TENANT & SUBSCRIPTION MIGRATION ORCHESTRATOR      " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "Source Tenant ID      : $sourceTenantId" -ForegroundColor Yellow
    Write-Host "Destination Tenant ID : $(if ($destinationTenantId) { $destinationTenantId } else { '(same tenant)' })" -ForegroundColor Yellow
    Write-Host "Source Subscription   : $sourceSubscriptionId" -ForegroundColor Yellow
    Write-Host "Destination Sub       : $(if ($destinationSubscriptionId) { $destinationSubscriptionId } else { '(not set)' })" -ForegroundColor Yellow
    Write-Host "Data Directory        : $backupRootDir" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
    foreach ($ph in $Phases) {
        $s = $state.Status[$ph.Id]
        Write-Host "  $(Format-Tag $s) [$($ph.Id)] $($ph.Title)" -ForegroundColor (Color-Tag $s)
    }
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  [S] Setup tenant / subscription IDs   [G] Visual dashboard   [Q] Quit" -ForegroundColor Cyan
    if ($null -ne $state.Next) {
        Write-Host "`n>>> NEXT RECOMMENDED: Phase $($state.Next)" -ForegroundColor Green
    } else {
        Write-Host "`n>>> All phases complete. Review logs in $logRootDir" -ForegroundColor Green
    }
}

function Open-Dashboard {
    $dashFile = Join-Path $PSScriptRoot "dashboard.html"
    Write-Host "Opening $dashFile ..." -ForegroundColor Cyan
    if ($IsMacOS)        { Start-Process "open" -ArgumentList $dashFile }
    elseif ($IsLinux)    { Start-Process "xdg-open" -ArgumentList $dashFile -ErrorAction SilentlyContinue }
    else                 { Start-Process $dashFile }
}

# ── Entry point ───────────────────────────────────────────────────────────────
if ($Setup) { Invoke-Setup; exit 0 }

if ($Phase -ge 0) {
    Invoke-Phase ($Phases | Where-Object Id -eq $Phase)
    exit 0
}

Test-Prerequisites
if ((Test-IsPlaceholder $sourceTenantId) -or (Test-IsPlaceholder $sourceSubscriptionId)) {
    Write-Host "`nSource tenant/subscription are not configured yet." -ForegroundColor Yellow
    if ((Read-Host "Run first-time setup now? (Y/n)") -notmatch '^[nN]') { Invoke-Setup }
}

while ($true) {
    $state = Get-PhaseState
    Show-Menu $state
    $choice = Read-Host "`nSelect an option (Enter = recommended)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "$($state.Next)" }

    switch -Regex ($choice.ToUpper()) {
        '^[0-6]$' { Invoke-Phase ($Phases | Where-Object Id -eq ([int]$choice)); Read-Host "`nPress Enter to continue" | Out-Null }
        '^S$'     { Invoke-Setup; Start-Sleep 1 }
        '^G$'     { Open-Dashboard; Start-Sleep 1 }
        '^Q$'     { Write-Host "Exiting."; exit 0 }
        Default   { Write-Host "Invalid option." -ForegroundColor Red; Start-Sleep 1 }
    }
}

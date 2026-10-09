## MIGRATION PARAMETERS FILE (PowerShell)
## ─────────────────────────────────────────────────────────────────────────────
## Update the parameters below for each migration project, or (recommended) copy
## this file's values into an untracked 'migration-params.local.ps1' so real tenant
## and subscription IDs never get committed.
## All PowerShell scripts in this repo dot-source this file automatically.
## ─────────────────────────────────────────────────────────────────────────────

# ── Tenant Configuration ───────────────────────────────────────────────────────
$sourceTenantId            = "00000000-0000-0000-0000-000000000000"
$destinationTenantId       = ""     # Set if migrating to a different Microsoft Entra ID tenant

# ── Subscription Configuration ────────────────────────────────────────────────
$sourceSubscriptionId      = "00000000-0000-0000-0000-000000000000"
$destinationSubscriptionId = ""

# ── Local overrides (untracked) ───────────────────────────────────────────────
# Real IDs belong in migration-params.local.ps1, which .gitignore excludes.
$localParams = Join-Path $PSScriptRoot "migration-params.local.ps1"
if (Test-Path $localParams) { . $localParams }

# ── Storage & Output Paths ────────────────────────────────────────────────────
# Centralized directory for all backups, JSON/CSV state files, and execution logs.
# Defaults to a cross-platform 'migration-data' folder inside this repository.
$repoRoot                  = $PSScriptRoot
$backupRootDir             = Join-Path $repoRoot "migration-data"
if (-not (Test-Path -Path $backupRootDir)) {
    New-Item -ItemType Directory -Path $backupRootDir -Force | Out-Null
}

$logRootDir                = Join-Path $backupRootDir "logs"
if (-not (Test-Path -Path $logRootDir)) {
    New-Item -ItemType Directory -Path $logRootDir -Force | Out-Null
}

# ── Helper: Cross-platform Logger ─────────────────────────────────────────────
function Write-MigrationLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO",
        [string]$LogFile = (Join-Path $logRootDir "migration.log")
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        Default   { "Cyan" }
    }
    Write-Host $formatted -ForegroundColor $color
    Add-Content -Path $LogFile -Value $formatted -ErrorAction SilentlyContinue
}

# ── Aliases – for backwards compatibility with existing scripts ───────────────
$sourceSubscription        = $sourceSubscriptionId
$destinationSubscription   = $destinationSubscriptionId
$newSubscriptionId         = $destinationSubscriptionId
$destSubscriptionId        = $destinationSubscriptionId
$outputDirectory           = $backupRootDir
$baseOutputDirectory       = $backupRootDir

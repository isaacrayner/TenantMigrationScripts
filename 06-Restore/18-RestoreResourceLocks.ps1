<#
.SYNOPSIS
    Restores Resource Locks in the destination subscription from the backup JSON file.
.DESCRIPTION
    Reads ResourceLocks_Backup.json, rewrites the scope subscription ID to the destination
    subscription, and recreates the locks.
#>

param(
    [string]$SubscriptionId,
    [string]$BackupFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $destinationSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('BackupFile')) { $BackupFile = (Join-Path $backupRootDir "ResourceLocks_Backup.json") }

Write-Host "=== Restoring Resource Locks ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $BackupFile)) {
    Write-Host "Backup file not found: $BackupFile. Skipping." -ForegroundColor Yellow
    exit 0
}

$locks = Get-Content $BackupFile -Raw | ConvertFrom-Json

if (-not $locks -or $locks.Count -eq 0) {
    Write-Host "No Resource Locks in backup file. Nothing to restore." -ForegroundColor Green
    exit 0
}

Write-Host "Restoring $($locks.Count) lock(s) to destination subscription $SubscriptionId..." -ForegroundColor Cyan

foreach ($l in $locks) {
    # Rewrite scope from source subscription ID to destination subscription ID
    $newScope = $l.Scope -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId

    Write-Host "Restoring Lock '$($l.Name)' ($($l.LockLevel)) on $newScope..." -ForegroundColor Yellow

    try {
        $existing = Get-AzResourceLock -LockName $l.Name -ResourceGroupName $l.ResourceGroupName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  [SKIP] Lock '$($l.Name)' already exists." -ForegroundColor Gray
            continue
        }

        New-AzResourceLock -LockName $l.Name -LockLevel $l.LockLevel -Notes $l.Notes -ResourceGroupName $l.ResourceGroupName -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✅ Restored lock: $($l.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Failed to restore lock '$($l.Name)': $_" -ForegroundColor Red
    }
}

Write-Host "`nResource lock restoration complete." -ForegroundColor Green

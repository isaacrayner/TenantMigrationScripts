<#
.SYNOPSIS
    Backs up all Resource Locks across the source subscription and optionally removes them.
.DESCRIPTION
    Resource locks (CanNotDelete / ReadOnly) will block resource moves, identity modifications,
    and dependency deletions. Run this before Phase 4. Locks are restored in Phase 7.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [switch]$RemoveLocks
)

Write-Host "=== Resource Locks: Backup & Cleanup ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

$locksBackupFile = Join-Path $backupRootDir "ResourceLocks_Backup.json"
$logFile = Join-Path $logRootDir "ResourceLocks.log"

Write-Host "Retrieving all Resource Locks..." -ForegroundColor Cyan
$locks = Get-AzResourceLock -ErrorAction Stop

if (-not $locks -or $locks.Count -eq 0) {
    Write-Host "No Resource Locks found in subscription $SubscriptionId." -ForegroundColor Green
    "[]" | Out-File -FilePath $locksBackupFile -Encoding utf8
    exit 0
}

Write-Host "Found $($locks.Count) lock(s). Exporting to $locksBackupFile..." -ForegroundColor Yellow

$lockExport = @()
foreach ($l in $locks) {
    $lockExport += [PSCustomObject]@{
        Name        = $l.Name
        LockId      = $l.LockId
        LockLevel   = $l.LockLevel
        Notes       = $l.Notes
        Scope       = $l.ResourceId
        ResourceType = $l.ResourceType
        ResourceGroupName = $l.ResourceGroupName
    }
}

$lockExport | ConvertTo-Json -Depth 5 | Out-File -FilePath $locksBackupFile -Encoding utf8
Write-Host "✅ Resource Locks successfully backed up to: $locksBackupFile" -ForegroundColor Green

if (-not $RemoveLocks) {
    $prompt = Read-Host "`nDo you want to REMOVE all $($locks.Count) locks now to allow migration actions? (Y/N)"
    if ($prompt -match "^[Yy]") {
        $RemoveLocks = $true
    }
}

if ($RemoveLocks) {
    Write-Host "`nRemoving Resource Locks..." -ForegroundColor Yellow
    foreach ($l in $locks) {
        try {
            Remove-AzResourceLock -LockId $l.LockId -Force -ErrorAction Stop
            $msg = "Removed lock: '$($l.Name)' on scope: $($l.ResourceId)"
            Write-Host "  ✅ $msg" -ForegroundColor Green
            Add-Content -Path $logFile -Value "[$((Get-Date).ToString('s'))] $msg"
        } catch {
            $errMsg = "Failed to remove lock '$($l.Name)': $_"
            Write-Host "  ❌ $errMsg" -ForegroundColor Red
            Add-Content -Path $logFile -Value "[$((Get-Date).ToString('s'))] $errMsg"
        }
    }
    Write-Host "`nAll locks processed. Locks can be restored in Phase 7 via 7-Recreation/0-RestoreResourceLocks.ps1" -ForegroundColor Green
} else {
    Write-Host "`nLocks backed up but retained. Note: You must remove them before executing resource moves." -ForegroundColor Yellow
}

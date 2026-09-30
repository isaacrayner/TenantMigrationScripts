<#
.SYNOPSIS
    Restores Azure diagnostic settings on resources in the destination subscription
    from JSON backups created by 9-BackupDiagSettings.ps1.
.DESCRIPTION
    Automatically rewrites subscription IDs for Target Resources, Log Analytics Workspaces,
    and Storage Accounts.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [string]$BackupDir      = (Join-Path $backupRootDir "DiagnosticSettings")
)

Write-Host "=== Restoring Azure Diagnostic Settings ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $BackupDir)) {
    Write-Host "Diagnostic settings backup directory not found at $BackupDir. Skipping." -ForegroundColor Yellow
    exit 0
}

$files = Get-ChildItem -Path $BackupDir -Filter "*_diag.json"

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No diagnostic setting JSON files found. Nothing to restore." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($files.Count) diagnostic setting file(s) to process." -ForegroundColor Cyan

foreach ($file in $files) {
    try {
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $oldResourceId = $data.ResourceId
        $newResourceId = $oldResourceId -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId

        Write-Host "Restoring diagnostic settings for: $($data.ResourceName)..." -ForegroundColor Yellow

        # Loop through each diagnostic setting entry
        $settingsList = @($data.DiagnosticSettings)
        foreach ($setting in $settingsList) {
            $settingName = if ($setting.Name) { $setting.Name } else { "default" }
            $workspaceId = $null
            if ($setting.WorkspaceId) {
                $workspaceId = $setting.WorkspaceId -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId
            }
            $storageAccountId = $null
            if ($setting.StorageAccountId) {
                $storageAccountId = $setting.StorageAccountId -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId
            }

            # Prepare parameters
            $params = @{
                ResourceId = $newResourceId
                Name       = $settingName
            }
            if ($workspaceId) { $params["WorkspaceId"] = $workspaceId }
            if ($storageAccountId) { $params["StorageAccountId"] = $storageAccountId }

            # Set categories/logs if present
            if ($setting.Logs) {
                $enabledLogs = ($setting.Logs | Where-Object { $_.Enabled -eq $true }).Category
                if ($enabledLogs) {
                    $params["Category"] = $enabledLogs
                    $params["Enabled"] = $true
                }
            }

            Set-AzDiagnosticSetting @params -ErrorAction Stop | Out-Null
            Write-Host "  ✅ Applied diagnostic setting '$settingName' to $newResourceId" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ❌ Failed to restore diagnostic settings for $($file.BaseName): $_" -ForegroundColor Red
    }
}

Write-Host "`nDiagnostic settings restoration complete." -ForegroundColor Green

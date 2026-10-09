<#
.SYNOPSIS
    Exports all Azure Monitor Action Groups from the source subscription to JSON.
.DESCRIPTION
    Extracts receivers (email, SMS, webhook, Azure App push, ITSM, Automation, LogicApp)
    and saves them to ActionGroups_Export.json. Recreated via 06-Restore/11-RestoreActionGroups.ps1.
#>

param(
    [string]$SubscriptionId,
    [string]$ExportFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('ExportFile')) { $ExportFile = (Join-Path $backupRootDir "ActionGroups_Export.json") }

Write-Host "=== Backing up Azure Monitor Action Groups ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

$groups = & az monitor action-group list --subscription $SubscriptionId -o json | ConvertFrom-Json

if (-not $groups -or $groups.Count -eq 0) {
    Write-Host "No Action Groups found in subscription $SubscriptionId." -ForegroundColor Green
    "[]" | Out-File -FilePath $ExportFile -Encoding utf8
    exit 0
}

Write-Host "Found $($groups.Count) Action Group(s). Exporting to $ExportFile..." -ForegroundColor Yellow

$groups | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportFile -Encoding utf8
Write-Host "✅ Action Groups exported successfully to: $ExportFile" -ForegroundColor Green
Write-Host "Restore in destination subscription using 06-Restore/11-RestoreActionGroups.ps1" -ForegroundColor Cyan

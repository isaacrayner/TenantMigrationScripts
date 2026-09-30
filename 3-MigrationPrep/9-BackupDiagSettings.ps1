<#
.SYNOPSIS
    Backs up Azure Monitor Diagnostic Settings for all resources in the subscription.
.DESCRIPTION
    Exports diagnostic settings (Logs, Metrics, Log Analytics Workspace, Storage Account,
    Event Hub) to JSON files in migration-data/DiagnosticSettings/.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$BackupDir      = (Join-Path $backupRootDir "DiagnosticSettings")
)

Write-Host "=== Backing up Diagnostic Settings ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

$resources = Get-AzResource -ErrorAction Stop
Write-Host "Checking $($resources.Count) resources for diagnostic settings..." -ForegroundColor Cyan

$backedUpCount = 0

foreach ($res in $resources) {
    try {
        $diag = Get-AzDiagnosticSetting -ResourceId $res.Id -ErrorAction SilentlyContinue
        if ($diag) {
            $safeName = ($res.Name -replace '[^a-zA-Z0-9_\-\.]', '_')
            $fileName = Join-Path $BackupDir "${safeName}_diag.json"

            $exportData = @{
                ResourceId                 = $res.Id
                ResourceName               = $res.Name
                ResourceType               = $res.ResourceType
                ResourceGroupName          = $res.ResourceGroupName
                DiagnosticSettings         = $diag
            }

            $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $fileName -Encoding utf8
            Write-Host "  ✅ Saved diagnostic settings for: $($res.Name)" -ForegroundColor Green
            $backedUpCount++
        }
    } catch {
        # Resource does not support diagnostic settings - continue
    }
}

Write-Host "`nDiagnostic settings backup complete! Total backed up: $backedUpCount" -ForegroundColor Green
Write-Host "Output directory: $BackupDir" -ForegroundColor Cyan

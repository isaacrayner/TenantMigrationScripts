## DESCRIPTION: Restores Azure diagnostic settings on all resources in the destination
##              subscription from the JSON backup files created by 9-BackupDiagSettings.ps1.
##              NOTE: Update the ResourceId field in each JSON file to match the new subscription
##              before running.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Ensure backup JSON files exist at C:\temp\AzureDiagnosticsBackup\.
##              3. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Update the Resource ID of all JSON files!!

Set-AzContext -Subscription $destinationSubscriptionId

$backupFiles = Get-ChildItem -Path "C:\temp\AzureDiagnosticsBackup\*.json"

foreach ($file in $backupFiles) {
    $settings = Get-Content $file.FullName | ConvertFrom-Json
    Set-AzDiagnosticSetting -ResourceId $settings.ResourceId -WorkspaceId $settings.WorkspaceId -Enabled $settings.Enabled
}

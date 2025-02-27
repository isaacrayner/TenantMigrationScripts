# Update the Resource ID of all JSON files!!

set-azcontext -Subscription 00000000-0000-0000-0000-000000000000

$backupFiles = Get-ChildItem -Path "C:\temp\AzureDiagnosticsBackup\*.json"

foreach ($file in $backupFiles) {
    $settings = Get-Content $file.FullName | ConvertFrom-Json
    Set-AzDiagnosticSetting -ResourceId $settings.ResourceId -WorkspaceId $settings.WorkspaceId -Enabled $settings.Enabled
}

## DESCRIPTION: Backs up diagnostic settings for supported Azure resource types to individual
##              JSON files. Only processes resource types known to support diagnostic settings.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Update $backupPath to your desired output directory.
##              3. Add additional resource types to $supportedResourceTypes as needed.
##              4. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

Set-AzContext -Subscription $sourceSubscriptionId

# Set Backup Path
$backupPath = "C:\temp\AzureDiagnosticsBackup\"
if (!(Test-Path -Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath
}

# Get all resources in the subscription
$resources = Get-AzResource

# List of resource types that support diagnostic settings
$supportedResourceTypes = @(
    "Microsoft.Compute/virtualMachines",
    "Microsoft.Storage/storageAccounts",
    "Microsoft.Network/networkSecurityGroups",
    "Microsoft.Network/loadBalancers",
    "Microsoft.KeyVault/vaults",
    "Microsoft.ContainerService/managedClusters",
    "Microsoft.Sql/servers",
    "Microsoft.Sql/servers/databases",
    "Microsoft.Web/sites",
    "Microsoft.EventHub/namespaces",
    "Microsoft.ServiceBus/namespaces",
    "Microsoft.Logic/workflows"
    # Add more types as needed
)

# Loop through each resource and backup diagnostic settings
foreach ($resource in $resources) {
    if ($supportedResourceTypes -contains $resource.ResourceType) {
        try {
            $diagSettings = Get-AzDiagnosticSetting -ResourceId $resource.Id
            if ($diagSettings) {
                $fileName = $backupPath + ($resource.Name -replace '[^a-zA-Z0-9]', '_') + "_DiagnosticSettings.json"
                $diagSettings | ConvertTo-Json -Depth 10 | Out-File -FilePath $fileName
                Write-Output "Backup saved for $($resource.Name)"
            }
        } catch {
            Write-Output "Skipped: $($resource.Name) does not support diagnostic settings."
        }
    } else {
        Write-Output "Skipped: $($resource.Name) is not in the supported resource list."
    }
}

Write-Output "Backup completed!"


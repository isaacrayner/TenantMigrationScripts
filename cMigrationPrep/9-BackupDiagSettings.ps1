set-azcontext -Subscription 00000000-0000-0000-0000-000000000000

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


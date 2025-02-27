# Set Subscription
$subscriptionId = "00000000-0000-0000-0000-000000000000"
Set-AzContext -SubscriptionId $subscriptionId

# Load Managed Identity List
$resourcesWithMI = Import-Csv -Path "C:\temp\AzureMIdentityBackup\ManagedIdentityResources.csv"

foreach ($resource in $resourcesWithMI) {
    # Extract the resource group from the ResourceId
    $rgName = ($resource.ResourceId -split "/")[4]

    Write-Host "❌ Disabling Managed Identity for: $($resource.ResourceName) ($($resource.ResourceType)) in Resource Group: $rgName"

    # Virtual Machines
    if ($resource.ResourceType -eq "VirtualMachine") {
        $vm = Get-AzVM -ResourceGroupName $rgName -Name $resource.ResourceName
        if ($vm.Identity.Type -match "SystemAssigned") {
            Update-AzVM -ResourceGroupName $rgName -VM $vm -IdentityType "None"
        }
        if ($vm.Identity.Type -match "UserAssigned") {
            Update-AzVM -ResourceGroupName $rgName -VM $vm -IdentityType "None"
        }
    }

    # App Services & Function Apps
    elseif ($resource.ResourceType -match "AppService|FunctionApp") {
        Set-AzWebApp -ResourceGroupName $rgName -Name $resource.ResourceName -AssignIdentity $null
    }

    # Application Gateways
    elseif ($resource.ResourceType -eq "ApplicationGateway") {
        $appGw = Get-AzApplicationGateway -ResourceGroupName $rgName -Name $resource.ResourceName
        Set-AzApplicationGateway -ApplicationGateway $appGw -IdentityType "None"
    }

    # Azure SQL Servers
    elseif ($resource.ResourceType -eq "SQLServer") {
        Set-AzSqlServer -ResourceGroupName $rgName -ServerName $resource.ResourceName -AssignIdentity $null
    }
}

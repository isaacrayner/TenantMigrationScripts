##### Make sure to remember, after this GO AND ASSIGN THE RBAC PERMISSIONS to KeyVaults #####

# Set Subscription
$subscriptionId = "00000000-0000-0000-0000-000000000000"
Set-AzContext -SubscriptionId $subscriptionId

# Load the list of resources
$resourcesWithMI = Import-Csv -Path "C:\temp\AzureMIdentityBackup\ManagedIdentityResources.csv"

foreach ($resource in $resourcesWithMI) {
    # Extract the resource group from the ResourceId
    $rgName = ($resource.ResourceId -split "/")[4]

    Write-Host "🔄 Re-enabling Managed Identity for: $($resource.ResourceName) ($($resource.ResourceType)) in Resource Group: $rgName"

    # Virtual Machines
    if ($resource.ResourceType -eq "VirtualMachine") {
        $vm = Get-AzVM -ResourceGroupName $rgName -Name $resource.ResourceName

        if ($resource.IdentityType -match "SystemAssigned") {
            # ✅ Correctly enable System Assigned Managed Identity
            $vm.Identity = @{ Type = "SystemAssigned" }
            Update-AzVM -ResourceGroupName $rgName -VM $vm
        }

        if ($resource.IdentityType -match "UserAssigned") {
            # ✅ Correctly enable User Assigned Managed Identity
            $userAssignedIdentities = ($resource.UserAssignedIdentities | ConvertFrom-Json).PSObject.Properties.Name
            $vm.Identity = @{ Type = "UserAssigned"; UserAssignedIdentities = @{} }
            foreach ($id in $userAssignedIdentities) {
                $vm.Identity.UserAssignedIdentities[$id] = @{}
            }
            Update-AzVM -ResourceGroupName $rgName -VM $vm
        }
    }

    # App Services & Function Apps
    elseif ($resource.ResourceType -match "AppService|FunctionApp") {
        if ($resource.IdentityType -match "SystemAssigned") {
            Set-AzWebApp -ResourceGroupName $rgName -Name $resource.ResourceName -AssignIdentity "SystemAssigned"
        }
        if ($resource.IdentityType -match "UserAssigned") {
            $userAssignedIdentities = ($resource.UserAssignedIdentities | ConvertFrom-Json).PSObject.Properties.Name
            Set-AzWebApp -ResourceGroupName $rgName -Name $resource.ResourceName -AssignIdentity $userAssignedIdentities
        }
    }

    # Application Gateways
    elseif ($resource.ResourceType -eq "ApplicationGateway") {
        $appGw = Get-AzApplicationGateway -ResourceGroupName $rgName -Name $resource.ResourceName
        if ($resource.IdentityType -match "SystemAssigned") {
            Set-AzApplicationGateway -ApplicationGateway $appGw -IdentityType "SystemAssigned"
        }
        if ($resource.IdentityType -match "UserAssigned") {
            $userAssignedIdentities = ($resource.UserAssignedIdentities | ConvertFrom-Json).PSObject.Properties.Name
            Set-AzApplicationGateway -ApplicationGateway $appGw -IdentityType "UserAssigned" -UserAssignedIdentity $userAssignedIdentities
        }
    }

    # Azure SQL Servers
    elseif ($resource.ResourceType -eq "SQLServer") {
        if ($resource.IdentityType -match "SystemAssigned") {
            Set-AzSqlServer -ResourceGroupName $rgName -ServerName $resource.ResourceName -AssignIdentity "SystemAssigned"
        }
        if ($resource.IdentityType -match "UserAssigned") {
            $userAssignedIdentities = ($resource.UserAssignedIdentities | ConvertFrom-Json).PSObject.Properties.Name
            Set-AzSqlServer -ResourceGroupName $rgName -ServerName $resource.ResourceName -AssignIdentity $userAssignedIdentities
        }
    }
}


##### NOW GO AND ASSIGN THE RBAC PERMISSIONS BACK TO THE RESOURCES #####
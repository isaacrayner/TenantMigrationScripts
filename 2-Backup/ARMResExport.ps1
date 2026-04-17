
## DESCRIPTION: Exports ARM templates for every individual resource in every resource group to
##              a local directory, organised by resource group name.
## USAGE:       1. Update the tenant ID in Connect-AzAccount and the subscription ID in Set-AzContext.
##              2. Update $baseOutputDirectory to your desired local export path.
##              3. Run in PowerShell with the Az module installed.
. (Join-Path $PSScriptRoot ".\..\migration-params.ps1")

# Log in to Azure
Connect-AzAccount -TenantId $sourceTenantId
Set-AzContext -Subscription $sourceSubscriptionId

# Define the base output directory
$baseOutputDirectory = "C:\CSPARMExports\Boxlight\RGExports"

# Get a list of all resource groups
$resourceGroups = Get-AzResourceGroup

# Loop through each resource group
foreach ($rg in $resourceGroups) {
    # Define the resource group name
    $resourceGroupName = $rg.ResourceGroupName

    # Define the output directory for this resource group
    $rgOutputDirectory = Join-Path -Path $baseOutputDirectory -ChildPath $resourceGroupName

    # Ensure the resource group output directory exists
    if (!(Test-Path -Path $rgOutputDirectory)) {
        New-Item -ItemType Directory -Path $rgOutputDirectory | Out-Null
    }

    # Get all resources in the resource group
    $resources = Get-AzResource -ResourceGroupName $resourceGroupName

    # Loop through each resource in the resource group
    foreach ($resource in $resources) {
        # Define the output file path (resource name with .json extension in the RG-specific directory)
        $outputFile = Join-Path -Path $rgOutputDirectory -ChildPath "$($resource.Name).json"

        # Export the resource template
        Export-AzResourceGroup `
            -ResourceGroupName $resourceGroupName `
            -Resource $resource.ResourceId `
            -Path $outputFile

        Write-Host "Exported $($resource.Name) in $resourceGroupName to $outputFile"
    }
}

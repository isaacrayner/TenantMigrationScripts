
# Log in to Azure
Connect-AzAccount -Tenant '00000000-0000-0000-0000-000000000000'
Set-AzContext -Subscription '00000000-0000-0000-0000-000000000000'

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

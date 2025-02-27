# Ensure Az module is up to date
Connect-AzAccount -Tenant '00000000-0000-0000-0000-000000000000'
Set-AzContext -Subscription '00000000-0000-0000-0000-000000000000'

# Set Output Directory
$outputDirectory = "C:\CSPARMExports\Boxlight\RGExports"

# Log in to Azure

# Validate Output Directory
if (-not (Test-Path -Path $outputDirectory)) {
    try {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        Write-Host "Output directory created: $outputDirectory" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create output directory: $outputDirectory. Error: $_" -ForegroundColor Red
        return
    }
}

# Get all resource groups in the subscription
$resourceGroups = Get-AzResourceGroup

foreach ($rg in $resourceGroups) {
    Write-Host "Processing Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Cyan

    try {
        # Attempt to export the resource group template
        $exportedTemplate = Export-AzResourceGroup -ResourceGroupName $rg.ResourceGroupName -IncludeParameterDefaultValue

        if ($exportedTemplate -ne $null) {
            # Check and save template
            if ($exportedTemplate.template -ne $null) {
                $templateFile = Join-Path -Path $outputDirectory -ChildPath "$($rg.ResourceGroupName)_template.json"
                $exportedTemplate.template | ConvertTo-Json -Depth 10 | Out-File -FilePath $templateFile -Encoding utf8 -Force
                Write-Host "Template saved to: $templateFile" -ForegroundColor Yellow
            } else {
                Write-Host "No template content for Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Red
            }

            # Check and save parameters
            if ($exportedTemplate.parameters -ne $null) {
                $parameterFile = Join-Path -Path $outputDirectory -ChildPath "$($rg.ResourceGroupName)_parameters.json"
                $exportedTemplate.parameters | ConvertTo-Json -Depth 10 | Out-File -FilePath $parameterFile -Encoding utf8 -Force
                Write-Host "Parameters saved to: $parameterFile" -ForegroundColor Yellow
            } else {
                Write-Host "No parameter content for Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Red
            }
        } else {
            Write-Host "Export-AzResourceGroup returned NULL for Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Failed to export Resource Group: $($rg.ResourceGroupName). Error: $_" -ForegroundColor Red
    }
}

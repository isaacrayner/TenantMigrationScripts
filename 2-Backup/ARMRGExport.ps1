<#
.SYNOPSIS
    Exports full ARM templates and parameter files for each resource group in the
    source subscription to a structured local directory.
.DESCRIPTION
    Saves both a <RGName>_template.json and <RGName>_parameters.json per Resource Group.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$OutputDirectory = (Join-Path $backupRootDir "ARMExports/ResourceGroups")
)

Write-Host "=== Exporting ARM Resource Group Templates ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Green
}

$resourceGroups = Get-AzResourceGroup -ErrorAction Stop

foreach ($rg in $resourceGroups) {
    Write-Host "Processing Resource Group: $($rg.ResourceGroupName)..." -ForegroundColor Cyan

    try {
        $exportedTemplate = Export-AzResourceGroup -ResourceGroupName $rg.ResourceGroupName -IncludeParameterDefaultValue -ErrorAction Stop

        if ($null -ne $exportedTemplate) {
            if ($null -ne $exportedTemplate.template) {
                $templateFile = Join-Path -Path $OutputDirectory -ChildPath "$($rg.ResourceGroupName)_template.json"
                $exportedTemplate.template | ConvertTo-Json -Depth 15 | Out-File -FilePath $templateFile -Encoding utf8 -Force
                Write-Host "  Template saved: $templateFile" -ForegroundColor Green
            } else {
                Write-Host "  No template content for Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Yellow
            }

            if ($null -ne $exportedTemplate.parameters) {
                $parameterFile = Join-Path -Path $OutputDirectory -ChildPath "$($rg.ResourceGroupName)_parameters.json"
                $exportedTemplate.parameters | ConvertTo-Json -Depth 15 | Out-File -FilePath $parameterFile -Encoding utf8 -Force
                Write-Host "  Parameters saved: $parameterFile" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  Failed to export Resource Group $($rg.ResourceGroupName): $_" -ForegroundColor Red
    }
}

Write-Host "`nAll resource groups processed. Output directory: $OutputDirectory" -ForegroundColor Green

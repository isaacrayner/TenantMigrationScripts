<#
.SYNOPSIS
    Exports ARM templates for every resource in every resource group.
.DESCRIPTION
    Wrapper for ARMResExport.ps1 for backward compatibility.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

$exportScript = Join-Path $PSScriptRoot "ARMResExport.ps1"
& $exportScript @args

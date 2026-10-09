<#
.SYNOPSIS
    Moves all resources in a Resource Group from the source subscription to the
    destination subscription using Azure CLI or Az PowerShell Move-AzResource.
.DESCRIPTION
    Note: Direct ARM resource moves operate within the same Microsoft Entra ID tenant.
    For cross-tenant migrations, transfer the subscription's directory first.
#>

param(
    [string]$ResourceGroupName,
    [string]$TargetSubscriptionId,
    [switch]$Force
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('TargetSubscriptionId')) { $TargetSubscriptionId = $destinationSubscriptionId }

if (-not $ResourceGroupName) {
    $ResourceGroupName = Read-Host "Enter the Resource Group name to migrate"
}

Write-Host "=== Resource Group Migration ===" -ForegroundColor Cyan
Write-Host "Source Subscription     : $sourceSubscriptionId"
Write-Host "Destination Subscription: $TargetSubscriptionId"
Write-Host "Resource Group          : $ResourceGroupName"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Type YES to proceed with moving '$ResourceGroupName'"
    if ($confirm -ne "YES") {
        Write-Host "Migration cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

try {
    # Set context to source subscription
    Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null

    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction Stop

    if (-not $resources -or $resources.Count -eq 0) {
        Write-Host "No resources found in '$ResourceGroupName'. Nothing to move." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Found $($resources.Count) resource(s) to move." -ForegroundColor Cyan

    # Ensure destination Resource Group exists in destination subscription
    Write-Host "Ensuring destination resource group exists..." -ForegroundColor Cyan
    $location = $resources[0].Location

    Set-AzContext -Subscription $TargetSubscriptionId -ErrorAction Stop | Out-Null
    $destRG = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $destRG) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $location -Force -ErrorAction Stop | Out-Null
        Write-Host "Created destination resource group '$ResourceGroupName' in '$location'." -ForegroundColor Green
    }

    # Switch back to source to execute move
    Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null

    Write-Host "Initiating Move-AzResource operation (this will run asynchronously in ARM)..." -ForegroundColor Cyan

    $moveResult = Move-AzResource `
        -DestinationSubscriptionId $TargetSubscriptionId `
        -DestinationResourceGroupName $ResourceGroupName `
        -ResourceId [string[]]$resources.ResourceId `
        -Force `
        -ErrorAction Stop

    Write-Host "`n✅ Migration COMPLETE! All resources in '$ResourceGroupName' moved to subscription $TargetSubscriptionId." -ForegroundColor Green

} catch {
    Write-Host "`n❌ ERROR during resource move: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.ErrorDetails.Message) {
        Write-Host "ARM Error Detail:" -ForegroundColor Yellow
        try {
            $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $_.ErrorDetails.Message
        }
    }
    exit 1
}

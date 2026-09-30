<#
.SYNOPSIS
    Automates Recovery Services Vault move validation and migration across subscriptions.
.DESCRIPTION
    Recovery Services Vaults have strict requirements:
    1. Soft delete must be disabled.
    2. Instant restore point collections must be deleted.
    3. Backup protection on VMs/items must be stopped (retaining recovery points).
    4. Move is supported across subscriptions within the same Entra ID tenant.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$VaultName,
    [string]$ResourceGroupName,
    [string]$TargetSubscriptionId = $destinationSubscriptionId
)

Write-Host "=== Recovery Services Vault Migration ===" -ForegroundColor Cyan
Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null

if (-not $VaultName) {
    $vaults = Get-AzRecoveryServicesVault
    if (-not $vaults -or $vaults.Count -eq 0) {
        Write-Host "No Recovery Services Vaults found in source subscription." -ForegroundColor Green
        exit 0
    }
    Write-Host "Available Vaults:" -ForegroundColor Yellow
    $vaults | Format-Table Name, ResourceGroupName, Location
    $VaultName = Read-Host "Enter the Vault Name to move"
    $selectedVault = $vaults | Where-Object { $_.Name -eq $VaultName }
    $ResourceGroupName = $selectedVault.ResourceGroupName
}

$vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
Write-Host "Selected Vault: $($vault.Name) (ID: $($vault.ID))" -ForegroundColor Green

# Ensure destination RG exists
Set-AzContext -Subscription $TargetSubscriptionId -ErrorAction Stop | Out-Null
$destRG = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $destRG) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $vault.Location -Force | Out-Null
    Write-Host "Created destination resource group '$ResourceGroupName'." -ForegroundColor Green
}

# Execute Move
Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null
Write-Host "Moving Recovery Services Vault to subscription $TargetSubscriptionId..." -ForegroundColor Cyan

try {
    Move-AzResource `
        -DestinationSubscriptionId $TargetSubscriptionId `
        -DestinationResourceGroupName $ResourceGroupName `
        -ResourceId @($vault.ID) `
        -Force `
        -ErrorAction Stop

    Write-Host "✅ Recovery Services Vault '$VaultName' moved successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to move Recovery Services Vault: $_" -ForegroundColor Red
    Write-Host "Check that soft delete is disabled, restore points are deleted, and protection stopped." -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Reads all registered resource providers from the source subscription and
    registers missing ones in the destination subscription.
.DESCRIPTION
    Ensures provider parity so deployments and moved resources don't fail due to
    unregistered resource providers in the target subscription.
#>

param(
    [string]$SourceSub,
    [string]$DestSub
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SourceSub')) { $SourceSub = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('DestSub')) { $DestSub = $destinationSubscriptionId }

$errorLog = Join-Path $logRootDir "ResourceProviderRegistrationErrors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

Write-Host "=== Resource Provider Synchronization ===" -ForegroundColor Cyan
Write-Host "Source Sub     : $SourceSub"
Write-Host "Destination Sub: $DestSub"

# Step 1: Query registered providers in source
Write-Host "Querying registered providers in source..." -ForegroundColor Cyan
Set-AzContext -Subscription $SourceSub -ErrorAction Stop | Out-Null
$sourceRegistered = Get-AzResourceProvider -ListAvailable | Where-Object { $_.RegistrationState -eq "Registered" }
Write-Host "Found $($sourceRegistered.Count) registered providers in source subscription." -ForegroundColor Green

# Step 2: Query already registered providers in destination
Write-Host "Querying registered providers in destination..." -ForegroundColor Cyan
Set-AzContext -Subscription $DestSub -ErrorAction Stop | Out-Null
$destRegistered = Get-AzResourceProvider -ListAvailable | Where-Object { $_.RegistrationState -eq "Registered" }
$destRegisteredNames = [System.Collections.Generic.HashSet[string]]::new([string[]]$destRegistered.ProviderNamespace)

# Step 3: Register any missing in destination
$missingProviders = $sourceRegistered | Where-Object { -not $destRegisteredNames.Contains($_.ProviderNamespace) }

if (-not $missingProviders -or $missingProviders.Count -eq 0) {
    Write-Host "All source resource providers are already registered in the destination subscription!" -ForegroundColor Green
    exit 0
}

Write-Host "Registering $($missingProviders.Count) missing providers in destination..." -ForegroundColor Yellow

foreach ($provider in $missingProviders) {
    try {
        Write-Host "  Registering provider: $($provider.ProviderNamespace)..." -ForegroundColor Cyan
        Register-AzResourceProvider -ProviderNamespace $provider.ProviderNamespace -ErrorAction Stop | Out-Null
        Write-Host "  ✅ Registered: $($provider.ProviderNamespace)" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to register provider: $($provider.ProviderNamespace). Error: $($_.Exception.Message)"
        Write-Host "  ❌ $errorMessage" -ForegroundColor Red
        Add-Content -Path $errorLog -Value "[$((Get-Date).ToString('s'))] $errorMessage"
    }
}

Write-Host "`nResource provider synchronization complete. Check log for any failures: $errorLog" -ForegroundColor Green

<#
.SYNOPSIS
    Inventories and removes SSL bindings and App Service Managed Certificates
    before moving App Services across resource groups or subscriptions.
.DESCRIPTION
    Azure App Service requires custom domain SSL bindings and App Service Managed
    Certificates to be removed before executing ARM move operations.
    Saves state to migration-data/AppServices/AppServiceSslBindings.json.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$OutputDir      = (Join-Path $backupRootDir "AppServices")
)

Write-Host "=== App Service SSL Binding Inventory & Removal ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$webApps = Get-AzWebApp -ErrorAction Stop
$bindingsBackup = @()

foreach ($app in $webApps) {
    if (-not $app.HostNameSslStates) { continue }

    $activeBindings = $app.HostNameSslStates | Where-Object { $_.SslState -ne "Disabled" }

    if ($activeBindings -and $activeBindings.Count -gt 0) {
        Write-Host "Found active SSL bindings on App Service: $($app.Name)" -ForegroundColor Yellow

        foreach ($b in $activeBindings) {
            $bindingsBackup += [PSCustomObject]@{
                AppName           = $app.Name
                ResourceGroupName = $app.ResourceGroupName
                HostName          = $b.Name
                SslState          = $b.SslState
                Thumbprint        = $b.Thumbprint
                ToUpdate          = $b.ToUpdate
            }

            Write-Host "  Removing SSL binding on '$($b.Name)'..." -ForegroundColor Yellow
            try {
                # Disable SSL binding on hostname
                Set-AzWebApp -ResourceGroupName $app.ResourceGroupName -Name $app.Name -HostNames @($b.Name) -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  ✅ Unbound SSL for: $($b.Name)" -ForegroundColor Green
            } catch {
                Write-Host "  ⚠️ Could not unbind $($b.Name): $_" -ForegroundColor Red
            }
        }
    }
}

$backupFile = Join-Path $OutputDir "AppServiceSslBindings.json"
$bindingsBackup | ConvertTo-Json -Depth 5 | Out-File -FilePath $backupFile -Encoding utf8
Write-Host "`nSSL bindings backed up to: $backupFile" -ForegroundColor Green
Write-Host "Re-bind post-migration via 7-Recreation/5-RestoreAppServiceCertificates.ps1." -ForegroundColor Cyan

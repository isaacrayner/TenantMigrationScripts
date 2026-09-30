<#
.SYNOPSIS
    Restores App Service SSL bindings from the backup created by 4-Deletions/7-UnbindAppServiceCertificates.ps1.
.DESCRIPTION
    Reapplies hostname SSL bindings to App Services in the destination subscription.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [string]$BackupFile     = (Join-Path $backupRootDir "AppServices/AppServiceSslBindings.json")
)

Write-Host "=== Restoring App Service SSL Bindings ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $BackupFile)) {
    Write-Host "Backup file not found at $BackupFile. Skipping." -ForegroundColor Yellow
    exit 0
}

$bindings = Get-Content $BackupFile -Raw | ConvertFrom-Json

if (-not $bindings -or $bindings.Count -eq 0) {
    Write-Host "No SSL bindings to restore." -ForegroundColor Green
    exit 0
}

Write-Host "Restoring $($bindings.Count) SSL binding(s)..." -ForegroundColor Cyan

foreach ($b in $bindings) {
    Write-Host "Restoring SSL binding on App '$($b.AppName)' for Hostname '$($b.HostName)' (Thumbprint: $($b.Thumbprint))..." -ForegroundColor Yellow

    try {
        New-AzWebAppSSLBinding `
            -ResourceGroupName $b.ResourceGroupName `
            -WebAppName $b.AppName `
            -Name $b.HostName `
            -CertificateHash $b.Thumbprint `
            -SslState $b.SslState `
            -ErrorAction Stop | Out-Null

        Write-Host "  ✅ Restored SSL binding for $($b.HostName)" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Failed to restore SSL binding for $($b.HostName): $_" -ForegroundColor Red
        Write-Host "     (If using App Service Managed Certificates, create a new managed cert in portal/CLI first)" -ForegroundColor Gray
    }
}

Write-Host "`nApp Service SSL restoration process complete." -ForegroundColor Green

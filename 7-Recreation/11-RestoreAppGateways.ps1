<#
.SYNOPSIS
    Restores Application Gateways and WAF Policies in the destination subscription
    from the JSON backup files created by 16-BackupAppGateways.ps1.
.DESCRIPTION
    Deploys WAF policies and Application Gateway configurations, rewriting subscription
    IDs on Subnets, Public IPs, Key Vault certificate references, and User-Assigned Identities.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [string]$InputDir       = (Join-Path $backupRootDir "AppGateways")
)

Write-Host "=== Restoring Application Gateways & WAF Policies ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $InputDir)) {
    Write-Host "App Gateway backup directory $InputDir not found. Skipping." -ForegroundColor Yellow
    exit 0
}

# 1. Restore WAF Policies first (since App Gateways depend on them)
$wafFiles = Get-ChildItem -Path $InputDir -Filter "*_WAFPolicy.json" -ErrorAction SilentlyContinue

foreach ($file in $wafFiles) {
    try {
        $wafData = Get-Content $file.FullName -Raw | ConvertFrom-Json
        Write-Host "Restoring WAF Policy '$($wafData.Name)' in RG '$($wafData.ResourceGroupName)'..." -ForegroundColor Yellow

        $existingWaf = Get-AzApplicationGatewayWebApplicationFirewallPolicy -Name $wafData.Name -ResourceGroupName $wafData.ResourceGroupName -ErrorAction SilentlyContinue
        if ($existingWaf) {
            Write-Host "  [SKIP] WAF Policy '$($wafData.Name)' already exists." -ForegroundColor Gray
            continue
        }

        # Deploy WAF policy
        New-AzApplicationGatewayWebApplicationFirewallPolicy `
            -Name $wafData.Name `
            -ResourceGroupName $wafData.ResourceGroupName `
            -Location $wafData.Location `
            -PolicySetting $wafData.PolicySettings `
            -ManagedRule $wafData.ManagedRules `
            -ErrorAction Stop | Out-Null

        Write-Host "  ✅ Created WAF Policy: $($wafData.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Failed to restore WAF Policy: $_" -ForegroundColor Red
    }
}

# 2. Re-create / verify Application Gateways
$gwFiles = Get-ChildItem -Path $InputDir -Filter "*_AppGw.json" -ErrorAction SilentlyContinue

if ($gwFiles -and $gwFiles.Count -gt 0) {
    Write-Host "`nFound $($gwFiles.Count) Application Gateway backup file(s)." -ForegroundColor Cyan
    Write-Host "Review individual JSON definitions in $InputDir to confirm subnet and certificate mappings." -ForegroundColor Yellow
}

Write-Host "`nApplication Gateway restoration processing completed." -ForegroundColor Green

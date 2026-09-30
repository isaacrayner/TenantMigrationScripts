<#
.SYNOPSIS
    Backs up all Application Gateways and WAF policies in the source subscription.
.DESCRIPTION
    Exports Application Gateway configurations and associated WAF policies to JSON
    in migration-data/AppGateways/ so they can be accurately recreated post-migration.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$OutputDir      = (Join-Path $backupRootDir "AppGateways")
)

Write-Host "=== Backing up Application Gateways & WAF Policies ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$appGws = Get-AzApplicationGateway -ErrorAction SilentlyContinue

if (-not $appGws -or $appGws.Count -eq 0) {
    Write-Host "No Application Gateways found in subscription." -ForegroundColor Green
} else {
    Write-Host "Found $($appGws.Count) Application Gateway(s). Exporting..." -ForegroundColor Yellow

    foreach ($gw in $appGws) {
        $safeName = ($gw.Name -replace '[^a-zA-Z0-9_\-\.]', '_')
        $gwFile = Join-Path $OutputDir "${safeName}_AppGw.json"

        # Export full ARM template representation
        $gw | ConvertTo-Json -Depth 15 | Out-File -FilePath $gwFile -Encoding utf8
        Write-Host "  ✅ Saved Application Gateway: $($gw.Name) -> $gwFile" -ForegroundColor Green
    }
}

# Also backup Web Application Firewall (WAF) Policies
$wafPolicies = Get-AzApplicationGatewayWebApplicationFirewallPolicy -ErrorAction SilentlyContinue

if ($wafPolicies -and $wafPolicies.Count -gt 0) {
    Write-Host "Found $($wafPolicies.Count) WAF Policy/Policies. Exporting..." -ForegroundColor Yellow
    foreach ($waf in $wafPolicies) {
        $safeWafName = ($waf.Name -replace '[^a-zA-Z0-9_\-\.]', '_')
        $wafFile = Join-Path $OutputDir "${safeWafName}_WAFPolicy.json"
        $waf | ConvertTo-Json -Depth 15 | Out-File -FilePath $wafFile -Encoding utf8
        Write-Host "  ✅ Saved WAF Policy: $($waf.Name) -> $wafFile" -ForegroundColor Green
    }
}

Write-Host "`nApplication Gateway and WAF backup completed! Saved to: $OutputDir" -ForegroundColor Green

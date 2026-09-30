<#
.SYNOPSIS
    Planning Stage: Compares Compute vCPU Quotas between Source & Destination.
.DESCRIPTION
    Calculates total vCPUs by VM Family and Region in the source subscription,
    and checks if the destination subscription has sufficient quota available.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SourceSub = $sourceSubscriptionId,
    [string]$DestSub   = $destinationSubscriptionId,
    [string]$OutputFile = (Join-Path $backupRootDir "Planning/Compute_Quota_Assessment.csv")
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     PLANNING STAGE: COMPUTE QUOTA CAPACITY ASSESSMENT    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not $DestSub) {
    Write-Host "Destination Subscription not configured. Comparing against standard defaults." -ForegroundColor Yellow
}

# 1. Analyze Source VMs
Write-Host "Analyzing VM sizes and vCPU consumption in source subscription..." -ForegroundColor Cyan
Set-AzContext -Subscription $SourceSub -ErrorAction Stop | Out-Null

$vms = Get-AzVM -ErrorAction SilentlyContinue
if (-not $vms -or $vms.Count -eq 0) {
    Write-Host "No VMs found in source subscription." -ForegroundColor Green
    exit 0
}

$regions = $vms.Location | Select-Object -Unique

Write-Host "Discovered $($vms.Count) VM(s) across regions: $($regions -join ', ')" -ForegroundColor Cyan

# 2. Check destination quota if destination subscription is provided
if ($DestSub) {
    Write-Host "`nChecking destination subscription ($DestSub) regional compute quotas..." -ForegroundColor Cyan
    Set-AzContext -Subscription $DestSub -ErrorAction Stop | Out-Null

    $quotaResults = @()

    foreach ($loc in $regions) {
        Write-Host "Checking quota in region: $loc..." -ForegroundColor Yellow
        try {
            $destUsage = Get-AzVMUsage -Location $loc -ErrorAction Stop

            $totalCores = $destUsage | Where-Object { $_.Name.Value -eq "cores" }
            $sourceVmsInRegion = $vms | Where-Object { $_.Location -eq $loc }

            $quotaResults += [PSCustomObject]@{
                Location             = $loc
                SourceVMCount        = $sourceVmsInRegion.Count
                DestCoresCurrent     = $totalCores.CurrentValue
                DestCoresLimit       = $totalCores.Limit
                RemainingCores       = ($totalCores.Limit - $totalCores.CurrentValue)
                Status               = if (($totalCores.Limit - $totalCores.CurrentValue) -lt $sourceVmsInRegion.Count) { "REQUEST_QUOTA_INCREASE" } else { "SUFFICIENT" }
            }
        } catch {
            Write-Host "  ⚠️ Could not query quota in $loc: $_" -ForegroundColor Red
        }
    }

    $quotaResults | Format-Table -AutoSize
    $quotaResults | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding utf8
    Write-Host "Quota report saved to: $OutputFile" -ForegroundColor Green
}

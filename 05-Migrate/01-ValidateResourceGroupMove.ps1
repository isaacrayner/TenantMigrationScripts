<#
.SYNOPSIS
    Validates whether all resources in a Resource Group can be moved to the destination
    subscription using the ARM validateMoveResources API.
.DESCRIPTION
    Surfaces blockers (unsupported types, active locks, missing providers, etc.)
    before executing the actual move operation.
#>

param(
    [string]$ResourceGroupName,
    [string]$TargetSubscriptionId,
    [switch]$AllResourceGroups
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('TargetSubscriptionId')) { $TargetSubscriptionId = $destinationSubscriptionId }

$logFile = Join-Path $logRootDir "ValidateRGMove.log"

function Validate-SingleRG {
    param([string]$rgName)

    Write-Host "`n=== Validating Resource Group: $rgName ===" -ForegroundColor Cyan
    $destinationRGId = "/subscriptions/$TargetSubscriptionId/resourceGroups/$rgName"

    try {
        $sourceRG  = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
        $resources = Get-AzResource -ResourceGroupName $rgName -ErrorAction Stop

        if (-not $resources -or $resources.Count -eq 0) {
            Write-Host "  ⚠️ No resources found in '$rgName'. Nothing to validate." -ForegroundColor Yellow
            return $true
        }

        Write-Host "  Found $($resources.Count) resource(s). Calling ARM validateMoveResources..." -ForegroundColor Cyan

        $result = Invoke-AzResourceAction `
            -Action "validateMoveResources" `
            -ResourceId $sourceRG.ResourceId `
            -Parameters @{
                resources           = [string[]]$resources.ResourceId
                targetResourceGroup = $destinationRGId
            } `
            -Force `
            -ErrorAction Stop

        Write-Host "  ✅ Validation PASSED — all resources in '$rgName' are ready to move." -ForegroundColor Green
        Add-Content -Path $logFile -Value "[$((Get-Date).ToString('s'))] [PASS] $rgName ($($resources.Count) resources)"
        return $true

    } catch {
        Write-Host "  ❌ Validation FAILED for '$rgName':" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red

        if ($_.ErrorDetails.Message) {
            Write-Host "  ARM Error Detail:" -ForegroundColor Yellow
            try {
                $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
            } catch {
                Write-Host $_.ErrorDetails.Message
            }
        }
        Add-Content -Path $logFile -Value "[$((Get-Date).ToString('s'))] [FAIL] $rgName - $($_.Exception.Message)"
        return $false
    }
}

Set-AzContext -Subscription $sourceSubscriptionId -ErrorAction Stop | Out-Null

if ($AllResourceGroups) {
    Write-Host "Validating ALL resource groups in subscription $sourceSubscriptionId..." -ForegroundColor Cyan
    $allRGs = Get-AzResourceGroup
    $passed = 0
    $failed = 0

    foreach ($rg in $allRGs) {
        $ok = Validate-SingleRG -rgName $rg.ResourceGroupName
        if ($ok) { $passed++ } else { $failed++ }
    }

    Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
    Write-Host "Passed: $passed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
} else {
    if (-not $ResourceGroupName) {
        $ResourceGroupName = Read-Host "Enter the Resource Group name to validate"
    }
    Validate-SingleRG -rgName $ResourceGroupName
}

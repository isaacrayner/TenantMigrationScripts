<#
.SYNOPSIS
    Recreates all Resource Groups from the source subscription in the destination
    subscription, preserving locations and tags.
.DESCRIPTION
    Must be run before moving resources or recreating infrastructure in Phase 5.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SourceSub = $sourceSubscriptionId,
    [string]$DestSub   = $destinationSubscriptionId
)

$logFile = Join-Path $logRootDir "ResourceGroupRecreation.log"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$level] $message"
    Write-Host $line -ForegroundColor $(if ($level -eq "ERROR") { "Red" } elseif ($level -eq "WARN") { "Yellow" } else { "Cyan" })
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== Recreating Resource Groups in Destination Subscription ==="
Write-Log "Source Subscription     : $SourceSub"
Write-Log "Destination Subscription: $DestSub"

try {
    # Step 1: Retrieve all resource groups from the source subscription
    Write-Log "Retrieving resource groups from source..."
    Set-AzContext -Subscription $SourceSub -ErrorAction Stop | Out-Null
    $sourceRGs = Get-AzResourceGroup -ErrorAction Stop

    if (-not $sourceRGs -or $sourceRGs.Count -eq 0) {
        Write-Log "No resource groups found in source subscription." "WARN"
        exit 0
    }
    Write-Log "Found $($sourceRGs.Count) resource group(s) in source."

    # Step 2: Switch context to destination subscription
    Write-Log "Setting context to destination subscription..."
    Set-AzContext -Subscription $DestSub -ErrorAction Stop | Out-Null
    $destRGs = Get-AzResourceGroup -ErrorAction SilentlyContinue
    $destRGNames = [System.Collections.Generic.HashSet[string]]::new([string[]]($destRGs | ForEach-Object { $_.ResourceGroupName }))

    # Step 3: Recreate RGs
    foreach ($rg in $sourceRGs) {
        $rgName   = $rg.ResourceGroupName
        $location = $rg.Location
        $tags     = $rg.Tags

        if ($destRGNames.Contains($rgName)) {
            Write-Log "Resource group '$rgName' already exists in destination. Ensuring tags..." "WARN"
            if ($tags -and $tags.Count -gt 0) {
                Update-AzTag -ResourceId "/subscriptions/$DestSub/resourceGroups/$rgName" -Tag $tags -Operation Merge -ErrorAction SilentlyContinue | Out-Null
            }
            continue
        }

        try {
            Write-Log "Creating Resource Group: '$rgName' in location: '$location'..."
            if ($tags -and $tags.Count -gt 0) {
                New-AzResourceGroup -Name $rgName -Location $location -Tag $tags -Force -ErrorAction Stop | Out-Null
            } else {
                New-AzResourceGroup -Name $rgName -Location $location -Force -ErrorAction Stop | Out-Null
            }
            Write-Log "Successfully created Resource Group: '$rgName'" "SUCCESS"
        } catch {
            Write-Log "ERROR creating Resource Group '$rgName': $_" "ERROR"
        }
    }

    Write-Log "Resource group pre-creation completed successfully." "SUCCESS"
} catch {
    Write-Log "Unexpected fatal error: $_" "ERROR"
    exit 1
}

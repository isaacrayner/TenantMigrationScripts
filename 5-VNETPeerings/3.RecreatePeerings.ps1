<#
.SYNOPSIS
    Recreates Virtual Network Peerings in the destination subscription from the backup CSV/JSON.
.DESCRIPTION
    1. Sets context to destination subscription.
    2. Rewrites RemoteVNetId to destination subscription if the remote VNet was also moved.
    3. Creates the peering on the local VNet with original traffic forwarding and gateway transit flags.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [string]$BackupFile     = (Join-Path $backupRootDir "VNETs/NetPeeringsBackup.csv")
)

$logFile = Join-Path $logRootDir "VNetPeering_Restore.log"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$level] $message"
    Write-Host $line -ForegroundColor $(if ($level -eq "ERROR") { "Red" } elseif ($level -eq "WARN") { "Yellow" } else { "Cyan" })
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== Restoring Virtual Network Peerings in Destination Subscription ==="
Write-Log "Destination Subscription: $SubscriptionId"

Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $BackupFile)) {
    Write-Log "Backup file not found at $BackupFile. Skipping." "WARN"
    exit 0
}

$peeringData = Import-Csv -Path $BackupFile
if (-not $peeringData -or $peeringData.Count -eq 0) {
    Write-Log "No peerings found in backup file." "INFO"
    exit 0
}

Write-Log "Found $($peeringData.Count) peering(s) to process."

foreach ($peering in $peeringData) {
    $localVNetName = $peering.LocalVNetName
    $localRG       = $peering.LocalResourceGroup
    $peeringName   = $peering.PeeringName
    $remoteVNetId  = $peering.RemoteVNetId

    # If the remote VNet was in the source subscription and also moved, rewrite the subscription ID
    $updatedRemoteVNetId = $remoteVNetId -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId

    Write-Log "Processing Peering '$peeringName' on Local VNet '$localVNetName' (RG: '$localRG')..."

    try {
        $localVNet = Get-AzVirtualNetwork -Name $localVNetName -ResourceGroupName $localRG -ErrorAction Stop

        $existing = Get-AzVirtualNetworkPeering -VirtualNetworkName $localVNetName -ResourceGroupName $localRG -Name $peeringName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "  [SKIP] Peering '$peeringName' already exists on '$localVNetName'." "WARN"
            continue
        }

        # Add the peering
        $params = @{
            Name                      = $peeringName
            VirtualNetwork            = $localVNet
            RemoteVirtualNetworkId    = $updatedRemoteVNetId
            AllowVirtualNetworkAccess = [System.Convert]::ToBoolean($peering.AllowVirtualNetworkAccess)
            AllowForwardedTraffic     = [System.Convert]::ToBoolean($peering.AllowForwardedTraffic)
            AllowGatewayTransit       = [System.Convert]::ToBoolean($peering.AllowGatewayTransit)
            UseRemoteGateways         = [System.Convert]::ToBoolean($peering.UseRemoteGateways)
        }

        Add-AzVirtualNetworkPeering @params -ErrorAction Stop | Out-Null
        Write-Log "  ✅ Created Peering: '$peeringName' on '$localVNetName'" "SUCCESS"

    } catch {
        Write-Log "  ❌ Failed to create peering '$peeringName': $_" "ERROR"
    }
}

Write-Log "`nVNet Peering restoration completed. Log saved to: $logFile" "SUCCESS"
<#
.SYNOPSIS
    Exports all Public IP address configurations from the source subscription.
.DESCRIPTION
    Captures SKU, allocation method, IP version, zones, DNS settings, and associations
    to allow accurate recreation or reassociation in the destination subscription.
#>

param(
    [string]$SubscriptionId,
    [string]$JsonFile,
    [string]$CsvFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('JsonFile')) { $JsonFile = (Join-Path $backupRootDir "PublicIP_Export.json") }
if (-not $PSBoundParameters.ContainsKey('CsvFile')) { $CsvFile = (Join-Path $backupRootDir "PublicIP_Export.csv") }

$logFile = Join-Path $logRootDir "PublicIP_Backup.log"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$level] $message"
    Write-Host $line -ForegroundColor $(if ($level -eq "ERROR") { "Red" } elseif ($level -eq "WARN") { "Yellow" } else { "Cyan" })
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== Backing up Public IP Addresses ==="
Write-Log "Source Subscription: $SubscriptionId"

try {
    Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

    $publicIPs = Get-AzPublicIpAddress -ErrorAction Stop

    if (-not $publicIPs -or $publicIPs.Count -eq 0) {
        Write-Log "No Public IPs found in subscription." "WARN"
        "[]" | Out-File -FilePath $JsonFile -Encoding utf8
        exit 0
    }

    Write-Log "Found $($publicIPs.Count) Public IP(s)."

    $ipList = @()
    foreach ($pip in $publicIPs) {
        $ipList += [PSCustomObject]@{
            Name                   = $pip.Name
            ResourceGroupName      = $pip.ResourceGroupName
            Location               = $pip.Location
            Sku                    = if ($pip.Sku.Name) { $pip.Sku.Name } else { "Standard" }
            AllocationMethod       = if ($pip.PublicIpAllocationMethod) { $pip.PublicIpAllocationMethod } else { "Static" }
            IpAddressVersion       = if ($pip.PublicIpAddressVersion) { $pip.PublicIpAddressVersion } else { "IPv4" }
            IpAddress              = $pip.IpAddress
            Zones                  = if ($pip.Zones) { $pip.Zones -join "," } else { "" }
            DomainNameLabel        = if ($pip.DnsSettings) { $pip.DnsSettings.DomainNameLabel } else { "" }
            Fqdn                   = if ($pip.DnsSettings) { $pip.DnsSettings.Fqdn } else { "" }
            AssociatedNicId        = if ($pip.IpConfiguration) { $pip.IpConfiguration.Id } else { "" }
            AssociatedIpConfigName = if ($pip.IpConfiguration) { ($pip.IpConfiguration.Id -split "/")[-1] } else { "" }
        }
    }

    $ipList | ConvertTo-Json -Depth 5 | Out-File -FilePath $JsonFile -Encoding utf8
    $ipList | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding utf8

    Write-Log "Public IP details exported to $JsonFile and $CsvFile" "SUCCESS"
} catch {
    Write-Log "ERROR retrieving Public IPs: $_" "ERROR"
    exit 1
}

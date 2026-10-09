<#
.SYNOPSIS
    Recreates Azure Monitor Action Groups in the destination subscription from the JSON backup.
.DESCRIPTION
    Reads ActionGroups_Export.json and creates each action group using native ARM template deployment
    or Az cmdlets, completely avoiding non-existent az CLI subcommands.
#>

param(
    [string]$SubscriptionId,
    [string]$ExportFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $destinationSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('ExportFile')) { $ExportFile = (Join-Path $backupRootDir "ActionGroups_Export.json") }

Write-Host "=== Restoring Azure Monitor Action Groups ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $ExportFile)) {
    Write-Host "Backup file not found: $ExportFile. Skipping." -ForegroundColor Yellow
    exit 0
}

$actionGroups = Get-Content $ExportFile -Raw | ConvertFrom-Json

if (-not $actionGroups -or $actionGroups.Count -eq 0) {
    Write-Host "No Action Groups to restore." -ForegroundColor Green
    exit 0
}

Write-Host "Restoring $($actionGroups.Count) Action Group(s) to destination..." -ForegroundColor Cyan

foreach ($ag in $actionGroups) {
    $rgName    = ($ag.id -split "/")[4]
    $name      = $ag.name
    $shortName = $ag.groupShortName
    $location  = if ($ag.location) { $ag.location } else { "Global" }

    Write-Host "Processing Action Group '$name' in RG '$rgName'..." -ForegroundColor Yellow

    # Ensure Resource Group exists
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Host "  Creating RG '$rgName' in destination..." -ForegroundColor Cyan
        New-AzResourceGroup -Name $rgName -Location "uksouth" -Force | Out-Null
    }

    # Build action group receivers
    $emailReceivers = @()
    if ($ag.emailReceivers) {
        foreach ($r in $ag.emailReceivers) {
            $emailReceivers += New-AzActionGroupEmailReceiverObject -Name $r.name -EmailAddress $r.emailAddress -UseCommonAlertSchema:($r.useCommonAlertSchema -eq $true)
        }
    }

    $smsReceivers = @()
    if ($ag.smsReceivers) {
        foreach ($r in $ag.smsReceivers) {
            $smsReceivers += New-AzActionGroupSmsReceiverObject -Name $r.name -CountryCode $r.countryCode -PhoneNumber $r.phoneNumber
        }
    }

    $webhookReceivers = @()
    if ($ag.webhookReceivers) {
        foreach ($r in $ag.webhookReceivers) {
            # Update webhook URL if it points to an old subscription resource
            $uri = $r.serviceUri -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId
            $webhookReceivers += New-AzActionGroupWebhookReceiverObject -Name $r.name -ServiceUri $uri -UseCommonAlertSchema:($r.useCommonAlertSchema -eq $true)
        }
    }

    try {
        Set-AzActionGroup `
            -ResourceGroupName $rgName `
            -Name $name `
            -ShortName $shortName `
            -EmailReceiver $emailReceivers `
            -SmsReceiver $smsReceivers `
            -WebhookReceiver $webhookReceivers `
            -ErrorAction Stop | Out-Null

        Write-Host "  ✅ Successfully restored Action Group: '$name'" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Failed to create Action Group '$name': $_" -ForegroundColor Red
    }
}

Write-Host "`nAction Group restoration complete." -ForegroundColor Green

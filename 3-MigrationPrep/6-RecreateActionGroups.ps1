## DESCRIPTION: Exports all Azure Monitor Action Groups from the source subscription to a JSON
##              file, then recreates them in the destination subscription. Requires Azure CLI.
## USAGE:       1. Update subscription IDs in the root migration-params.ps1 file.
##              2. Review and edit C:\temp\ActionGroups_Export.json before import if needed.
##              3. Run in PowerShell with the Azure CLI (az) installed.
##              4. Press Enter at the prompt to proceed with import after reviewing the export.
. (Join-Path $PSScriptRoot "..\migration-params.ps1")

# Define variables (loaded from migration-params.ps1)
# $sourceSubscriptionId and $destSubscriptionId are set from migration-params.ps1
$exportFile = "C:\temp\ActionGroups_Export.json"

# Ensure Azure CLI is installed
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI is not installed. Please install Azure CLI first." -ForegroundColor Red
    exit 1
}

# Step 1: Log in to Azure and Set Source Subscription
Write-Host "Logging into Azure..." -ForegroundColor Cyan
Start-Process "az" -ArgumentList "login --only-show-errors" -NoNewWindow -Wait

Write-Host "Setting Source Subscription: $sourceSubscriptionId" -ForegroundColor Cyan
Start-Process "az" -ArgumentList "account set --subscription $sourceSubscriptionId" -NoNewWindow -Wait

# Step 2: Get all Resource Groups in the Source Subscription
Write-Host "Retrieving Resource Groups in the Source Subscription..." -ForegroundColor Cyan
$resourceGroups = & az group list --query "[].name" -o json | ConvertFrom-Json

if (-not $resourceGroups) {
    Write-Host "No Resource Groups found in Subscription: $sourceSubscriptionId" -ForegroundColor Red
    exit 1
}

# Step 3: Export Action Groups to JSON
Write-Host "Exporting Action Groups from all Resource Groups..." -ForegroundColor Cyan
$allActionGroups = @()

foreach ($rg in $resourceGroups) {
    Write-Host "Checking Resource Group: $rg..." -ForegroundColor Yellow

    $actionGroups = & az monitor action-group list --resource-group $rg --query "[]" -o json | ConvertFrom-Json

    if (-not $actionGroups) {
        Write-Host "No Action Groups found in $rg." -ForegroundColor Gray
        continue
    }

    foreach ($actionGroup in $actionGroups) {
        $exportItem = @{
            ResourceGroup     = $rg
            Name              = $actionGroup.name
            ShortName         = $actionGroup.shortName
            Enabled           = $actionGroup.enabled
            EmailReceivers    = $actionGroup.emailReceivers | ForEach-Object { $_.emailAddress }
            SMSReceivers      = $actionGroup.smsReceivers | ForEach-Object { $_.phoneNumber }
            WebhookReceivers  = $actionGroup.webhookReceivers | ForEach-Object { $_.serviceUri }
        }
        $allActionGroups += $exportItem
    }
}

# Save the data to JSON
$allActionGroups | ConvertTo-Json -Depth 10 | Set-Content -Path $exportFile

Write-Host "Action Groups exported successfully to $exportFile" -ForegroundColor Green
Write-Host "Please modify the JSON if needed (e.g., update emails, phone numbers, or webhook URLs)." -ForegroundColor Yellow

# Prompt user before proceeding with import
Read-Host "Press Enter to continue with the import (or CTRL+C to cancel)..."

# Step 4: Switch to Destination Subscription
Write-Host "Setting Destination Subscription: $destSubscriptionId" -ForegroundColor Cyan
Start-Process "az" -ArgumentList "account set --subscription $destSubscriptionId" -NoNewWindow -Wait

# Step 5: Import and Recreate Action Groups in Destination Subscription
Write-Host "Importing Action Groups into the new subscription..." -ForegroundColor Cyan

$importData = Get-Content -Path $exportFile | ConvertFrom-Json

foreach ($entry in $importData) {
    $rg = $entry.ResourceGroup
    $name = $entry.Name
    $shortName = $entry.ShortName
    $enabled = $entry.Enabled
    $emailReceivers = $entry.EmailReceivers -join ","
    $smsReceivers = $entry.SMSReceivers -join ","
    $webhookReceivers = $entry.WebhookReceivers -join ","

    Write-Host "Creating Action Group: $name in Resource Group: $rg..." -ForegroundColor Yellow

    # Ensure the resource group exists in the destination
    Start-Process "az" -ArgumentList "group create --name $rg --location uksouth --only-show-errors" -NoNewWindow -Wait

    # Construct receivers array for CLI
    $receivers = "[]"

    if ($emailReceivers -ne "") {
        $receivers = & echo $receivers | az json set -p "0.emailAddress=$emailReceivers" -p "0.name='EmailReceiver'" -p "0.status='Enabled'"
    }
    if ($smsReceivers -ne "") {
        $receivers = & echo $receivers | az json set -p "1.phoneNumber=$smsReceivers" -p "1.name='SMSReceiver'" -p "1.status='Enabled'"
    }
    if ($webhookReceivers -ne "") {
        $receivers = & echo $receivers | az json set -p "2.serviceUri=$webhookReceivers" -p "2.name='WebhookReceiver'" -p "2.status='Enabled'"
    }

    # Create Action Group
    Start-Process "az" -ArgumentList "monitor action-group create --resource-group $rg --name `"$name`" --short-name `"$shortName`" --action $receivers --only-show-errors" -NoNewWindow -Wait

    if ($?) {
        Write-Host "Successfully created Action Group: $name in Resource Group: $rg" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to create Action Group: $name in Resource Group: $rg" -ForegroundColor Red
    }
}

Write-Host "Action Group migration completed successfully!" -ForegroundColor Green

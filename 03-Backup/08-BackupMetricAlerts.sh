#!/bin/bash
## DESCRIPTION: Exports all metric alerts from the source subscription to a clean JSON file.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.
##              Used by 06-Restore/17-RestoreMetricAlerts.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

EXPORT_FILE="${BACKUP_ROOT_DIR}/metric-alerts.json"

echo "=== Backing up Metric Alerts ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

echo "Exporting all metric alerts from source subscription..."
ALERTS=$(az monitor metrics alert list --subscription "$SOURCE_SUBSCRIPTION_ID" -o json)
ALERT_COUNT=$(echo "$ALERTS" | jq length)

echo "Found $ALERT_COUNT metric alert(s)."
echo "$ALERTS" > "$EXPORT_FILE"

echo "✅ Saved metric alerts to: $EXPORT_FILE"
echo "Restore in destination via 06-Restore/17-RestoreMetricAlerts.sh."
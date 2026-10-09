#!/bin/bash
## DESCRIPTION: Recreates metric alerts in the destination subscription from the JSON backup
##              produced by 03-Backup/08-BackupMetricAlerts.sh.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

EXPORT_FILE="${BACKUP_ROOT_DIR}/metric-alerts.json"

if [[ ! -f "$EXPORT_FILE" ]]; then
    echo "Alert backup file not found at $EXPORT_FILE. Skipping."
    exit 0
fi

echo "=== Restoring Metric Alerts in Destination Subscription ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

ALERT_COUNT=$(jq length "$EXPORT_FILE")
if [[ "$ALERT_COUNT" -eq 0 ]]; then
    echo "No alerts in backup file."
    exit 0
fi

echo "Processing $ALERT_COUNT alert(s)..."

jq -c '.[]' "$EXPORT_FILE" | while read -r alert; do
    NAME=$(echo "$alert" | jq -r '.name')
    ALERT_ID=$(echo "$alert" | jq -r '.id')
    RG=$(echo "$ALERT_ID" | awk -F'/' '{print $5}')
    DESCRIPTION=$(echo "$alert" | jq -r '.description // ""')
    SEVERITY=$(echo "$alert" | jq -r '.severity // 2')
    ENABLED=$(echo "$alert" | jq -r '.enabled // true')
    WINDOW_SIZE=$(echo "$alert" | jq -r '.windowSize // "PT5M"')
    EVAL_FREQ=$(echo "$alert" | jq -r '.evaluationFrequency // "PT1M"')

    # Rewrite scopes and actions: swap SOURCE_SUBSCRIPTION_ID for DESTINATION_SUBSCRIPTION_ID
    SCOPES=$(echo "$alert" | jq -r '.scopes[]' | sed "s|${SOURCE_SUBSCRIPTION_ID}|${DESTINATION_SUBSCRIPTION_ID}|g")
    ACTIONS=$(echo "$alert" | jq -r '.actions[].actionGroupId // empty' | sed "s|${SOURCE_SUBSCRIPTION_ID}|${DESTINATION_SUBSCRIPTION_ID}|g")

    echo "Recreating Metric Alert: '$NAME' in RG '$RG'..."

    # Extract single condition if present
    METRIC=$(echo "$alert" | jq -r '.criteria.allOf[0].metricName // empty')
    OPERATOR=$(echo "$alert" | jq -r '.criteria.allOf[0].operator // empty')
    THRESHOLD=$(echo "$alert" | jq -r '.criteria.allOf[0].threshold // empty')
    AGGREGATION=$(echo "$alert" | jq -r '.criteria.allOf[0].timeAggregation // empty')

    # Build create arguments
    CMD=(az monitor metrics alert create \
        --name "$NAME" \
        --resource-group "$RG" \
        --severity "$SEVERITY" \
        --window-size "$WINDOW_SIZE" \
        --evaluation-frequency "$EVAL_FREQ" \
        --subscription "$DESTINATION_SUBSCRIPTION_ID" \
        --only-show-errors)

    if [[ -n "$DESCRIPTION" ]]; then
        CMD+=(--description "$DESCRIPTION")
    fi

    for s in $SCOPES; do
        CMD+=(--scopes "$s")
    done

    for a in $ACTIONS; do
        CMD+=(--action "$a")
    done

    if [[ -n "$METRIC" && -n "$OPERATOR" && -n "$THRESHOLD" && -n "$AGGREGATION" ]]; then
        CMD+=(--condition "type=static threshold=$THRESHOLD metric=$METRIC operator=$OPERATOR aggregation=$AGGREGATION")
    fi

    # Execute
    if "${CMD[@]}"; then
        echo "  ✅ Created Metric Alert: $NAME"
    else
        echo "  ❌ Failed to create Metric Alert: $NAME"
    fi
done

echo "All metric alerts processed successfully!"

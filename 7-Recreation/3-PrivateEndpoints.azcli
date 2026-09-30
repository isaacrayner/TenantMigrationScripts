#!/bin/bash
## DESCRIPTION: Recreates all private endpoints in the destination subscription from JSON backups.
##              Rewrites subscription IDs in subnet IDs and privateLinkServiceId.
## USAGE:       Run in bash/WSL after resources have moved to the destination subscription.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

PE_BACKUP_DIR="${BACKUP_ROOT_DIR}/PrivateEndpoints"

if [[ ! -d "$PE_BACKUP_DIR" ]]; then
    echo "Private endpoint backup directory $PE_BACKUP_DIR not found. Skipping."
    exit 0
fi

echo "=== Recreating Private Endpoints in Destination Subscription ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

for file in "$PE_BACKUP_DIR"/*_PrivateEndpoint.json; do
    [[ -f "$file" ]] || continue

    name=$(jq -r '.name' "$file")
    rg=$(jq -r '.resourceGroup' "$file")
    location=$(jq -r '.location' "$file")

    # Rewrite subnet ID and target resource ID from source subscription to destination subscription
    raw_subnet_id=$(jq -r '.subnet.id' "$file")
    subnet_id="${raw_subnet_id//$SOURCE_SUBSCRIPTION_ID/$DESTINATION_SUBSCRIPTION_ID}"

    raw_pls_id=$(jq -r '.privateLinkServiceConnections[0].privateLinkServiceId // empty' "$file")
    pls_id="${raw_pls_id//$SOURCE_SUBSCRIPTION_ID/$DESTINATION_SUBSCRIPTION_ID}"

    group_ids=$(jq -r '.privateLinkServiceConnections[0].groupIds[]? // empty' "$file" | tr '\n' ' ')

    echo "Recreating Private Endpoint: $name in RG: $rg..."

    # Check if PE already exists
    EXISTS=$(az network private-endpoint show --name "$name" --resource-group "$rg" --query "name" -o tsv 2>/dev/null || true)
    if [[ -n "$EXISTS" ]]; then
        echo "  [SKIP] Private Endpoint '$name' already exists in RG '$rg'."
        continue
    fi

    CMD=(az network private-endpoint create \
        --name "$name" \
        --resource-group "$rg" \
        --location "$location" \
        --subnet "$subnet_id" \
        --connection-name "${name}-connection" \
        --subscription "$DESTINATION_SUBSCRIPTION_ID")

    if [[ -n "$pls_id" ]]; then
        CMD+=(--private-connection-resource-id "$pls_id")
    fi

    if [[ -n "$group_ids" ]]; then
        CMD+=(--group-id $group_ids)
    fi

    if "${CMD[@]}"; then
        echo "  ✅ Private Endpoint $name created successfully."

        # Check and restore DNS Zone Groups if saved
        dns_file="${PE_BACKUP_DIR}/${name}_DnsZoneGroups.json"
        if [[ -f "$dns_file" ]]; then
            echo "  Restoring Private DNS Zone Group for $name..."
            jq -c '.[]' "$dns_file" | while read -r dzg; do
                dzg_name=$(echo "$dzg" | jq -r '.name')
                zone_id=$(echo "$dzg" | jq -r '.privateDnsZoneConfigs[0].privateDnsZoneId // empty' | sed "s|${SOURCE_SUBSCRIPTION_ID}|${DESTINATION_SUBSCRIPTION_ID}|g")
                if [[ -n "$zone_id" ]]; then
                    az network private-endpoint dns-zone-group create \
                        --endpoint-name "$name" \
                        --resource-group "$rg" \
                        --name "$dzg_name" \
                        --private-dns-zone "$zone_id" \
                        --zone-name "default" 2>/dev/null || true
                fi
            done
        fi
    else
        echo "  ❌ Failed to recreate Private Endpoint: $name"
    fi
done

echo "Private Endpoint recreation process completed!"

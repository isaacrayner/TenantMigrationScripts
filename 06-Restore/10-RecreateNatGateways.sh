#!/bin/bash
## DESCRIPTION: Recreates NAT Gateways and reattaches them to subnets in the destination subscription
##              using the backup JSON files produced by 03-Backup/14-BackupNatGateways.sh.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

BACKUP_DIR="${BACKUP_ROOT_DIR}/NATGateways"
NAT_GATEWAYS_FILE="${BACKUP_DIR}/nat_gateways.json"
SUBNETS_FILE="${BACKUP_DIR}/subnets.json"

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "NAT Gateway backup directory $BACKUP_DIR not found. Skipping."
    exit 0
fi

echo "=== Recreating NAT Gateways & Reattaching to Subnets ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

# Step 1: Recreate NAT Gateways if needed
if [[ -f "$NAT_GATEWAYS_FILE" ]]; then
    jq -c '.[]?' "$NAT_GATEWAYS_FILE" | while read -r nat; do
        NAT_NAME=$(echo "$nat" | jq -r '.name')
        RG=$(echo "$nat" | jq -r '.resourceGroup')
        LOCATION=$(echo "$nat" | jq -r '.location')
        SKU=$(echo "$nat" | jq -r '.sku.name // "Standard"')

        echo "Ensuring NAT Gateway '$NAT_NAME' exists in RG '$RG'..."
        EXISTS=$(az network nat gateway show --name "$NAT_NAME" --resource-group "$RG" --query "name" -o tsv 2>/dev/null || true)
        if [[ -z "$EXISTS" ]]; then
            az network nat gateway create \
                --name "$NAT_NAME" \
                --resource-group "$RG" \
                --location "$LOCATION" \
                --sku "$SKU" \
                --subscription "$DESTINATION_SUBSCRIPTION_ID" \
                --only-show-errors
            echo "  ✅ Created NAT Gateway: $NAT_NAME"
        else
            echo "  [EXISTS] NAT Gateway '$NAT_NAME' is present."
        fi
    done
fi

# Step 2: Reattach to Subnets
if [[ -f "$SUBNETS_FILE" ]]; then
    echo "Reattaching NAT Gateways to subnets..."
    jq -c '.[]?' "$SUBNETS_FILE" | while read -r subnet; do
        SUBNET_NAME=$(echo "$subnet" | jq -r '.name')
        SUBNET_ID=$(echo "$subnet" | jq -r '.id')
        RG=$(echo "$SUBNET_ID" | awk -F'/' '{print $5}')
        VNET_NAME=$(echo "$SUBNET_ID" | awk -F'/' '{print $9}')
        NAT_GATEWAY_ID=$(echo "$subnet" | jq -r '.natGateway.id // empty')

        if [[ -n "$NAT_GATEWAY_ID" ]]; then
            NAT_GATEWAY_NAME=$(basename "$NAT_GATEWAY_ID")
            echo "Reattaching NAT Gateway: $NAT_GATEWAY_NAME to Subnet: $SUBNET_NAME in VNet: $VNET_NAME (RG: $RG)..."

            az network vnet subnet update \
                --name "$SUBNET_NAME" \
                --vnet-name "$VNET_NAME" \
                --resource-group "$RG" \
                --nat-gateway "$NAT_GATEWAY_NAME" \
                --subscription "$DESTINATION_SUBSCRIPTION_ID" \
                --only-show-errors

            echo "  ✅ Reattached NAT Gateway to $SUBNET_NAME"
        fi
    done
fi

echo "NAT Gateway restoration complete!"

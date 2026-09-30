#!/bin/bash
## DESCRIPTION: Backs up all NAT Gateway configurations and associated VNet subnet details
##              to migration-data/NATGateways/ for restoration after migration.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

BACKUP_DIR="${BACKUP_ROOT_DIR}/NATGateways"
mkdir -p "$BACKUP_DIR"

echo "=== Backing up NAT Gateways & Subnet Associations ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

# Backup NAT Gateways
echo "Backing up NAT Gateways..."
NAT_GATEWAYS_FILE="${BACKUP_DIR}/nat_gateways.json"
az network nat gateway list --subscription "$SOURCE_SUBSCRIPTION_ID" -o json > "$NAT_GATEWAYS_FILE"
NAT_COUNT=$(jq length "$NAT_GATEWAYS_FILE")
echo "Found $NAT_COUNT NAT Gateway(s)."

# Backup Subnet Associations
echo "Backing up Subnet Associations..."
SUBNETS_FILE="${BACKUP_DIR}/subnets.json"
echo "[]" > "$SUBNETS_FILE"

VNETS=$(az network vnet list --subscription "$SOURCE_SUBSCRIPTION_ID" --query "[].{name:name, rg:resourceGroup}" -o json)

echo "$VNETS" | jq -c '.[]' | while read -r vnet; do
    VNET_NAME=$(echo "$vnet" | jq -r '.name')
    RG=$(echo "$vnet" | jq -r '.rg')

    SUBNET_LIST=$(az network vnet subnet list --resource-group "$RG" --vnet-name "$VNET_NAME" -o json)

    # Filter to subnets that have a NAT gateway attached
    NAT_SUBNETS=$(echo "$SUBNET_LIST" | jq '[.[] | select(.natGateway != null)]')
    if [[ $(echo "$NAT_SUBNETS" | jq length) -gt 0 ]]; then
        echo "  Found NAT Gateway associated subnets in VNet: $VNET_NAME"
        jq -s '.[0] + .[1]' "$SUBNETS_FILE" <(echo "$NAT_SUBNETS") > "${SUBNETS_FILE}.tmp" && mv "${SUBNETS_FILE}.tmp" "$SUBNETS_FILE"
    fi
done

echo "✅ NAT Gateway backup completed! Saved in: $BACKUP_DIR"

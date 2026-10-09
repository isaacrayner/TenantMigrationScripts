#!/bin/bash
## DESCRIPTION: Reattaches public IP addresses to migrated NICs/VMs in the destination subscription.
##              Reads the mapping saved by 04-Cleanup/05-DisassociatePublicIPs.sh.
## USAGE:       Run in bash/WSL after resources have been migrated to the destination subscription.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

TEMP_FILE="${BACKUP_ROOT_DIR}/public_ips_associations.json"

if [[ ! -f "$TEMP_FILE" ]]; then
    echo "Public IP association file not found at $TEMP_FILE. Skipping."
    exit 0
fi

echo "=== Reattaching Public IPs in Destination Subscription ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

RECORD_COUNT=$(jq length "$TEMP_FILE")
if [[ "$RECORD_COUNT" -eq 0 ]]; then
    echo "No Public IP associations to restore."
    exit 0
fi

echo "Processing $RECORD_COUNT association(s)..."

jq -c '.[]' "$TEMP_FILE" | while read -r item; do
    VM_NAME=$(echo "$item" | jq -r '.VM')
    NIC_NAME=$(echo "$item" | jq -r '.NicName')
    IPCONFIG_NAME=$(echo "$item" | jq -r '.IpConfigName // "ipconfig1"')
    PUBLIC_IP_NAME=$(echo "$item" | jq -r '.PublicIPName')
    RESOURCE_GROUP=$(echo "$item" | jq -r '.ResourceGroup')

    echo "Reattaching Public IP '$PUBLIC_IP_NAME' to NIC '$NIC_NAME' ($IPCONFIG_NAME) in RG '$RESOURCE_GROUP'..."

    # Check if Public IP exists in destination RG
    PIP_ID=$(az network public-ip show --name "$PUBLIC_IP_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv 2>/dev/null || true)

    if [[ -z "$PIP_ID" ]]; then
        echo "  ⚠️ Public IP '$PUBLIC_IP_NAME' not found in RG '$RESOURCE_GROUP'. Skipping."
        continue
    fi

    # Reattach Public IP
    if az network nic ip-config update \
        --name "$IPCONFIG_NAME" \
        --nic-name "$NIC_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --public-ip-address "$PIP_ID" \
        --subscription "$DESTINATION_SUBSCRIPTION_ID" \
        --only-show-errors; then
        echo "  ✅ Successfully reattached $PUBLIC_IP_NAME to $NIC_NAME ($IPCONFIG_NAME)"
    else
        echo "  ❌ Failed to reattach $PUBLIC_IP_NAME to $NIC_NAME"
    fi
done

echo "Public IP reattachment completed!"

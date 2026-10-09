#!/bin/bash
## DESCRIPTION: Restores SSH public keys in the destination subscription from the JSON backup.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

SSH_BACKUP_DIR="${BACKUP_ROOT_DIR}/SSHKeys"
KEYS_FILE="${SSH_BACKUP_DIR}/ssh_keys.json"

if [[ ! -f "$KEYS_FILE" ]]; then
    echo "SSH keys backup file not found at $KEYS_FILE. Skipping."
    exit 0
fi

echo "=== Restoring SSH Public Keys in Destination Subscription ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

KEY_COUNT=$(jq length "$KEYS_FILE")
if [[ "$KEY_COUNT" -eq 0 ]]; then
    echo "No SSH keys to restore."
    exit 0
fi

jq -c '.[]' "$KEYS_FILE" | while read -r item; do
    NAME=$(echo "$item" | jq -r '.name')
    RG=$(echo "$item" | jq -r '.resourceGroup')
    LOCATION=$(echo "$item" | jq -r '.location')
    PUBLIC_KEY=$(echo "$item" | jq -r '.publicKey')

    echo "Processing SSH Key: $NAME in RG: $RG..."

    # Ensure resource group exists
    az group create --name "$RG" --location "$LOCATION" --subscription "$DESTINATION_SUBSCRIPTION_ID" --output none 2>/dev/null || true

    # Check if key already exists
    EXISTS=$(az sshkey show --name "$NAME" --resource-group "$RG" --subscription "$DESTINATION_SUBSCRIPTION_ID" --query "name" -o tsv 2>/dev/null || true)
    if [[ -n "$EXISTS" ]]; then
        echo "  [SKIP] SSH Key '$NAME' already exists in RG '$RG'."
        continue
    fi

    az sshkey create \
        --name "$NAME" \
        --public-key "$PUBLIC_KEY" \
        --resource-group "$RG" \
        --subscription "$DESTINATION_SUBSCRIPTION_ID" \
        --output none

    echo "  ✅ Created SSH Key: $NAME"
done

echo "SSH key restoration completed successfully!"

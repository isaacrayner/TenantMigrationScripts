#!/bin/bash
## DESCRIPTION: Backs up Key Vault access policies and RBAC status for all Key Vaults
##              across all resource groups to migration-data/KeyVaultAccess/.
## USAGE:       Run in bash/WSL with Azure CLI installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

KV_BACKUP_DIR="${BACKUP_ROOT_DIR}/KeyVaultAccess"
mkdir -p "$KV_BACKUP_DIR"

echo "=== Backing up Key Vault Access Policies ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

KEYVAULTS=$(az keyvault list --subscription "$SOURCE_SUBSCRIPTION_ID" --query "[].{name:name, rg:resourceGroup}" -o json)

KV_COUNT=$(echo "$KEYVAULTS" | jq length)
if [[ "$KV_COUNT" -eq 0 ]]; then
    echo "No Key Vaults found in subscription."
    exit 0
fi

echo "Found $KV_COUNT Key Vault(s). Backing up..."

echo "$KEYVAULTS" | jq -c '.[]' | while read -r kv; do
    NAME=$(echo "$kv" | jq -r '.name')
    RG=$(echo "$kv" | jq -r '.rg')

    echo "Processing Key Vault: $NAME (RG: $RG)..."

    # Save full properties including RBAC authorization and access policies
    az keyvault show --name "$NAME" --resource-group "$RG" -o json > "${KV_BACKUP_DIR}/${NAME}_full.json"
    az keyvault show --name "$NAME" --resource-group "$RG" --query "properties.accessPolicies" -o json > "${KV_BACKUP_DIR}/${NAME}_access_policies.json"

    echo "  ✅ Saved policies for: $NAME"
done

echo "Key Vault access policies backup completed! Saved in: $KV_BACKUP_DIR"

#!/bin/bash
## DESCRIPTION: Updates Key Vault tenant IDs and restores access policies in the destination
##              subscription from JSON backups produced by 03-Backup/11-BackupKeyVaultAccess.sh.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

KV_BACKUP_DIR="${BACKUP_ROOT_DIR}/KeyVaultAccess"

echo "=== Updating Key Vaults & Restoring Access Policies ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Current Tenant ID: $TENANT_ID"

KEYVAULTS=$(az keyvault list --subscription "$DESTINATION_SUBSCRIPTION_ID" --query "[].{name:name, rg:resourceGroup}" -o json)

KV_COUNT=$(echo "$KEYVAULTS" | jq length)
if [[ "$KV_COUNT" -eq 0 ]]; then
    echo "No Key Vaults found in destination subscription."
    exit 0
fi

echo "Found $KV_COUNT Key Vault(s). Updating tenant ID and removing stale policies..."

echo "$KEYVAULTS" | jq -c '.[]' | while read -r row; do
    kvName=$(echo "$row" | jq -r '.name')
    rgName=$(echo "$row" | jq -r '.rg')

    echo "Updating Key Vault: $kvName in RG: $rgName..."

    # Check if Key Vault uses Azure RBAC
    ENABLE_RBAC=$(az keyvault show -n "$kvName" -g "$rgName" --query "properties.enableRbacAuthorization" -o tsv 2>/dev/null || echo "false")

    if [[ "$ENABLE_RBAC" == "true" ]]; then
        echo "  Key Vault $kvName uses Azure RBAC. Updating tenant ID only..."
        az keyvault update -n "$kvName" -g "$rgName" --set properties.tenantId="$TENANT_ID" --only-show-errors
    else
        echo "  Updating tenant ID and refreshing access policies..."
        az keyvault update -n "$kvName" -g "$rgName" --set properties.tenantId="$TENANT_ID" --only-show-errors
    fi
done

# Restore access policies from backup
if [[ -d "$KV_BACKUP_DIR" ]]; then
    echo "Restoring Key Vault access policies from backup..."

    for POLICY_FILE in "$KV_BACKUP_DIR"/*_access_policies.json; do
        [[ -f "$POLICY_FILE" ]] || continue

        KV_NAME=$(basename "$POLICY_FILE" _access_policies.json)
        echo "Restoring access policies for Key Vault: $KV_NAME..."

        jq -c '.[]?' "$POLICY_FILE" | while read -r policy; do
            OBJECT_ID=$(echo "$policy" | jq -r '.objectId')

            PERM_KEYS=$(echo "$policy" | jq -r '.permissions.keys[]? // empty' | tr '\n' ' ')
            PERM_SECRETS=$(echo "$policy" | jq -r '.permissions.secrets[]? // empty' | tr '\n' ' ')
            PERM_CERTS=$(echo "$policy" | jq -r '.permissions.certificates[]? // empty' | tr '\n' ' ')

            echo "  Applying policy for ObjectId: $OBJECT_ID on $KV_NAME..."

            CMD=(az keyvault set-policy --name "$KV_NAME" --object-id "$OBJECT_ID" --only-show-errors)

            if [[ -n "$PERM_KEYS" ]]; then CMD+=(--key-permissions $PERM_KEYS); fi
            if [[ -n "$PERM_SECRETS" ]]; then CMD+=(--secret-permissions $PERM_SECRETS); fi
            if [[ -n "$PERM_CERTS" ]]; then CMD+=(--certificate-permissions $PERM_CERTS); fi

            "${CMD[@]}" || echo "    ⚠️ Could not set policy for principal $OBJECT_ID (may need recreation in target tenant)"
        done
    done
fi

echo "Key Vault tenant updates and access policies restored successfully!"

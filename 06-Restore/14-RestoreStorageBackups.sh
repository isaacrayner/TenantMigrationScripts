#!/bin/bash
## DESCRIPTION: Restores Azure File Share backup protection in the destination subscription
##              using the backup CSV produced by 03-Backup/13-BackupStorageBackupSettings.sh.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

INPUT_FILE="${BACKUP_ROOT_DIR}/BackupSettings/storage-backup.csv"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Backup file not found at $INPUT_FILE. Skipping."
    exit 0
fi

echo "=== Restoring Azure File Share Backups in Destination Subscription ==="
echo "Destination Subscription: $DESTINATION_SUBSCRIPTION_ID"

az account set --subscription "$DESTINATION_SUBSCRIPTION_ID"

tail -n +2 "$INPUT_FILE" | while IFS=',' read -r STORAGE_ACCOUNT FILE_SHARE FRIENDLY_NAME RESOURCE_ID RESOURCE_GROUP VAULT POLICY_NAME POLICY_ID; do
    [[ -z "$STORAGE_ACCOUNT" ]] && continue
    echo "Restoring backup for File Share: $FRIENDLY_NAME in Storage Account: $STORAGE_ACCOUNT..."

    # Check if policy exists in vault
    POLICY_EXISTS=$(az backup policy show --vault-name "$VAULT" --resource-group "$RESOURCE_GROUP" --name "$POLICY_NAME" --query "name" -o tsv 2>/dev/null || true)
    if [[ -z "$POLICY_EXISTS" ]]; then
        echo "  ⚠️ Backup policy '$POLICY_NAME' not found in vault '$VAULT'. Skipping."
        continue
    fi

    az backup protection enable-for-azurefileshare \
        --vault-name "$VAULT" \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$POLICY_NAME" \
        --storage-account "$STORAGE_ACCOUNT" \
        --file-share "$FRIENDLY_NAME" \
        --only-show-errors

    echo "  ✅ Backup re-enabled for File Share: $FRIENDLY_NAME"
done

echo "Storage Account backup restore process completed!"

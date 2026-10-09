#!/bin/bash
## DESCRIPTION: Backs up Azure File Share backup configurations from all Recovery Services Vaults
##              across all resource groups to migration-data/BackupSettings/storage-backup.csv.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

OUTPUT_DIR="${BACKUP_ROOT_DIR}/BackupSettings"
OUTPUT_FILE="${OUTPUT_DIR}/storage-backup.csv"
mkdir -p "$OUTPUT_DIR"

echo "=== Backing up Storage Account & File Share Backup Settings ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

echo "StorageAccountName,FileShareName,FriendlyName,ResourceId,ResourceGroup,VaultName,PolicyName,PolicyId" > "$OUTPUT_FILE"

RESOURCE_GROUPS=$(az group list --query "[].name" -o tsv)

for RG in $RESOURCE_GROUPS; do
    VAULTS=$(az backup vault list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || true)
    [[ -z "$VAULTS" ]] && continue

    for VAULT in $VAULTS; do
        echo "Checking Vault: $VAULT in RG: $RG..."

        BACKUP_ITEMS=$(az backup item list --vault-name "$VAULT" --resource-group "$RG" \
            --query "[?properties.workloadType=='AzureFileShare']" -o json 2>/dev/null || true)

        if [[ -z "$BACKUP_ITEMS" || "$BACKUP_ITEMS" == "[]" ]]; then
            continue
        fi

        echo "$BACKUP_ITEMS" | jq -c '.[]' | while read -r ITEM; do
            STORAGE_ACCOUNT=$(echo "$ITEM" | jq -r '.properties.sourceResourceId' | awk -F'/' '{print $(NF)}')
            FILE_SHARE_NAME=$(echo "$ITEM" | jq -r '.properties.friendlyName')
            RESOURCE_ID=$(echo "$ITEM" | jq -r '.properties.sourceResourceId')
            POLICY_NAME=$(echo "$ITEM" | jq -r '.properties.policyName // "Unknown"')
            POLICY_ID=$(echo "$ITEM" | jq -r '.properties.policyId // "Unknown"')

            if [[ -n "$STORAGE_ACCOUNT" && -n "$FILE_SHARE_NAME" && -n "$RESOURCE_ID" ]]; then
                echo "  Found backup: $STORAGE_ACCOUNT / $FILE_SHARE_NAME (Policy: $POLICY_NAME)"
                echo "$STORAGE_ACCOUNT,$FILE_SHARE_NAME,$FILE_SHARE_NAME,$RESOURCE_ID,$RG,$VAULT,$POLICY_NAME,$POLICY_ID" >> "$OUTPUT_FILE"
            fi
        done
    done
done

echo "✅ Storage backup configurations exported to: $OUTPUT_FILE"

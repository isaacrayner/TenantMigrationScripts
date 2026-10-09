#!/bin/bash
## DESCRIPTION: Deletes all private endpoints in the source subscription.
##              Private endpoints cannot be moved across subscriptions and must be removed.
## USAGE:       Run in bash/WSL after running 03-Backup/10-BackupPrivateEndpoints.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

echo "=== Deleting Private Endpoints in Source Subscription ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

PES=$(az network private-endpoint list --subscription "$SOURCE_SUBSCRIPTION_ID" --query "[].id" -o tsv)

if [[ -z "$PES" ]]; then
    echo "No Private Endpoints found to delete."
    exit 0
fi

for pe_id in $PES; do
    name=$(az network private-endpoint show --ids "$pe_id" --query "name" -o tsv)
    rg=$(az network private-endpoint show --ids "$pe_id" --query "resourceGroup" -o tsv)

    echo "Deleting Private Endpoint: $name (RG: $rg)..."
    az network private-endpoint delete --name "$name" --resource-group "$rg" --only-show-errors
    echo "  ✅ Deleted: $name"
done

echo "All Private Endpoints successfully removed from source subscription."

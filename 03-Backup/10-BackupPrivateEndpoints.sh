#!/bin/bash
## DESCRIPTION: Backs up all private endpoint configurations and their Private DNS Zone Groups
##              in the source subscription to JSON files in migration-data/PrivateEndpoints/.
## USAGE:       Run in bash/WSL with Azure CLI and jq installed and authenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

PE_BACKUP_DIR="${BACKUP_ROOT_DIR}/PrivateEndpoints"
mkdir -p "$PE_BACKUP_DIR"

echo "=== Backing up Private Endpoints ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

PES=$(az network private-endpoint list --subscription "$SOURCE_SUBSCRIPTION_ID" --query "[].id" -o tsv)

if [[ -z "$PES" ]]; then
    echo "No Private Endpoints found in subscription."
    exit 0
fi

for pe_id in $PES; do
    name=$(az network private-endpoint show --ids "$pe_id" --query "name" -o tsv)
    rg=$(az network private-endpoint show --ids "$pe_id" --query "resourceGroup" -o tsv)

    echo "Backing up Private Endpoint: $name (RG: $rg)..."
    az network private-endpoint show --ids "$pe_id" -o json > "${PE_BACKUP_DIR}/${name}_PrivateEndpoint.json"

    # Also backup Private DNS Zone Groups if associated
    DNS_GROUPS=$(az network private-endpoint dns-zone-group list --endpoint-name "$name" --resource-group "$rg" -o json 2>/dev/null || true)
    if [[ -n "$DNS_GROUPS" && "$DNS_GROUPS" != "[]" ]]; then
        echo "$DNS_GROUPS" > "${PE_BACKUP_DIR}/${name}_DnsZoneGroups.json"
        echo "  Saved DNS Zone Groups for: $name"
    fi
done

echo "✅ Private endpoint backup completed! Saved in: $PE_BACKUP_DIR"

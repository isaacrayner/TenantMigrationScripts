#!/bin/bash
## DESCRIPTION: Disassociates public IP addresses from VMs across all resource groups in the
##              source subscription. Captures VM, NIC name, IP Config name, and Public IP name
##              so they can be precisely reassociated after migration.
## USAGE:       Run in bash/WSL before executing VM/resource migration.
##              Output file is used by 06-Restore/02-AssociatePublicIPs.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../migration-params.sh"

TEMP_FILE="${BACKUP_ROOT_DIR}/public_ips_associations.json"
echo "[]" > "$TEMP_FILE"

echo "=== Disassociating Public IPs from VMs in Source Subscription ==="
echo "Source Subscription: $SOURCE_SUBSCRIPTION_ID"

az account set --subscription "$SOURCE_SUBSCRIPTION_ID"

RESOURCE_GROUPS=$(az group list --subscription "$SOURCE_SUBSCRIPTION_ID" --query "[].name" -o json)

if [[ -z "$RESOURCE_GROUPS" || "$RESOURCE_GROUPS" == "[]" ]]; then
    echo "No Resource Groups found in subscription."
    exit 0
fi

DISASSOCIATION_LIST=()

for RG in $(echo "$RESOURCE_GROUPS" | jq -r '.[]'); do
    echo "Checking Resource Group: $RG..."

    # Query all NICs in the RG that have a public IP address
    NICS=$(az network nic list --resource-group "$RG" --query "[?ipConfigurations[?publicIpAddress!=null]]" -o json 2>/dev/null || true)

    if [[ -z "$NICS" || "$NICS" == "[]" ]]; then
        continue
    fi

    echo "$NICS" | jq -c '.[]' | while read -r nic; do
        NIC_NAME=$(echo "$nic" | jq -r '.name')
        VM_ID=$(echo "$nic" | jq -r '.virtualMachine.id // empty')
        VM_NAME=$(basename "$VM_ID")

        # Find the specific ipConfig containing the public IP
        echo "$nic" | jq -c '.ipConfigurations[] | select(.publicIpAddress != null)' | while read -r ipcfg; do
            IPCONFIG_NAME=$(echo "$ipcfg" | jq -r '.name')
            PIP_ID=$(echo "$ipcfg" | jq -r '.publicIpAddress.id')
            PIP_NAME=$(basename "$PIP_ID")

            echo "  Found Public IP '$PIP_NAME' on NIC '$NIC_NAME' (IPConfig: '$IPCONFIG_NAME', VM: '$VM_NAME')"

            RECORD=$(jq -n \
                --arg vm "$VM_NAME" \
                --arg nic "$NIC_NAME" \
                --arg ipcfg "$IPCONFIG_NAME" \
                --arg pip "$PIP_NAME" \
                --arg rg "$RG" \
                '{VM: $vm, NicName: $nic, IpConfigName: $ipcfg, PublicIPName: $pip, ResourceGroup: $rg}')

            jq --argjson rec "$RECORD" '. += [$rec]' "$TEMP_FILE" > "${TEMP_FILE}.tmp" && mv "${TEMP_FILE}.tmp" "$TEMP_FILE"

            echo "  Disassociating Public IP from $NIC_NAME ($IPCONFIG_NAME)..."
            az network nic ip-config update \
                --name "$IPCONFIG_NAME" \
                --nic-name "$NIC_NAME" \
                --resource-group "$RG" \
                --remove publicIpAddress \
                --only-show-errors
            echo "  ✅ Disassociated $PIP_NAME from $NIC_NAME"
        done
    done
done

TOTAL_SAVED=$(jq length "$TEMP_FILE")
echo ""
echo "Public IP disassociation complete. Total disassociated: $TOTAL_SAVED"
echo "Mapping saved to: $TEMP_FILE"
echo "Reassociate in destination subscription via 06-Restore/02-AssociatePublicIPs.sh."

#!/bin/bash
## MIGRATION PARAMETERS FILE (bash)
## ─────────────────────────────────────────────────────────────────────────────
## Update the parameters below for each migration project, or (recommended) put
## your values in an untracked 'migration-params.local.sh' so real tenant and
## subscription IDs never get committed.
## All bash/azcli scripts in this repo source this file automatically.
## ─────────────────────────────────────────────────────────────────────────────

# ── Tenant Configuration ───────────────────────────────────────────────────────
SOURCE_TENANT_ID="00000000-0000-0000-0000-000000000000"
DESTINATION_TENANT_ID=""    # Set if migrating to a different Microsoft Entra ID tenant

# ── Subscription Configuration ────────────────────────────────────────────────
SOURCE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
DESTINATION_SUBSCRIPTION_ID=""

# ── Local overrides (untracked) ───────────────────────────────────────────────
# Real IDs belong in migration-params.local.sh, which .gitignore excludes.
_PARAMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "${_PARAMS_DIR}/migration-params.local.sh" ]] && source "${_PARAMS_DIR}/migration-params.local.sh"

# ── Storage & Output Paths ────────────────────────────────────────────────────
# Centralized directory for all backups, JSON/CSV state files, and execution logs.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BACKUP_ROOT_DIR="${REPO_ROOT}/migration-data"
LOG_ROOT_DIR="${BACKUP_ROOT_DIR}/logs"
mkdir -p "${BACKUP_ROOT_DIR}" "${LOG_ROOT_DIR}"

# ── Logging helper ────────────────────────────────────────────────────────────
log_message() {
    local level="$1"
    local message="$2"
    local logfile="${3:-${LOG_ROOT_DIR}/migration.log}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message"
    echo "[$timestamp] [$level] $message" >> "$logfile" 2>/dev/null || true
}

# ── Aliases – for backwards compatibility with existing scripts ───────────────
OLD_SUBSCRIPTION_ID="$SOURCE_SUBSCRIPTION_ID"
NEW_SUBSCRIPTION_ID="$DESTINATION_SUBSCRIPTION_ID"
SOURCE_SUB="$SOURCE_SUBSCRIPTION_ID"
TARGET_SUB="$DESTINATION_SUBSCRIPTION_ID"

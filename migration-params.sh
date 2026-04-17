#!/bin/bash
## MIGRATION PARAMETERS FILE (bash)
## ─────────────────────────────────────────────────────────────────────────────
## Update the four values below for each new project.
## All bash/azcli scripts in this repo source this file automatically.
## ─────────────────────────────────────────────────────────────────────────────

# ── Edit these for each project ──────────────────────────────────────────────
SOURCE_TENANT_ID="00000000-0000-0000-0000-000000000000"
DESTINATION_TENANT_ID=""    # Set if migrating to a different Azure AD tenant

SOURCE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
DESTINATION_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

# ── Aliases – do not edit ─────────────────────────────────────────────────────
# These allow individual scripts to keep their original variable names unchanged.
OLD_SUBSCRIPTION_ID="$SOURCE_SUBSCRIPTION_ID"
NEW_SUBSCRIPTION_ID="$DESTINATION_SUBSCRIPTION_ID"
SOURCE_SUB="$SOURCE_SUBSCRIPTION_ID"
TARGET_SUB="$DESTINATION_SUBSCRIPTION_ID"

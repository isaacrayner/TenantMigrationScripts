## MIGRATION PARAMETERS FILE
## ─────────────────────────────────────────────────────────────────────────────
## Update the four values below for each new project.
## All PowerShell scripts in this repo dot-source this file automatically.
## ─────────────────────────────────────────────────────────────────────────────

# ── Edit these for each project ──────────────────────────────────────────────
$sourceTenantId            = "00000000-0000-0000-0000-000000000000"
$destinationTenantId       = ""     # Set if migrating to a different Azure AD tenant

$sourceSubscriptionId      = "00000000-0000-0000-0000-000000000000"
$destinationSubscriptionId = ""

# ── Aliases – do not edit ─────────────────────────────────────────────────────
# These allow individual scripts to keep their original variable names unchanged.
$sourceSubscription      = $sourceSubscriptionId
$destinationSubscription = $destinationSubscriptionId
$newSubscriptionId       = $destinationSubscriptionId
$destSubscriptionId      = $destinationSubscriptionId

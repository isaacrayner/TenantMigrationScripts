# Azure Tenant & Subscription Migration Toolkit

[![CI](https://github.com/isaacrayner/TenantMigrationScripts/actions/workflows/ci.yml/badge.svg)](https://github.com/isaacrayner/TenantMigrationScripts/actions/workflows/ci.yml)
![PowerShell](https://img.shields.io/badge/PowerShell-Az%20module-5391FE?logo=powershell&logoColor=white)
![Azure CLI](https://img.shields.io/badge/Azure%20CLI-bash-0078D4?logo=microsoftazure&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A phased, repeatable toolkit for moving an Azure subscription between resource scopes or Microsoft Entra ID tenants **without losing the things Azure silently destroys on the way**: RBAC assignments, managed identities, Key Vault access policies, private endpoints, VNet peerings, backup protection, locks and diagnostic settings.

Every phase *backs up state to JSON/CSV first*, *removes only what blocks the move*, and *restores it afterwards* with identities remapped to their new object IDs.

## Why this exists

An ARM resource move or a subscription directory transfer looks like one operation, but it quietly breaks a long list of dependencies:

| Scenario | Mechanism | What breaks |
|---|---|---|
| **A. Same-tenant sub-to-sub** | `Move-AzResource` | System-assigned MIs, private endpoints, VNet peerings, backup protection, locks |
| **B. Cross-tenant directory change** | `az account tenant-change` | **All RBAC wiped**, MIs deleted, Key Vault tenant IDs, app registrations |
| **C. Cross-tenant sub-to-sub** | B, then A in the target tenant | Both |

This toolkit turns that into an ordered, auditable runbook of 60+ scripts, and an interactive orchestrator that tracks which phase you are in.

## What it demonstrates

- **Azure governance & identity**: RBAC export/restore with old→new principal ID translation, custom role definitions, managed identity lifecycle, Entra ID lookups, CSP foreign principals
- **Networking**: private endpoints and DNS zone groups, VNet peering teardown/rebuild, NAT gateways, public IP re-association, Application Gateway / WAF policy backup
- **Data protection**: Recovery Services Vault, VM and file-share backup settings, Key Vault access policies
- **Platform operations**: resource provider sync, quota comparison, resource locks, App Service certificate/binding handling, diagnostic settings with Log Analytics rewrites
- **Engineering practice**: one config shared by PowerShell and bash, a data-driven state-aware orchestrator, destructive phases gated behind explicit confirmation, 300+ automated tests and privacy checks in CI

## Quick start

```powershell
./Start-Migration.ps1
```

On first run it checks prerequisites and asks for your tenant and subscription IDs, writing them to **untracked** local files. After that the menu shows which phases are complete (by inspecting `./migration-data`) and recommends the next one: press **Enter** to run it.

```
 [COMPLETED]   [0] Planning: export permissions, map identities, compare quotas
 [COMPLETED]   [1] Pre-flight: find migration blockers and encrypted disks
 [PENDING]     [2] Prepare destination: sync resource providers, create resource groups
 ...
 >>> NEXT RECOMMENDED: Phase 2
```

Inside a phase, **Enter** runs every default script in order; type a script number to run just that one. Phases 4 and 5 change or delete resources and require typing `YES` (or `-Force`).

Non-interactive use:

```powershell
./Start-Migration.ps1 -Setup           # write migration-params.local.* and exit
./Start-Migration.ps1 -Phase 3         # run the Backup phase and exit
./03-Backup/05-BackupPublicIPs.ps1     # or run any single script directly
```

Prefer a visual checklist? Open [`dashboard.html`](dashboard.html): per-phase scripts with copy-paste commands and a same-tenant / cross-tenant scenario switch.

### Prerequisites

- PowerShell 7+ with the [`Az`](https://learn.microsoft.com/powershell/azure/install-azure-powershell) module
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), `bash` and `jq` for the `.sh` scripts (WSL on Windows)
- Owner (or equivalent) on the source and destination subscriptions; Entra ID read access to the target tenant for identity resolution

### Configuration

`migration-params.ps1` / `migration-params.sh` ship with all-zero placeholder IDs. **Never put real IDs in them.** `-Setup` creates `migration-params.local.ps1` and `migration-params.local.sh` (git-ignored), which override the placeholders for both PowerShell and bash scripts. Everything the scripts produce lands in `./migration-data/` (also git-ignored, because exports contain tenant data).

> ⚠️ **Phase 4 is destructive** (it disables backups, detaches identities and deletes peerings). Complete and verify the Phase 3 backups first, and rehearse in a non-production subscription.

## Phases

Folders are numbered in execution order and every script inside is numbered in run order, so `ls` is the runbook.

| Phase | Folder | Purpose |
|---|---|---|
| 0 | [`00-Planning`](00-Planning) | Export all permissions, build an identity mapping plan, resolve target identities, compare vCPU quotas |
| 1 | [`01-Preflight`](01-Preflight) | Find migration blockers, audit disk encryption (ADE/CMK), CSP access |
| 2 | [`02-PrepareDestination`](02-PrepareDestination) | Sync resource providers, pre-create resource groups |
| 3 | [`03-Backup`](03-Backup) | Snapshot RBAC, identities, networking, backups, alerts, SSH keys, ARM templates (read-only) |
| 4 | [`04-Cleanup`](04-Cleanup) | Disable backups, detach identities, unbind certificates, delete peerings and private endpoints |
| 5 | [`05-Migrate`](05-Migrate) | Validate and move resource groups, move Recovery Services Vaults, or transfer the directory |
| 6 | [`06-Restore`](06-Restore) | Recreate everything, translating old identity IDs to new ones |

The full ordered list with what each script writes is in [`Docs/Runbook.md`](Docs/Runbook.md); working notes live in [`Docs/Notes`](Docs/Notes).

## Testing

```bash
tests/run-tests.sh
```

Runs privacy checks (no real IDs, credentials, emails, logs or exports tracked), bash and PowerShell syntax checks, and a Pester suite ([`tests/Repo.Tests.ps1`](tests/Repo.Tests.ps1)) that verifies:

- every script parses and its `param()` block actually binds (defaults that depend on config are applied *after* the params file loads)
- every script appears in the dashboard and the runbook, so the docs cannot drift
- the orchestrator runs scripts in numeric order, skips optional ones, honours the `YES` gate and passes the right arguments, tested against stub scripts so nothing touches Azure
- PSScriptAnalyzer reports no errors

The same checks, plus ShellCheck, run in [CI](.github/workflows/ci.yml) on every push. Locally you need PowerShell 7 with `Install-Module Pester`.

## Repository layout

```
Start-Migration.ps1         Interactive, state-aware orchestrator
dashboard.html              Browser checklist for every phase
migration-params.ps1/.sh    Shared config (placeholders; real values go in *.local.*)
00-Planning/ … 06-Restore/  Scripts, numbered in execution order
Docs/                       Runbook and working notes
tests/                      Repository checks and Pester suite
```

## Disclaimer

These scripts change and delete Azure resources. Review each one, test in a lab subscription, and take your own backups before running anything against production. Provided as-is under the [MIT License](LICENSE).

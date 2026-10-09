# Azure Tenant & Subscription Migration Guide

> **Configuration**: Run `./Start-Migration.ps1 -Setup` (or create `migration-params.local.ps1` / `.sh` by hand) before starting. All scripts automatically source their parameters and write output to `./migration-data/`.
> **Orchestrator**: You can run `./Start-Migration.ps1` for an interactive, menu-driven phase execution.

---

## Migration Archetypes: Same-Tenant vs. Cross-Tenant

Before executing, identify which scenario applies:

| Scenario | Migration Mechanism | What Breaks / Requires Recreation |
|---|---|---|
| **A. Same-Tenant Sub-to-Sub** | `Move-AzResource` (ARM Resource Move) | System-assigned MIs, Private Endpoints, VNet Peerings, Backup Protection, Resource Locks. RBAC is preserved on resources. |
| **B. Cross-Tenant Directory Change** | `az account tenant-change` (Directory Transfer) | **ALL RBAC assignments wiped**, System-assigned MIs deleted, Key Vault tenant IDs break, App Registrations must be recreated. |
| **C. Cross-Tenant Sub-to-Sub** | Directory transfer to target tenant first, then move resources within target tenant. | Both of the above combined. |

---

---

## Phase 0 — Planning & Permission Assessment

Run at project kickoff to inventory permissions, map identities and verify compute quota before scheduling cutover.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `00-Planning/01-ExportAllPermissions.ps1` | Comprehensive export of all RBAC (Sub, RG, Resource levels), Custom Roles, Key Vault policies, MI roles, and SQL admins |
| 2 | `00-Planning/02-GenerateIdentityMappingTemplate.ps1` | Generates `Identity_Mapping_Plan.csv` template listing all users, groups, and SPs needing mapping |
| 3 | `00-Planning/03-ResolveTargetIdentities.ps1` | Connects to destination tenant, queries Entra ID, and auto-resolves TargetObjectIds for the mapping plan |
| 4 | `00-Planning/04-CompareSubscriptionQuotas.ps1` | Compares source VM core/vCPU consumption against destination subscription regional quotas |
| 5 | `00-Planning/05-ExportPrincipalInventory.ps1` | Optional. Lists the users, groups and service principals referenced in the source subscription to CSV. |

---

## Phase 1 — Pre-Flight Discovery

Run before touching anything. Finds the blockers that would make moves or deletions fail.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `01-Preflight/01-CheckMigrationBlockers.ps1` | Scans for Resource Locks, VNet Peerings, Private Endpoints, MIs, RSVs, SSL bindings, and Basic PIPs |
| 2 | `01-Preflight/02-CheckVMDiskEncryption.ps1` | Audits VMs and Disks for BitLocker/ADE or Customer-Managed Keys (DES) |
| 3 | `01-Preflight/03-GrantCspForeignPrincipal.ps1` | (CSP only) Grants partner Foreign Principal Owner rights on subscription |

---

## Phase 2 — Prepare the Destination Subscription

Makes the destination ready to receive resources.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `02-PrepareDestination/01-SyncResourceProviders.ps1` | Synchronizes resource provider registrations between source and destination |
| 2 | `02-PrepareDestination/02-CreateResourceGroups.ps1` | Pre-creates all Resource Groups in destination with matching locations and tags |

---

## Phase 3 — Full Backup (Source Subscription)

Order matters and this phase is read-only. Complete and verify it **before** Phase 4. Output goes to `./migration-data/`.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `03-Backup/01-BackupResourceLocks.ps1` | Removes all CanNotDelete and ReadOnly resource locks |
| 2 | `03-Backup/02-BackupCustomRoles.ps1` | `CustomRoles/*.json` — Custom RBAC role definitions |
| 3 | `03-Backup/03-BackupRoleAssignments.ps1` | `RBAC_Assignments.json` — Complete RBAC assignment inventory |
| 4 | `03-Backup/04-BackupManagedIdentities.ps1` | `ManagedIdentities/` — Resource identity types, PrincipalIds & role assignments held by MIs |
| 5 | `03-Backup/05-BackupPublicIPs.ps1` | `PublicIP_Export.json` — Public IP configurations & NIC mappings |
| 6 | `03-Backup/06-BackupActionGroups.ps1` | `ActionGroups_Export.json` — Monitor action groups and receivers |
| 7 | `03-Backup/07-BackupSshKeys.sh` | `SSHKeys/ssh_keys.json` — Azure SSH public keys |
| 8 | `03-Backup/08-BackupMetricAlerts.sh` | `metric-alerts.json` — Metric alert criteria and actions |
| 9 | `03-Backup/09-BackupDiagnosticSettings.ps1` | `DiagnosticSettings/*_diag.json` — Resource diagnostic settings |
| 10 | `03-Backup/10-BackupPrivateEndpoints.sh` | `PrivateEndpoints/` — Private endpoints and Private DNS Zone Groups |
| 11 | `03-Backup/11-BackupKeyVaultAccess.sh` | `KeyVaultAccess/` — Key Vault access policies and RBAC status |
| 12 | `03-Backup/12-BackupVMBackupSettings.ps1` | `BackupSettings/VMBackupConfig.csv` — VM backup vault & policy associations |
| 13 | `03-Backup/13-BackupStorageBackupSettings.sh` | `BackupSettings/storage-backup.csv` — File share backup configurations |
| 14 | `03-Backup/14-BackupNatGateways.sh` | `NATGateways/` — NAT Gateways and subnet bindings |
| 15 | `03-Backup/15-BackupAppGateways.ps1` | `AppGateways/` — Application Gateways and WAF policies |
| 16 | `03-Backup/16-BackupVNetPeerings.ps1` | `VNETs/NetPeeringsBackup.csv` — Virtual network peering settings |
| 17 | `03-Backup/17-ExportArmTemplatesByResourceGroup.ps1` | `ARMExports/ResourceGroups/` — Complete ARM template snapshots |
| 18 | `03-Backup/18-ExportArmTemplatesByResource.ps1` | Optional. Exports a template for every individual resource; safe to re-run if interrupted. |
| 19 | `03-Backup/19-UploadArmTemplatesToBlob.ps1` | Optional. Exports per-resource templates and uploads them to Azure Blob Storage (also runs as an Automation runbook). |

---

## Phase 4 — Pre-Migration Cleanup (Source Subscription)

**Destructive.** Puts resources into a state ARM will agree to move. Remove locks first with `03-Backup/01-BackupResourceLocks.ps1 -RemoveLocks`.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `04-Cleanup/01-DisableVMBackups.ps1` | Stops VM backup protection (retains recovery points) & deletes instant restore point collections |
| 2 | `04-Cleanup/02-DisableStorageBackups.sh` | Disables Storage Account / File Share backup protection (retains recovery points) |
| 3 | `04-Cleanup/03-DetachManagedIdentities.ps1` | Detaches system and user-assigned managed identities |
| 4 | `04-Cleanup/04-UnbindAppServiceCertificates.ps1` | Unbinds SSL certificates and removes free managed certs from App Services |
| 5 | `04-Cleanup/05-DisassociatePublicIPs.sh` | Disassociates Public IPs from NICs and saves NIC/IPConfig mapping |
| 6 | `04-Cleanup/06-DeletePrivateEndpoints.sh` | Deletes Private Endpoints |
| 7 | `04-Cleanup/07-DeleteVNetPeerings.ps1` | Deletes Virtual Network peerings |
| 8 | `04-Cleanup/08-DeleteBlockingResources.ps1` | Selective cleanup: Disk Snapshots, NAT Gateways, VPN Gateways |

---

## Phase 5 — Validate & Execute the Migration

These scripts are alternatives, not a sequence. Pick the one that matches your scenario.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `05-Migrate/01-ValidateResourceGroupMove.ps1` | Calls ARM validateMoveResources to confirm zero blockers remain. |
| 2 | `05-Migrate/02-MoveResourceGroup.ps1` | Executes ARM resource move to target subscription. |
| 3 | `05-Migrate/03-MoveRecoveryServicesVault.ps1` | Moves RSV to destination subscription. |
| 4 | `05-Migrate/04-TransferSubscriptionDirectory.ps1` | (Cross-Tenant only) Executes az account tenant-change. |
| 5 | `05-Migrate/05-ValidateResourceMove.ps1` | Validates a named list of resources (or one resource group) with the ARM validateMoveResources API. |

---

## Phase 6 — Recreate & Restore (Destination Subscription)

Restores dependencies and state in the destination, translating old identity IDs to new ones.

| # | Script | What it does |
|---|--------|--------------|
| 1 | `06-Restore/01-RecreateVNetPeerings.ps1` | Recreates VNet peerings with destination subscription ID rewriting |
| 2 | `06-Restore/02-AssociatePublicIPs.sh` | Reattaches Public IPs to exact NICs and IPConfigs |
| 3 | `06-Restore/03-RecreatePrivateEndpoints.sh` | Recreates Private Endpoints with destination sub IDs & DNS Zone Groups |
| 4 | `06-Restore/04-RestoreCustomRoles.ps1` | Recreates custom RBAC role definitions in target |
| 5 | `06-Restore/05-RecreateManagedIdentities.ps1` | Re-enables MIs and generates `NewManagedIdentitiesMapping.json` |
| 6 | `06-Restore/06-RestoreKeyVaultAccess.ps1` | Restores Key Vault access policies for newly issued MI ObjectIds |
| 7 | `06-Restore/07-UpdateKeyVaultTenant.sh` | Updates Key Vault tenant IDs and restores access policies |
| 8 | `06-Restore/08-RestoreRoleAssignments.ps1` | Restores RBAC assignments, automatically translating old MI IDs to new IDs |
| 9 | `06-Restore/09-RestoreAppServiceCertificates.ps1` | Restores App Service hostname SSL bindings |
| 10 | `06-Restore/10-RecreateNatGateways.sh` | Recreates NAT Gateways and rebinds to subnets |
| 11 | `06-Restore/11-RestoreActionGroups.ps1` | Restores Azure Monitor Action Groups |
| 12 | `06-Restore/12-RestoreSshKeys.sh` | Restores SSH public keys |
| 13 | `06-Restore/13-RestoreVMBackups.ps1` | Re-enables VM backup protection in destination vaults |
| 14 | `06-Restore/14-RestoreStorageBackups.sh` | Re-enables File Share backup protection |
| 15 | `06-Restore/15-RestoreDiagnosticSettings.ps1` | Restores diagnostic settings with rewritten Log Analytics Workspace IDs |
| 16 | `06-Restore/16-RestoreAppGateways.ps1` | Restores WAF policies and Application Gateway configurations |
| 17 | `06-Restore/17-RestoreMetricAlerts.sh` | Recreates metric alerts from metric-alerts.json. |
| 18 | `06-Restore/18-RestoreResourceLocks.ps1` | Restores original Resource Locks |
| 19 | `06-Restore/19-DeployArmTemplate.ps1` | Optional. Deploys an exported template to recreate unmovable resources (for example WAF policies). |

---

## Phase 7 — Verification Checklist

1. **Verify Managed Identity Connectivity**: Ensure VMs and App Services can authenticate to Key Vault and Storage.
2. **Review `RBAC_Restore.log`**: Verify that all role assignments were applied and check for any external principals needing re-invitation.
3. **Trigger Test Backup**: Initiate an on-demand backup in the Recovery Services Vault to verify protection is active.
4. **Test Network Connectivity**: Check that VNet peerings show status **Connected** and Private Endpoints resolve via DNS.

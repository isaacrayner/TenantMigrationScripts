# Azure Tenant & Subscription Migration Guide

> **Configuration**: Edit `migration-params.ps1` (for PowerShell) and `migration-params.sh` (for Bash) in the repo root before starting. All scripts automatically source their parameters and write output to `./migration-data/`.
> **Orchestrator**: You can run `.\Start-Migration.ps1` for an interactive, menu-driven phase execution.

---

## Migration Archetypes: Same-Tenant vs. Cross-Tenant

Before executing, identify which scenario applies:

| Scenario | Migration Mechanism | What Breaks / Requires Recreation |
|---|---|---|
| **A. Same-Tenant Sub-to-Sub** | `Move-AzResource` (ARM Resource Move) | System-assigned MIs, Private Endpoints, VNet Peerings, Backup Protection, Resource Locks. RBAC is preserved on resources. |
| **B. Cross-Tenant Directory Change** | `az account tenant-change` (Directory Transfer) | **ALL RBAC assignments wiped**, System-assigned MIs deleted, Key Vault tenant IDs break, App Registrations must be recreated. |
| **C. Cross-Tenant Sub-to-Sub** | Directory transfer to target tenant first, then move resources within target tenant. | Both of the above combined. |

---

## Phase P — Planning & Permission Assessment

Run during project kickoff/scoping to inventory permissions, map identities, and verify compute quotas before scheduling cutover.

| # | Script | What it does |
|---|--------|--------------|
| P.1 | `0-Planning/1-ExportAllPermissions.ps1` | Comprehensive export of all RBAC (Sub, RG, Resource levels), Custom Roles, Key Vault policies, MI roles, and SQL admins |
| P.2 | `0-Planning/2-GenerateIdentityMappingTemplate.ps1` | Generates `Identity_Mapping_Plan.csv` template listing all users, groups, and SPs needing mapping |
| P.3 | `0-Planning/3-ResolveTargetIdentities.ps1` | Connects to destination tenant, queries Entra ID, and auto-resolves TargetObjectIds for the mapping plan |
| P.4 | `0-Planning/4-CompareSubscriptionQuotas.ps1` | Compares source VM core/vCPU consumption against destination subscription regional quotas |

---

## Phase 0 — Pre-Flight Discovery & Readiness Assessment

Run this before touching anything. This identifies blockers that would cause moves or deletions to fail.

| # | Script | What it does |
|---|--------|--------------|
| 0.1 | `1-InitialReview/2-CheckMigrationBlockers.ps1` | Scans for Resource Locks, VNet Peerings, Private Endpoints, MIs, RSVs, SSL bindings, and Basic PIPs |
| 0.2 | `1-InitialReview/1-CheckVMDiskEncryption.ps1` | Audits VMs and Disks for BitLocker/ADE or Customer-Managed Keys (DES) |
| 0.3 | `1-InitialReview/CSPForeignPrincipal.ps1` | (CSP only) Grants partner Foreign Principal Owner rights on subscription |

---

## Phase 1 — Prepare Destination Subscription

| # | Script | What it does |
|---|--------|--------------|
| 1 | `3-MigrationPrep/2-RegisterResources.ps1` | Synchronizes resource provider registrations between source and destination |
| 2 | `3-MigrationPrep/3-ResourceGroups.ps1` | Pre-creates all Resource Groups in destination with matching locations and tags |

---

## Phase 2 — Full Backup (Source Subscription)

Order is critical. Run **before** any deletions or modifications.

| # | Script | What it saves to `./migration-data/` |
|---|--------|--------------------------------------|
| 3 | `3-MigrationPrep/0-BackupAndRemoveResourceLocks.ps1` | `ResourceLocks_Backup.json` — All Resource Locks |
| 4 | `3-MigrationPrep/4-BackupCustomRoles.ps1` | `CustomRoles/*.json` — Custom RBAC role definitions |
| 5 | `3-MigrationPrep/4-ListRoleAssignmentsv2.ps1` | `RBAC_Assignments.json` — Complete RBAC assignment inventory |
| 6 | `3-MigrationPrep/11-BackupIdentities.ps1` | `ManagedIdentities/` — Resource identity types, PrincipalIds & role assignments held by MIs |
| 7 | `3-MigrationPrep/5-BackupPublicIPs.ps1` | `PublicIP_Export.json` — Public IP configurations & NIC mappings |
| 8 | `3-MigrationPrep/6-BackupActionGroups.ps1` | `ActionGroups_Export.json` — Monitor action groups and receivers |
| 9 | `3-MigrationPrep/7-ExportSSHKeys.azcli` | `SSHKeys/ssh_keys.json` — Azure SSH public keys |
| 10 | `3-MigrationPrep/8-BackupMetricAlerts.azcli` | `metric-alerts.json` — Metric alert criteria and actions |
| 11 | `3-MigrationPrep/9-BackupDiagSettings.ps1` | `DiagnosticSettings/*_diag.json` — Resource diagnostic settings |
| 12 | `3-MigrationPrep/10-BackupPrivateEndpoints.azcli` | `PrivateEndpoints/` — Private endpoints and Private DNS Zone Groups |
| 13 | `3-MigrationPrep/12-BackupAccessPolicies.azcli` | `KeyVaultAccess/` — Key Vault access policies and RBAC status |
| 14 | `3-MigrationPrep/13-BackupVMBackupSettings.ps1` | `BackupSettings/VMBackupConfig.csv` — VM backup vault & policy associations |
| 15 | `3-MigrationPrep/14-BackupSABackupSettings.azcli` | `BackupSettings/storage-backup.csv` — File share backup configurations |
| 16 | `3-MigrationPrep/15-BackupNATsettings.azcli` | `NATGateways/` — NAT Gateways and subnet bindings |
| 17 | `3-MigrationPrep/16-BackupAppGateways.ps1` | `AppGateways/` — Application Gateways and WAF policies |
| 18 | `5-VNETPeerings/1.Export-VNETs.ps1` | `VNETs/NetPeeringsBackup.csv` — Virtual network peering settings |
| 19 | `2-Backup/ARMRGExport.ps1` | `ARMExports/ResourceGroups/` — Complete ARM template snapshots |

---

## Phase 3 — Pre-Migration Cleanup (Source Subscription)

Resources must be in an unencumbered state before ARM will permit a move.

| # | Script | What it does |
|---|--------|--------------|
| 20 | `3-MigrationPrep/0-BackupAndRemoveResourceLocks.ps1` (with `-RemoveLocks`) | Removes all CanNotDelete and ReadOnly resource locks |
| 21 | `4-Deletions/5-DisableBackups.ps1` | Stops VM backup protection (retains recovery points) & deletes instant restore point collections |
| 22 | `4-Deletions/6-DisableSABackups.azcli` | Disables Storage Account / File Share backup protection (retains recovery points) |
| 23 | `4-Deletions/4-DisableMIdentities.ps1` | Detaches system and user-assigned managed identities |
| 24 | `4-Deletions/7-UnbindAppServiceCertificates.ps1` | Unbinds SSL certificates and removes free managed certs from App Services |
| 25 | `4-Deletions/1-PublicIPdiss.azcli` | Disassociates Public IPs from NICs and saves NIC/IPConfig mapping |
| 26 | `4-Deletions/3-PrivateEndpoints.azcli` | Deletes Private Endpoints |
| 27 | `5-VNETPeerings/2.DeleteVNETs.ps1` | Deletes Virtual Network peerings |
| 28 | `4-Deletions/2-Misc.ps1` | Selective cleanup: Disk Snapshots, NAT Gateways, VPN Gateways |

---

## Phase 4 — Validate & Execute Migration

### Option 1: Resource Group Move (Same Tenant)
Run validation on all resource groups first:
1. `6-MIGRATION/1-ValidateRGMove.ps1 -AllResourceGroups`
2. For each RG: `6-MIGRATION/2-MigrateRG.ps1 -ResourceGroupName <Name>`
3. For Recovery Services Vaults: `6-MIGRATION/3-MigrateRecoveryServicesVault.ps1`

### Option 2: Subscription Directory Transfer (Cross-Tenant)
If moving the subscription to a new Entra ID tenant:
1. Run `6-MIGRATION/4-TransferSubscriptionDirectory.ps1`
2. Allow 10–15 minutes for directory propagation.
3. Authenticate to the destination tenant: `az login --tenant <destTenantId>` and `Connect-AzAccount -TenantId <destTenantId>`.

---

## Phase 5 — Recreate & Restore (Destination Subscription)

Run these to restore dependencies and state in the destination subscription.

| # | Script | What it does |
|---|--------|--------------|
| 29 | `5-VNETPeerings/3.RecreatePeerings.ps1` | Recreates VNet peerings with destination subscription ID rewriting |
| 30 | `7-Recreation/1-PublicIPass.azcli` | Reattaches Public IPs to exact NICs and IPConfigs |
| 31 | `7-Recreation/3-PrivateEndpoints.azcli` | Recreates Private Endpoints with destination sub IDs & DNS Zone Groups |
| 32 | `7-Recreation/5-RestoreCustomRoles.ps1` | Recreates custom RBAC role definitions in target |
| 33 | `7-Recreation/4-A-RecreateMIdentities.ps1` | Re-enables MIs and generates `NewManagedIdentitiesMapping.json` |
| 34 | `7-Recreation/4-B-RestoreKeyVaultAccess.ps1` | Restores Key Vault access policies for newly issued MI ObjectIds |
| 35 | `7-Recreation/2-KeyVault.azcli` | Updates Key Vault tenant IDs and restores access policies |
| 36 | `7-Recreation/5-RestoreRoleAssignments.ps1` | Restores RBAC assignments, automatically translating old MI IDs to new IDs |
| 37 | `7-Recreation/5-RestoreAppServiceCertificates.ps1`| Restores App Service hostname SSL bindings |
| 38 | `7-Recreation/6-NATGateway.azcli` | Recreates NAT Gateways and rebinds to subnets |
| 39 | `7-Recreation/7-RestoreActionGroups.ps1` | Restores Azure Monitor Action Groups |
| 40 | `7-Recreation/7-RestoreSSHKeys.sh` | Restores SSH public keys |
| 41 | `7-Recreation/8-VMBackups.ps1` | Re-enables VM backup protection in destination vaults |
| 42 | `7-Recreation/9-SABackups.azcli` | Re-enables File Share backup protection |
| 43 | `7-Recreation/10-RestoreDiagSettings.ps1` | Restores diagnostic settings with rewritten Log Analytics Workspace IDs |
| 44 | `7-Recreation/11-RestoreAppGateways.ps1` | Restores WAF policies and Application Gateway configurations |
| 45 | `7-Recreation/0-RestoreResourceLocks.ps1` | Restores original Resource Locks |

---

## Phase 6 — Verification Checklist

1. **Verify Managed Identity Connectivity**: Ensure VMs and App Services can authenticate to Key Vault and Storage.
2. **Review `RBAC_Restore.log`**: Verify that all role assignments were applied and check for any external principals needing re-invitation.
3. **Trigger Test Backup**: Initiate an on-demand backup in the Recovery Services Vault to verify protection is active.
4. **Test Network Connectivity**: Check that VNet peerings show status **Connected** and Private Endpoints resolve via DNS.

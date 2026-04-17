# Subscription-to-Subscription Migration (Same Tenant)

> All scripts dot-source `migration-params.ps1` from the repo root. Set `$sourceSubscriptionId` and `$destinationSubscriptionId` there before starting. Leave `$destinationTenantId` blank for same-tenant moves.

---

## Phase 1 — Prepare Destination

| # | Script | What it does |
|---|--------|--------------|
| 1 | `3-MigrationPrep/2-RegisterResources.ps1` | Registers all resource providers from source into destination subscription |
| 2 | `3-MigrationPrep/3-ResourceGroups.ps1` | Recreates all RGs in destination (same names, locations, tags) |

---

## Phase 2 — Back Up Everything (source subscription)

Run these **before** disabling anything. Order matters for RBAC.

| # | Script | What it does |
|---|--------|--------------|
| 3 | `2-Backup/ARMRGExport.ps1` | ARM template snapshot of all RGs (safety net) |
| 4 | `3-MigrationPrep/11-BackupIdentities.ps1` | Inventories all managed identities → `ManagedIdentityResources.csv` |
| 5 | `3-MigrationPrep/4-ListRoleAssignmentsv2.ps1` | Exports all RBAC assignments → `RBAC_Assignments.json` — **run before disabling MIs** |
| 6 | `3-MigrationPrep/13-BackupVMBackupSettings.ps1` | Saves VM backup vault/policy config → CSV |
| 7 | `3-MigrationPrep/9-BackupDiagSettings.ps1` | Saves diagnostic settings per resource → JSON files |
| 8 | `5-VNETPeerings/1.Export-VNETs.ps1` | Saves all VNet peering configs → CSV (required before deletion) |
| 9 | `3-MigrationPrep/10-BackupPrivateEndpoints.azcli` | Saves private endpoint configs |
| 10 | `3-MigrationPrep/5-BackupPublicIPs.ps1` | Saves public IP associations |

---

## Phase 3 — Pre-Migration Cleanup (source subscription)

Resources must be in a moveable state. Work through this list top to bottom.

| # | Script | What it does |
|---|--------|--------------|
| 11 | `4-Deletions/5-DisableBackups.ps1` | Stops VM backup protection (retains recovery points) |
| 12 | `4-Deletions/6-DisableSABackups.azcli` | Disables Storage Account backup policies |
| 13 | `4-Deletions/4-DisableMIdentities.ps1` | Removes managed identities from all resources — **required before move** |
| 14 | `4-Deletions/1-PublicIPdiss.azcli` | Disassociates public IPs from NICs/resources |
| 15 | `4-Deletions/3-PrivateEndpoints.azcli` | Deletes private endpoints (cannot move with resources) |
| 16 | `5-VNETPeerings/2.DeleteVNETs.ps1` | Removes VNet peerings (peerings break on subscription change) |
| 17 | `4-Deletions/2-Misc.ps1` | Deletes any remaining blockers: disk snapshots, VPN gateways, NAT gateways — **run sections selectively** |

---

## Phase 4 — Validate & Migrate

Run validate first for each RG. Fix any failures before proceeding to move.

| # | Script | What it does |
|---|--------|--------------|
| 18 | `6-MIGRATION/1-ValidateRGMove.ps1` | Calls ARM validateMoveResources — surfaces blockers before touching anything |
| 19 | `6-MIGRATION/2-MigrateRG.ps1` | Moves all resources in the RG to destination subscription |

> Repeat steps 18–19 for each resource group.

---

## Phase 5 — Restore (destination subscription)

| # | Script | What it does |
|---|--------|--------------|
| 20 | `5-VNETPeerings/3.RecreatePeerings.ps1` | Recreates VNet peerings from CSV backup |
| 21 | `7-Recreation/1-PublicIPass.azcli` | Reassociates public IPs |
| 22 | `7-Recreation/3-PrivateEndpoints.azcli` | Recreates private endpoints |
| 23 | `7-Recreation/2-KeyVault.azcli` | Restores Key Vault access policies |
| 24 | `7-Recreation/4-A-RecreateMIdentities.ps1` | Re-enables managed identities — Azure issues new ObjectIds for system-assigned |
| 25 | `7-Recreation/5-RestoreRoleAssignments.ps1` | Restores RBAC — MI assignments will log as FAIL (expected, see note below) |
| 26 | `7-Recreation/8-VMBackups.ps1` | Re-enables VM backup protection |
| 27 | `7-Recreation/9-SABackups.azcli` | Re-enables Storage Account backup policies |
| 28 | `7-Recreation/10-RestoreDiagSettings.ps1` | Restores diagnostic settings from JSON backup |
| 29 | `7-Recreation/6-NATGateway.azcli` | Recreates NAT gateway associations |
| 30 | `7-Recreation/MetricAlerts.azcli` | Recreates metric alerts |

---

## Phase 6 — Manual Follow-Up

These cannot be scripted reliably and must be done by hand after Phase 5.

1. **Reassign MI role assignments** — Check `C:\temp\RBAC_Restore.log` for `FAIL - PrincipalNotFound` lines. For each one, get the new ObjectId from the destination and reassign:
   ```powershell
   # Example for App Services
   Get-AzWebApp -Name "<app-name>" | Select -ExpandProperty Identity
   # Then: New-AzRoleAssignment -ObjectId <new-id> -RoleDefinitionName "<role>" -Scope "<scope>"
   ```

2. **Verify application connectivity** — Check that App Services, VMs, and any services using managed identities can reach Key Vault, Storage, and other downstream resources.

3. **Confirm backup jobs** — Open Recovery Services Vaults in the destination and confirm the first backup job runs successfully.

4. **Update DNS** — If any private DNS zones or custom DNS entries reference the old subscription's resource IDs, update them.

---

## What moves automatically (no action needed)

- Resource-level RBAC assignments
- VM disks, data, and OS configuration
- App Service application settings and connection strings
- Resource tags
- Network Security Group rules
- User-assigned managed identity resources (they move as regular resources and keep their ObjectId)

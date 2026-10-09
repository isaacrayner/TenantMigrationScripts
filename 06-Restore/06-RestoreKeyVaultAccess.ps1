<#
.SYNOPSIS
    Restores Key Vault access policies for newly recreated Managed Identities.
.DESCRIPTION
    Uses the PrincipalId translation map from 4-A-RecreateMIdentities to automatically
    re-grant Key Vault permissions to the newly issued ObjectIds.
#>

param(
    [string]$SubscriptionId,
    [string]$MappingFile,
    [string]$KvBackupDir
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $destinationSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('MappingFile')) { $MappingFile = (Join-Path $backupRootDir "ManagedIdentities/NewManagedIdentitiesMapping.json") }
if (-not $PSBoundParameters.ContainsKey('KvBackupDir')) { $KvBackupDir = (Join-Path $backupRootDir "KeyVaultAccess") }

Write-Host "=== Restoring Key Vault Access for Managed Identities ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $MappingFile)) {
    Write-Host "Mapping file not found at $MappingFile. Run 06-Restore/05-RecreateManagedIdentities.ps1 first." -ForegroundColor Red
    exit 1
}

$mappings = Get-Content $MappingFile -Raw | ConvertFrom-Json
$idMap = @{}
foreach ($m in $mappings) {
    if ($m.OldPrincipalId -and $m.NewPrincipalId) {
        $idMap[$m.OldPrincipalId] = $m.NewPrincipalId
    }
}

Write-Host "Loaded $($idMap.Count) identity mappings." -ForegroundColor Cyan

# Check if Key Vault policy backups exist
$policyFiles = Get-ChildItem -Path $KvBackupDir -Filter "*_access_policies.json" -ErrorAction SilentlyContinue

if (-not $policyFiles -or $policyFiles.Count -eq 0) {
    Write-Host "No Key Vault access policy backup files found in $KvBackupDir." -ForegroundColor Yellow
    exit 0
}

foreach ($file in $policyFiles) {
    $kvName = $file.BaseName -replace "_access_policies$", ""
    Write-Host "Processing Key Vault: $kvName..." -ForegroundColor Cyan

    $policies = Get-Content $file.FullName -Raw | ConvertFrom-Json

    foreach ($p in $policies) {
        $oldId = $p.objectId

        # Check if this policy belonged to an identity that has been remapped
        $targetId = if ($idMap.ContainsKey($oldId)) { $idMap[$oldId] } else { $oldId }

        $keyPerms    = if ($p.permissions.keys) { [string[]]$p.permissions.keys } else { $null }
        $secPerms    = if ($p.permissions.secrets) { [string[]]$p.permissions.secrets } else { $null }
        $certPerms   = if ($p.permissions.certificates) { [string[]]$p.permissions.certificates } else { $null }

        $setParams = @{
            VaultName = $kvName
            ObjectId  = $targetId
        }
        if ($keyPerms) { $setParams["PermissionsToKeys"] = $keyPerms }
        if ($secPerms) { $setParams["PermissionsToSecrets"] = $secPerms }
        if ($certPerms) { $setParams["PermissionsToCertificates"] = $certPerms }

        try {
            Set-AzKeyVaultAccessPolicy @setParams -ErrorAction Stop | Out-Null
            Write-Host "  ✅ Applied policy to Key Vault '$kvName' for principal $targetId" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ Failed to set policy on '$kvName' for principal ${targetId}: $_" -ForegroundColor Red
        }
    }
}

Write-Host "`nKey Vault access restoration complete." -ForegroundColor Green

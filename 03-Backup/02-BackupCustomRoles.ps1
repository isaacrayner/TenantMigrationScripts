<#
.SYNOPSIS
    Exports all custom RBAC role definitions in the source subscription to JSON files.
.DESCRIPTION
    Custom roles must be exported and recreated in the target directory/subscription
    before RBAC role assignments can be restored.
#>

param(
    [string]$SubscriptionId,
    [string]$OutputDir
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('OutputDir')) { $OutputDir = (Join-Path $backupRootDir "CustomRoles") }

Write-Host "=== Exporting Custom RBAC Role Definitions ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$customRoles = Get-AzRoleDefinition | Where-Object { $_.IsCustom -eq $true }

if (-not $customRoles -or $customRoles.Count -eq 0) {
    Write-Host "No custom RBAC roles found in subscription $SubscriptionId." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($customRoles.Count) custom role(s). Exporting to $OutputDir..." -ForegroundColor Yellow

$summary = @()
foreach ($role in $customRoles) {
    $safeName = ($role.Name -replace '[^a-zA-Z0-9_\-\.]', '_')
    $roleFile = Join-Path $OutputDir "$safeName.json"

    # Sanitize role definition for recreation in destination:
    # 1. AssignableScopes must be rewritten for the new subscription
    # 2. Id must be omitted so Azure creates a new role GUID in target
    $roleExport = @{
        Name             = $role.Name
        Description      = $role.Description
        Actions          = $role.Actions
        NotActions       = $role.NotActions
        DataActions      = $role.DataActions
        NotDataActions   = $role.NotDataActions
        AssignableScopes = $role.AssignableScopes
    }

    $roleExport | ConvertTo-Json -Depth 10 | Out-File -FilePath $roleFile -Encoding utf8
    Write-Host "  ✅ Exported custom role: '$($role.Name)' -> $roleFile" -ForegroundColor Green

    $summary += [PSCustomObject]@{
        RoleName         = $role.Name
        ActionsCount     = $role.Actions.Count
        DataActionsCount = $role.DataActions.Count
        Scopes           = ($role.AssignableScopes -join "; ")
        File             = $roleFile
    }
}

$summaryFile = Join-Path $OutputDir "CustomRoles_Summary.csv"
$summary | Export-Csv -Path $summaryFile -NoTypeInformation
Write-Host "`nCustom role export complete. Summary saved to: $summaryFile" -ForegroundColor Green

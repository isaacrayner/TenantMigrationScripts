<#
.SYNOPSIS
    Recreates custom RBAC roles in the destination subscription from the exported JSON files.
.DESCRIPTION
    Updates AssignableScopes to match the destination subscription ID and creates
    the custom role definition.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [string]$InputDir       = (Join-Path $backupRootDir "CustomRoles")
)

Write-Host "=== Restoring Custom RBAC Roles in Destination ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $InputDir)) {
    Write-Host "No custom roles backup directory found at $InputDir. Skipping." -ForegroundColor Yellow
    exit 0
}

$roleFiles = Get-ChildItem -Path $InputDir -Filter "*.json"

if (-not $roleFiles -or $roleFiles.Count -eq 0) {
    Write-Host "No custom role JSON files found in $InputDir." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($roleFiles.Count) custom role file(s) to process." -ForegroundColor Cyan

foreach ($file in $roleFiles) {
    try {
        $roleDef = Get-Content $file.FullName -Raw | ConvertFrom-Json

        Write-Host "Processing custom role '$($roleDef.Name)'..." -ForegroundColor Yellow

        # Check if role definition already exists in destination
        $existing = Get-AzRoleDefinition -Name $roleDef.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  [SKIP] Role '$($roleDef.Name)' already exists in destination." -ForegroundColor Gray
            continue
        }

        # Rewrite AssignableScopes: replace source subscription ID with destination subscription ID
        $newScopes = @()
        foreach ($scope in $roleDef.AssignableScopes) {
            $updated = $scope -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId
            $newScopes += $updated
        }

        # Create new role definition object
        $newRole = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition
        $newRole.Name = $roleDef.Name
        $newRole.Description = $roleDef.Description
        $newRole.Actions = $roleDef.Actions
        $newRole.NotActions = $roleDef.NotActions
        $newRole.DataActions = $roleDef.DataActions
        $newRole.NotDataActions = $roleDef.NotDataActions
        $newRole.AssignableScopes = $newScopes

        New-AzRoleDefinition -Role $newRole -ErrorAction Stop | Out-Null
        Write-Host "  ✅ Created custom role: '$($roleDef.Name)'" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Failed to create custom role '$($file.BaseName)': $_" -ForegroundColor Red
    }
}

Write-Host "`nCustom role restoration complete." -ForegroundColor Green

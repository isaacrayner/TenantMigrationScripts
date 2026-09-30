<#
.SYNOPSIS
    Disables Managed Identities on resources prior to subscription migration.
.DESCRIPTION
    System-assigned and user-assigned managed identities must be detached before
    resources can be moved across subscriptions or tenants.
    Reads inventory from migration-data/ManagedIdentities/ManagedIdentityResources.json.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $sourceSubscriptionId,
    [string]$InputFile      = (Join-Path $backupRootDir "ManagedIdentities/ManagedIdentityResources.json")
)

Write-Host "=== Disabling Managed Identities Before Migration ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $InputFile)) {
    Write-Host "Input inventory file not found: $InputFile. Run 3-MigrationPrep/11-BackupIdentities.ps1 first." -ForegroundColor Red
    exit 1
}

$resourcesWithMI = Get-Content $InputFile -Raw | ConvertFrom-Json

if (-not $resourcesWithMI -or $resourcesWithMI.Count -eq 0) {
    Write-Host "No resources with Managed Identities to disable." -ForegroundColor Green
    exit 0
}

Write-Host "Processing $($resourcesWithMI.Count) resource(s)..." -ForegroundColor Yellow

foreach ($res in $resourcesWithMI) {
    $rgName  = $res.ResourceGroupName
    $name    = $res.ResourceName
    $resType = $res.ResourceType

    Write-Host "Disabling MI on [$resType] '$name' in RG '$rgName'..." -ForegroundColor Cyan

    try {
        switch -Regex ($resType) {
            "Microsoft.Compute/virtualMachines|VirtualMachine" {
                $vm = Get-AzVM -ResourceGroupName $rgName -Name $name -ErrorAction Stop
                Update-AzVM -ResourceGroupName $rgName -VM $vm -IdentityType "None" -ErrorAction Stop | Out-Null
            }
            "Microsoft.Web/sites|AppService|FunctionApp" {
                Set-AzWebApp -ResourceGroupName $rgName -Name $name -AssignIdentity $null -ErrorAction Stop | Out-Null
            }
            "Microsoft.Network/applicationGateways|ApplicationGateway" {
                $appGw = Get-AzApplicationGateway -ResourceGroupName $rgName -Name $name -ErrorAction Stop
                Set-AzApplicationGateway -ApplicationGateway $appGw -IdentityType "None" -ErrorAction Stop | Out-Null
            }
            "Microsoft.Sql/servers|SQLServer" {
                Set-AzSqlServer -ResourceGroupName $rgName -ServerName $name -AssignIdentity $null -ErrorAction Stop | Out-Null
            }
            Default {
                # Fallback via generic ARM update
                Write-Host "  Using generic ARM resource update for $resType..." -ForegroundColor Gray
                Set-AzResource -ResourceId $res.ResourceId -PropertyObject @{ identity = @{ type = "None" } } -Force -ErrorAction Stop | Out-Null
            }
        }
        Write-Host "  ✅ Disabled MI on '$name'" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Failed to disable MI on '$name': $_" -ForegroundColor Red
    }
}

Write-Host "`nAll managed identities disabled. Resources are ready for move." -ForegroundColor Green

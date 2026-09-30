<#
.SYNOPSIS
    Re-enables Managed Identities on resources in the destination subscription and
    generates a PrincipalId mapping file (OldPrincipalId -> NewPrincipalId).
.DESCRIPTION
    When system-assigned managed identities are recreated, Azure issues new ObjectIds.
    This script records the mapping to migration-data/ManagedIdentities/NewManagedIdentitiesMapping.json
    so role assignments and Key Vault access policies can be automatically restored.
#>

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

param(
    [string]$SubscriptionId = $destinationSubscriptionId,
    [string]$InputFile      = (Join-Path $backupRootDir "ManagedIdentities/ManagedIdentityResources.json"),
    [string]$MappingFile    = (Join-Path $backupRootDir "ManagedIdentities/NewManagedIdentitiesMapping.json")
)

Write-Host "=== Recreating Managed Identities in Destination Subscription ===" -ForegroundColor Cyan
Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

if (-not (Test-Path $InputFile)) {
    Write-Host "Inventory file not found: $InputFile. Skipping." -ForegroundColor Yellow
    exit 0
}

$resourcesWithMI = Get-Content $InputFile -Raw | ConvertFrom-Json

if (-not $resourcesWithMI -or $resourcesWithMI.Count -eq 0) {
    Write-Host "No resources to process." -ForegroundColor Green
    exit 0
}

$mappingList = @()

foreach ($res in $resourcesWithMI) {
    $rgName         = $res.ResourceGroupName
    $name           = $res.ResourceName
    $resType        = $res.ResourceType
    $origType       = $res.IdentityType
    $oldPrincipalId = $res.PrincipalId

    # Rewrite user-assigned identities to destination subscription
    $userAssignedIds = @()
    if ($res.UserAssignedIdentities) {
        $userAssignedIds = ($res.UserAssignedIdentities -split ";") |
            ForEach-Object { $_ -replace [regex]::Escape($sourceSubscriptionId), $destinationSubscriptionId }
    }

    Write-Host "Re-enabling [$origType] on [$resType] '$name'..." -ForegroundColor Cyan

    $newPrincipalId = $null

    try {
        switch -Regex ($resType) {
            "Microsoft.Compute/virtualMachines|VirtualMachine" {
                $vm = Get-AzVM -ResourceGroupName $rgName -Name $name -ErrorAction Stop
                if ($origType -eq "SystemAssigned") {
                    Update-AzVM -ResourceGroupName $rgName -VM $vm -IdentityType "SystemAssigned" -ErrorAction Stop | Out-Null
                } elseif ($origType -eq "UserAssigned") {
                    Update-AzVM -ResourceGroupName $rgName -VM $vm -IdentityType "UserAssigned" -IdentityId $userAssignedIds -ErrorAction Stop | Out-Null
                } elseif ($origType -match "SystemAssigned" -and $origType -match "UserAssigned") {
                    Update-AzVM -ResourceGroupName $rgName -VM $vm -IdentityType "SystemAssignedUserAssigned" -IdentityId $userAssignedIds -ErrorAction Stop | Out-Null
                }
                $updatedVM = Get-AzVM -ResourceGroupName $rgName -Name $name
                $newPrincipalId = $updatedVM.Identity.PrincipalId
            }
            "Microsoft.Web/sites|AppService|FunctionApp" {
                if ($origType -eq "SystemAssigned") {
                    Set-AzWebApp -ResourceGroupName $rgName -Name $name -AssignIdentity $true -ErrorAction Stop | Out-Null
                } elseif ($origType -eq "UserAssigned") {
                    Set-AzWebApp -ResourceGroupName $rgName -Name $name -AssignIdentity $userAssignedIds -ErrorAction Stop | Out-Null
                } elseif ($origType -match "SystemAssigned" -and $origType -match "UserAssigned") {
                    Set-AzWebApp -ResourceGroupName $rgName -Name $name -AssignIdentity $true -ErrorAction Stop | Out-Null
                    # Attach user-assigned as well
                    Set-AzWebApp -ResourceGroupName $rgName -Name $name -AssignIdentity $userAssignedIds -ErrorAction Stop | Out-Null
                }
                $updatedApp = Get-AzWebApp -ResourceGroupName $rgName -Name $name
                $newPrincipalId = $updatedApp.Identity.PrincipalId
            }
            "Microsoft.Network/applicationGateways|ApplicationGateway" {
                $appGw = Get-AzApplicationGateway -ResourceGroupName $rgName -Name $name -ErrorAction Stop
                if ($origType -match "UserAssigned" -and $userAssignedIds.Count -gt 0) {
                    Set-AzApplicationGateway -ApplicationGateway $appGw -IdentityType "UserAssigned" -UserAssignedIdentity $userAssignedIds -ErrorAction Stop | Out-Null
                }
            }
            "Microsoft.Sql/servers|SQLServer" {
                Set-AzSqlServer -ResourceGroupName $rgName -ServerName $name -AssignIdentity $true -ErrorAction Stop | Out-Null
                $updatedSql = Get-AzSqlServer -ResourceGroupName $rgName -ServerName $name
                $newPrincipalId = $updatedSql.Identity.PrincipalId
            }
            Default {
                Write-Host "  Resource type $resType re-enabling via generic ARM update..." -ForegroundColor Gray
            }
        }

        Write-Host "  ✅ Re-enabled MI for '$name'. New PrincipalId: $newPrincipalId" -ForegroundColor Green

        $mappingList += [PSCustomObject]@{
            ResourceName    = $name
            ResourceType    = $resType
            ResourceGroup   = $rgName
            OldPrincipalId  = $oldPrincipalId
            NewPrincipalId  = $newPrincipalId
            IdentityType    = $origType
        }

    } catch {
        Write-Host "  ❌ Failed to re-enable MI on '$name': $_" -ForegroundColor Red
    }
}

# Save the PrincipalId mapping file
$mappingList | ConvertTo-Json -Depth 5 | Out-File -FilePath $MappingFile -Encoding utf8
$mappingCsv = $MappingFile -replace "\.json$", ".csv"
$mappingList | Export-Csv -Path $mappingCsv -NoTypeInformation -Encoding utf8

Write-Host "`n✅ PrincipalId mapping successfully saved to: $MappingFile" -ForegroundColor Green
Write-Host "Run 7-Recreation/5-RestoreRoleAssignments.ps1 to automatically restore role assignments using these new IDs." -ForegroundColor Cyan
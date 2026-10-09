<#
.SYNOPSIS
    Exports all RBAC role assignments from the source subscription to JSON and CSV.
.DESCRIPTION
    Captures complete assignment metadata (Scope, RoleDefinition, ObjectId, ObjectType,
    SignInName, DisplayName) to enable restoring permissions in Phase 6.
#>

param(
    [string]$SubscriptionId,
    [string]$JsonFile,
    [string]$CsvFile
)

$paramsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "migration-params.ps1"
if (Test-Path $paramsPath) { . $paramsPath }

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) { $SubscriptionId = $sourceSubscriptionId }
if (-not $PSBoundParameters.ContainsKey('JsonFile')) { $JsonFile = (Join-Path $backupRootDir "RBAC_Assignments.json") }
if (-not $PSBoundParameters.ContainsKey('CsvFile')) { $CsvFile = (Join-Path $backupRootDir "RBAC_Assignments.csv") }

$logFile = Join-Path $logRootDir "RBAC_Export.log"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$level] $message"
    Write-Host $line -ForegroundColor $(if ($level -eq "ERROR") { "Red" } elseif ($level -eq "WARN") { "Yellow" } else { "Cyan" })
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== RBAC Role Assignment Export ==="
Write-Log "Source Subscription: $SubscriptionId"

try {
    Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Log "Subscription context set successfully."
} catch {
    Write-Log "ERROR setting subscription context: $_" "ERROR"
    exit 1
}

try {
    Write-Log "Querying all role assignments in subscription..."
    $rbacAssignments = Get-AzRoleAssignment -ErrorAction Stop

    if (-not $rbacAssignments -or $rbacAssignments.Count -eq 0) {
        Write-Log "No RBAC assignments found." "WARN"
        "[]" | Out-File -FilePath $JsonFile -Encoding utf8
        exit 0
    }

    Write-Log "Found $($rbacAssignments.Count) role assignment(s)."

    # Format structured export
    $exportItems = @()
    foreach ($a in $rbacAssignments) {
        $exportItems += [PSCustomObject]@{
            RoleAssignmentId   = $a.RoleAssignmentId
            RoleDefinitionName = $a.RoleDefinitionName
            RoleDefinitionId   = $a.RoleDefinitionId
            Scope              = $a.Scope
            DisplayName        = $a.DisplayName
            SignInName         = $a.SignInName
            ObjectId           = $a.ObjectId
            ObjectType         = $a.ObjectType
            CanDelegate        = $a.CanDelegate
        }
    }

    $exportItems | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonFile -Encoding utf8
    Write-Log "Exported JSON to: $JsonFile" "SUCCESS"

    $exportItems | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding utf8
    Write-Log "Exported CSV to : $CsvFile" "SUCCESS"

} catch {
    Write-Log "ERROR retrieving role assignments: $_" "ERROR"
    exit 1
}

Write-Log "RBAC export complete. Restore via 06-Restore/08-RestoreRoleAssignments.ps1." "SUCCESS"

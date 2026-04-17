## DESCRIPTION: Validates that specified resources can be moved between two resource groups using
##              Azure's validateMoveResources API. Run this before executing any resource moves
##              to catch compatibility issues early.
## USAGE:       1. Set $sourceName and $destinationName to the source and destination RG names.
##              2. Set $resourcesToMove to an array of resource names to validate.
##              3. Run in PowerShell with the Az module installed. Review output for errors.

# Script to check resources in preparation for the move

$sourceName = "sourceRG"
$destinationName = "destinationRG"
$resourcesToMove = @("app1", "app2")

$sourceResourceGroup = Get-AzResourceGroup -Name $sourceName
$destinationResourceGroup = Get-AzResourceGroup -Name $destinationName

$resources = Get-AzResource -ResourceGroupName $sourceName | Where-Object { $_.Name -in $resourcesToMove }

Invoke-AzResourceAction -Action validateMoveResources -ResourceId $sourceResourceGroup.ResourceId -Parameters @{
      resources = $resources.ResourceId;  # Wrap in an @() array if providing a single resource ID string.
      targetResourceGroup = $destinationResourceGroup.ResourceId
   }
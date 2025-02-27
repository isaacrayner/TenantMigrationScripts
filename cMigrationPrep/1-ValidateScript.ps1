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
Param(
    [string]$ManagedImageName,
    [string]$ManagedImageResourceGroupName,
    [string]$AgentPoolResourceGroup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


Write-Output "Remove all temporary Packer resource groups"
Get-AzureRmResourceGroup | Where-Object ResourceGroupName -like packer-resource-group-* | Remove-AzureRmResourceGroup -Force

Write-Output "Remove agent pool resource group"
Remove-AzureRmResourceGroup -Name $AgentPoolResourceGroup -Force

Write-Output "Remove Managed Image"
Remove-AzureRmImage -ResourceGroupName $ManagedImageResourceGroupName -ImageName $ManagedImageName -Force

Write-Output "Remove Image resource group"
Remove-AzureRmResourceGroup -Name $ManagedImageResourceGroupName -Force

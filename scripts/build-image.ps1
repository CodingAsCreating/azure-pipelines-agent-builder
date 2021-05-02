Param(
    [string]$Location,
    [string]$PackerFile,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$TenantId,
    [string]$SubscriptionId,
    [string]$ObjectId,
    [string]$ManagedImageResourceGroupName,
    [string]$ManagedImageName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module AzureRM

Write-Output "Creating new resource group $ManagedImageResourceGroupName"
New-AzureRmResourceGroup -Name $ManagedImageResourceGroupName -Location $Location -ErrorAction SilentlyContinue


Get-AzureRmResourceGroup -Name $ManagedImageResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue
if ( -Not $notPresent) {
    Write-Output "Cleaning up previous image versions"
    Remove-AzureRmImage -ResourceGroupName $ManagedImageResourceGroupName -ImageName $ManagedImageName -Force
}

Write-Output "Build Image"
if ($env:BUILD_REPOSITORY_LOCALPATH) {
    Set-Location $env:BUILD_REPOSITORY_LOCALPATH
}

$commitId = $(git log --pretty=format:'%H' -n 1)
Write-Output "CommitId: $commitId"
  
packer build `
    -var "commit_id=$commitId" `
    -var "client_id=$ClientId" `
    -var "client_secret=$ClientSecret" `
    -var "tenant_id=$TenantId" `
    -var "subscription_id=$SubscriptionId" `
    -var "object_id=$ObjectId" `
    -var "location=$Location" `
    -var "managed_image_resource_group_name=$ManagedImageResourceGroupName" `
    -var "managed_image_name=$ManagedImageName" `
    -on-error=abort `
    $PackerFile

if ($LASTEXITCODE -eq 1){
    Write-Error "Packer build faild"
    exit 1
}
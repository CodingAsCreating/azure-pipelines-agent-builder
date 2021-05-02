Param(
    [string]$VMUserName,
    [string]$VMUserPassword,
    [string]$VMName,
    [string]$AgentPoolResourceGroup,
    [string]$AgentPoolName,
    [string]$ScaleSetName,
    [string]$Location,
    [string]$AzureDevOpsPAT,
    [string]$AzureDevOpsURL
)

function NewRandomName {
    (-join((48..57) + (65..90) + (97..122) | Get-Random -Count 10| % {[char]$_})).ToLower()
}

Write-Output "Deploying Agent script to VM"

$StorageAccountName = NewRandomName
$ContainerName = "scripts"
    
$StorageAccountAvailability = Get-AzureRmStorageAccountNameAvailability -Name $StorageAccountName
    
if ($StorageAccountAvailability.NameAvailable) {
    Write-Output "Creating storage account $StorageAccountName in $AgentPoolResourceGroup"
    New-AzureRmStorageAccount -ResourceGroupName $AgentPoolResourceGroup -AccountName $StorageAccountName -Location $Location -SkuName "Standard_LRS"
}
else {
    Write-Output "Storage account $StorageAccountName in $AgentPoolResourceGroup already exists"
}
    
$StorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $AgentPoolResourceGroup -Name $StorageAccountName).Value[0]
$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    
$container = Get-AzureStorageContainer -Context $StorageContext |  where-object {$_.Name -eq "scripts"}
if ( -Not $container) {
    Write-Output "Creating container $ContainerName in $StorageAccountName"
    New-AzureStorageContainer -Name $ContainerName -Context $StorageContext -Permission blob
}
else {
    Write-Output "Container $ContainerName in $StorageAccountName already exists"
}
    
$FileName = "install-agent-extension.ps1";
$basePath = $PWD;
if ($env:SYSTEM_DEFAULTWORKINGDIRECTORY) {
    $basePath = "$env:SYSTEM_DEFAULTWORKINGDIRECTORY"
}
$LocalFile = "$basePath/scripts/$FileName"

Write-Output "Uploading file $LocalFile to $StorageAccountName"
Set-AzureStorageBlobContent `
    -Container $ContainerName `
    -Context $StorageContext `
    -File $Localfile `
    -Blob $Filename `
    -ErrorAction Stop -Force | Out-Null
    
$publicSettings = @{ 
            "fileUris" = @("https://$StorageAccountName.blob.core.windows.net/$ContainerName/$FileName");
};            

$arguments = "-AzureDevOpsPAT $AzureDevOpsPAT -AzureDevOpsURL $AzureDevOpsURL -windowsLogonAccount $VMUserName -windowsLogonPassword $VMUserPassword -AgentPoolName $AgentPoolName"
$SecureArguments = ConvertTo-SecureString $arguments -AsPlainText -Force        

$protectedSettings = @{
     "commandToExecute" = "PowerShell -ExecutionPolicy Unrestricted .\$FileName -AzureDevOpsPAT $AzureDevOpsPAT -AzureDevOpsURL $AzureDevOpsURL -windowsLogonAccount $VMUserName -windowsLogonPassword $VMUserPassword -AgentPoolName $AgentPoolName";
    };

Write-Output "Get information about the scale set"
$vmss = Get-AzureRmVmss `
    -ResourceGroupName $AgentPoolResourceGroup `
    -VMScaleSetName $ScaleSetName

Write-Output "Use Custom Script Extension to install VSTS Agent"
Add-AzureRmVmssExtension -VirtualMachineScaleSet $vmss `
    -Name "Azure_DevOps_Agent" `
    -Publisher "Microsoft.Compute" `
    -Type "CustomScriptExtension" `
    -TypeHandlerVersion 1.8 `
    -ErrorAction Stop `
    -ProtectedSetting $protectedSettings `
    -Setting $publicSettings 


Write-Output "Update the scale set and apply the Custom Script Extension to the VM instances"
Update-AzureRmVmss `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Name $ScaleSetName `
    -VirtualMachineScaleSet $vmss
    
Write-Output "Finished creating VM Scale Set and installing Agent"

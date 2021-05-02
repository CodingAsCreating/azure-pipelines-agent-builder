Param(
    [string]$VMUserName ,
    [string]$VMUserPassword,
    [string]$VMName,
    [string]$ManagedImageResourceGroupName,
    [string]$ManagedImageName,
    [string]$AgentPoolResourceGroup,
    [string]$ScaleSetName,
    [string]$Location
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Get-AzureRmResourceGroup -Name $AgentPoolResourceGroup -ev notPresent -ea 0

if (-Not $notPresent) {
    Write-Output "Removing $AgentPoolResourceGroup"
    Remove-AzureRmResourceGroup -Name $AgentPoolResourceGroup -Force 
}

Write-Output "Create a new resource group $AgentPoolResourceGroup"
New-AzureRmResourceGroup -Name $AgentPoolResourceGroup -Location $Location

Write-Output "Create a virtual network subnet"
$subnet = New-AzureRmVirtualNetworkSubnetConfig `
    -Name "Subnet" `
    -AddressPrefix 10.0.0.0/24

Write-Output "Create a virtual network"
$vnet = New-AzureRmVirtualNetwork `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Name "AgentVnet" `
    -Location $Location `
    -AddressPrefix 10.0.0.0/16 `
    -Subnet $subnet `
    -Force

Write-Output "Create a public IP address"
$publicIP = New-AzureRmPublicIpAddress `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Location $Location `
    -AllocationMethod Static `
    -Name "LoadBalancerPublicIP" `
    -Force

Write-Output "Create a frontend and backend IP pool"
$frontendIP = New-AzureRmLoadBalancerFrontendIpConfig `
    -Name "FrontEndPool" `
    -PublicIpAddress $publicIP
$backendPool = New-AzureRmLoadBalancerBackendAddressPoolConfig `
    -Name "BackEndPool"

Write-Output "Create a Network Address Translation (NAT) pool"
$inboundNATPool = New-AzureRmLoadBalancerInboundNatPoolConfig `
    -Name "RDPRule" `
    -FrontendIpConfigurationId $frontendIP.Id `
    -Protocol TCP `
    -FrontendPortRangeStart 50001 `
    -FrontendPortRangeEnd 59999 `
    -BackendPort 3389

Write-Output "Create the load balancer"
$lb = New-AzureRmLoadBalancer `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Name "LoadBalancer" `
    -Location $Location `
    -FrontendIpConfiguration $frontendIP `
    -BackendAddressPool $backendPool `
    -InboundNatPool $inboundNATPool `
    -Force

Write-Output "Create a load balancer health probe on port 80"
Add-AzureRmLoadBalancerProbeConfig -Name "HealthProbe" `
    -LoadBalancer $lb `
    -Protocol TCP `
    -Port 80 `
    -IntervalInSeconds 15 `
    -ProbeCount 2

Write-Output "Create a load balancer rule to distribute traffic on port 80"
Add-AzureRmLoadBalancerRuleConfig `
    -Name "LoadBalancerRule" `
    -LoadBalancer $lb `
    -FrontendIpConfiguration $lb.FrontendIpConfigurations[0] `
    -BackendAddressPool $lb.BackendAddressPools[0] `
    -Protocol TCP `
    -FrontendPort 80 `
    -BackendPort 80

Write-Output "Update the load balancer configuration"
Set-AzureRmLoadBalancer -LoadBalancer $lb

Write-Output "Create IP address configurations"
$ipConfig = New-AzureRmVmssIpConfig `
    -Name "IPConfig" `
    -LoadBalancerBackendAddressPoolsId $lb.BackendAddressPools[0].Id `
    -LoadBalancerInboundNatPoolsId $inboundNATPool.Id `
    -SubnetId $vnet.Subnets[0].Id

Write-Output "Create a vmss config"
$vmssConfig = New-AzureRmVmssConfig `
    -Location $Location `
    -SkuCapacity 1 `
    -SkuName "Standard_B2s" `
    -UpgradePolicyMode Automatic

Write-Output "Set the VM image"
$image = Get-AzureRMImage -ImageName $ManagedImageName -ResourceGroupName $ManagedImageResourceGroupName
Set-AzureRmVmssStorageProfile $vmssConfig `
    -OsDiskCreateOption FromImage `
    -ManagedDisk Standard_LRS `
    -OsDiskCaching "None" `
    -OsDiskOsType Windows `
    -ImageReferenceId $image.id

Write-Output "Set up information for authenticating with the virtual machine"
Set-AzureRmVmssOsProfile $vmssConfig `
    -AdminUsername $VMUserName `
    -AdminPassword $VMUserPassword `
    -ComputerNamePrefix $VMName

Write-Output "Attach the virtual network to the config object"
Add-AzureRmVmssNetworkInterfaceConfiguration `
    -VirtualMachineScaleSet $vmssConfig `
    -Name "network-config" `
    -Primary $true `
    -IPConfiguration $ipConfig

Write-Output "Create the scale set with the config object (this step might take a few minutes)"
New-AzureRmVmss `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Name $ScaleSetName `
    -VirtualMachineScaleSet $vmssConfig
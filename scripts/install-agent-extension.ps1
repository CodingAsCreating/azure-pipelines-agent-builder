Param(
    [string]$AzureDevOpsPAT,
    [string]$AzureDevOpsURL,
    [string]$windowsLogonAccount,
    [string]$windowsLogonPassword,
    [string]$AgentPoolName
)

$ErrorActionPreference="Stop";

If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{
     throw "Run command in Administrator PowerShell Prompt"
};
     
if(-NOT (Test-Path $env:SystemDrive\'vstsagent'))
{
    mkdir $env:SystemDrive\'vstsagent'
}; 

Set-Location $env:SystemDrive\'vstsagent'; 

for($i=1; $i -lt 100; $i++)
{
    $destFolder="A"+$i.ToString();
    if(-NOT (Test-Path ($destFolder)))
    {
        mkdir $destFolder;
        Set-Location $destFolder;
        break;
    }
}; 

$agentZip="$PWD\agent.zip";

$DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy;
$WebClient=New-Object Net.WebClient; 
$Uri='https://vstsagentpackage.azureedge.net/agent/2.183.1/vsts-agent-win-x64-2.183.1.zip';


if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri)))
{
    $WebClient.Proxy = New-Object Net.WebProxy($DefaultProxy.GetProxy($Uri).OriginalString, $True);
}; 

$WebClient.DownloadFile($Uri, $agentZip);
Add-Type -AssemblyName System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory($agentZip, "$PWD");

.\config.cmd --unattended `
             --url $AzureDevOpsURL `
             --auth PAT `
             --token $AzureDevOpsPAT `
             --pool $AgentPoolName `
             --agent $env:COMPUTERNAME `
             --replace `
             --runasservice `
             --work '_work' `
             --windowsLogonAccount $windowsLogonAccount `
             --windowsLogonPassword $windowsLogonPassword 

#Remove-Item $agentZip;

 .\run.cmd
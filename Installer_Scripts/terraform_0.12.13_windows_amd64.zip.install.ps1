$ErrorActionPreference = "Stop"
# https://releases.hashicorp.com/terraform/0.12.13/terraform_0.12.13_windows_amd64.zip
<#
 # Requires .\Configs.psm1
#>
$ScriptInvocation = $MyInvocation
function Get-ScriptPath {
    $path = (pwd)
    try {
        $path = Split-Path $ScriptInvocation.MyCommand.Path -Parent
    }
    catch {}

    return $path
}

$ConfigName = "configs"
Get-Module -Name $ConfigName | Remove-Module 
(Get-ChildItem "$(Get-ScriptPath)\$ConfigName.psm1") | Import-Module

$softwareUri = 'https://releases.hashicorp.com/terraform/0.12.13/terraform_0.12.13_windows_amd64.zip'
$fileName = Save-RepositoryFileInstaller -Uri $softwareUri -FileName terraform_0.12.13_windows_amd64.zip
Install-RepositoryZippedInstaller -FileName $fileName -NewRelativeEnvironmentPath '.'

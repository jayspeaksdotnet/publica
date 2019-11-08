# using powershell module as a configuration provider

# Region

function Get-RepositoryModuleName {
    $name = 'configs'
    try {
        $name = $script:MyInvocation.MyCommand.Name
    }
    catch {}

    $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
    return $name
}   

function Get-ExecutingName {
    $name = 'configs'
    try {
        $name = $script:MyInvocation.ScriptName
        $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
    }
    catch {}
    return $name
}
 function Get-ScriptParentPath {
    $path = (pwd)
    try {
        $path = Split-Path -parent $script:MyInvocation.MyCommand.Path
    }
    catch {}
    return $path
}

function Get-Configs {
    $configName = Get-RepositoryModuleName
    $configFile = "$configName.json"

    return (Get-Content $configFile | ConvertFrom-Json)
}

function Get-RepositoryInstallers {
    return Resolve-Path (Get-Configs).repositoryInstallers
}

function Get-RepositoryInstallations {
    return Resolve-Path (Get-Configs).repositoryInstallations
}

function Add-RepositoryEnvPath {
    PARAM(
        [Parameter(Mandatory=$true)] $PathToAdd,
        [Parameter(Mandatory=$false)] $PathScope = [EnvironmentVariableTarget]::User
    )

    # set path if does not exists
    # another method: https://codingbee.net/powershell/powershell-make-a-permanent-change-to-the-path-environment-variable
    $fullPathToAdd = (Resolve-Path -Path $PathToAdd).Path
    $pathExists = Test-Path $fullPathToAdd
    if (-Not $pathExists) {
        Write-Host "Skipped adding environment path because it is not found at: $fullPathToAdd"
        return;
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", $pathScope);
    $pathes = $userPath -split ';'
    $hasPathAdded = $pathes -contains $fullPathToAdd;
    if ($hasPathAdded) {
        Write-Host "Already added Env Path: $fullPathToAdd"
    }
    else {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$fullPathToAdd", $pathScope)
        Write-Host "Added to Env Path: $fullPathToAdd"
    }
}

# added file to repository
function Save-RepositoryFileInstaller {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory=$true)] [String] $Uri,
        [Parameter(Mandatory=$false)] [String] $FileName,
        [Parameter(Mandatory=$false)] [String] $ConfigName = "configs"
    )

    BEGIN {
        $currentModule = Get-RepositoryModuleName
        if ($ConfigName -ne $currentModule) {
            Get-Module -Name $ConfigName | Remove-Module 
            (Get-ChildItem "$(Get-ScriptPath)\$ConfigName.psm1") | Import-Module    
        }
    }
    
    PROCESS {
        # sometimes, url would contain the file name.  can spend 15 minutes to get it parsed.
        # source: http://mirror.math.princeton.edu/pub/eclipse//technology/epp/downloads/release/2019-09/R/eclipse-jee-2019-09-R-win32-x86_64.zip&mirror_id=1249
        # actual1: http://mirror.math.princeton.edu/pub/eclipse//technology/epp/downloads/release/2019-09/R/eclipse-jee-2019-09-R-win32-x86_64.zip
        # actual2: https://download.sonatype.com/nexus/3/latest-win64.zip
        # notice that actual1 can perform parsing, but not actual2.
        if ($null -eq $FileName) {
            $parsedFileName = [System.IO.Path]::GetFileNameWithoutExtension($Uri)
            $parsedFileNameWithExtAndQuery = $Uri.Substring($Uri.LastIndexOf($parsedFileName))
            
            $parsedFileNameWithExt = $parsedFileNameWithExtAndQuery
            $queryIndex = $parsedFileNameWithExt.IndexOf('&')
            if ($queryIndex -gt 0) {
                $parsedFileNameWithExt = $parsedFileNameWithExt.Substring(0, $queryIndex)
            }
            
            $FileName = $parsedFileNameWithExt
        }
        
        $repoLocation = Get-RepositoryInstallers
        $sourcePath = "$repoLocation\$FileName"

        # Download
        if (-Not (Test-Path $sourcePath)) {
            Invoke-WebRequest -OutFile $sourcePath -Uri $Uri
            Write-Host "Saved to: $sourcePath"
        }
        else {
            Write-Host "Found existing file at: $sourcePath"
        }

        return $FileName
    }
    END {
        $currentModule = Get-RepositoryModuleName
        if ($ConfigName -ne $currentModule) {
            Remove-Module -Name $ConfigName
        }
    }
}

# credit: https://www.gngrninja.com/script-ninja/2016/5/15/powershell-getting-started-part-8-accepting-pipeline-input
function Install-RepositoryZippedInstaller {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory=$true)] [String] $FileName,
        [Parameter(Mandatory=$false)] [String] $ConfigName = "configs",
        [Parameter(Mandatory=$false)] [String] $NewRelativeEnvironmentPath = $null
    )

    BEGIN {
        $currentModule = Get-RepositoryModuleName
        if ($ConfigName -ne $currentModule) {
            Get-Module -Name $ConfigName | Remove-Module 
            (Get-ChildItem "$(Get-ScriptPath)\$ConfigName.psm1") | Import-Module    
        }
    }
    
    PROCESS {
        $repoLocation = Get-RepositoryInstallers
        $source = "$repoLocation\$FileName"

        $targetFullPath = Get-RepositoryInstallations
        $sourceWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($source)
        $targetPath = "$targetFullPath\$sourceWithoutExtension"

        # Extract
        $hasOldPackages = Test-Path $targetPath
        if (-Not $hasOldPackages) {
            Expand-Archive -Path $source -DestinationPath $targetPath
        }

        # Add to Environment Folder, e.g., Bin path
        if ($null -ne $NewRelativeEnvironmentPath) {
            Add-RepositoryEnvPath -PathToAdd "$targetPath\$NewRelativeEnvironmentPath"
        }

        Write-Host "Installed to: $targetPath"
    }

    END {
        $currentModule = Get-RepositoryModuleName
        if ($ConfigName -ne $currentModule) {
            Remove-Module -Name $ConfigName
        }
    }
}

function Install-RepositoryMsiInstaller {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory=$true)] [String] $FileName,
        [Parameter(Mandatory=$false)] [String] $ConfigName = "configs",
        [Parameter(Mandatory=$false)] [String] $NewRelativeEnvironmentPath = $null,
        [Parameter(Mandatory=$false)] [String] $MsiOptions = $null
    )

    BEGIN {
        $currentModule = Get-RepositoryModuleName
        if ($ConfigName -ne $currentModule) {
            Get-Module -Name $ConfigName | Remove-Module 
            (Get-ChildItem "$(Get-ScriptPath)\$ConfigName.psm1") | Import-Module    
        }
    }
    
    PROCESS {
        $repoLocation = Get-RepositoryInstallers
        $source = "$repoLocation\$FileName"
        $options = $MsiOptions
        
        $targetFullPath = Get-RepositoryInstallations
        $sourceWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($source)
        $targetPath = "$targetFullPath\$sourceWithoutExtension"

        $arguments = "/I ""$source"" /qn $options"
        write-host "msiexec.exe $arguments"
        $result = Start-Process msiexec.exe -Wait -ArgumentList $arguments -NoNewWindow
        if ($result.ExitCode -ne 0) {
            throw "failed installation.  Check Log"
        }

        # Add to Environment Folder, e.g., Bin path
        $shallAddEnvPath = ($null -ne $NewRelativeEnvironmentPath) -and ("" -ne $NewRelativeEnvironmentPath)
        if ($shallAddEnvPath) {
            Add-RepositoryEnvPath -PathToAdd "$targetPath\$NewRelativeEnvironmentPath"
        }

        Write-Host "Installed $source"
    }

    END {
        $currentModule = Get-RepositoryModuleName
        if ($ConfigName -ne $currentModule) {
            Remove-Module -Name $ConfigName
        }
    }
}

function Add-RepositoryLog {

}

# EndRegion

# Exports
Export-ModuleMember -Function Get-Repository*
Export-ModuleMember -Function Add-Repository*
Export-ModuleMember -Function Install-Repository*
Export-ModuleMember -Function Save-Repository*
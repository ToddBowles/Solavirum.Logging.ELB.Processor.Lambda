function Get-NuGetExecutable
{
    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $commonScriptsDirectoryPath = "$rootDirectoryPath\scripts\common"

    . "$commonScriptsDirectoryPath\Functions-FileSystem.ps1"

    $nugetExecutablePath = "$rootDirectoryPath\tools\nuget.exe"

    return Test-FileExists $nugetExecutablePath
}

function NuGet-EnsurePackageAvailable
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$package,
        [string]$version="latest",
        [scriptblock]$DI_nugetInstall={ 
            param
            (
                [string]$package, 
                [string]$version, 
                [string]$installDirectory,
                [string]$source
            ) 
            
            Nuget-Install -PackageId $package -Version $version -OutputDirectory $installDirectory -Source $source
        }
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $packagesDir = "$rootDirectoryPath\tools\packages"
    if ($version -ne "latest")
    {
        $expectedDirectory = "$packagesDir\$package.$version"

        if (Test-Path $expectedDirectory)
        {
            return $expectedDirectory;
        }
    }

    Write-Verbose "Attempting to install package [$package.$version] via Nuget"
    $maxAttempts = 5
    $waitSeconds = 1
    $success = $false
    $attempts= 1

    while (-not $success -and $attempts -lt $maxAttempts)
    {
        try
        {
            & $DI_nugetInstall -Package $package -Version $version -InstallDirectory $packagesDir
            $success = $true
        }
        catch
        {
            Write-Warning "An error occurred while attempting to install the package [$package.$version]. Trying again in [$waitSeconds] seconds. This was attempt number [$attempts]."
            Write-Warning $_

            $attempts++
            if ($attempts -lt $maxAttempts) { Sleep -Seconds $waitSeconds }

            $waitSeconds = $waitSeconds * 2
        }
    }

    if (-not($success))
    {
        throw "The package [$package.$version] was not installed and will not be available. Check previous log messages for details."
    }

    if ($version -eq "latest")
    {
        $directory = @(Get-ChildItem -Path $packagesDir -Filter "$package*" -Directory | Sort-Object -Property Name -Descending)[0]
        return $directory.FullName
    }
    else
    {
        return $expectedDirectory
    }
}

function NuGet-Restore
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$solutionOrProjectFile,
        [string[]]$extraRestoreArgs
    )

    $nugetExecutable = Get-NuGetExecutable

    $command = "restore"
    $arguments = @()
    $arguments += $command
    $arguments += "`"$($solutionOrProjectFile.FullName)`""
    $arguments += "-NoCache"
    $arguments += "-DisableParallelProcessing"
    $arguments = $arguments + $extraRestoreArgs
    
    $nugetRestoreCommand = "$($nugetExecutable.FullName)"
    write-host  "Running $nugetRestoreCommand with args $arguments"

    write-verbose "Restoring NuGet Packages for [$($solutionOrProjectFile.FullName)]."
    (& "$($nugetExecutable.FullName)" $arguments) | Write-Verbose
    $return = $LASTEXITCODE
    if ($return -ne 0)
    {
        throw "NuGet '$command' failed. Exit code [$return]."
    }
}

function NuGet-Publish
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.IO.FileInfo]$package,
        [Parameter(Mandatory=$true)]
        [string]$apiKey,
        [Parameter(Mandatory=$true)]
        [string]$feedUrl,
        [scriptblock]$DI_ExecutePublishUsingNuGetExeAndArguments={ 
            param
            (
                [System.IO.FileInfo]$nugetExecutable, 
                [array]$arguments
            ) 
            
            (& "$($nugetExecutable.FullName)" $arguments) | Write-Verbose 
        }
    )

    begin
    {
        $nugetExecutable = Get-NuGetExecutable
    }
    process
    {
        $command = "push"
        $arguments = @()
        $arguments += $command
        $arguments += "`"$($package.FullName)`""
        $arguments += "-ApiKey"
        $arguments += "`"$apiKey`""
        $arguments += "-Source"
        $arguments += "`"$feedUrl`""
        $arguments += "-Timeout"
        $arguments += "1800"

        write-verbose "Publishing package[$($package.FullName)] to [$feedUrl]."
        & $DI_ExecutePublishUsingNuGetExeAndArguments $nugetExecutable $arguments
        $return = $LASTEXITCODE
        if ($return -ne $null -and $return -ne 0)
        {
            throw "NuGet '$command' failed. Exit code [$return]."
        }
    }
}

function NuGet-Pack
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$projectOrNuspecFile,
        [Parameter(Mandatory=$true)]
        [System.IO.DirectoryInfo]$outputDirectory,
        [string]$version,
        [string]$configuration="Release",
        [string[]]$additionalArguments,
        [scriptblock]$DI_ExecutePackUsingNuGetExeAndArguments={ 
            param
            (
                [System.IO.FileInfo]$nugetExecutable, 
                [array]$arguments
            ) 
            
            (& "$($nugetExecutable.FullName)" $arguments) | Write-Verbose 
        },
        [switch]$createSymbolsPackage=$true
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $nugetExecutable = Get-NuGetExecutable

    $command = "pack"
    $arguments = @()
    $arguments += $command
    $arguments += "`"$($projectOrNuspecFile.FullName)`""
    $arguments += "-OutputDirectory"
    $arguments += "`"$($outputDirectory.FullName)`""
    if ($version -ne $null -and $version -ne "latest")
    {
        $arguments += "-Version"
        $arguments += "$($version.ToString())"
    }
    
    $arguments += "-Properties"
    $arguments += "Configuration=$configuration"
    
    if ($createSymbolsPackage)
    {
        $arguments += "-Symbols"
    }
    
    $arguments += "-Verbosity"
    $arguments += "detailed"

    $arguments = $arguments + $additionalArguments

    write-verbose "Packing [$($projectOrNuspecFile.FullName)] to [$($outputDirectory.FullName)]."
    & $DI_ExecutePackUsingNuGetExeAndArguments $nugetExecutable $arguments
    $return = $LASTEXITCODE
    if ($return -ne 0)
    {
        throw "NuGet '$command' failed. Exit code [$return]."
    }

    # Sometimes the project or Nuspec file might not match exactly with the created package (which may have
    # used the default namespace/output name). We use the project/nuspec file specified, but strip the 
    # extension and add a match all to the start (to deal with the situation where the file is a shortened
    # version of the package).
    $packageMatcher = "*$([System.IO.Path]::GetFileNameWithoutExtension($projectOrNuspecFile.Name)).*.nupkg"
    
    . "$rootDirectoryPath\scripts\common\Functions-Enumerables.ps1"
    return Get-ChildItem -Path $outputDirectory -Filter $packageMatcher
}

function NuGet-Install
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$packageId,
        [string]$version,
        [Parameter(Mandatory=$true)]
        [string]$outputDirectory,
        [string]$source
    )

    
    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $nugetExecutable = Get-NuGetExecutable

    $command = "install"
    $arguments = @()
    $arguments += $command
    $arguments += "`"$packageId`""
    if (-not([string]::IsNullOrEmpty($version)) -and ($version -ne "latest"))
    {
        $arguments += "-Version"
        $arguments += $version
    }

    $arguments += "-OutputDirectory"
    $arguments += "`"$outputDirectory`""
    $arguments += "-NoCache"

    if (-not([String]::IsNullOrEmpty($source)))
    {
        $arguments += "-Source"
        $arguments += "`"$source`""
    }
    else
    {
        $configFilePath = _LocateNugetConfigFile
        if ($configFilePath -ne $null)
        {
            $arguments += "-Config"
            $arguments += "`"$configFilePath`""
        }
    }

    write-verbose "Installing NuGet Package [$packageId.$version] into [$outputDirectory] using config [$configFilePath]."

    # If you write this to debug, for some ungodly reason, it will fail when it is run
    # on an AWS instance. God only knows why (invalid UTF 8 contination byte).
    (& "$($nugetExecutable.FullName)" $arguments) | Write-Debug

    $return = $LASTEXITCODE
    if ($return -ne 0)
    {
        throw "NuGet '$command' failed. Exit code [$return]."
    }
}

function _LocateNugetConfigFile
{
    Write-Verbose "Attempting to locate Nuget config file"
    $standardPath = "$rootDirectoryPath\tools\nuget.config"
    if (Test-Path $standardPath)
    {
        Write-Verbose "Config file found at [$standardPath]"
        return $standardPath
    }
    
    $searchRootPath = "$rootDirectoryPath\src"
    Write-Verbose "Searching for Nuget config files recursively in [$searchRootPath]"
    $configFiles = Get-ChildItem -Path $searchRootPath -Recurse -Filter "nuget.config"
    if ($configFiles.Length -ne 0)
    {
        Write-Verbose "Some nuget configuration files were found in the directory [$searchRootPath]. Selecting the first one in the list"
        return ($configFiles | Select -First 1).FullName
    }

    Write-Verbose "No Nuget config file found. Thats okay, it will just use the defaults."

    return $null
}

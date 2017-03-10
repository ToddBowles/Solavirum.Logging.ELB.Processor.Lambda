[CmdletBinding()]
param
(
    [int]$number
)

function Invoke-Npm
{
    param
    (
        [string]$root,
        [string[]]$arguments
    )
    
    $currentLocation = Get-Location;
    Set-Location $root;

    try 
    {
        & cmd /c npm $arguments "2>&1" | Write-Verbose

        $return = $LASTEXITCODE
        if ($return -ne 0)
        {
            $message = "NPM Command [$arguments] failed (non-zero exit code). Exit code [$return]."
            throw $message
        }
    }
    catch 
    {
        Set-Location $currentLocation;
    }

}

$error.Clear();

$ErrorActionPreference = "Stop";

$here = Split-Path $script:MyInvocation.MyCommand.Path;

. "$here\_Find-RootDirectory.ps1";
$rootDirectoryPath = (Find-RootDirectory $here).FullName;

$package = ConvertFrom-Json ([System.IO.File]::ReadAllText("$rootDirectoryPath\package.json"));
$version = $package.Version;
$versionRegex = "(?<breaking>[0-9]+)\.(?<patch>[0-9]+)\.(?<build>.*)"
if (-not ($version -match $versionRegex))
{
    throw "The version specified in the package.json [$version] could not be interpreted by the version regex [$versionRegex]"
}

$breaking = $matches["breaking"];
$patch = $matches["patch"];

if ($number -eq 0)
{
    $currentUtcDateTime = [System.DateTime]::UtcNow;
    $build = $currentUtcDateTime.ToString("yy") + $currentUtcDateTime.DayOfYear.ToString("000");
    $revision = ([int](([int]$currentUtcDateTime.Subtract($currentUtcDateTime.Date).TotalSeconds) / 2)).ToString();
    $prereleaseTag = "-p$build$revision";
}

$newVersion = "$breaking.$patch.$number$prereleaseTag";

$env:Path = "$rootDirectoryPath/tools/node-x64-4.3.2;$env:Path";

Invoke-Npm -Root $rootDirectoryPath -Arguments @("install");
& "$rootDirectoryPath/tools/nuget.exe" pack "$rootDirectoryPath/src/Solavirum.Logging.ELB.Processor.Lambda.nuspec" -version $newVersion -outputdirectory "$rootDirectoryPath/build-output/$newversion";
function Get-OctopusParameter
{
    [CmdletBinding()]
    param
    (
        [string]$key
    )

    if ($OctopusParameters -eq $null)
    {
        throw "No variable called OctopusParameters is available. This script should be executed as part of an Octopus deployment."
    }

    if (-not($OctopusParameters.ContainsKey($key)))
    {
        throw "The key [$key] could not be found in the set of OctopusParameters."
    }

    return $OctopusParameters[$key]
}

function Get-AwsCliExecutablePath
{
    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $commonScriptsDirectoryPath = "$rootDirectoryPath\scripts\common"

    . "$commonScriptsDirectoryPath\Functions-Compression.ps1"

    $toolsDirectoryPath = "$rootDirectoryPath\tools"
    $nugetPackagesDirectoryPath = "$toolsDirectoryPath\packages"

    $packageId = "AWSCLI-x64"
    $packageVersion = "1.11.93"

    $expectedDirectory = "$nugetPackagesDirectoryPath\$packageId.$packageVersion"
    if (-not (Test-Path $expectedDirectory))
    {
        $extractedDir = 7Zip-Unzip "$toolsDirectoryPath\$packageId.$packageVersion.7z" "$toolsDirectoryPath\packages"
    }

    $executable = "$expectedDirectory\aws.exe"

    return $executable
}

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\_Find-RootDirectory.ps1"

$rootDirectory = Find-RootDirectory $here;
$rootDirectoryPath = $rootDirectory.FullName;

$awsKey = Get-OctopusParameter "AWS.Deployment.Key";
$awsSecret = Get-OctopusParameter "AWS.Deployment.Secret";
$awsRegion = Get-OctopusParameter "AWS.Deployment.Region";

$version = Get-OctopusParameter "Octopus.Release.Number";

$functionName = Get-OctopusParameter "AWS.Lambda.Function.Name";

$aws = Get-AwsCliExecutablePath

$env:AWS_ACCESS_KEY_ID = $awsKey
$env:AWS_SECRET_ACCESS_KEY = $awsSecret
$env:AWS_DEFAULT_REGION = $awsRegion

$functionPath = "$here\function"

Write-Verbose "Compressing lambda code file"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[system.io.compression.zipfile]::CreateFromDirectory($functionPath, "index.zip")

Write-Verbose "Updating Log Processor lambda function [$functionName] to version [$version]"
(& $aws lambda update-function-configuration --function-name $functionName --runtime "dotnetcore1.0" --handler "Solavirum.Logging.ELB.Processor.Lambda::Solavirum.Logging.ELB.Processor.Lambda.Handler::Handle") | Write-Verbose
(& $aws lambda update-function-code --function-name $functionName --zip-file fileb://index.zip) | Write-Verbose
(& $aws lambda update-function-configuration --function-name $functionName --description $version) | Write-Verbose

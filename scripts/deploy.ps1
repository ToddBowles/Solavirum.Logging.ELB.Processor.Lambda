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

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\_Find-RootDirectory.ps1"


$rootDirectory = Find-RootDirectory $here
$rootDirectoryPath = $rootDirectory.FullName

$awsKey = $OctopusParameters["AWS.Deployment.Key"]
$awsSecret = $OctopusParameters["AWS.Deployment.Secret"]
$awsRegion = $OctopusParameters["AWS.Deployment.Region"]

$environment = $OctopusParameters["Octopus.Environment.Name"]
$version = $OctopusParameters["Octopus.Release.Number"]

$functionName = Get-OctopusParameter "AWS.Lambda.Function.Name";

. "$rootDirectoryPath\scripts\common\Functions-Aws.ps1"
$aws = Get-AwsCliExecutablePath

$env:AWS_ACCESS_KEY_ID = $awsKey
$env:AWS_SECRET_ACCESS_KEY = $awsSecret
$env:AWS_DEFAULT_REGION = $awsRegion

$functionPath = "$here\src\function"

Write-Verbose "Compressing lambda code file"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[system.io.compression.zipfile]::CreateFromDirectory($functionPath, "index.zip")

Write-Verbose "Publishing ELB Logs Processor version [$version] to [$functionName]"
(& $aws lambda update-function-code --function-name $functionName --zip-file fileb://index.zip) | Write-Verbose

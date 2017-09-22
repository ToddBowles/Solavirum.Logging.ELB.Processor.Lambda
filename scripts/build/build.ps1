[CmdletBinding()]
param
(
    [switch]$deploy,
    [string]$octopusServerUrl,
    [string]$octopusApiKey,
    [string]$component,
    [string]$commaSeparatedDeploymentEnvironments,
	[string[]]$projects,
    [int]$buildNumber,
    [switch]$prerelease,
    [string]$prereleaseTag
)

$error.Clear()

$ErrorActionPreference = "Stop"

$here = Split-Path $script:MyInvocation.MyCommand.Path

. "$here\_Find-RootDirectory.ps1"

$rootDirectory = Find-RootDirectory $here
$rootDirectoryPath = $rootDirectory.FullName

. "$rootDirectoryPath\scripts\common\Functions-Build.ps1";
. "$rootDirectoryPath\scripts\common\Functions-Credentials.ps1";
. "$rootDirectoryPath\scripts\common\Functions-Aws.ps1";

$credentials = @{
    "elb-processor-s3-test"=@{
        Key=(Get-CredentialByKey "ELB_LOGS_PROCESSOR_TESTS_AWS_KEY");
        Secret=(Get-CredentialByKey "ELB_LOGS_PROCESSOR_TESTS_AWS_SECRET");
    }
}

$build = {
    $arguments = @{}
    $arguments.Add("Deploy", $deploy)
    $arguments.Add("CommaSeparatedDeploymentEnvironments", $commaSeparatedDeploymentEnvironments)
    $arguments.Add("OctopusServerUrl", $octopusServerUrl)
    $arguments.Add("OctopusServerApiKey", $octopusApiKey)
    $arguments.Add("Projects", $projects)
    $arguments.Add("VersionStrategy", "SemVerWithPatchFilledAutomaticallyWithBuildNumber")
    $arguments.Add("buildNumber", $buildNumber)
    $arguments.Add("Prerelease", $prerelease)
    $arguments.Add("PrereleaseTag", $prereleaseTag)
    $arguments.Add("BuildEngineName", "dotnet-nuget");
    $arguments.Add("preDeploymentTestEngineName", "dotnet");
    $arguments.Add("postDeploymentTestEngineName", "none");

    Build-DeployableComponent @arguments
}

Run-WithProfiles -Script $build -Credentials $credentials;
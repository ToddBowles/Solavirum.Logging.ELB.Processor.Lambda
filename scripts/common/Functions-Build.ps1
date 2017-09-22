function _GetPrereleaseTag
{
    param
    (
        [switch]$prerelease,
        [string]$prereleaseTag
    )

    if ($prerelease)
    {
        if([string]::IsNullOrEmpty($prereleaseTag))
        {
            return "prerelease"
        } else {
            return $prereleaseTag
        }
    } 
    else 
    {
        return $null
    }
} 

$dotnetNugetBuildEngine = {
    [CmdletBinding()]
    param
    (
        [string]$srcDirectoryPath,
        [System.IO.DirectoryInfo]$buildDirectory,
        $versionChangeResult,
        [switch]$sign,
        [hashtable]$certificatePasswords
    )

    if ($sign)
    {
        throw "Signing is not currently supported for the dotnet Build Engine"
    }

    Write-Host "##teamcity[blockOpened name='Compiling']"

    $solutionFile = (Get-ChildItem -Path "$srcDirectoryPath" -Filter *.sln -Recurse) |
        Single -Predicate { -not ($_.FullName -match "packages" -or ($_.FullName -match "tests")) } -Description "Single .sln file in [$srcDirectoryPath]";
    $solutionFilePath = $solutionFile.FullName;

    . "$rootDirectoryPath\scripts\common\Functions-Dotnet.ps1";

    $outputDirectoryPath = "$srcDirectoryPath\publish";
    if (Test-Path $outputDirectoryPath) 
    { 
        Write-Verbose "The output directory for the dotnet publish [$outputDirectoryPath] exists. Deleting it";
        Remove-Item -Path $outputDirectoryPath -Recurse -Force; 
    }

    Write-Verbose "Restoring packages for solution [$solutionFilePath]";
    Invoke-Dotnet @("restore", $solutionFilePath);

    $config = "Release";
    Write-Verbose "Building solution [$solutionFilePath] in [$config] mode";
    Invoke-Dotnet @("build", "-c", $config, $solutionFilePath);

    $projectFile = (Get-ChildItem -Path "$srcDirectoryPath" -Filter *.csproj -Recurse) |
        Single -Predicate { -not ($_.FullName -match "packages" -or ($_.FullName -match "tests")) } -Description "Single non-test .csproj file in [$srcDirectoryPath]";
    $projectFilePath = $projectFile.FullName;

    Write-Verbose "Publishing project [$projectFilePath]";

    $publishArgs = @(
        "publish",
        "-o",
        "$outputDirectoryPath",
        "-c",
        "Release",
        $projectFilePath
    );

    Invoke-Dotnet $publishArgs;
    
    Write-Host "##teamcity[blockClosed name='Compiling']";
    Write-Host "##teamcity[progressMessage 'Compiling Successful']";
    
    Write-Host "##teamcity[blockOpened name='Packaging']";

    $nuspecFile = Get-ChildItem -Path $srcDirectoryPath -Filter *.nuspec | 
        Single -Description "Single nuspec file in [$srcDirectoryPath]";

    . "$rootDirectoryPath\scripts\common\Functions-NuGet.ps1";

    NuGet-Pack $nuspecFile.FullName $buildDirectory.FullName -Version $versionChangeResult.Informational -createSymbolsPackage:$false;

    Write-Host "##teamcity[blockClosed name='Packaging']";
    Write-Host "##teamcity[progressMessage 'Packaging Successful']";
}

$buildEngines = @{
    "dotnet-nuget"=$dotnetNugetBuildEngine;
}

$emptyPreDeploymentTestEngine = {
    [CmdletBinding()]
    param
    (
        [System.IO.DirectoryInfo]$srcDirectory,
        [System.IO.DirectoryInfo]$buildDirectory,
        [switch]$throwOnTestFailures
    )

    Write-Verbose "This is an empty Pre-Deployment Test Engine, which does not actually perform any tests at all. It is used for projects without tests that need to be executed before a build is complete"
}

$dotnetPredeploymentTestEngine = {
    [CmdletBinding()]
    param
    (
        [System.IO.DirectoryInfo]$srcDirectory,
        [System.IO.DirectoryInfo]$buildDirectory,
        [switch]$throwOnTestFailures
    )

    . "$rootDirectoryPath\scripts\common\Functions-Dotnet.ps1";

    Write-Host "##teamcity[testSuiteStarted name='dotnet test']";
    
    $testProjects = @(Get-ChildItem -Path $srcDirectory -File -Recurse -Filter "*.Test*.csproj");
    foreach ($project in $testProjects)
    {
        $testResultFilePath = "$($buildDirectory.FullName)\$($project.Name).tests.trx";
        try 
        {
            Invoke-Dotnet @("test", $project.FullName, "-c", "Release", "--no-build", "--logger", "trx;LogFileName=$testResultFilePath");
        }
        finally 
        {
            Write-Host "##teamcity[importData type='mstest' path='$testResultFilePath']";
            Write-Host "##teamcity[publishArtifacts '$testResultFilePath']";
        }
    }  

    Write-Host "##teamcity[testSuiteFinished name='dotnet test']";
}

$preDeploymentTestEngines = @{
    "none"=$emptyPreDeploymentTestEngine;
    "dotnet"=$dotnetPredeploymentTestEngine;
}

$emptyPostDeploymentTestEngine = {
    [CmdletBinding()]
    param
    (
        [System.IO.DirectoryInfo]$srcDirectory,
        [System.IO.DirectoryInfo]$buildDirectory,
        [switch]$throwOnTestFailures
    )

    Write-Verbose "This is an empty Post-Deployment Test Engine, which does not actually perform any tests at all. It is used for projects without tests that occur after deployment"
}

$postDeploymentTestEngines = @{
    "none"=$emptyPostDeploymentTestEngine;
}

function Build-DeployableComponent
{
    [CmdletBinding()]
    param
    (
        [switch]$deploy,
        [string]$environment,
        [string]$octopusProjectPrefix,
        [string]$octopusServerUrl,
        [string]$octopusServerApiKey,
        [string]$subDirectory,
        [string[]]$projects,
        [ValidateSet("dotnet-nuget")]
        [string]$buildEngineName="dotnet-nuget",
        [int]$buildNumber,
        [string]$versionStrategy="AutomaticIncrementBasedOnCurrentUtcTimestamp",
        [scriptblock]$DI_sourceDirectory={ return "$rootDirectoryPath\src" },
        [scriptblock]$DI_buildOutputDirectory={ return "$rootDirectoryPath\build-output" },
        [string]$commaSeparatedDeploymentEnvironments,
        [switch]$failOnTestFailures=$true,
        [scriptblock]$buildEngine,
        [ValidateSet("none", "dotnet")]
        [string]$preDeploymentTestEngineName="dotnet",
        [scriptblock]$preDeploymentTestEngine,
        [ValidateSet("none")]
        [string]$postDeploymentTestEngineName="none",
        [scriptblock]$postDeploymentTestEngine,
		[switch]$prerelease=$false,
        [string]$prereleaseTag="prerelease",
        [switch]$Sign=$false,
        [hashtable]$certificatePasswords=@{},
        [TimeSpan]$deploymentMaximumWaitTime=[System.TimeSpan]::FromMinutes(10)
    )

    try
    {
        $error.Clear()
        $ErrorActionPreference = "Stop"

        Write-Host "##teamcity[blockOpened name='Setup']"

        $here = Split-Path $script:MyInvocation.MyCommand.Path

        . "$here\_Find-RootDirectory.ps1"

        $rootDirectory = Find-RootDirectory $here
        $rootDirectoryPath = $rootDirectory.FullName

        . "$rootDirectoryPath\scripts\common\Functions-Strings.ps1"
        . "$rootDirectoryPath\scripts\common\Functions-Versioning.ps1"
        . "$rootDirectoryPath\scripts\common\Functions-Enumerables.ps1"

        if ($buildEngine -eq $null)
        {
            $buildEngine = $buildEngines[$buildEngineName]
        }

        if ($deploy)
        {
            $octopusServerUrl | ShouldNotBeNullOrEmpty -Identifier "OctopusServerUrl"
            $octopusServerApiKey | ShouldNotBeNullOrEmpty -Identifier "OctopusServerApiKey"

            if ($projects -eq $null -or (-not ($projects | Any)))
            {
                if ([string]::IsNullOrEmpty($octopusProjectPrefix))
                {
                    throw "One of OctopusProjectPrefix or Projects must be set to determine which Octopus Projects to deploy to."
                }
            }

            if ((($projects -ne $null) -and ($projects | Any)) -and -not [string]::IsNullOrEmpty($octopusProjectPrefix))
            {
                Write-Warning "Both a specific list of projects and a project prefix were specified. The list will take priority for deployment purposes."
            }

            if (-not([string]::IsNullOrEmpty($environment)) -and -not([string]::IsNullOrEmpty($commaSeparatedDeploymentEnvironments)))
            {
                throw "You have specified both the singular deployment environment (obsolete) [Parameter: '-Environment', Value: [$environment]] as well as the plural deployment environments [Parameter: '-CommaSeparatedDeploymentEnvironments', Value: [$commaSeparatedDeploymentEnvironments]]. Only one may be specified."
            }

            if (-not([string]::IsNullOrEmpty($environment)))
            {
                Write-Warning "You have specified the deployment environment via [Parameter: '-Environment']. This is the obsolete way of specifying deployment targets. Use [Parameter: '-CommaSeparatedDeploymentEnvironments'] instead."
                $environments = @($environment)
            }
            else
            {
                $environments = $commaSeparatedDeploymentEnvironments.Split(@(',', ' '), [StringSplitOptions]::RemoveEmptyEntries)
            }

            if ($environments.Length -gt 2)
            {
                throw "Too many environments to deploy to were specified. This script currently only supports a maximum of 2 environments, typically CI and Staging."
            }
        }

        $srcDirectoryPath = & $DI_sourceDirectory
        if (![string]::IsNullOrEmpty($subDirectory))
        {
            $srcDirectoryPath = "$srcDirectoryPath\$subDirectory"
        }

        Write-Host "##teamcity[blockOpened name='Versioning']"

		if ($buildNumber -eq 0 -and $versionStrategy -eq "SemVerWithPatchFilledAutomaticallyWithBuildNumber")
		{
			Write-Warning "The version strategy [$versionStrategy] was specified, but no build number was supplied. This build will be marked as a prerelease build."
			$prerelease = $true
			$currentUtcDateTime = (Get-Date).ToUniversalTime();
			$build = $currentUtcDateTime.ToString("yy") + $currentUtcDateTime.DayOfYear.ToString("000");
			$revision = ([int](([int]$currentUtcDateTime.Subtract($currentUtcDateTime.Date).TotalSeconds) / 2)).ToString();
			$prereleaseTag = "$build$revision";
		}
		
        $sharedAssemblyInfo = _FindSharedAssemblyInfoForVersioning -srcDirectoryPath $srcDirectoryPath
        $versionChangeResult = Update-AutomaticallyIncrementAssemblyVersion -AssemblyInfoFile $sharedAssemblyInfo -VersionStrategy $versionStrategy -BuildNumber $buildNumber -infoVersion (_GetPrereleaseTag -Prerelease:$prerelease -PrereleaseTag $prereleaseTag)

        Write-Host "##teamcity[blockClosed name='Versioning']"

        write-host "##teamcity[buildNumber '$($versionChangeResult.Informational)']"

        . "$rootDirectoryPath\scripts\common\Functions-FileSystem.ps1"
        $buildOutputRoot = & $DI_buildOutputDirectory
        if (![string]::IsNullOrEmpty($subDirectory))
        {
            $buildOutputRoot = "$buildOutputRoot\$subDirectory"
        }
        $buildDirectory = Ensure-DirectoryExists ([System.IO.Path]::Combine($rootDirectory.FullName, "$buildOutputRoot\$($versionChangeResult.Informational)"))

        Write-Host "##teamcity[blockClosed name='Setup']"

        & $buildEngine -SrcDirectoryPath $srcDirectoryPath -BuildDirectory $buildDirectory -VersionChangeResult $versionChangeResult -Sign:$sign -CertificatePasswords $certificatePasswords
        
        if ($preDeploymentTestEngine -eq $null)
        {
            $preDeploymentTestEngine = $preDeploymentTestEngines[$preDeploymentTestEngineName]
        }
        
        & $preDeploymentTestEngine -SrcDirectory $srcDirectoryPath -BuildDirectory $buildDirectory -ThrowOnTestFailures:$failOnTestFailures

        write-host "##teamcity[publishArtifacts '$($buildDirectory.FullName)/*.nupkg']"

        if ($deploy)
        {
            Write-Host "##teamcity[blockOpened name='Creating Octopus Releases']"
            Write-Host "##teamcity[progressMessage 'Creating Octopus Releases']"

            $packages = Get-ChildItem -Path ($buildDirectory.FullName) | 
                Where-Object { $_.FullName -like "*.nupkg" }
            $feedUrl = "$octopusServerUrl/nuget/packages"

            . "$rootDirectoryPath\scripts\common\Functions-NuGet.ps1"

            foreach ($package in $packages)
            {
                NuGet-Publish -Package $package -ApiKey $octopusServerApiKey -FeedUrl $feedUrl
            }   

            . "$rootDirectoryPath\scripts\common\Functions-OctopusDeploy.ps1"
            
            if ($projects -eq $null)
            {
                Write-Verbose "No projects to deploy to have been specified. Deploying to all projects starting with [$octopusProjectPrefix]."
                $octopusProjects = Get-AllOctopusProjects -octopusServerUrl $octopusServerUrl -octopusApiKey $octopusServerApiKey | 
                    Where-Object { $_.Name -like "$octopusProjectPrefix*" }

                if (-not ($octopusProjects | Any -Predicate { $true }))
                {
                    throw "You have elected to do a deployment, but no Octopus Projects could be found to deploy to (using prefix [$octopusProjectPrefix]."
                }
                
                $projects = ($octopusProjects | Select-Object -ExpandProperty Name)
            }

            foreach ($project in $projects)
            {
                New-OctopusRelease -ProjectName $project -OctopusServerUrl $octopusServerUrl -OctopusApiKey $octopusServerApiKey -Version $versionChangeResult.Informational -ReleaseNotes "[SCRIPT] Automatic Release created as part of Build."
            }

            Write-Host "##teamcity[progressMessage 'Octopus Releases Created']"
            Write-Host "##teamcity[blockClosed name='Created Octopus Releases']"
            
            if ($environments | Any)
            {
                $deployedEnvironments = @()
                $initialDeploymentEnvironment = $environments[0]
                Write-Host "##teamcity[blockOpened name='Deployment ($initialDeploymentEnvironment)']"
                Write-Host "##teamcity[progressMessage 'Deploying to ($initialDeploymentEnvironment)']"

                foreach ($project in $projects)
                {
                    New-OctopusDeployment -ProjectName $project -Environment "$initialDeploymentEnvironment" -Version $versionChangeResult.Informational -OctopusServerUrl $octopusServerUrl -OctopusApiKey $octopusServerApiKey -Wait -WaitTimeout $deploymentMaximumWaitTime
                }

                $deployedEnvironments += $initialDeploymentEnvironment

                Write-Host "##teamcity[progressMessage '($initialDeploymentEnvironment) Deploy Successful']"
                Write-Host "##teamcity[blockClosed name='Deployment ($initialDeploymentEnvironment)']"

                if ($prerelease)
                {
                    Write-Warning "The execution of the post-deployment tests (previously called functional tests) has been disabled because this is a prerelease deployment. This means that subsequent deployments (i.e. environments after the first one in the list) will also not occur"
                }
                else
                {
                    if ($postDeploymentTestEngine -eq $null)
                    {
                        $postDeploymentTestEngine = $postDeploymentTestEngines[$postDeploymentTestEngineName]
                    }
                    
                    & $postDeploymentTestEngine -SrcDirectory $srcDirectoryPath -BuildDirectory $buildDirectory -ThrowOnTestFailures:$failOnTestFailures

                    if ($environments.Length -eq 2)
                    {
                        $secondaryDeploymentEnvironment = $environments[1]
                
                        Write-Host "##teamcity[blockOpened name='Deployment ($secondaryDeploymentEnvironment)']"
                        Write-Host "##teamcity[progressMessage 'Deploying to ($secondaryDeploymentEnvironment)']"
                
                        foreach ($project in $projects)
                        {
                            New-OctopusDeployment -ProjectName $project -Environment "$secondaryDeploymentEnvironment" -Version $versionChangeResult.Informational -OctopusServerUrl $octopusServerUrl -OctopusApiKey $octopusServerApiKey -Wait -WaitTimeout $deploymentMaximumWaitTime
                        }

                        $deployedEnvironments += $secondaryDeploymentEnvironment
                        Write-Host "##teamcity[progressMessage '($secondaryDeploymentEnvironment) Deploy Successful']"
                        Write-Host "##teamcity[blockClosed name='Deployment ($secondaryDeploymentEnvironment)']"
                    }
                }
            }
        }

        $result = @{}
        $result.Add("VersionInformation", $versionChangeResult)
        $result.Add("BuildOutput", $buildDirectory.FullName)

        return $result
    }
    finally
    {
        if (($deployedEnvironments -ne $null) -and ($deployedEnvironments | Any))
        {
            $commaDelimitedDeployedEnvironments = [string]::Join(", ", $deployedEnvironments)
            Write-Host "##teamcity[buildStatus text='{build.status.text}; Deployed ($commaDelimitedDeployedEnvironments)']"
        }

        Write-Host "##teamcity[blockOpened name='Cleanup']"

        if ($versionChangeResult -ne $null)
        {
            Write-Verbose "Restoring version to old version to avoid making permanent changes to the SharedAssemblyInfo file."
            $version = Set-AssemblyVersion $sharedAssemblyInfo $versionChangeResult.Old
        }

        Write-Host "##teamcity[blockClosed name='Cleanup']"
    }
}

function _FindSharedAssemblyInfoForVersioning
{
    
    [CmdletBinding()]
    param
    (
        [string]$srcDirectoryPath
    )

    function doesntContain($file, $x)
    {
        $escapedDir = [Regex]::Escape($srcDirectoryPath)        
        $withoutDir = $file.FullName -Replace $escapedDir, ""
        return -not $withoutDir.Contains($x)
    }

    try
    {
        $allFiles = Get-ChildItem -Path $srcDirectoryPath -Filter SharedAssemblyInfo.cs -Recurse
        $filtered = $allFiles | Where-Object { (doesntContain $_ "packages\") -and (doesntContain $_ "test-working\") }
        $sharedAssemblyInfo = $filtered | Single 
    }
    catch
    {
        throw new-object Exception("A SharedAssemblyInfo file (used for versioning) could not be found when searching from [$srcDirectoryPath]", $_.Exception)
    }

    return $sharedAssemblyInfo
}
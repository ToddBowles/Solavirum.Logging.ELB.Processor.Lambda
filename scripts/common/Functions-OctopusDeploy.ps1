function Get-OctopusToolsExecutable
{
    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    . "$rootDirectoryPath\scripts\common\Functions-Nuget.ps1"

    $package = "OctopusTools"
    $version = "3.5.4"
    $expectedDirectory = Nuget-EnsurePackageAvailable -Package $package -Version $version

    $executable = new-object System.IO.FileInfo("$expectedDirectory\tools\octo.exe")

    return $executable
}

function Ensure-OctopusClientClassesAvailable
{
    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $commonScriptsDirectoryPath = "$rootDirectoryPath\scripts\common"
    . "$commonScriptsDirectoryPath\Functions-Enumerables.ps1"
        . "$commonScriptsDirectoryPath\Functions-Nuget.ps1"

    $toolsDirectoryPath = "$rootDirectoryPath\tools"

    $nugetPackagesDirectoryPath = "$toolsDirectoryPath\packages"

    $octoPackageId = "Octopus.Client"
    $octoVersion = "3.5.4"
    $expectedOctoDirectoryPath = "$nugetPackagesDirectoryPath\$octoPackageId.$octoVersion"
    $expectedOctoDirectory = Nuget-EnsurePackageAvailable -Package $octoPackageId -Version $octoVersion

    $newtonsoftJsonDirectory = Get-ChildItem -Path $nugetPackagesDirectoryPath -Directory | 
        Where-Object { $_.FullName -match "Newtonsoft\.Json\.(.*)" } | 
        Sort-Object { $_.FullName } -Descending |
        First

    Write-Verbose "Loading Octopus .NET Client Libraries."
    $jsonDotNetPath = "$($newtonsoftJsonDirectory.FullName)\lib\net45\Newtonsoft.Json.dll"
    $octopusPath = "$expectedOctoDirectoryPath\lib\net45\Octopus.Client.dll"
    _LoadDll $jsonDotNetPath
    _LoadDll $octopusPath
    
}

function _LoadDll
{
    param
    (
        [string]$path
    )

    if (-not (Test-Path $path))
    {
        throw "Cannot load DLL from path [$path] because it doesnt exist"
    }

    Add-Type -Path $path | Write-Verbose
}

function _ExecuteOctopusWithArguments
{
    param
    (
        [string]$command,
        [array]$arguments
    )

    $executable = Get-OctopusToolsExecutable
    $executablePath = $executable.FullName

    (& "$executablePath" $arguments) | Write-Verbose
    $octoReturn = $LASTEXITCODE
    if ($octoReturn -ne 0)
    {
        $message = "Octopus Command [$command] failed (non-zero exit code). Exit code [$octoReturn]."
        throw $message
    }
}

function New-OctopusRelease
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$projectName,
        [string]$releaseNotes,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$version,
        [Parameter(Mandatory=$false)]
        [hashtable]$stepPackageVersions
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    $command = "create-release"
    $arguments = @()
    $arguments += $command
    $arguments += "--project"
    $arguments += $projectName
    $arguments += "--server"
    $arguments += $octopusServerUrl
    $arguments += "--apiKey" 
    $arguments += $octopusApiKey
    if (![String]::IsNullOrEmpty($releaseNotes))
    {
        $arguments += "--releasenotes"
        $arguments += "`"$releaseNotes`""
    }
    if (![String]::IsNullOrEmpty($version))
    {
        $arguments += "--version"
        $arguments += $version
        $arguments += "--packageversion"
        $arguments += $version
    }

    if ($stepPackageVersions -ne $null) {
        foreach ($stepname in $stepPackageVersions.Keys) {
            $stepPackageVersion = $stepPackageVersions[$stepname]
            $arguments += "--package=${stepname}:$stepPackageVersion"
        }
    }

    _ExecuteOctopusWithArguments $command $arguments
}

function New-OctopusDeployment
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$projectName,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environment,
        [string]$version,
        [switch]$wait,
        [System.TimeSpan]$waitTimeout=[System.TimeSpan]::FromMinutes(10),
        [hashtable]$variables,
        [Parameter(Mandatory=$false)]
        [ValidateSet("current", "octopus")]
        [string]$targetMachine
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    
    if ([String]::IsNullOrEmpty($version)) {
        Write-Verbose "No version for deployment specified. Getting last version of project [$projectName] deployed to environment [$environment]."
        $version = Get-LastReleaseToEnvironment -projectName $projectName -environmentName $environment -octopusServerUrl $octopusServerUrl -octopusApiKey $octopusApiKey
    }

    $command = "deploy-release"
    $arguments = @()
    $arguments += $command
    $arguments += "--project"
    $arguments += $projectName
    $arguments += "--server"
    $arguments += $octopusServerUrl
    $arguments += "--apiKey"
    $arguments += $octopusApiKey
    $arguments += "--version"
    $arguments += $version
    $arguments += "--deployTo"
    $arguments += "`"$environment`""

    if ($targetMachine -eq "current")
    {
        $machineName = $env:COMPUTERNAME
        try
        {
            # This code gets the AWS instance name, because machines are registered with their AWS instance name now, instead of
            # just machine name (for tracking purposes inside Octopus) and it was hard to actually rename the machine.
            $response = Invoke-WebRequest -Uri "http://169.254.169.254/latest/meta-data/instance-id" -UseBasicParsing
            if ($response.StatusCode -eq 200) { $machineName = $response.Content }
        }
        catch { }
    }
    else 
    {
        $machineName = $targetMachine
    }
    
    if (![string]::IsNullOrEmpty($machineName)) {
        $arguments += "--specificmachines"
        $arguments += $machineName
    }

    if ($wait)
    {
        $arguments += "--waitfordeployment"
        $arguments += "--deploymenttimeout=$waitTimeout"
    }

    if ($variables -ne $null)
    {
        $variables.Keys | ForEach-Object { $arguments += "--variable"; $arguments += "$($_):$($variables.Item($_))" }
    }

    try
    {
        _ExecuteOctopusWithArguments $command $arguments
    }
    catch
    {
        Write-Warning "Deployment of version [$version] of project [$projectName] to environment [$environment] failed."
        Write-Warning $_
        
        throw new-object Exception("Deploy [$environment] Failed", $_.Exception)
    }
}

function Get-OctopusProjectByName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$projectName
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    write-verbose "Retrieving Octopus Projects."
    $result = $repository.Projects.FindByName($projectName)

    return $result
}

function Get-AllOctopusProjects
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    write-verbose "Retrieving Octopus Projects."
    $result = $repository.Projects.FindAll()

    return $result
}

function Get-LastReleaseToEnvironment
{
	[CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$projectName,
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentName,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [switch]$newAlgorithm=$true
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $commonScriptsDirectoryPath = "$rootDirectoryPath\scripts\common"
    . "$commonScriptsDirectoryPath\Functions-Enumerables.ps1"

    Ensure-OctopusClientClassesAvailable $octopusServerUrl $octopusApiKey
    
    Write-Verbose "Locating the most recent successful deployment of project [$projectName] to environment [$environmentName]"

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl, $octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    $env = $repository.Environments.FindByName($environmentName)
    $project = $repository.Projects.FindByName($projectName)

    if ($newAlgorithm)
    {
        Write-Verbose "Using Octopus API directly to determine last successful deployment"

        $projectId = $project.Id;
        $environmentId = $env.Id;

        $headers = @{"X-Octopus-ApiKey" = $octopusApiKey}
        $uri = "$octopusServerUrl/api/deployments?environments=$environmentId&projects=$projectId"
        while ($true) {
            Write-Verbose "Getting the next set of deployments from Octopus using the URI [$uri]"
            $deployments = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -Verbose:$false
            if (-not ($deployments.Items | Any))
            {
                $version = "latest";
                Write-Verbose "No deployments could not found for project [$projectName ($projectId)] in environment [$environmentName ($environmentId)]. Returning the value [$version], which will indicate that the most recent release is to be used"
                return $version
            }

            Write-Verbose "Finding the first successful deployment in the set of deployments returned. There were [$($deployments.TotalResults)] total deployments, and we're currently searching through a set of [$($deployments.Items.Length)]"
            $successful = $deployments.Items | First -Predicate { 
                $uri = "$octopusServerUrl$($_.Links.Task)"; 
                Write-Verbose "Getting the task the deployment [$($_.Id)] was linked to using URI [$uri] to determine whether or not the deployment was successful"
                $task = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -Verbose:$false; 
                $task.FinishedSuccessfully; 
            } -Default "NONE"
            
            if ($successful -ne "NONE")
            {
                Write-Verbose "Finding the release associated with the successful deployment [$($successful.Id)]"
                $release = Invoke-RestMethod "$octopusServerUrl$($successful.Links.Release)" -Headers $headers -Method Get -Verbose:$false
                $version = $release.Version
                Write-Verbose "A successful deployment of project [$projectName ($projectId)] was found in environment [$environmentName ($environmentId)]. Returning the version of the release attached to that deployment, which was [$version]"
                return $version
            }

            Write-Verbose "Finished searching through the current page of deployments for project [$projectName ($projectId)] in environment [$environmentName ($environmentId)] without finding a successful one. Trying the next page"
            $next = $deployments.Links."Page.Next"
            if ($next -eq $null)
            {
                Write-Verbose "There are no more deployments available for project [$projectName ($projectId)] in environment [$environmentName ($environmentId)]. We're just going to return the string [latest] and hope for the best"
                return "latest"
            }
            else
            {
                $uri = "$octopusServerUrl$next"
            }
        }
    }
    else
    {
        Write-Verbose "Using Octopus Client library classes to determine last successful deployment"

        $deployments = $repository.Deployments.FindMany({ param($x) $x.EnvironmentId -eq $env.Id -and $x.ProjectId -eq $project.Id })

        if ($deployments | Any)
        {
            Write-Verbose "Deployments of project [$projectName] to environment [$environmentName] were found. Selecting the most recent successful deployment."
            $latestDeployment = $deployments |
                Sort -Descending -Property Created |
                First -Predicate { $repository.Tasks.Get($_.TaskId).FinishedSuccessfully -eq $true } -Default "latest"

            $release = $repository.Releases.Get($latestDeployment.ReleaseId)
        }
        else
        {
            Write-Verbose "No deployments of project [$projectName] to environment [$environmentName] were found."
        }

        $version = if ($release -eq $null) { "latest" } else { $release.Version }

        Write-Verbose "The version of the recent successful deployment of project [$projectName] to environment [$environmentName] was [$version]. 'latest' indicates no successful deployments, and will mean the very latest release version is used."

        return $version
    }
}

function New-OctopusEnvironment
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentName,
        [string]$environmentDescription="[SCRIPT] Environment automatically created by Powershell script."
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    $properties = @{Name="$environmentName";Description=$environmentDescription}
 
    $environment = New-Object Octopus.Client.Model.EnvironmentResource -Property $properties

    write-verbose "Creating Octopus Environment with Name [$environmentName]."
    $result = $repository.Environments.Create($environment)

    return $result
}

function Get-OctopusEnvironmentByName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentName
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    write-verbose "Retrieving Octopus Environment with Name [$environmentName]."
    $result = $repository.Environments.FindByName($environmentName)

    return $result
}

function Delete-OctopusEnvironment
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentId
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    write-verbose "Deleting Octopus Environment with Id [$environmentId]."
    $result = $repository.Environments.Delete($repository.Environments.Get($environmentId))

    return $result
}

function Get-OctopusMachinesByRole
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$role
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    $machines = $repository.Machines.FindAll() | Where-Object { $_.Roles -contains $role }

    return $machines
}

function Get-OctopusMachinesByEnvironment
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentId
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    $machines = $repository.Machines.FindAll() | Where-Object { $_.EnvironmentIds -contains $environmentId }

    return $machines
}


function Add-OctopusEnvironmentToMachine
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentName,
        [ValidateNotNullOrEmpty()]
        [string]$machineName
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint
    $octopusEnvironment = $repository.Environments.FindByName($environmentName)
    if ($octopusEnvironment -eq $null) { throw "could not find octopus environment with name [$environmentName]" }

    $octopusMachine = $repository.Machines.FindByName($machineName)
    if ($octopusMachine -eq $null) { throw "could not find octopus machine with name [$machineName]" }

    if ($octopusMachine.EnvironmentIds | where-object { $octopusEnvironment.Id -contains $_ })
    {
        write-verbose "machine [$machineName] already contains environmentId [$($octopusEnvironment.Id)]"
        return $false
    }

    write-verbose "Adding environment [$environmentName] with Id [$($octopusEnvironment.Id)] to machine [$machineName]"
    $octopusMachine.EnvironmentIds.Add($octopusEnvironment.Id)
    $result = $repository.Machines.Modify($octopusMachine)

    return $result
}

function Remove-OctopusEnvironmentFromMachine
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$environmentName,
        [ValidateNotNullOrEmpty()]
        [string]$machineName
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    $octopusMachine = $repository.Machines.FindByName($machineName)
    if ($octopusMachine -eq $null) { throw "could not find octopus machine with name [$machineName]" }

    $octopusEnvironment = $repository.Environments.FindByName($environmentName)
    if ($octopusEnvironment -eq $null) 
    {
        Write-Verbose "could not find octopus environment with name [$environmentName]"
        return $false
    }

    #check if machine contains environment to remove
    if ($octopusMachine.EnvironmentIds -NotContains $octopusEnvironment.Id)
    {
      write-verbose "machine [$machineName] does not contain environmentId [$($octopusEnvironment.Id)]"
      return $false   #should i throw instead?
    }

    write-verbose "removing environment [$($octopusEnvironment.Id)] from machine [$($octopusMachine.Name)]"
    $updatedMachine = $octopusMachine.EnvironmentIds.Remove($octopusEnvironment.Id)
    $result = $repository.Machines.Modify($octopusMachine)

    return $result
}

function Delete-OctopusMachine
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$octopusApiKey,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$machineId
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }

    Ensure-OctopusClientClassesAvailable

    $endpoint = new-object Octopus.Client.OctopusServerEndpoint $octopusServerUrl,$octopusApiKey
    $repository = new-object Octopus.Client.OctopusRepository $endpoint

    write-verbose "Deleting Octopus Machine with Id [$machineId]."
    $result = $repository.Machines.Delete($repository.Machines.Get($machineId))

    return $result
}

function Ensure-AwsPowershellFunctionsAvailable
{
    [CmdletBinding()]
    param
    (
        [string]$DI_packagesDirectoryPath
    )

    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $commonScriptsDirectoryPath = "$rootDirectoryPath\scripts\common"

    . "$commonScriptsDirectoryPath\Functions-Waiting.ps1"
    . "$commonScriptsDirectoryPath\Functions-Compression.ps1"

    $toolsDirectoryPath = "$rootDirectoryPath\tools"

    if ([String]::IsNullOrEmpty($DI_packagesDirectoryPath))
    {
        $nugetPackagesDirectoryPath = "$toolsDirectoryPath\packages"
    }
    else
    {
        $nugetPackagesDirectoryPath = $DI_packagesDirectoryPath
    }

    $packageId = "AWSPowershell"
    $packageVersion = "3.3.84.0"

    $checkExtractAndLoad = {
        $mutex = new-object System.Threading.Mutex($false, "Global\AWSPowershell-Bootstrap");
        if ($mutex.WaitOne(10000))
        {
            try 
            {
                $expectedDirectory = "$nugetPackagesDirectoryPath\$packageId.$packageVersion";

                function Import-AWSPowershellModule
                {
                    Write-Verbose "Loading [$packageId.$packageVersion] Module"
                    $modulePath = "$expectedDirectory\AWSPowerShell.psd1"
                    if (Test-Path $modulePath)
                    {
                        $previousVerbosePreference = $VerbosePreference
                        $VerbosePreference = "SilentlyContinue"
                        $imported = Import-Module $modulePath -Force
                        $VerbosePreference = $previousVerbosePreference
                    }
                }

                if ((Get-Module | Where-Object { $_.Name -eq $packageId -and $_.Version -eq $packageVersion }) -ne $null)
                {
                    Write-Debug "The module [$packageId] version [$packageVersion] is already present in the list of modules currently available. No loading will be performed.";
                    return;
                }

                if ((Get-Module | Where-Object { $_.Name -eq $packageId } ) -ne $null)
                {
                    Write-Warning "The module [$packageId] is already present, but is a different version to the one requested. The module will be unloaded/removed, in order to load the new one";
                    Remove-Module $packageId;
                }
                
                
                if (Test-Path $expectedDirectory)
                {
                    try 
                    {
                        Import-AWSPowershellModule;
                        return $true;
                    }
                    catch 
                    {
                        Write-Warning "There was something wrong with the AWSPowershell module at [$expectedDirectory], which existed already but the module was not already loaded. Going to delete it and try to extract again"
                        Remove-Item -Path $expectedDirectory -Recurse -Force;
                        $isMissing = $true;
                    }
                }
                else 
                {
                    $isMissing = $true;
                }

                if ($isMissing)
                {
                    Write-Verbose "The expected location for the [$packageId] module [$expectedDirectory] did not exist. Attempted to extract it from the distributed archive";
                    $directory = 7Zip-Unzip "$toolsDirectoryPath\dist\$packageId.$packageVersion.7z" "$nugetPackagesDirectoryPath";
                }

                Import-AWSPowershellModule;
            }
            finally 
            {
                $mutex.ReleaseMutex();
                $mutex.Dispose();
            }
        }
        else 
        {
            return $false;
        }

        return $true
    }

    $result = Retry -Script $checkExtractAndLoad -ScriptDescription "Checking for AWSPowershell Package, Extracting If Not Exists" -MaxAttempts 3
}

function Setup-AWSProfile
{
    [CmdletBinding()]
    param
    (
        [string]$profileName,
        [string]$awsKey,
        [string]$awsSecret
    )

    if ($rootDirectory -eq $null) { throw "RootDirectory script scoped variable not set. That's bad, its used to find dependencies." };
    $rootDirectoryPath = $rootDirectory.FullName;

    . "$rootDirectoryPath\scripts\common\Functions-Aws.ps1";
    Ensure-AwsPowershellFunctionsAvailable;

    Write-Verbose "Checking to see if a profile with name [$profileName] already exists";

    $existingProfile = Get-AWSCredentials -ProfileName $profileName;
    $profileExists = $existingProfile -ne $null;

    if($profileExists)
    {
        Write-Warning "AWS profile [$profileName] already exists. It will not be changed";
    } 
    else 
    {
        Set-AWSCredentials -AccessKey $awskey -SecretKey $awsSecret -StoreAs $profileName;
        Write-Verbose "Could not find an existing profile with name [$profileName]. This profile has been registered with the specified credentials";
    }

    return $profileExists
}

function Remove-AWSProfile
{
    [CmdletBinding()]
    param
    (
        [string]$profileName
    )

    if ($rootDirectory -eq $null) { throw "RootDirectory script scoped variable not set. That's bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    . "$rootDirectoryPath\scripts\common\Functions-Aws.ps1"
    Ensure-AwsPowershellFunctionsAvailable

    Remove-AWSCredentialProfile -ProfileName $profileName -Force;
}

function Run-WithProfiles
{
    [CmdletBinding()]
    param
    (
        [scriptblock]$script,
        [hashtable]$credentials
    )

    if ($rootDirectory -eq $null) { throw "RootDirectory script scoped variable not set. That's bad, its used to find dependencies." };
    $rootDirectoryPath = $rootDirectory.FullName;

    . "$rootDirectoryPath\scripts\common\Functions-Aws.ps1";
    Ensure-AwsPowershellFunctionsAvailable;

    $credsExisted = @{};
    foreach ($key in $credentials.Keys)
    {
        $creds = $credentials[$key];
        $existed = Setup-AWSProfile -profileName $key -awsKey $creds.Key -awsSecret $creds.Secret;
        $credsExisted.Add($key, $existed);
    }

    try 
    {
        & $script;
    }
    finally 
    {
        foreach ($key in $credsExisted.Keys)
        {
            if (-not $credsExisted[$key])
            {
                Write-Verbose "The AWS Profile with name [$key] did not exist before this execution. Cleaning it up";
                Remove-AWSProfile $key;
            }
        }
    }
}
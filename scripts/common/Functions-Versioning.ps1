function Get-AssemblyVersionRegexString
{
    return "^(\[assembly: AssemblyVersion\()(`")(.*)(`"\)\])$"
}

function Get-AssemblyFileVersionRegexString
{
    return "^(\[assembly: AssemblyFileVersion\()(`")(.*)(`"\)\])$"
}

function Get-AssemblyInformationalVersionRegexString
{
    return "^(\[assembly: AssemblyInformationalVersion\()(`")(.*)(`"\)\])$"
}

function TrimTo([string]$inputString, [int]$maxLength){
    if($maxLength -lt 0){
        $maxLength = 0
    }

    $lengthOfInput = $inputString.Length
    $trimLength = $lengthOfInput
    if($lengthOfInput -gt $maxLength){
        $trimLength = $maxLength
    }
    return $inputString.Substring(0,$trimLength)
}

function SanitizeVersionStringForNuget([string]$inputString)
{
    $sanitized = $inputString -replace '[^a-zA-Z0-9-]', ''
    if ($sanitized -notmatch '^[a-zA-Z]')
    {
        $sanitized = "p" + $sanitized
    }

    return $sanitized
}

function Update-AutomaticallyIncrementAssemblyVersion
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [System.IO.FileInfo]$assemblyInfoFile,
        [int]$buildNumber=9999,
        [string]$versionStrategy="AutomaticIncrementBasedOnCurrentUtcTimestamp",
		[string]$infoVersion=""
    )

    $existingVersion = Get-AssemblyVersion -AssemblyInfoFile $assemblyInfoFile

    $splitVersion = $existingVersion.Split(@("."))
 
    write-verbose ("Current version is [" + $existingVersion + "].")
 
    if ($versionStrategy -eq "AutomaticIncrementBasedOnCurrentUtcTimestamp")
    {
        $newVersion = _GetVersion_AutomaticIncrementBasedOnCurrentUtcTimestamp $splitVersion[0] $splitVersion[1]
    }
    elseif ($versionStrategy -eq "DerivedFromYearMonthAndBuildNumber")
    {
        $newVersion = _GetVersion_DerivedFromYearMonthAndBuildNumber $splitVersion[0] $buildNumber
    }
    elseif ($versionStrategy -eq "SemVerWithPatchFilledAutomaticallyWithBuildNumber")
    {
        $newVersion = _GetVersion_SemVerWithPatchFilledAutomaticallyWithBuildNumber $splitVersion[0] $splitVersion[1] $buildNumber
    }
    else
    {
        throw "The version number generation strategy [$versionStrategy] is unknown."
    }

    $nugetVersion = $newVersion
    if (-not([string]::IsNullOrEmpty($infoVersion)))
    {
        if ($versionStrategy -ne "SemVerWithPatchFilledAutomaticallyWithBuildNumber")
        {
            throw "Prerelease versions can only be generated when the version strategy is set to [SemVerWithPatchFilledAutomaticallyWithBuildNumber] as nuget pack does not support SemVer 2.0.0. Change the build configuration (commonly found in file [build.ps1]) to specify '-VersionStrategy SemVerWithPatchFilledAutomaticallyWithBuildNumber' and ensure the supplied shared assembly value is incremented so that the generated version number is semantically greater than all previous builds."
        }

        $splitNewVersion = $newVersion.Split(@("."))

        $sanitizedInfoVersion = SanitizeVersionStringForNuget $infoVersion

        $trimmedInfoVersion = TrimTo $sanitizedInfoVersion 20
        $nugetVersion = [System.String]::Format("{0}.{1}.{2}-{3}", $splitNewVersion[0], $splitNewVersion[1], $splitNewVersion[2], $trimmedInfoVersion)
    }

    $newVersion = Set-AssemblyVersion $assemblyInfoFile $newVersion $nugetVersion

    $result = new-object psobject @{ "Old"=$existingVersion; "New"=$newVersion; "Informational"=$nugetVersion }
    return $result
}

function _GetVersion_AutomaticIncrementBasedOnCurrentUtcTimestamp
{
    param
    (
        [int]$major,
        [int]$minor,
        [scriptblock]$DI_getSystemUtcDateTime={ return [System.DateTime]::UtcNow }
    )

    $currentUtcDateTime = & $DI_getSystemUtcDateTime

    $major = $major
    $minor = $minor
    $build = $currentUtcDateTime.ToString("yy") + $currentUtcDateTime.DayOfYear.ToString("000")
    $revision = ([int](([int]$currentUtcDateTime.Subtract($currentUtcDateTime.Date).TotalSeconds) / 2)).ToString()
 
    $newVersion = [System.String]::Format("{0}.{1}.{2}.{3}", $major, $minor, $build, $revision)

    return $newVersion
}

function _GetVersion_DerivedFromYearMonthAndBuildNumber
{
    param
    (
        [int]$major,
        [int]$buildNumber,
        [scriptblock]$DI_getSystemUtcDateTime={ return [System.DateTime]::UtcNow }
    )

    $currentUtcDateTime = & $DI_getSystemUtcDateTime

    $major = $major
    $minor = $currentUtcDateTime.ToString("yy").PadLeft(2, "0")
    $build = $currentUtcDateTime.Month.ToString("000")
    $revision = $buildNumber.ToString("0000")
 
    $newVersion = [System.String]::Format("{0}.{1}.{2}.{3}", $major, $minor, $build, $revision)

    return $newVersion
}

function _GetVersion_SemVerWithPatchFilledAutomaticallyWithBuildNumber{
    param
    (
        [int]$major,
        [int]$minor,
        [int]$buildNumber
    )

    $newVersion = [System.String]::Format("{0}.{1}.{2}", $major, $minor, $buildNumber)

    return $newVersion
}

function Set-AssemblyVersion
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [System.IO.FileInfo]$assemblyInfoFile,
        [Parameter(Position=1, Mandatory=$true)]
        [string]$newVersion,
		[Parameter(Position=2, Mandatory=$false)]
		[string]$infoVersion
    )

    $fullyQualifiedAssemblyInfoPath = $assemblyInfoFile.FullName
    $assemblyVersionRegex = Get-AssemblyVersionRegexString
    $assemblyFileVersionRegex = Get-AssemblyFileVersionRegexString
    $assemblyInformationalVersionRegex = Get-AssemblyInformationalVersionRegexString
 
	if ([string]::IsNullOrEmpty($infoVersion))
	{
        $infoVersion = $newVersion
	}
 
    write-verbose ("Replacing AssemblyVersion and AssemblyFileVersion in [" + $fullyQualifiedAssemblyInfoPath + "] with new version [" + $newVersion + "].")
    write-verbose ("Replacing AssemblyInformationVersion in [" + $fullyQualifiedAssemblyInfoPath + "] with new version [" + $infoVersion + "].")

    $replacement = '$1"' + $newVersion + "`$4"
    $informationReplacement = '$1"' + $infoVersion + "`$4"

    $fileContent = (get-content $fullyQualifiedAssemblyInfoPath) |
        foreach {
            if ($_ -match $assemblyVersionRegex) { $_ -replace $assemblyVersionRegex, $replacement }
            elseif ($_ -match $assemblyFileVersionRegex) { $_ -replace $assemblyFileVersionRegex, $replacement }
            elseif ($_ -match $assemblyInformationalVersionRegex) { $_ -replace $assemblyInformationalVersionRegex, $informationReplacement }
            else { $_ }
        } |
        set-content $fullyQualifiedAssemblyInfoPath

    return $newVersion
}

function Get-AssemblyVersion
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.IO.FileInfo]$assemblyInfoFile,
        [switch]$all=$false
    )

    $fullyQualifiedAssemblyInfoPath = $assemblyInfoFile.FullName

    function Get-VersionMatchingRegex
    {
        param
        (
            [string]$assemblyFilePath,
            [string]$regex
        )

        try
        {
            $version = (select-string -Path "$assemblyFilePath" -Pattern $regex).Matches[0].Groups[3].Value
        }
        catch
        {
            throw new-object Exception("Unable to determine version from file [$assemblyFilePath]. Check to make sure there is a line that matches [$regex].", $_.Exception)
        }

        return $version
    }

    $version = Get-VersionMatchingRegex -assemblyFilePath $fullyQualifiedAssemblyInfoPath -regex (Get-AssemblyVersionRegexString)

    if (-not $all)
    {
        return $version
    }

    $fileVersion = Get-VersionMatchingRegex -assemblyFilePath $fullyQualifiedAssemblyInfoPath -regex (Get-AssemblyFileVersionRegexString)
    $informationalVersion = Get-VersionMatchingRegex -assemblyFilePath $fullyQualifiedAssemblyInfoPath -regex (Get-AssemblyInformationalVersionRegexString)

    return new-object PSObject @{"Version"=$version;"FileVersion"=$fileVersion;"InformationalVersion"=$informationalVersion}
}


function Get-7ZipExecutable
{
     if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $package = "7-Zip.CommandLine"
    $version = "9.20.0"

    $executable = Get-Item -Path "$rootDirectoryPath\tools\dist\7za-9.20.0.exe"
    return $executable
}

function 7Zip-ZipDirectories
{
    param
    (
        [CmdletBinding()]
        [Parameter(Mandatory=$true)]
        [System.IO.DirectoryInfo[]]$include,
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$destination,
        [switch]$additive,
        [string[]]$subdirectoriesToExclude=@()
    )

    $7zipExecutable = Get-7ZipExecutable

    $7zipExecutablePath = $7zipExecutable.FullName

    if ((-not $additive) -and ($destination.Exists))
    {
        Write-Verbose "Destination archive [$($destination.FullName)] exists and Additive switch not set. Deleting."
        $destination.Delete()
    }

    foreach ($directory in $include)
    {
        Write-Verbose "Zipping Directory [$($directory.FullName)] into [$($destination.FullName)] with additive: [$additive], exluding subdirectories matching [$([string]::Join(", ", $subdirectoriesToExclude))]."

        $arguments = "a","$($destination.FullName)","$($directory.FullName)"

        foreach ($subdirectory in $subdirectoriesToExclude)
        {
            $arguments += "-xr!$subdirectory"
        }

        $output = (& $7zipExecutablePath $arguments)

        $7ZipExitCode = $LASTEXITCODE
        if ($7ZipExitCode -ne 0)
        {
            $message = "An error occurred while zipping [$directory]. 7Zip Exit Code was [$7ZipExitCode]";
            Write-Warning $output;
            
            $destination.Delete();
            throw $message;
        }
    }

    return $destination
}

function 7Zip-ZipFiles
{
    param
    (
        [CmdletBinding()]
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo[]]$include,
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$destination,
        [switch]$additive
    )

    $7zipExecutable = Get-7ZipExecutable

    $7zipExecutablePath = $7zipExecutable.FullName

    if ((-not $additive) -and ($destination.Exists))
    {
        Write-Verbose "Destination archive [$($destination.FullName)] exists. Deleting."
        $destination.Delete()
    }

    foreach ($file in $include)
    {
        Write-Verbose "Zipping file [$($file.FullName)] into [$($destination.FullName)] with additive: [$additive]."

        $output = (& "$7zipExecutablePath" a "$($destination.FullName)" "$($file.FullName)")

        $7ZipExitCode = $LASTEXITCODE
        if ($7ZipExitCode -ne 0)
        {
            $destination.Delete()
            throw "An error occurred while zipping [$file]. 7Zip Exit Code was [$7ZipExitCode]."
        }
    }

    return $destination
}

function 7Zip-Unzip
{
    param
    (
        [CmdletBinding()]
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$archive,
        [Parameter(Mandatory=$true)]
        [System.IO.DirectoryInfo]$destinationDirectory
    )

    $7zipExecutable = Get-7ZipExecutable

    $7zipExecutablePath = $7zipExecutable.FullName
    $archivePath = $archive.FullName
    $destinationDirectoryPath = $destinationDirectory.FullName

    Write-Verbose "Unzipping [$archivePath] to [$destinationDirectoryPath] using 7Zip at [$7zipExecutablePath]."
    $output = (& $7zipExecutablePath x "$archivePath" -o"$destinationDirectoryPath" -aoa)

    $7zipExitCode = $LASTEXITCODE
    if ($7zipExitCode -ne 0)
    {
        throw "An error occurred while unzipping [$archivePath] to [$destinationDirectoryPath]. 7Zip Exit Code was [$7zipExitCode]."
    }

    return $destinationDirectory
}
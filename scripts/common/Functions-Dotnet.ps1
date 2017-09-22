function Get-DotnetExecutablePath
{
    if ($rootDirectory -eq $null) { throw "rootDirectory script scoped variable not set. Thats bad, its used to find dependencies." }
    $rootDirectoryPath = $rootDirectory.FullName

    $commonScriptsDirectoryPath = "$rootDirectoryPath\scripts\common"

    . "$commonScriptsDirectoryPath\Functions-Compression.ps1"

    $toolsDirectoryPath = "$rootDirectoryPath\tools"

    $package = "Dotnet.sdk.win.x64";
    $version = "1.0.4";

    $expectedDirectory = "$toolsDirectoryPath\packages\$package.$version"
    if (-not (Test-Path $expectedDirectory))
    {
        $extractedDir = 7Zip-Unzip "$toolsDirectoryPath\dist\$package.$version.7z" "$toolsDirectoryPath\packages"
    }

    $executable = "$expectedDirectory\dotnet.exe";

    return $executable;
}

function Invoke-Dotnet
{
    [CmdletBinding()]
    param
    (
        [array]$args
    )

    $dotnet = Get-DotnetExecutablePath;
    Write-Verbose "Executing dotnet from [$dotnet] with args [$args]";
    & $dotnet $args | Write-Verbose;
    $dotnetExit = $LASTEXITCODE;
    if ($dotnetExit -ne 0)
    {
        throw "An error occurred executing dotnet with args [$args]. Check logs for more information"
    }
}
    
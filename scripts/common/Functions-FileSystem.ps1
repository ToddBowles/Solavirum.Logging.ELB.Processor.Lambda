function Test-FileExists
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$file
    )

    if (!$file.Exists)
    {
        throw "File not present at [$($file.FullName)]."
    }

    return $file
}

function Ensure-DirectoryExists
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.IO.DirectoryInfo]$directory
    )

    if (!$directory.Exists)
    {
        $directory.Create()
    }

    return $directory
}
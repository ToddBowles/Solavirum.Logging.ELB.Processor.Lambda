function Find-RootDirectory
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.IO.DirectoryInfo]$searchStart
    )

    if ((Get-ChildItem -Path $searchStart.FullName -Filter script-root-indicator) -eq $null) { return Find-RootDirectory $searchStart.Parent }
    
    return $searchStart 
}
function ReplaceTokensInFile
{
    [CmdletBinding()]
    param
    (
        [System.IO.FileInfo]$source,
        [System.IO.FileInfo]$destination,
        [Parameter(Mandatory=$true)]
        [hashtable]$substitutions
    )
        
    $content = Get-Content $source
    foreach ($token in $substitutions.Keys)
    {
        $content = $content -replace $token, $substitutions.Get_Item($token)
    }  
    Set-Content $destination $content

    return $destination
}
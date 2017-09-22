function StringNullOrEmptyCoalesce
{
    [CmdletBinding()]
    param
    (
        [string]$a,
        [string]$b
    )

    if ($a -eq $null) { return $b }
    if ([String]::IsNullOrEmpty($a)) { return $b }
    return $a
}

function ShouldNotBeNullOrEmpty
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true)]
        [string]$a,
        [Parameter(Mandatory=$true)]
        [string]$identifier
    )

    process
    {
        if ([string]::IsNullOrEmpty($_)) { throw "Supplied string [$identifier] was empty." }
    }
}
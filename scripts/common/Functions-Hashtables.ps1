function Merge-Hashtables
{
    [CmdletBinding()]
    param
    (
        [hashtable]$first,
        [hashtable]$second
    )

    $combined = @{}
    foreach ($key in $first.Keys)
    {
        $combined.Add($key, $first[$key])
    }

    foreach ($key in $second.Keys)
    {
        if ($combined.ContainsKey($key))
        {
            $value = $second[$key]
            Write-Verbose "The key [$key] is being overwritten with the value [$value]"
            $combined[$key] = $second[$key]
        }
        else
        {
            $combined.Add($key, $second[$key])
        }
    }

    return $combined
}

function Try-Get
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [hashtable]$Hashtable,
        [Parameter(Mandatory=$true)]
        $Key,
        [Parameter(Mandatory=$true)]
        $Default
    )

    if ($Hashtable.ContainsKey($Key))
    {
        Write-Verbose "Try-Get: The key [$key] was found in the supplied hashtable."
        return $Hashtable[$Key]
    }

    Write-Verbose "Try-Get: The key [$key] could not be found in the supplied hashtable. Defaulting to the value [$Default]"
    return $Default
}
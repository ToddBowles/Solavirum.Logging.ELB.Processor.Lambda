function Single
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $input,
        [Parameter(Mandatory=$false, Position=0)]
        [scriptblock]$predicate,
        [string]$description="No description supplied",
        [scriptblock]$valueStringifier={param($value) $value}
    )

    $accepted = $null
    $hasMatch = $false

    if ($predicate -eq $null) { $loggedPredicate = "No Predicate Specified" }
    else { $loggedPredicate = $predicate }

    foreach ($_ in $input)
    {
        if ($predicate -eq $null -or (& $predicate $_))
        {
            write-debug "Single: [$_] matches when tested with [$loggedPredicate]"
            if ($hasMatch) { throw "Multiple elements matching predicate found. Predicate: [$loggedPredicate], Description: [$description], First Match: [$(& $valueStringifier $accepted)], This Element: [$(& $valueStringifier $_)]" }

            $accepted = $_
            $hasMatch = $true
        }
    }

    if ($hasMatch) 
    {
        return $accepted
    }
    else
    {
        throw "Single: There were no elements matching the supplied predicate. Predicate: [$loggedPredicate], Description: [$description]" 
    }
}

function First
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $input,
        [Parameter(Mandatory=$false)]
        $predicate,
        [Parameter(Mandatory=$false)]
        $default,
        [string]$description="No description supplied"
    )

    if ($predicate -eq $null) { $loggedPredicate = "No Predicate Specified" }
    else { $loggedPredicate = $predicate }
    foreach ($_ in $input)
    {
        if ($predicate -eq $null -or (& $predicate $_))
        {
            write-debug "First: [$_] matches when tested with [$loggedPredicate]"

            return $_
        }
        else
        {
            Write-debug "First: [$_] does not match when tested with [$loggedPredicate]"
        }
    }

    if ($default -eq $null)
    {
        throw "No element matching predicate found. Predicate: [$loggedPredicate], Description: [$description]"
    }
    else
    {
        Write-debug "First: no matches when tested with [$loggedPredicate]. Returning specified default"
        return $default
    }
}

function Any
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $input,
        [Parameter(Mandatory=$false)]
        [scriptblock]$predicate
    )

    if ($predicate -eq $null) { $loggedPredicate = "No Predicate Specified" }
    else { $loggedPredicate = $predicate }

    foreach ($_ in $input)
    {
        if ($predicate -eq $null -or ( & $predicate $_))
        {
            write-debug "Any: [$_] matched [$loggedPredicate]. Returning true."
            return $true
        }
        else
        {
            write-debug "Any: [$_] does not match when tested with [$loggedPredicate]"
        }
    }

    return $false
}

function All
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $input,
        [Parameter(Mandatory=$false)]
        [scriptblock]$predicate
    )

    if ($predicate -eq $null) { $loggedPredicate = "No Predicate Specified" }
    else { $loggedPredicate = $predicate }

    foreach ($_ in $input)
    {
        if ($predicate -eq $null -or ( & $predicate $_))
        {
            write-debug "All: [$_] matched [$loggedPredicate]"
        }
        else
        {
            write-debug "All: [$_] does not match when tested with [$loggedPredicate]. Returning false."
            return $false
        }
    }

    return $true
}
function _ToString
{
    [CmdletBinding()]
    param
    (
        $value,
        [int]$maxLength=100
    )

    $asString = "$value";
    $length = $asString.Length;

    if ($asString.Length -gt $maxLength)
    {
        return $asString.Substring(0, $maxLength) + "...";
    }

    return $asString;
}

function Wait
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [scriptblock]$ScriptToFillActualValue,
        [scriptblock]$Condition,
        [scriptblock]$FailureCondition,
        [int]$TimeoutSeconds=30,
        [int]$IncrementSeconds=2,
        [string]$ScriptDescription,
        [string]$ConditionDescription,
        [string]$FailureConditionDescription,
        [scriptblock]$ConvertActualToLoggedString={ $actual.ToString(); }
    )

    if ([string]::IsNullOrEmpty($ScriptDescription))
    {
        $ScriptDescription = $ScriptToFillActualValue
    }

    if ([string]::IsNullOrEmpty($ConditionDescription))
    {
        $ConditionDescription = $Condition
        if ([string]::IsNullOrEmpty($ConditionDescription)) 
        { 
            $ConditionDescription = "No Condition"
        }
    }

    if ([string]::IsNullOrEmpty($FailureConditionDescription))
    {
        $FailureConditionDescription = $FailureCondition
        if ([string]::IsNullOrEmpty($FailureConditionDescription)) 
        { 
            $FailureConditionDescription = "No failure condition"
        }
    }

    Write-Verbose "Waiting for the output of the script [$ScriptDescription] to meet the success condition [$ConditionDescription] or the failure condition [$FailureConditionDescription]. Will wait at maximum [$TimeoutSeconds] seconds, checking every [$IncrementSeconds] seconds"

    $totalWaitTimeSeconds = 0
    while ($true)
    {
        try
        {
            $actual = & $ScriptToFillActualValue;
            $loggedActual = _ToString -Value (& $ConvertActualToLoggedString $actual)
        }
        catch
        {
            $actual = $null;
            $loggedActual = [String]::Empty;
            Write-Verbose "An error occurred while evaluating the script to get the actual value. As a result, the actual value will be undefined (NULL) for condition evaluation. `$error = [$_]"
        }

        try
        {
            $result = & $condition
        }
        catch
        {
            Write-Verbose "An error occurred while evaluating the condition to determine if the wait is over. `$actual = [$loggedActual], `$error = [$_]"

            $result = $false
        }

        if ($result)
        {
            Write-Verbose "The output of the script block [$ScriptDescription] met the condition [$ConditionDescription] after [$totalWaitTimeSeconds] seconds. `$actual = [$loggedActual]"
            return $actual
        }

        if ($FailureCondition -ne $null)
        {
            try
            {
                $failureResult = & $FailureCondition
            }
            catch
            {
                Write-Verbose "An error occurred while evaluating the failure condition to determine if an failing end state was reached. `$actual = [$loggedActual], `$error = [$_]"

                $failureResult = $false
            }

            if ($failureResult)
            {
                $message = "The output of the script block [$ScriptDescription] met the failure condition [$FailureConditionDescription] after [$totalWaitTimeSeconds] seconds. `$actual = [$loggedActual]"
                Write-Warning $message
                throw $message
            }
        }

        Write-Verbose "The current output of the condition is [$result]. Have waited [$totalWaitTimeSeconds/$TimeoutSeconds] seconds so far. `$actual = [$loggedActual]"
        
        if ($totalWaitTimeSeconds -ge $TimeoutSeconds)
        {
            $message = "The output of the script block [$ScriptDescription] did not meet the condition [$condition] after [$totalWaitTimeSeconds] seconds. `$actual = [$loggedActual]"
            Write-Warning $message
            throw $message
        }

        Sleep -Seconds $IncrementSeconds
        $totalWaitTimeSeconds = $totalWaitTimeSeconds + $IncrementSeconds
    }
}

function Retry
{
    [CmdletBinding()]
    param
    (
        [scriptblock]$script,
        [string]$scriptDescription,
        [int]$maxAttempts=5
    )

    if ([string]::IsNullOrEmpty($ScriptDescription))
    {
        $ScriptDescription = $script
    }

    $attempts = 1
    $hasError = $true
    while ($attempts -le $maxAttempts)
    {
        try
        {
            return & $script;
        }
        catch
        {
            Write-Warning "An error occurred while attempting to execute script [$scriptDescription]. This was attempt [$attempts/$maxAttempts], `$error = [$_]";
            $attempts++;
        }
    }

    throw new-object System.Exception("The script [$scriptDescription] did not successfully execute after [$attempts] attempts", $_.Exception);
}

function Get-CredentialByKey
{
    [CmdletBinding()]
    param
    (
        [string]$keyName
    )

    $credsPath = "C:\creds\powershell.tests.credentials";
    $helpMessage = "Credentials can be specified by: Specifying the 'globalCredentialsLookup' argument when running the Pester tests via Invoke-Pester (with the normal hashtable format of @{KEY=VALUE}), creating a file at [$credsPath] with credentials specified therein (using KEY=VALUE\r\n) or setting a global hashtable variable (using `$global:credentialsLookup) in your current session";

    # This check is required for backwards compatibility, as we used to set the global credentials lookup via a variable that just
    # happened to be in scope rather than an actual globally scoped variable (we never used to change it, just read it, until we introdued known
    # credentials file location as a development helper)
    if ($global:credentialsLookup -eq $null -and $globalCredentialsLookup -ne $null)
    {
        Write-Warning "Legacy global credentials hashtable found and globally scoped credentials hashtable is null. Using legacy value to set the value of the globally scoped variable. If you see this message, go and check to see what is setting this variable as we replaced that approach with the variable '`$global:credentialsLookup' which is actually globally scoped";
        $global:credentialsLookup = $globalCredentialsLookup;
    }

    if ($global:credentialsLookup -eq $null)
    {
        Write-Warning "Global credentials hashtable variable referenced by '`$global:credentialsLookup' was not found. Attempting to load from known disk location [$credsPath]";
        if (-not(Test-Path $credsPath))
        {
            Write-Warning "The local credentials file could not be found at [$credsPath]";
        }
        else 
        {
            try 
            {
                $global:credentialsLookup = ConvertFrom-StringData ([System.IO.File]::ReadAllText($credsPath));
                Write-Verbose "Successfully loaded credentials from known disk location [$credsPath]";
            }
            catch
            {
                Write-Warning "An error occurred while attempting to load the credentials from [$credsPath]. The error was [$_]";
                Write-Warning $helpMessage;
            }
        }
        
    }

    if (-not ($global:credentialsLookup.ContainsKey($keyName)))
    {
        throw "The credential with key [$keyName] could not be found in the global hashtable variable referenced by '`$global:credentialsLookup'. $helpMessage";
    }

    return $global:credentialsLookup.Get_Item($keyName)
}
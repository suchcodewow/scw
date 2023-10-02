# VSCODE: ctrl/cmd+k+1 folds all functions, ctrl/cmd+k+j unfold all functions. Check '.vscode/launch.json' for any current parameters
param (
    [switch] $help, # show other command options and exit
    [switch] $verbose # default output level is 1 (info/errors), use -v for level 0 (debug/info/errors)
)

#Dynatrace Azure Check Utility

# Functions
function Send-Update {
    # Handle output to screen & log, execute commands to cloud systems and return results
    param(
        [string] $content, # Message content to log/write to screen
        [int] $type, # [0/1/2] log levels respectively: debug/info/errors, info/errors, errors
        [string] $run, # Run a command and return result
        [switch] $append, # [$true/false] skip the newline (next entry will be on same line)
        [switch] $ErrorSuppression, # use this switch to suppress error output (useful for extraneous warnings)
        [switch] $OutputSuppression # use to suppress normal output
    )
    $Params = @{}
    if ($run) {
        $Params['ForegroundColor'] = "Magenta"; $start = "[>]"
    }
    else {
        Switch ($type) {
            0 { $Params['ForegroundColor'] = "DarkBlue"; $start = "[.]" }
            1 { $Params['ForegroundColor'] = "DarkGreen"; $start = "[-]" }
            2 { $Params['ForegroundColor'] = "DarkRed"; $start = "[X]" }
            default { $Params['ForegroundColor'] = "Gray"; $start = "" }
        }
    }
    # Format the command to show on screen if user wants to see it
    if ($run -and $showCommands) { $showcmd = " [ $run ] " }
    if ($currentLogEntry) { $screenOutput = "$content$showcmd" } else { $screenOutput = "   $start $content$showcmd" }
    if ($append) { $Params['NoNewLine'] = $true; $script:currentLogEntry = "$script:currentLogEntry $content$showcmd"; }
    if (-not $append) {
        #This is the last item in-line.  Write it out if log exists
        if ($logFile) {
            "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $currentLogEntry $content$showcmd" | out-file $logFile -Append
        }
        #Reset inline recording
        $script:currentLogEntry = $null
    }
    # output if user wants to see this level of content
    if ($type -ge $outputLevel) {
        write-host @Params $screenOutput
    }
    if ($run -and $ErrorSuppression -and $OutputSuppression) { return invoke-expression $run 2>$null 1>$null }
    if ($run -and $ErrorSuppression) { return invoke-expression $run 2>$null }
    if ($run -and $OutputSuppression) { return invoke-expression $run 1>$null }
    if ($run) { return invoke-expression $run }
}
function Get-Prefs($scriptPath) {
    if ($verbose) { $script:outputLevel = 0 } else { $script:outputLevel = 1 }
    $script:ProgressPreference = "SilentlyContinue"
    if ($scriptPath) {
        $script:configFile = "$scriptPath.conf"
        if (Test-Path $configFile) {
            Send-Update -c "Reading config $script:configfile" -t 0
            $script:config = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable
        }
        else {
            $script:config = @{}
            $config["schemaVersion"] = "2.0"
            if ($MyInvocation.MyCommand.Name) {
                $config | ConvertTo-Json | Out-File $configFile
                Send-Update -c "CREATED config" -t 0
            }
        }
    }
    write-host

}
function Set-Prefs {
    param(
        $u, # Add this value to a user's settings (mostly for mult-user setup sweetness)
        $k, # key
        $v # value
    )
    if ($u) {
        # Focus on user subkey
        if ($k) {
            # Create User nested hashtable if needed
            if (-not $config.Users.$u) { $config.Users.$u = @{} }
            if ($v) {
                # Update User Value
                Send-Update -c "Updating $u user key: $k -> $v" -t 0
                $config.Users.$u[$k] = $v 
            }
            else {
                if ($k -and $config.Users.$u.containsKey($k)) {
                    # Attempt to delete the user's key
                    Send-Update -c "Deleting $u user key: $k" -t 0
                    $config.Users.$u.remove($k)
                }
                else {
                    Send-Update -c "$u Key didn't exist: $k" -t 0
                }
            }
        }
        else {
            if ($config.Users.$u) {
                # Attempt to remove the entire user
                Send-Update -c "Removing $u user" -t 0
                $config.Users.remove($u)
            }
            else {
                Send-Update -c "User $u didn't exists" -t 0
            }
        }
    }
    else {
        # Update at main schema level
        if ($v) {
            Send-Update -c "Updating key: $k -> $v" -t 0
            $config[$k] = $v 
        }
        else {
            if ($k -and $config.containsKey($k)
            ) {
                Send-Update -c "Deleting config key: $k" -t 0
                $config.remove($k)
            }
            else {
                Send-Update -c "Key didn't exist: $k" -t 0
            }
        }     
    }
    if ($MyInvocation.MyCommand.Name) {
        $config | ConvertTo-Json | Out-File $configFile
    }
    else {
        Send-Update -c "No command name, skipping write" -t 0
    }
}
function Get-Result {

    if ($config.isAzureGov -eq "y") {
        Send-Update -c "Using GOV Azure" -t 0
        $adEndpoint = 'https://login.microsoftonline.us'
        $managementEndpoint = 'https://management.core.usgovcloudapi.net/'
        $resourceEndpoint = 'management.usgovcloudapi.net'
    }
    else {
        Send-Update -c "Using Commercial Azure" -t 0
        $adEndpoint = 'https://login.microsoftonline.com'
        $managementEndpoint = 'https://management.core.windows.net/'
        $resourceEndpoint = 'management.azure.com'
    }

    $param = @{
        Uri    = "$adEndpoint/$($config.tenantId)/oauth2/token?api-version=2020-06-01";
        Method = 'Post';
        Body   = @{
            grant_type    = 'client_credentials';
            resource      = $managementEndpoint;
            client_id     = $($config.appId);
            client_secret = $($config.secretValue);
        }
    }

    $result = Invoke-RestMethod @param
    $token = $result.access_token

    if ($token) {
        # List subscriptions
        $param_subList = @{
            Uri         = "https://$resourceEndpoint/subscriptions?api-version=2020-01-01"
            ContentType = 'application/json'
            Method      = 'GET'
            headers     = @{
                authorization = "Bearer $token"
                host          = $resourceEndpoint
            }
        }

        $response = Invoke-RestMethod @param_subList
        if ($response.value.count -gt 0) {
            $response.value
            write-host "Successfully connected and retrieved subscriptions."
        }
        else {
            write-host ""
            write-host "Credentials authenticated, but FAILED to retrieve subscriptions."
            write-host ""
        }

    }
    else {
        write-host ""
        write-host "FAILED to authenticate. See Error above."
        write-host ""
    }
}
function Get-Answer {
    param(
        $prompt, #what to ask
        $variable #variable name to update
    )
    $trimVariableTo = 8
    if ($config[$variable]) {
        # variable exists, offer it as default
        $defaultResponse = $config[$variable]
        if ($defaultResponse.length -gt $trimVariableTo) {
            # trim variable to limit
            $defaultResponse = "$($defaultResponse.substring(0,$trimVariableTo-2)).."
        }
        $defaultResponsePrompt = " [<enter> to use: '$defaultResponse']"
    }
    $response = read-host -prompt "$prompt$defaultResponsePrompt"
    if (-not $response ) {
        # No response - abort if no existing value
        if (-not $config[$variable]) { exit }
        
    }
    else {
        set-Prefs -k $variable -v $response
    }
}

# Main
Get-Prefs($Myinvocation.MyCommand.Source)
Get-Answer -p "Directory (Tenant) Id" -v tenantId
Get-Answer -p "Application (client) ID" -v appId
Get-Answer -p "Secret Value (NOT the ID!)" -v secretValue
Get-Answer -p "Connect to Azure GOV? (y for yes, n for no)" -v isAzureGov
Get-Result
write-host "Exiting.  Remember to delete .conf file if done!"
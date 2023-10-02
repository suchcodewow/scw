#Installer for webapps across a  resource group

Param(
    [Parameter(Mandatory = $false)] [string] $url,
    [Parameter(Mandatory = $false)] [string] $token,
    [Parameter(Mandatory = $false)] [string] $group,
    [Parameter(Mandatory = $false)] [string] $webapp,
    [Parameter(Mandatory = $false)] [string] $mode,
    [Parameter(Mandatory = $false)] [string] $plan
)
#region ---Settings 
# [Core Settings]
$logLevel = 3 # 0 = results only, 1 = status, 2 = prev + info, 3 = prev + az commands
$iUrl = "" # Your Dynatrace tenant URL (in place of -url cmd line option)
$iToken = "" # Your Dynatrace PAAS token (in place of -token cmd line option)
$apiTimeout = 30 # How many 3 second loops to wait until abandoning install
# [Azure Web App Settings]
$iPlan = "" #app service plan (required only if creating webapps)
$iWebapp = "" # Specific web app within resource group (optional)
$iGroup = "" # The resource group scope for this script (in place of -group cmd line option)
#$runtime = "TOMCAT:10.0-java11"
#$startup_file = """curl -o /tmp/installer.sh -s '$($URL)/api/v1/deployment/installer/agent/unix/paas-sh/latest?Api-Token=$($token)&arch=x86' && sh /tmp/installer.sh /home && LD_PRELOAD='/home/dynatrace/oneagent/agent/lib64/liboneagentproc.so'"""
$dtAzExt = "Dynatrace" # Leave as-is

#endregion

#region ---Functions---
function ChangeSubscription()
{
    $all_accounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
    $counter = 0; $account_choices = Foreach ($i in $all_accounts)
    {
        $counter++
        New-object PSCustomObject -Property @{option = $counter; id = $i.id; subscription = $i.name; }

    }
    $account_choices | sort-object -property option |  format-table -Property option, subscription |  Out-Host
    $account_selected = read-host -prompt "Connect which account? <enter> to cancel"
    if ($account_selected)
    {
        $new_account_id = $account_choices | Where-Object -FilterScript { $_.Option -eq $account_selected } | Select-Object -Property id, name -first 1
        az account set --subscription $new_account_id.id
        Update-Menu
    }
}
function Generatewebapp()
{
    if (-not($plan)) { write-host -foregroundcolor red "Skipping webapp generation.  '-plan' not specified."; break }
    if ($runtime) { $runtime = "--runtime $runtime" }
    write-host -foregroundcolor green "Creating random webapp..."
    $Unique_id = -join ((65..90) | get-Random -Count 10 | ForEach-Object { [char]$_ })
    $generateCommand = @{cmd = "az webapp create -g $group -p $plan -n $Unique_id $runtime -o none"; comments = "webapp create command" }
    show-cmd($generateCommand)
    write-host -foregroundcolor green "$Unique_id created"
}

function Show-cmd($str)
{
    #Function to execute any command while showing exact command to user if settings is on
    if ($logLevel -ge 3)
    {
        write-host "$($str.comments)> " -NoNewline
        write-host -foregroundcolor green "$($str.cmd)"
    }
    return Invoke-Expression $str.cmd
}
function ProcessWebapps
{
    if ($logLevel -ge 1) { write-host -foregroundColor Green "Loading Web Apps..." -NoNewline }
    $targetWebapps = [System.Collections.ArrayList]@()
    if ($webapp) { $azWebapps = @{name = $webapp } }
    else
    {
        $azWebapps = az webapp list -g $group --query '[].{name:name}' | ConvertFrom-Json
    }
    # Build list of webapps & URL's
    foreach ($i in $azWebapps)
    {

        $credsCommand = @{cmd = "az webapp deployment list-publishing-credentials -g $group -n $($i.name) --query '{name:publishingUserName, pass:publishingPassword}' | ConvertFrom-Json"; comments = "Getting credentials" }
        $loginInfo = show-cmd($credsCommand)
        if (-not($loginInfo)) { break }
        $creds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("$($loginInfo.name):$($loginInfo.pass)")))
        $header = @{
            Authorization = "Basic $creds"; "Content-Type" = "Application/JSON"
        }
        #kudu URL's
        $kuduUrl = "https://$($i.name).scm.azurewebsites.net"
        [void]$targetWebapps.add((@{
                    name = $i.name; todo = "query"; notes = ""; header = $header; state = "unchanged"
                    kuduApiUrl = "$kuduUrl/api/siteextensions";
                    kuduDtInstallUrl = "$kuduUrl/api/siteextensions/$dtAzExt";
                    kuduDtStatusUrl = "$kuduUrl/$dtAzExt/api/status";
                    kuduDtSettingsUrl = "$kuduUrl/$dtAzExt/api/settings"
                }))
    }
    if ($logLevel -ge 1) { write-host -foregroundColor Green "$($targetWebapps.Count) loaded. Getting current states..." -NoNewline }
    #Query each webapp for current status
    foreach ($i in $($targetWebapps))
    {
        $allExts = Invoke-RestMethod -Method 'Get' -Uri $i.kuduApiUrl -Headers $i.header
        $dtExtUrl = ($allExts | Where-Object id -Match "Dynatrace")
        if (-not($dtExtUrl))
        {
            # Dynatrace extension not present
            $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "install"; $_.notes = "" }
        }
        else
        {
            # Query status of DT extension
            $dtStatus = Invoke-RestMethod -Method 'Get' -Uri $i.kuduDtStatusUrl -Headers $i.header
            Switch ($dtStatus.state)
            {
                NotInstalled
                { $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "configure"; $_.notes = "Extension present; needs config" } }
                Installed
                {
                    if ($dtStatus.isUpgradeAvailable)
                    { $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "upgrade"; $_.notes = $dtStatus.version } }
                    else
                    { $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "up-to-date"; $_.notes = $dtStatus.version } }
                }
                Failed
                { $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "install"; $_.notes = $($dtStatus.message) } }
                Default
                { $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "FAILED"; $_.notes = "installation status unknown: $($dtStatus.state)" } }
            }
        }
    }
    if ($logLevel -ge 1) { write-host -foregroundColor Green "Success" }
    if ($logLevel -ge 2) { $targetWebapps | ForEach-Object { [PSCustomObject]$_ } | format-table -AutoSize -Property name, todo, notes, state | Out-Host }
    if ($mode)
    {
        if ($mode -eq "stop")
        {
            if ($logLevel -ge 1) { write-host -foregroundColor Green "$(($targetWebapps | Where-Object todo -In ("install", "configure") | select-object -expand name).Count) apps to shut down" }
            foreach ($i in $($targetWebapps) | Where-Object todo -In ("install", "configure"))
            {
                if ($logLevel -ge 2) { write-host -foregroundColor green "Stopping webapp: $($i.name)..." -NoNewline }
                $shutdownCommand = @{cmd = "az webapp stop -n $($i.name) -g $resource_group"; comments = "Shutting down $($i.name)" }
                show-cmd($shutdownCommand)
                if ($logLevel -ge 2) { write-host -foregroundColor green "Success" }
                $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.state = "down" }
            }
        }
        #Install Extension
        if ($logLevel -ge 1) { write-host -foregroundColor Green "Install to do: $(($targetWebapps | Where-Object todo -Match "install" | select-object -expand name).Count)" }
        foreach ($i in $($targetWebapps) | Where-Object todo -Match "install")
        {
            if ($logLevel -ge 2) { write-host -foregroundColor green "Starting install on $($i.name)..." -NoNewline }
            $result = Invoke-RestMethod -Method 'Put' -Uri $i.kuduDtInstallUrl -Headers $i.header
            if ($result.provisioningState -eq "Succeeded")
            {
                if ($logLevel -ge 2) { write-host -foregroundColor green "Provisioned...Pinging extension up to $apiTimeout times waiting for 'success'..." -NoNewline }
                #Hang tight until settings page is ready
                $counter = 0
                Do
                {
                    Start-Sleep 3
                    $Error.clear()
                    try
                    {
                        $result = Invoke-RestMethod -Method 'Get' -Uri $i.kuduDtSettingsUrl -Headers $i.header 
                    }
                    catch
                    {
                        # Loop catches errors
                    }
                    $counter++
                    if ($logLevel -ge 2) { write-host -foregroundColor green "$counter " -NoNewline }
                    if ($counter -ge $apiTimeout)
                    {
                        #We've reached the max number of attempts and need to move on
                        $Error.clear()
                        $abortInstall = $true
                    }
                } until (-not($Error))
                #Add to configure list or mark as failed
                if ($abortInstall)
                {
                    if ($logLevel -ge 2) { write-host -foregroundColor red "Aborting" }
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "FAILED"; $_.notes = "Installation timeout ($apiTimeout) reached" }
                }
                else
                {
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Success" }
                        
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "configure"; $_.notes = "" }
                }
            }
            else
            {
                #Add this webapp to fail list
                $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "FAIL"; $_.notes = "provisioning state: $($result)" }
                if ($logLevel -ge 2) { write-host -foregroundColor red "Installation failed: $($result)" }
            }
        }
        #Configure
        if ($logLevel -ge 1) { write-host -foregroundColor Green "Extension to configure: $(($targetWebapps | Where-Object todo -Match "configure" | select-object -expand name).Count)" }
        foreach ($i in $($targetWebapps) | Where-Object todo -Match "configure")
        {
            if ($logLevel -ge 2) { write-host -foregroundColor green "Configuring $($i.name)..." -NoNewline }
            $body = @{environmentId = $tenantId; apiToken = $token } | ConvertTo-Json
            #Configure [possible todo? handle errors during this method?]
            $result = Invoke-RestMethod -Method 'Put' -Body $body -Uri $i.kuduDtSettingsUrl -Headers $i.header
            #Hang tight while configuration/setup occurs
            if ($logLevel -ge 2) { write-host -foregroundColor green "Done; Checking up to $apiTimeout times max for 'Installed'..." -NoNewline }
            $installResult = "Installing"
            $counter = 0
            Do
            {
                Start-Sleep 3
                $installLoop = Invoke-RestMethod -Method 'Get' -Uri $i.kuduDtStatusUrl -Headers $i.header
                $installResult = $installLoop.state
                if ($logLevel -ge 2) { write-host -foregroundColor green "$installResult, " -NoNewline }
                if ($installResult -eq "Failed") { break }
                $counter++; if ($counter -ge $apiTimeout) { $installResult = "abort"; break }
            } until ($installResult -eq "Installed")
            switch ($installResult)
            {
                abort
                {
                    if ($logLevel -ge 2) { write-host -foregroundColor red "Aborting" }
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "FAIL"; $_.notes = "Reached max tries ($apiTimeout).  Last configuration status was $installResult" }
                }
                Failed
                {
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Failed" }
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "FAIL"; $_.state = "restart required"; $_.notes = "$($installLoop.message)" }
                }
                Installed
                {
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Success" }
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.todo = "up-to-date"; $_.state = "restart required"; $_.notes = "$($installLoop.version)" }
                }
            }
        }
        # Recycle/start by flag
        foreach ($i in $($targetWebapps) | Where-Object state -Match "restart required")
        {
            Switch ($mode)
            {
                stop
                {
                    # Start webapps
                    $startupCommand = @{cmd = "az webapp start -g $resource_group -n $($i.name)"; comments = "starting webapp $($i.name)" }
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Starting webapp $($i.name)..." -NoNewline }
                    show-cmd($startupCommand)
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Success" }
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.state = "Startup Successful" }

                }
                recycle
                {
                    # Recycle webapps
                    $recycleCommand = @{cmd = "az webapp restart -g $resource_group -n $($i.name)"; comments = "starting webapp $($i.name)" }
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Recycling webapp $($i.name)..." -NoNewline }
                    show-cmd($recycleCommand)
                    if ($logLevel -ge 2) { write-host -foregroundColor green "Success" }
                    $targetWebapps | Where-Object name -Match $i.name | ForEach-Object { $_.state = "Recycle Successful" }
                }
                default
                {
                    #no flag so leave apps running with 'restart required' notice
                }
            }
        }
    } 
    
    #Output Results
    $targetWebapps | ForEach-Object { [PSCustomObject]$_ } | format-table -AutoSize -Property name, todo, notes, state | Out-Host

    if (-not($mode))
    {
        write-host -ForegroundColor yellow "Running in 'what if' mode.  Use ' -mode' flag with of these options to make changes: install recycle stop"
    }
}
function DeleteWebapps
{
    write-host "Deleting webapps"
    $azWebapps = az webapp list -g $group --query '[].{name:name,id:id}' | ConvertFrom-Json
    foreach ($i in $azWebapps)
    {
        az webapp delete --id $i.id
        write-host "Killed webapp: $($i.name)"
    }
}
function Update-Menu
{
    #reset things
    $script:cmd_options = @()
    $script:cmd_counter = 0
    #subscription selection option
    $current_subscription = az account show --query '{ id:id, name:name }' | Convertfrom-Json
    Add-MenuOption -cmd "ChangeSubscription" -cmd_type "script" -text "Change subscription [currently: $($current_subscription.name)]"
    Add-MenuOption -cmd "GenerateWebapp" -cmd_type "script" -text "Generate a new web app"
    #List existing webapps
    Add-MenuOption -cmd "ProcessWebapps" -cmd_type "script" -text "Get info on webapps"

}
function Add-MenuOption()
{
    Param(
        #Command to run
        [Parameter(Mandatory = $true)] [string] $cmd,
        #Command type.  Options are script, azcli
        [Parameter(Mandatory = $true)] [string] $cmd_type,
        #Text to display
        [Parameter(Mandatory = $true)] [string] $text,
        #Custom menu option
        [Parameter(Mandatory = $false)] [string] $option
    )
    if ($option) { $counter_value = $option }else
    {
        $script:cmd_counter++; $counter_value = $cmd_counter
    }        
    $script:cmd_options += New-object PSCustomObject -Property @{Option = $counter_value; Text = $text; cmd = $cmd; cmd_type = $cmd_type }
}
function Invoke-Option($option)
{
    if (-not($option))
    {
        write-host -ForegroundColor red "Hey... just what you see pal."
    }
    else
    {
        Switch ($option.cmd_type)
        {
            script
            {
                Invoke-Expression $option.cmd
            }
            azcli
            {
                Invoke-Expression $option.cmd
            }
        }
    }
}
function MenuLoop
{
    Update-Menu
    While ($true)
    {
        if ($show_commands)
        {
            $script:cmd_options | sort-object -property Option | format-table -Property Option, Text, Cmd | Out-Host
        }
        else
        {
            $script:cmd_options | sort-object -property Option | format-table -Property Option, Text | Out-Host
        }
        $cmd_selected = read-host -prompt "Select an option [<enter> to quit]"
        if (-not($cmd_selected)) { write-host "`r`nbuh bye!"; exit }
        $cmd_to_run = $script:cmd_options | Where-Object -FilterScript { $_.Option -eq $cmd_selected } | Select-Object -first 1 
        Invoke-Option $cmd_to_run
    }
}
#endregion

# ---Preflight check
# Are we logged into Azure?
$signedIn = az ad signed-in-user show 2>null
if (-not $signedIn) { write-host -ForegroundColor green "No valid login detected.  Please run 'az login' and retry."; exit }
# Do we have needed input?
if (-not($url)) { $url = $iUrl }; If ($url -eq "") { write-host "No URL was specified."; exit }
if (-not($token)) { $token = $iToken }; if ($token -eq "") { write-host "No token found"; exit }
if (-not($group)) { $group = $iGroup }; if ($group -eq "") { write-host "No Azure resource group specified"; exit }
if (-not($plan)) { $plan = $iPlan }
if (-not($webapp)) { $webapp = $iWebapp }
if ($url.substring($url.length - 1, 1) -eq "/") { $url = $url.substring(0, $url.length - 1) }
$tenantId = $url.split(".")[0]; $tenantId = $tenantId.split("//"); if ($tenantId.Length -eq 2) { $tenantId = $tenantId[1] }
if ($tenantId.Length -ne 8) { write-host "Your tenant ID ($tenantId) isn't the correct length of 8 characters."; exit }

# Set flags based on command line input
if ($mode -notin ("install", "stop", "recycle", $null))
{
    write-host -foregroundcolor red "mode: '$mode' invalid.  Leave blank for read-only mode.  Execution options are: install recycle stop"
    exit
    
}
else
{
    #mode is valid; continue
}

Clear-Host
# Uncomment options below for testing to create/remove webapps
# DANGER: do not use until you confirm resource group target contains test data ONLY!
#DeleteWebapps
GenerateWebapp

#Main production function
#ProcessWebapps
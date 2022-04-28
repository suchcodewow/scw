Param(
    [Parameter(Mandatory = $false)] [string] $url,
    [Parameter(Mandatory = $false)] [string] $token
)
#region ---Settings
# [Core Setting] Show commands (chatty, but informative)
$show_commands = $true
# [Core Setting] Your Dynatrace tenant URL (Ignore after ;)
$iUrl = "" ; 
# [Core Setting] Your Dynatrace PAAS token
$iToken = ""
# [Core Setting] The resource group scope for this script
$resource_group = "scw-group-shawn.pearson"
# [Azure Web App Settings]
$webapp_plan = "shawn-projects"
$runtime = "TOMCAT:10.0-java11"
$startup_file = """curl -o /tmp/installer.sh -s '$($URL)/api/v1/deployment/installer/agent/unix/paas-sh/latest?Api-Token=$($token)&arch=x86' && sh /tmp/installer.sh /home && LD_PRELOAD='/home/dynatrace/oneagent/agent/lib64/liboneagentproc.so'"""
$dt_azure_extension = "Dynatrace"
$dt_azure_baseURL = "dynatrace"
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
    $Unique_id = -join ((65..90) | get-Random -Count 10 | ForEach-Object { [char]$_ })
    az webapp create -g $resource_group -p $webapp_plan -n $Unique_id -o none
}

function Show-cmd($str)
{
    #Function to execute any command while showing exact command to user if settings is on
    write-host "`r`n$($str.comments)..." | Out-Host
    if ($show_commands) { write-host -ForegroundColor Green "$($str.cmd)`r`n" | Out-Host }
    Invoke-Expression $str.cmd
}
function ProcessWebapps
{
    $todo_baseinstall = @()
    $todo_configure = @()
    $todo_upgrade = @()
    $fail_list = @()
    $done_list = @()
    $all_webapps = az webapp list -g $resource_group --query '[].{name:name}' | ConvertFrom-Json

    foreach ($i in $all_webapps)
    {
        $credentials_command = @{cmd = "az webapp deployment list-publishing-credentials -g $resource_group -n $($i.name) --query '{name:publishingUserName, pass:publishingPassword}' | ConvertFrom-Json"; comments = "Getting credentials" }
        $login_info = show-cmd($credentials_command)
        $creds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("$($login_info.name):$($login_info.pass)")))
        $header = @{
            Authorization = "Basic $creds"
        }
        #Base webapp connect info
        $kuduUrl = "https://$($i.name).scm.azurewebsites.net"
        $kuduDTUrl = "$kuduUrl/$dt_azure_baseURL/api/status"
        $kuduApiUrl = "$kuduUrl/api/siteextensions/$dt_azure_extension"
        #$kuduApiUrl = "$kuduUrl/api/extensionfeed";
        #Get all extensions
        #$results = Invoke-RestMethod -Method 'Get' -Uri $kuduApiUrl -Headers $header
        # 1. Check DT extension status
        #Invoke-RestMethod -Method 'Get' -Uri $kuduDTUrl -Headers $header
        #try
        #{
        $error.Clear()
        $dt_status = Invoke-RestMethod -Method 'Get' -Uri $kuduDTUrl -Headers $header -ErrorAction Continue
        if ($error)
        {
            write-host "There was an error: $error"
            #If got a 404, install agent here
        }
        else
        {
            $dt_status
            Switch ($dt_status.state)
            {
                NotInstalled
                {
                    $todo_configure += @{name = $i.name; creds = $creds }
                }
                Installed
                {
                    if ($dt_status.isUpgradeAvailable)
                    { 
                        write-host "Can be upgraded" 
                        $todo_upgrade += @{name = $i.name }
                    }
                    else { write-host "up to date" }
                    $done_list += @{name = $i.name }
                }
                Default
                {
                    #Shouldn't get here.
                    write-host "Couldn't identify a solution"
                }
            }
        }
 
    }

    #Do base installs
    write-host "$($todo_baseinstall.Count) base installs needed"
    foreach ($i in $todo_baseinstall)
    {
        write-host "Installing shell on $($i.name)"
        $kuduUrl = "https://$($i.name).scm.azurewebsites.net"
        $kuduDTUrl = "$kuduUrl/$dt_azure_baseURL/api/status"
        $kuduApiUrl = "$kuduUrl/api/siteextensions/$dt_azure_extension"
        $result = Invoke-RestMethod -Method 'Put' -Uri $kuduApiUrl -Headers $header
        if ($result.provisioningStatus -eq "Succeeded")
        {
            #Add this webapp to install list
            write-host "Successful on $($i.name)"
        }
        else
        {
            #ADd this webapp to fail list
            write-host "FAILURE: $($i.name) full result: $result"
        }
    }
    #Configure new installations
    write-host "$($todo_configure.Count) configurations needed"
    foreach ($i in $todo_configure)
    {
        $header = @{
            Authorization = "Basic $($i.creds)"; "Content-Type" = "Application/JSON"
        }
        $kuduUrl = "https://$($i.name).scm.azurewebsites.net"
        $kuduSettingsUrl = "$kuduUrl/$dt_azure_baseURL/api/settings"

        $body = @{environmentId = $tenantId; apiToken = $token } | ConvertTo-Json
        $result = Invoke-RestMethod -Method 'Put' -Body $body -Uri $kuduSettingsUrl -Headers $header
        $result
    }

    #Failed Installs
    write-host "$($fail_list.Count) failed"
    #Done Installs
    write-host "$($done_list.Count) are up to date"
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

#Configure Variables

if (-not($url)) { $url = $iUrl }; If ($url -eq "") { write-host "No URL was specified."; exit }
if (-not($token)) { $token = $iToken }; if ($token -eq "") { write-host "No token found"; exit }
if ($url.substring($url.length - 1, 1) -eq "/") { $url = $url.substring(0, $url.length - 1) }
$tenantId = $url.split(".")[0]; $tenantId = $tenantId.split("//"); if ($tenantId.Length -eq 2) { $tenantId = $tenantId[1] }
if ($tenantId.Length -ne 8) { write-host "Your tenant ID ($tenantId) isn't the correct length of 8 characters."; exit }

#MenuLoop

ProcessWebapps
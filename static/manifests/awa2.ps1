#region ---Settings
# [Core Setting] Show commands (chatty, but informative)
$show_commands = $true
# [Core Setting] Your Dynatrace tenant URL (Ignore after ;)
$URL = "" ; if ($URL.substring($URL.length - 1, 1) -eq "/") { $URL = $URL.substring(0, $URL.length - 1) }
# [Core Setting] Your Dynatrace PAAS token
$token = ""
# [Core Setting] The resource group scope for this script
$resource_group = "scw-group-shawn.pearson"
# [Azure Web App Settings]
$webapp_plan = "shawn-projects"
$runtime = "TOMCAT:10.0-java11"
$startup_file = """curl -o /tmp/installer.sh -s '$($URL)/api/v1/deployment/installer/agent/unix/paas-sh/latest?Api-Token=$($token)&arch=x86' && sh /tmp/installer.sh /home && LD_PRELOAD='/home/dynatrace/oneagent/agent/lib64/liboneagentproc.so'"""
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
function CreateWebapp()
{
    write-host $webapp_plan
}
function Update-Menu
{
    #reset things
    $script:cmd_options = @()
    $script:cmd_counter = 0
    #subscription selection option
    $current_subscription = az account show --query '{id:id,name:name}' | Convertfrom-Json
    Add-MenuOption -cmd "ChangeSubscription" -cmd_type "script" -text "Change subscription [currently: $($current_subscription.name)]"
    Add-MenuOption -cmd "GenerateWebapp" -cmd_type "script" -text "Generate a new web app"
    #List existing webapps
    Add-MenuOption -cmd "az webapp list -g $resource_group --query '[].{name:defaultHostName}' -o table" -cmd_type "azcli" -text "List current webapps"

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
function blah
{
    $Unique_id = -join ((65..90) | get-Random -Count 10 | ForEach-Object { [char]$_ })
    $create_webapp_command = "az webapp create -n $Unique_id -g $resource_group -p $webapp_plan --runtime $runtime --startup-file $startup_file --query '[].{id:id}'"
    write-host -foregroundcolor green $create_webapp_command
    $results = invoke-expression $create_webapp_command | Convertfrom-Json
    write-host "Tailing log for $Unique_id" | Out-Host
    az webapp log tail -n $Unique_id -g $resource_group
    #Foreach ($i in $(az webapp list -g $resource_group --query '[].{name:name}' |Convertfrom-Json)){
    #    write-host "az webapp log show -n $($i.name) -g $resource_group"
    #}
}
#endregion

#region ---Main---

MenuLoop

#endregion


#Running STARTUP_COMMAND: curl -o /tmp/installer.sh -s 'https://kge67267.live.dynatrace.com/v1/deployment/installer/agent/unix/paas-sh/latest?Api-Token=dt0c01.WOH3AKM2F2TCU5U32L5C4SD3.RP7VFPYHGMMGU57THONKAKHQBRHRXG6QHAA556VDUHEPXKQSR6NHPG56PWLKY2RL&arch=x86' && sh /tmp/installer.sh /home && LD_PRELOAD='/home/dynatrace/oneagent/agent/lib64/liboneagentproc.so'
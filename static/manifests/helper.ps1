#region ---Settings--- 
# $true = ask for subscription, $false=assume current
$subscription_mode = $true
# $true = show any commands as they run (verbose), $false = hide commands
$show_commands = $true
#endregion

#region ---Functions---

function Get-Choice($cmd_choices)
{
    # Present list of options and get selection
    $cmd_choices | sort-object -property Option | format-table -Property Option, Name, Command_Line | Out-Host
    $cmd_selected = read-host -prompt "Which option to execute? [<enter> to quit]"
    if (-not($cmd_selected))
    {
        write-host "buh bye!`r`n" | Out-Host
        exit
    }
    return $cmd_choices | Where-Object -FilterScript { $_.Option -eq $cmd_selected } | Select-Object -ExpandProperty Command_Line -first 1 
}

function Invoke-Choice($cmd)
{
    #Execute menu option selected
    $msg = [regex]::match($cmd, '\[(.*?)\]').Groups[1].value
    $replace = [regex]::match($cmd, '\[(.*?)\]').Groups[0].value
    if ($msg)
    {
        $replacement = read-host -prompt "$($msg)?"
        $cmd = $cmd.replace($replace, $replacement)

    }
    $menu_command = @{cmd = $cmd; comments = "Executing menu command" }
    show-cmd($menu_command)
    if ($cmd.contains("az group delete")) { write-host "Group deleted...exiting"; exit }
}

function Show-cmd($str)
{
    #Function to execute any command while showing exact command to user if settings is on
    write-host "`r`n$($str.comments)..." | Out-Host
    if ($show_commands) { write-host -ForegroundColor Green "$($str.cmd)`r`n" | Out-Host }
    Invoke-Expression $str.cmd
}
#endregion

# Startup


# Are we logged into Azure?
$signedIn = az ad signed-in-user show 2>null
if (-not ($signedIn)) { write-host -foregroundcolor red "`r`nNo valid azure credential found.  Please login with 'az login' then retry."; exit }

write-host -ForegroundColor Green "Lines in this color show commands exactly as they are executed."
#region ---subscription selection---
if ($subscription_mode)
{
    $current_id = az account show --query '{name:name, id:id}' | Convertfrom-Json
    $all_accounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
    $counter = 0; $account_choices = Foreach ($i in $all_accounts)
    {
        $counter++
        if ($i.id -eq $current_id)
        {
            $current_account = $true
            $account_default = $counter
        }
        else
        {
            $current_account = $false
        }
        New-object PSCustomObject -Property @{option = $counter; id = $i.id; subscription = $i.name; current = $current_account }
    }

    $account_choices | sort-object -property option |  format-table -Property option, subscription, id |  Out-Host
    $account_selected = read-host -prompt "Connect which account? [$account_default]"
    if ($account_selected)
    {
        $new_account_id = $account_choices | Where-Object -FilterScript { $_.Option -eq $account_selected } | Select-Object -Property id, name -first 1
        az account set --subscription $new_account_id.id
    
    }
}
#endregion

$NewSub = az account show --query '{name:name,email:user.name,id:id}' | ConvertFrom-Json; $SubName = $NewSub.name; $SubId = $NewSub.id; $UserName = (($NewSub.email).split("@")[0]).replace(".","_")
write-host "Loading command options for: $SubName" | Out-Host

#region ---Create resource group if needed---
$target_group = "scw-group-$UserName"
$check_group_command = @{cmd = "az group exists -g $target_group --subscription $SubId"; comments = "Check if group already exists" }
if ($(Show-cmd($check_group_command)) -eq "false")
{
    $OkToCreate = read-host -prompt "Create resource group and vm? [y/n]"
    if ($OkToCreate -ne "y") { write-host "`r`nBailing out!" | Out-Host; exit }
    $query_locations_command = @{cmd = "az account list-locations --query ""[?metadata.regionCategory=='Recommended']. { name:displayName, id:name }"""; comments = "Getting a list of regions" }
    $available_locations = Show-cmd($query_locations_command) | Convertfrom-Json
    $counter = 0; $location_choices = Foreach ($i in $available_locations)
    {
        $counter++
        New-object PSCustomObject -Property @{Option = $counter; id = $i.id; name = $i.name }
    }
    $location_choices | sort-object -property Option | format-table -Property Option, name | Out-Host
    $location_selected = read-host -prompt "Which region for your resource group?"
    $location_id = $location_choices | Where-Object -FilterScript { $_.Option -eq $location_selected } | Select-Object -ExpandProperty id -first 1
    if (-not($location_id)) { write-host "No location found; exiting."; exit }
    $create_group_command = @{cmd = "az group create --name $target_group --location $location_id -o none"; comments = "Creating your group" }
    Show-cmd($create_group_command)
}
$cmd_choices = @()
$cmd_choices += New-object PSCustomObject -Property @{Option = "del"; Name = "End Tutorial (delete all)"; Command_Line = "az group delete -n $target_group" }
#endregion

#region ---Create VM if needed---
# $target_host = "scw-host-$UserName"
# $Check_host_command = @{cmd = "az vm list -g $target_group --query ""[?name=='$target_host']"""; comments = "Check if host exists" }
# if (-not(Show-cmd($Check_host_command) | Convertfrom-Json))
# {
#     while (-not($host_result))
#     {
#         #$pw = read-host "Enter a password for your host.  It must be 12 characters long and have: lower, upper, special character"
#         #$create_host_command = @{cmd = "az vm create --resource-group $target_group --name $target_host --image UbuntuLTS --size Standard_B2ms --public-ip-sku Standard --admin-username azureuser --admin-password $pw"; comments = "Creating your host" }
#         $create_host_command = @{cmd = "az vm create --resource-group $target_group --name $target_host --image UbuntuLTS --size Standard_B2ms --public-ip-sku Standard --admin-username azureuser --generate-ssh-keys"; comments = "Creating your host" }
#         $host_result = Show-cmd($create_host_command) | Convertfrom-json
#         Write-Output $host_result.publicIpAddress > myip
#     }
#     # open port 80 to the host
#     $open_port_command = @{cmd = "az vm open-port -g $target_group -n $target_host --port 80 --priority 100 -o none"; comments = "Open port 80" }
#     Show-cmd($open_port_command)
# }
#endregion

#region ---Create AKS cluster  if needed---
$target_cluster = "scw-AKS-$UserName"
$Check_cluster_command = @{cmd = "az aks show -n $target_cluster -g $target_group --query id 2>nul"; comments = "Check if cluster already exists"}
$cluster_creds_command = @{cmd="az aks get-credentials --admin -g $target_group -n $target_cluster";comments="Get cluster credentials"}
 
if (-not(Show-cmd($Check_cluster_command)))
{$create_cluster_command = @{cmd="az aks create -g $target_group -n $target_cluster --node-count 2 --generate-ssh-keys"; comments = "Creating AKS cluster"}
Show-cmd($create_cluster_command)
Show-cmd($cluster_creds_command)
}
else
{
    Show-cmd($cluster_creds_command)
}


#region ---Menu: VM Options---
$vm_list = az vm list --query '[].{id:id,name:name,user:osProfile.adminUsername,publicIP:publicIps}' -g $target_group -d | ConvertFrom-Json
$counter = 0; $vm_choices = @(); $vm_choices = Foreach ($i in $vm_list)
{
    $counter++
    # $az_list = az vm list-ip-addresses --id $($i.id)  --query '[].{publicIP:virtualMachine.network.publicIpAddresses[0].ipAddress}' | ConvertFrom-Json
    New-object PSCustomObject -Property @{Option = $counter; Name = "login to $($i.name)"; Command_Line = "ssh $($i.user)@$($i.publicIP)" 
    }
    $counter++
    new-object PSCustomObject -Property @{Option = $counter; Name = "reset password"; Command_Line = "az vm user update -u $($i.user) -p [new password] -n $target_host -g $target_group -o none" 
    }
    $counter++
    new-object PSCustomObject -Property @{Option = $counter; Name = "open port 80"; Command_Line = "az vm open-port -g $target_group -n $target_host --port 80 --priority 100 -o none" }
}
#endregion

# Combine choices and show options
$cmd_choices += $vm_choices
while ($true)
{
    $cmd = Get-Choice($cmd_choices)
    if ($cmd)
    {
        Invoke-Choice($cmd)
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
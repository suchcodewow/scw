# ---Settings--- 
# $true = ask for subscription, $false=assume current
$subscription_mode = $true

# ---Functions---

function Get-Choice($cmd_choices)
{
    # Present list of options and get selection
    $cmd_choices | sort-object -property Option | format-table -Property Option, Name, Type, Command_Line | Out-Host
    $cmd_selected = read-host -prompt "Which command to execute? [<enter> to quit]"
    if (-not($cmd_selected))
    {
        write-host "`r`nbuh bye!" | Out-Host
        exit
    }
    return $cmd_choices | Where-Object -FilterScript { $_.Option -eq $cmd_selected } | Select-Object -ExpandProperty Command_Line -first 1 
}

function Invoke-Choice($cmd)
{
    write-Host "Executing: $cmd" | Out-Host
    Invoke-Expression $cmd
}

# ---Main Script---
# Pick subscription
if ($subscription_mode)
{
    $current_id = az account show --query 'id' -o tsv
    $all_accounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
    $account_choices = @()
    $counter = 0

    Foreach ($i in $all_accounts)
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
        $choice = @(
            [PSCustomObject]@{
                Option = $counter; id = $i.id; subscription = $i.name; current = $current_account
            }
            $account_choices += $choice
        )
    }

    $account_choices | sort-object -property Option | format-table -Property Option, subscription | Out-Host
    $account_selected = read-host -prompt "Connect which account? [$account_default]"
    if ($account_selected)
    {
        $new_account_id = $account_choices | Where-Object -FilterScript { $_.Option -eq $account_selected } | Select-Object -Property id,name -first 1
        az account set --subscription $new_account_id.id
        

    }
}
$NewSubName = az account show --query 'name' -o tsv
write-host "Loading command options for: $NewSubName" | Out-Host
# Add VM connections to list of options using type = ssh (currently the only option)
$vm_list = az vm list --query '[].{id:id,name:name,user:osProfile.adminUsername}' | ConvertFrom-Json
$cmd_choices = @()
$counter = 0
Foreach ($i in $vm_list)
{
    $counter++
    $az_list = az vm list-ip-addresses --id $($i.id)  --query '[].{publicIP:virtualMachine.network.publicIpAddresses[0].ipAddress}' | ConvertFrom-Json
    $vm_choice = [PSCustomObject]@{
        Option = $counter; Name = $i.name; id = $i.id; Type = "ssh"; Command_Line = "ssh $($i.user)@$($az_list[0].publicIP)"
    }
    $cmd_choices += $vm_choice
}

# Offer command choices until exit
while ($true)
{
    $cmd = Get-Choice($cmd_choices)
    Invoke-Choice($cmd)
}
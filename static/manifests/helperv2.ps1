#region ---Variables

#Settings to Modify
$outputLevel = 0 # [0/1/2] message level to send to screen: debug/info/errors, info/errors, errors
$retainLog = $false # [$true/false] keep written log between executions
$useAWS = $true # [$true/false] use AWS
$useAzure = $true # [$true/$false] use Azure
$useGCP = $true # [$true/$false] use GCP
$showCommands = $true # [$true/$false] show cloud commands as they execute
# [DO NOT MODIFY BELOW] Internal variables/setup
[System.Collections.ArrayList]$providerList = @()
[System.Collections.ArrayList]$choices = @()
[System.Collections.ArrayList]$status = @()
$script:currentLogEntry = $null
if ($MyInvocation.MyCommand.Name) {
    $logFile = "$(Split-Path $MyInvocation.MyCommand.Name  -LeafBase).log"
    if ((test-path $logFile) -and -not $retainLog) {
        Remove-Item $logFile
    }
}
write-host
#endregion

#region ---Functions 
function Send-Update {
    # Handle output to screen & log, execute commands to cloud systems and return results
    param(
        [string] $content, # Message content to log/write to screen
        [int] $type, # [0/1/2] log levels respectively: debug/info/errors, info/errors, errors
        [string] $cmd, # Include a command to run and return result
        [switch] $append # [$true/false] skip the newline (next entry will be on same line)
    )
    $Params = @{}
    Switch ($type) {
        0 { $Params['ForegroundColor'] = "DarkBlue"; $start = "[.]" }
        1 { $Params['ForegroundColor'] = "DarkGreen"; $start = "[>]" }
        2 { $Params['ForegroundColor'] = "DarkRed"; $start = "[X]" }
        default { $Params['ForegroundColor'] = "Gray"; $start = "" }
    }
    # Format the command to show on screen if user wants to see it
    if ($cmd -and $showCommands) { $showcmd = " [ $cmd ] " }
    if ($currentLogEntry) { $screenOutput = "$content$showcmd" } else { $screenOutput = "   $start $content$showcmd" }
    if ($append) { $Params['NoNewLine'] = $true; $script:currentLogEntry = "$script:currentLogEntry$content"; }
    if (-not $append) {
        #This is the last item in-line.  Write it out if log exists
        if ($logFile) {
            "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $currentLogEntry$content" | out-file $logFile -Append
        }
        #Reset inline recording
        $script:currentLogEntry = $null
    }
    # output if user wants to see this level of content
    if ($type -ge $outputLevel) {
        write-host @Params $screenOutput
    }
    if ($cmd) { return invoke-Expression $cmd }
}
function Add-Choice() {
    param(
        [string] $k, # key identifying this choice, unique only
        [string] $d, # description of item
        [string] $c, # current selection of item, if applicable
        [string] $f, # function name to call if changing item
        [object] $p # parameters needed in the function
    )
    # If this key exists, delete it and anything that followed
    $keyOption = $choices | Where-Object { $_.key -eq $k } | select-object -Property Option -first 1
    if ($keyOption) {
        Send-Update -content "key: '$k' found at option: '$($keyOption.Option)'. Deleting Option " -append
        $choices | ForEach-Object { if ($_.Option -ge $keyOption.Option) { $choices.Remove($_); Send-Update -content "$($_.Option), " -type 0 -append } }
        Send-Update -content "done"
    }
    $choice = New-Object PSCustomObject -Property @{
        key            = $k
        description    = $d
        current        = $c
        callFunction   = $f
        callProperties = $p
        Option         = $choices.count + 1

    }
    [void]$choices.add($choice)
}

function Add-Provider() {
    param(
        [string] $p, # provider
        [string] $n, # name of item
        [string] $i, # item unique identifier
        [switch] $d, # [$true/$false] default option
        [string] $u # unique user identifier (for creating groups/clusters)
    )
    #TODO match Add-Choice Params
    #---Add an option selector to item then add to provider list
    $provider = New-Object PSCustomObject -Property @{
        provider   = $p
        name       = $n
        identifier = $i
        default    = $d
        userid     = $u
        option     = $providerLIst.count + 1
    }
    [void]$providerList.add($provider)
}
function Get-Choice($cmd_choices) {
    # Present list of options and get selection
    write-output $choices | sort-object -property Option | format-table -Property Option, Description, Current, callFunction, callProperties | Out-Host
    # $cmd_choices | sort-object -property Option | format-table -Property Option, Name, Command_Line | Out-Host
    $cmd_selected = read-host -prompt "Which option to execute? [<enter> to quit]"
    if (-not($cmd_selected)) {
        write-host "buh bye!`r`n" | Out-Host
        exit
    }
    return $choices | Where-Object { $_.Option -eq $cmd_selected } | Select-Object  -first 1 
}
function Get-Providers() {
    # AZURE
    Send-Update -content "Gathering provider options: " -type 1 -append
    $providerList.Clear()
    if ($useAzure) {
        if (get-command 'az' -ea SilentlyContinue) {
            Send-Update -content "Azure... " -type 1 -append
            $azureSignedIn = az ad signed-in-user show 2>$null 
        }
        else { Send-Update -content "Azure... " -type 2 -append }
        if ($azureSignedIn) {
            #Azure connected, get current subscription
            $currentAccount = az account show --query '{name:name,email:user.name,id:id}' | Convertfrom-Json
            $allAccounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
            foreach ($i in $allAccounts) {
                $Params = @{}
                if ($i.id -eq $currentAccount.id) { $Params['d'] = $true }
                Add-Provider @Params -p "Azure" -n "subscription: $($i.name)" -i $i.id -u (($currentAccount.email).split("@")[0]).replace(".", "")
            }
        }
    }
    # AWS
    if ($useAWS) {
        if (get-command 'aws' -ea SilentlyContinue) {
            Send-Update -content "AWS... " -type 1 -append
            $awsSignedIn = aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]' 2>$null 
        }
        else { Send-Update -content "AWS... " -type 2 -append }
        if ($awsSignedIn) {
            # Add-Provider(New-object PSCustomObject -Property @{Provider = "AWS"; Name = "region:  $($awsSignedIn)"; Identifier = $awsSignedIn; default = $true })
            Add-Provider -p "AWS" -n "region: $($awsSignedIn)" -i $awsSignedIn -d
        }
    }
    # GCP
    if ($useGCP) {
        if (get-command 'gcloud' -ea SilentlyContinue) { Send-Update -content "GCP... " -type 1 -append; $GCPSignedIn = gcloud config get-value project -quiet 2>$null }
        else { Send-Update -content "GCP... " -type 2 -append }
        if ($GCPSignedIn) {
            $currentProject = gcloud config get-value project
            $allProjects = gcloud projects list --format=json | Convertfrom-Json
            foreach ($i in $allProjects) {
                $Params = @{}
                if ($i.name -eq $currentProject) { $Params['d'] = $true } 
                Add-Provider @Params -p "GCP" -n "project: $($i.name)" -i $i.projectNumber 
            }
        }
    
    }
    # Done getting options
    Send-Update -content "Done!" -type 1
    #Take action based on # of providers
    if ($providerList.count -eq 0) { write-output "`nCouldn't find a valid target cloud environment. `nLogin to Azure, AWS, or GCP and retry.`n"; exit }
    #If there's one default, set it as the current option
    $providerDefault = $providerList | Where-Object default -eq $true
    if ($providerDefault.count -eq 1) {
        # Select the default
        #Add-Choice -k "target" -d "change script target" -c "$($providerDefault[0].Provider) $($providerDefault[0].Name)" -f "Set-Provider"
        Set-Provider -preset $providerDefault
    }
    else {
        # Select from 2+ default providers
        Set-Provider
    }
}
function Set-Provider() {
    param(
        [object] $preset # optional preset to bypass selection
    )
    $providerSelected = $preset
    while (-not $providerSelected) {
        write-output $providerList | sort-object -property Option | format-table -property Option, Provider, Name | Out-Host
        $newProvider = read-host -prompt "Which environment to use? <enter> to cancel"
        if (-not($newProvider)) {
            return
        }
        $providerSelected = $providerList | Where-Object { $_.Option -eq $newProvider } | Select-Object  -first 1
        if (-not $providerSelected) {
            write-host -ForegroundColor red "`r`nY U no pick valid option?" 
        }
    }
    $functionProperties = @{provider = $providerSelected.Provider; id = $providerSelected.identifier; userid = $providerSelected.userid }
    # Reset choices
    # Add option to change destination again
    Add-Choice -k "target" -d "change script target" -c "$($providerSelected.Provider) $($providerSelected.Name)" -f "Set-Provider" -p $functionProperties
    # build options for specified provider
    switch ($providerSelected.Provider) {
        "Azure" { Add-AzureSteps }
        "AWS" { Add-AWSSteps }
        "GCP" { Add-GloudSteps }
    }
}
function Add-AzureSteps() {
    # Get Azure specific properties from current choice
    $azureProperties = $choices | where-object { $_.key -eq "target" } | select-object -expandproperty callProperties
    $targetGroup = "scw-group-$($azureProperties.userid)"; $SubId = $azureProperties.id
    # if ($showCommands) { Send-Update -content "Azure: Group exists? " }
    $groupExists = Send-Update -content "Azure: Resource group exists?" -cmd "az group exists -g $targetGroup --subscription $SubId" -append
    if ($groupExists -eq "true") {
        Send-Update -content "yes"
        $status.add("group Exists")
    }
    else {
        Send-Update -content "no"
        # $query_locations_command = @{cmd = "az account list-locations --query ""[?metadata.regionCategory=='Recommended']. { name:displayName, id:name }"""; comments = "Getting a list of regions" }
        $azureLocations = Send-Update -content "Azure: Available resource group locations?" -cmd "az account list-locations --query ""[?metadata.regionCategory=='Recommended']. { name:displayName, id:name }""" | Convertfrom-Json
        $counter = 0; $locationChoices = Foreach ($i in $azureLocations) {
            $counter++
            New-object PSCustomObject -Property @{Option = $counter; id = $i.id; name = $i.name }
        }
        $locationChoices | sort-object -property Option | format-table -Property Option, name | Out-Host
        while (-not $locationId) {
            $locationSelected = read-host -prompt "Which region for your resource group?"
            $locationId = $locationChoices | Where-Object -FilterScript { $_.Option -eq $locationSelected } | Select-Object -ExpandProperty id -first 1
            if (-not $locationId) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
        }
        write-host $locationId
    }
}

# Create resource group if needed
    
# Deploy AKS


function Add-AWSSteps() {}
function Add-GloudSteps() {}
function Invoke-Step() {
    # Run steps and return results 
    param(
        [Parameter(Mandatory = $true)]
        [string] $cmd, #What to run
        [string] $note, #Optional comment
        [switch] $append # [$true/$false] pass along append flag
    )
    if ($showCommands) { Send-Update -content "$note-> $cmd" $append }
    return Invoke-Expression $cmd
}
#endregion

#region ---Main

Get-Providers


# Main Menu loop
while ($choices.count -gt 0) {
    $cmd = Get-Choice($choices)
    if ($cmd) {
        Invoke-Expression $cmd.callFunction
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
#endregion
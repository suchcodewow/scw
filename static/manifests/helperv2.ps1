#VSCODE: ctrl/cmd+k+2 folds all functions
#region ---Variables

#Visibility Options
$outputLevel = 0 # [0/1/2] message level to send to screen: debug & extra menu details/info/errors, info/errors, errors
$showCommands = $true # [$true/$false] show cloud commands as they execute
$retainLog = $false # [$true/false] keep written log between executions
#Cloud Options
$useAWS = $false # [$true/false] use AWS
$useAzure = $true # [$true/$false] use Azure
$useGCP = $false # [$true/$false] use GCP

# [DO NOT MODIFY BELOW] Internal variables/setup
[System.Collections.ArrayList]$providerList = @()
[System.Collections.ArrayList]$choices = @()
$script:currentLogEntry = $null
if ($MyInvocation.MyCommand.Name) {
    $logFile = "$(Split-Path $MyInvocation.MyCommand.Name  -LeafBase).log"
    if ((test-path $logFile) -and -not $retainLog) {
        Remove-Item $logFile
    }
}
if ($outputLevel -eq 0) {
    $choiceColumns = @("Option", "description", "current", "key", "callFunction", "callProperties") 
}
else {
    $choiceColumns = @("Option", "description", "current")
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
    if ($cmd) {
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
    #example: Add-Choice -k 'key' -d 'description' -c 'current' -f 'function' -p 'parameters'
    param(
        [string] $k, # key identifying this choice, unique only
        [string] $d, # description of item
        [string] $c, # current selection of item, if applicable
        [string] $f, # function name to call if changing item
        [object] $p # parameters needed in the function
    )
    # If this key exists, delete it and anything that followed
    $keyOption = $choices | Where-Object { $_.key -eq $k } | select-object -expandProperty Option -first 1
    if ($keyOption) {
        $staleOptions = $choices | Where-Object { $_.Option -ge $keyOption }
        $staleOptions | foreach-object { Send-Update -content "Removing $($_.Option) $($_.key)" -type 0; $choices.remove($_) }
    
        #     Send-Update -content "key: '$k' found at option: '$keyOption'. Deleting Option " -type 0 -append
        #     $choices | ForEach-Object { 
        #         if ($_.Option -ge $keyOption) {
        #             $choices.Remove($_);
        #             Send-Update -content "[$($_.key), choices: $($choices.count)] " -type 0 -append 
        #         }
        #         else {
        #             Send-Update "[Skip $($_.key), choices: $($choices.count)] " -type 0 -append
        #         } 
        #     }
        #     Send-Update -content "done" -type 0
    }
    $choice = New-Object PSCustomObject -Property @{
        Option         = $choices.count + 1
        key            = $k
        description    = $d
        current        = $c
        callFunction   = $f
        callProperties = $p
        

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
function Get-Choice() {
    # Present list of options and get selection

    write-output $choices | sort-object -property Option | format-table  $choiceColumns | Out-Host
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
    Add-Choice -k "TARGET" -d "change script target" -c "$($providerSelected.Provider) $($providerSelected.Name)" -f "Set-Provider" -p $functionProperties
    # build options for specified provider
    switch ($providerSelected.Provider) {
        "Azure" { Add-AzureSteps }
        "AWS" { Add-AWSSteps }
        "GCP" { Add-GloudSteps }
    }
}
function Add-AzureResourceGroup($targetGroup) {
    $azureLocations = Send-Update -content "Azure: Available resource group locations?" -cmd "az account list-locations --query ""[?metadata.regionCategory=='Recommended']. { name:displayName, id:name }""" | Convertfrom-Json
    $counter = 0; $locationChoices = Foreach ($i in $azureLocations) {
        $counter++
        New-object PSCustomObject -Property @{Option = $counter; id = $i.id; name = $i.name }
    }
    $locationChoices | sort-object -property Option | format-table -Property Option, name | Out-Host
    while (-not $locationId) {
        $locationSelected = read-host -prompt "Which region for your resource group? <enter> to cancel"
        if (-not $locationSelected) { return }
        $locationId = $locationChoices | Where-Object -FilterScript { $_.Option -eq $locationSelected } | Select-Object -ExpandProperty id -first 1
        if (-not $locationId) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
    }
    Send-Update -content "Azure: Create resource group" -cmd "az group create --name $targetGroup --location $locationId -o none"
    Add-AzureSteps
}
function Remove-AzureResourceGroup($targetGroup) {
    Send-Update -content "Azure: Remove resource group" -cmd "az group delete -n $targetGroup"
    Add-AzureSteps
}
function Add-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -content "Azure: Create AKS Cluster" -cmd "az aks create -g $g -n $c --node-count 1 --node-vm-size 'Standard_B2s' --generate-ssh-keys"
    Get-AKSCluster -g $g -c $c
    Add-AzureSteps
} 
function Remove-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -content "Azure: Remove AKS Cluster" -cmd "az aks delete -g $g -n $c"
    Add-AzureSteps
}
function Get-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -content "Azure: Get AKS Crendentials" -cmd "az aks get-credentials --admin -g $g -n $c --overwrite-existing"
}
function Add-AzureSteps() {
    # Get Azure specific properties from current choice
    $azureProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
    #Resource Group Check
    $targetGroup = "scw-group-$($azureProperties.userid)"; $SubId = $azureProperties.id
    $groupExists = Send-Update -content "Azure: Resource group exists?" -cmd "az group exists -g $targetGroup --subscription $SubId" -append
    if ($groupExists -eq "true") {
        Send-Update -content "yes" -type 0
        Add-Choice -k "AZRG" -d "Delete Resource Group & all content" -c $targetGroup -f "Remove-AzureResourceGroup $targetGroup"
    }
    else {
        Send-Update -content "no" -type 0
        Add-Choice -k "AZRG" -d "Required: Create Resource Group" -c "" -f "Add-AzureResourceGroup $targetGroup"
        return
    }
    #AKS Cluster Check
    $targetCluster = "scw-AKS-$($azureProperties.userid)"
    $aksExists = Send-Update -content "Azure: AKS Cluster exists?" -cmd "az aks show -n $targetCluster -g $targetGroup --query id 2>nul" -append
    if ($aksExists) {
        send-Update -content "yes" -type 0
        Add-Choice -k "AZAKS" -d "Delete AKS Cluster" -c $targetCluster -f "Remove-AKSCluster -c $targetCluster -g $targetGroup"
        Add-Choice -k "AZCRED" -d "Load Cluster Credentials" -f "Get-AKSCluster -c $targetCluster -g $targetGroup"
    }
    else {
        send-Update -content "no" -type 0
        Add-Choice -k "AZAKS" -d "Required: Create AKS Cluster" -c "" -f "Add-AKSCluster -g $targetGroup -c $targetCluster"
    }

}
function Add-AWSSteps() {}
function Add-GloudSteps() {}
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
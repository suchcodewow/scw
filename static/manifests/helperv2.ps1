#region ---Variables

#Settings to Modify
$outputLevel = 0 # [0/1/2] message level to send to screen: debug/info/errors, info/errors, errors
$retainLog = $false # [$true/false] keep written log between executions
$useAWS = $true # [$true/false] use AWS
$useAzure = $true # [$true/$false] use Azure
$useGcloud = $true # [$true/$false] use Gcloud


# [DO NOT MODIFY BELOW] Internal variables/setup
$script:selectedCLI = $false
[System.Collections.ArrayList]$providerList = @()
[System.Collections.ArrayList]$choices = @()
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
function Write-Log {
    # Write to screen/Logging Function
    param(
        [string] $content, # Message content to log/write to screen
        [int] $type, # [0/1/2] log levels respectively: debug/info/errors, info/errors, errors
        [switch] $append # [$true/false] skip the newline (next entry will be on same line)
    )
    $Params = @{}
    Switch ($type) {
        0 { $Params['ForegroundColor'] = "DarkBlue"; $start = "[.]" }
        1 { $Params['ForegroundColor'] = "DarkGreen"; $start = "[>]" }
        2 { $Params['ForegroundColor'] = "DarkRed"; $start = "[X]" }
        default { $Params['ForegroundColor'] = "Gray"; $start = "" }
    }
    if ($currentLogEntry) { $screenOutput = $content } else { $screenOutput = "   $start $content" }
    if ($append) { $Params['NoNewLine'] = $true; $script:currentLogEntry = "$script:currentLogEntry$content"; }
    if (-not $append) {
        #This is the last item in-line.  Write it out if log exists
        if ($logFile) {
            "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $currentLogEntry$content" | out-file $logFile -Append
        }
        #Reset inline recording
        $script:currentLogEntry = $null
    }
    
    if ($type -ge $outputLevel) {
        #write-host -ForegroundColor $color  $(if ($append) { @{NoNewLine } }) "   $start $content"
        write-host @Params $screenOutput
    }
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
        Write-Log -content "key: '$k' found at option: '$($keyOption.Option)'. Deleting Option " -append
        $choices | ForEach-Object { if ($_.Option -ge $keyOption.Option) { $choices.Remove($_); Write-Log -content "$($_.Option), " -type 0 -append } }
        Write-Log -content "done"
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

function Add-Provider($provider) {
    #TODO match Add-Choice Params
    #---Add an option selector to item then add to provider list
    $provider | Add-Member -MemberType NoteProperty -Name Option -value $($providerList.count + 1)
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
    Write-Log -content "Gathering provider options: " -type 1 -append
    $providerList.Clear()
    # Check for AZURE subscritions
    if ($useAzure) {
        if (get-command 'az' -ea SilentlyContinue) {
            Write-Log -content "Azure... " -type 1 -append
            $azureSignedIn = az ad signed-in-user show 2>$null 
        }
        else { Write-Log -content "Azure... " -type 2 -append }
        if ($azureSignedIn) {
            #Azure connected, get current subscription
            $currentAccount = az account show --query 'id' | Convertfrom-Json
            $allAccounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
            foreach ($i in $allAccounts) {
                if ($i.id -eq $currentAccount) { $defaultOption = $true } else { $defaultOption = $false }
                Add-Provider(New-object PSCustomObject -Property @{Provider = "Azure"; Name = "subscription: $($i.name)"; Identifier = $i.id; default = $defaultOption })
            }
        }
    }
    # Check for AWS region
    if ($useAWS) {
        if (get-command 'aws' -ea SilentlyContinue) {
            Write-Log -content "AWS... " -type 1 -append
            $awsSignedIn = aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]' 2>$null 
        }
        else { Write-Log -content "AWS... " -type 2 -append }
        if ($awsSignedIn) {
            Add-Provider(New-object PSCustomObject -Property @{Provider = "AWS"; Name = "region:  $($awsSignedIn)"; Identifier = $awsSignedIn; default = $true })
        }
    }
    # Check for GCLOUD projects
    if ($useGcloud) {
        if (get-command 'gcloud' -ea SilentlyContinue) { Write-Log -content "Gcloud... " -type 1 -append; $gcloudSignedIn = gcloud config get-value project -quiet 2>$null }
        else { Write-Log -content "Gcloud... " -type 2 -append }
        if ($gcloudSignedIn) {
            $currentProject = gcloud config get-value project
            $allProjects = gcloud projects list --format=json | Convertfrom-Json
            foreach ($i in $allProjects) {
                if ($i.name -eq $currentProject) { $defaultOption = $true } else { $defaultOption = $false }
                Add-Provider(New-object PSCustomObject -Property @{Provider = "GCP"; Name = "project: $($i.name)"; Identifier = $i.projectNumber; default = $defaultOption })
            }
        }
    
    }
    # Done getting options
    Write-Log -content "Done!" -type 1
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
    $functionProperties = @{provider = $providerSelected.Provider; id = $providerSelected.identifier }
    # Reset choices
    # Add option to change destination again
    Add-Choice -k "target" -d "change script target" -c "$($providerSelected.Provider) $($providerSelected.Name)" -f "Set-Provider" -p $functionProperties
    # build options for specified provider
    switch ($providerSelected.Provider) {
        "Azure" { Add-AzureSteps }
        "AWS" { Add-AWSSteps }
        "Gcloud" { Add-GloudSteps }
    }
}
function Add-AzureSteps() {
    # Create a resource group
    
    # Deploy AKS

}
function Add-AWSSteps() {}
function Add-GloudSteps() {}
#endregion

#region ---Main
#Take action depending on how many Providers were found
Get-Providers
if ($providerList.count -eq 0) { write-output "`nCouldn't find a valid target cloud environment. `nConfirm you have at least one az, aws, or gcloud command available in your path & you are logged in.`n"; exit }
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

# Main Menu loop
while ($choices.count -gt 0) {
    $cmd = Get-Choice($choices)
    if ($cmd) {
        Invoke-Expression $cmd.callFunction
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
#endregion
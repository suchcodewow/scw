#region ---Variables

#Settings to Modify
$outputLevel = 1 # [0/1/2] message level to send to screen: debug/info/errors, info/errors, errors
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
        0 { $Params['ForegroundColor'] = "DarkGray"; $start = [char]26 }
        1 { $Params['ForegroundColor'] = "DarkGreen"; $start = "($([char]16) )" }
        2 { $Params['ForegroundColor'] = "DarkRed"; $start = "(XX)" }
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

function Add-Choice($choice) {
    #Adds a choice to the menu
    $choice | Add-Member -MemberType NoteProperty -Name Option -value $($choices.count + 1)
    [void]$choices.add($choice)
}

function Add-Provider($provider) {
    #---Add an option selector to item then add to provider list
    $provider | Add-Member -MemberType NoteProperty -Name Option -value $($providerList.count + 1)
    [void]$providerList.add($provider)
}
function Get-Choice($cmd_choices) {
    # Present list of options and get selection
    
    write-output $choices | sort-object -property Option | format-table -Property Option, Description, Current | Out-Host
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
                Add-Provider(New-object PSCustomObject -Property @{Provider = "Azure"; Name = $i.name; Identifier = $i.id; default = $defaultOption })
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
            Add-Provider(New-object PSCustomObject -Property @{Provider = "AWS"; Name = $awsSignedIn; default = $true })
        }
    }
    # Check for GCLOUD projects
    if ($useGcloud) {
        if (get-command 'gcloud' -ea SilentlyContinue) { Write-Log -content "Gcloud... " -type 1 -append; $gcloudSignedIn = gcloud config get-value project  2>$null }
        else { Write-Log -content "Gcloud... " -type 2 -append }
        if ($gcloudSignedIn) {
            $currentProject = gcloud config get-value project
            $allProjects = gcloud projects list --format=json | Convertfrom-Json
            foreach ($i in $allProjects) {
                if ($i.name -eq $currentProject) { $defaultOption = $true } else { $defaultOption = $false }
                Add-Provider(New-object PSCustomObject -Property @{Provider = "GCP"; Name = $i.name; Identifier = $i.projectNumber; default = $defaultOption })
            }
        }
    }
    # Done getting options
    Write-Log -content "Done!" -type 1
}
#endregion

#region ---Main
#Take action depending on how many Providers were found
Get-Providers
if ($providerList.count -eq 0) { write-output "`nCouldn't find a valid target cloud environment. `nConfirm you have at least one az, aws, or gcloud command available in your path & you are logged in.`n"; exit }
#If there's one default, set it as the current option
$providerDefault = $providerList | Where-Object default -eq $true
if ($providerDefault.count -eq 1) {
    # One default option, select it and move on (most likely for workshop running a cloud shell)
    Add-Choice(New-object PSCustomObject -Property @{Key = "target"; Description = "Change Script Target"; Current = " $($providerDefault[0].Provider) -> $($providerDefault[0].Name)" })
}
else {
    # Somebody's popular in cloud land. (user running script locally & logged into multiple clouds)  Need to prompt for correct cloud environment
}

# Main Menu loop
while ($true) {
    $cmd = Get-Choice($choices)
    if ($cmd) {
        # Invoke-Choice($cmd)
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
#endregion
#Option, Key, Description, Current, Function, Properties

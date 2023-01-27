# VSCODE: ctrl/cmd+k+1 folds all functions, ctrl/cmd+k+j unfold all functions. Check '.vscode/launch.json' for any current parameters
param (
    [switch] $help, # show other command options and exit
    [switch] $verbose, # default output level is 1 (info/errors), use -v for level 0 (debug/info/errors)
    [switch] $cloudCommands, # enable to show commands
    [switch] $logReset, # enable to reset log between runs
    [int] $users, # Users to create, switches to multiuser mode
    [string] $network, # Allows multiple attendees to use the same CloudFormation VPC for faster deployment
    [switch] $aws, # use aws
    [switch] $azure, # use azure
    [switch] $gcp # use gcp
)

# Core Functions
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
    if ($help) { Get-Help }
    if ($verbose) { $script:outputLevel = 0 } else { $script:outputLevel = 1 }
    if ($cloudCommands) { $script:showCommands = $true } else { $script:showCommands = $false }
    if ($logReset) { $script:retainLog = $false } else { $script:retainLog = $true }
    if ($aws) { $script:useAWS = $true }
    if ($azure -eq $true) { $script:useAzure = $true }
    if ($gcp) { $script:useGCP = $true }
    # If no cloud selected, use all
    if ((-not $useAWS) -and (-not $useAzure) -and (-not $useGCP)) { write-host "setting all"; $script:useAWS = $true; $script:useAzure = $true; $script:useGCP = $true }
    # Set Script level variables and housekeeping stuffs
    [System.Collections.ArrayList]$script:providerList = @()
    [System.Collections.ArrayList]$script:choices = @()
    $script:currentLogEntry = $null
    # Any yaml here will be available for installation- file should be namespace (i.e. x.yaml = x namescape)
    $script:yamlList = @("https://raw.githubusercontent.com/suchcodewow/dbic/main/deploy/dbic.yaml" )
    #$script:ProgressPreference = "SilentlyContinue"
    if ($scriptPath) {
        $script:logFile = "$($scriptPath).log"
        Send-Update -t 0 -c "Log: $logFile"
        if ((test-path $logFile) -and -not $retainLog) {
            Remove-Item $logFile
        }
        $script:configFile = "$($scriptPath).conf"
        Send-Update -t 0 -c "Config: $configFile"
    }
    if ($outputLevel -eq 0) {
        $script:choiceColumns = @("Option", "description", "current", "key", "callFunction", "callProperties")
        $script:providerColumns = @("option", "provider", "name", "identifier", "userid", "default")
    }
    else {
        $script:choiceColumns = @("Option", "description", "current")
        $script:providerColumns = @("option", "provider", "name")
    }
    # Load preferences/settings.  Access with $config variable anywhere.  Set-Prefs automatically updates $config variable and saves to file
    # Set with Set-Prefs function
    if ($scriptPath) {
        $script:configFile = "$scriptPath.conf"
        if (Test-Path $configFile) {
            Send-Update -c "Reading config" -t 0
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
    Set-Prefs -k UserCount -v $users
    write-host

}
function Set-Prefs {
    param(
        $u, # Add this value to a user's settings (mostly for mult-user setup sweetness)
        $k, # key
        $v # value
    )
    # Create Users hashtable if needed
    if (-not $config.Users) { $config.Users = @{} }
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
function Add-Choice() {
    #example: Add-Choice -k 'key' -d 'description' -c 'current' -f 'function' -p 'parameters'
    param(
        [string] $key, # key identifying this choice, unique only
        [string] $description, # description of item
        [string] $current, # current selection of item, if applicable
        [string] $function, # function name to call if changing item
        [object] $parameters # parameters needed in the function
    )
    # If this key exists, delete it and anything that followed
    $keyOption = $choices | Where-Object { $_.key -eq $key } | select-object -expandProperty Option -first 1
    if ($keyOption) {
        $staleOptions = $choices | Where-Object { $_.Option -ge $keyOption }
        $staleOptions | foreach-object { Send-Update -c "Removing $($_.Option) $($_.key)" -t 0; $choices.remove($_) }
    }
    $choice = New-Object PSCustomObject -Property @{
        Option         = $choices.count + 1
        key            = $key
        description    = $description
        current        = $current
        callFunction   = $function
        callProperties = $parameters
        

    }
    [void]$choices.add($choice)
}
function Get-Choice() {


    # Present list of options and get selection

    write-output $choices | sort-object -property Option | format-table  $choiceColumns | Out-Host
    $cmd_selected = read-host -prompt "Which option to execute? [<enter> to quit]"
    if (-not($cmd_selected)) {

        write-host "buh bye!`r`n" | Out-Host
        exit
    }
    if ($cmd_selected -eq 0) { Get-Quote }
    return $choices | Where-Object { $_.Option -eq $cmd_selected } | Select-Object  -first 1 
}
function Get-Quote {
    $list = @("That, I DID know.", "I was having twelve percent of a moment.", "OMG, that was really violent!", "Hang on. I got you, Kid.", "And sometimes, I take out the trash.")
    write-host
    Get-Random -InputObject $list | Out-Host
}
function Get-Joke {
    $allJokes = @("Knock Knock (Who's there?);Little old lady (Little old lady who?);I didn't know you could yoddle!",
        "What did the fish say when he ran into the wall?;DAM!",
        "What do you call a fish with no eyes?;Dead!",
        "What do you get when you cross a rhetorical question and a joke? (I don't know, what?);...",
        "There are 3 types of people in this world.;Those who can count. And those who can't.",
        "I sold my vacuum the other day.;All it was doing was collecting dust.",
        "My new thesaurus is terrible.;Not only that, but it's terrible.",
        "What do you call a psychic little person who escaped from prison?;A small medium at large!",
        "What did Blackbeard say when he turned 80?; Aye, Matey!",
        "What's the best part about living in Switzerland?;I don't know- but the flag's a big plus!",
        "What do you call a bear in a bar?;Lost!",
        "I can cut a piece of in half just by looking at it.;You might not believe me, but I saw it with my own eyes.",
        "A limbo champion walks into a bar.;He loses.",
        "What's the leading cause of dry skin?;Towels.",
        "When does a joke become a Dad joke?;When it becomes apparent.")
    return (Get-Random $allJokes).split(";")
}
function Get-Help {
    # Hey let's do Get Help! -What? Get Help! -No.
    write-host "Options:"
    write-host "                    -v Show debug/trivial messages"
    write-host "                    -c Show cloud commands as they run"
    write-host "                    -l Reset the log on each run"
    write-host "    -aws, -azure, -gcp Use specific cloud only (can be combined)"
    exit
}
function Get-UserName {
    $Prefix = @(
        "abundant",
        "delightful",
        "high",
        "nutritious",
        "square",
        "adorable",
        "dirty",
        "hollow",
        "obedient",
        "steep",
        "agreeable",
        "drab",
        "hot",
        "living",
        "dry",
        "hot",
        "odd",
        "straight",
        "dusty",
        "huge",
        "strong",
        "beautiful",
        "eager",
        "icy",
        "orange",
        "substantial",
        "better",
        "early",
        "immense",
        "panicky",
        "sweet",
        "bewildered",
        "easy",
        "important",
        "petite",
        "swift",
        "big",
        "elegant",
        "inexpensive",
        "plain",
        "tall",
        "embarrassed",
        "itchy",
        "powerful",
        "tart",
        "black",
        "prickly",
        "tasteless",
        "faint",
        "jolly",
        "proud",
        "teeny",
        "brave",
        "famous",
        "kind",
        "purple",
        "tender",
        "breeze",
        "fancy",
        "broad",
        "fast",
        "quaint",
        "thoughtful",
        "tiny",
        "bumpy",
        "light",
        "quiet",
        "calm",
        "fierce",
        "little",
        "rainy",
        "careful",
        "lively",
        "rapid",
        "uneven",
        "chilly",
        "flaky",
        "interested",
        "flat",
        "relieved",
        "unsightly",
        "clean",
        "fluffy",
        "loud",
        "uptight",
        "clever",
        "freezing",
        "vast",
        "clumsy",
        "fresh",
        "lumpy",
        "victorious",
        "cold",
        "magnificent",
        "warm",
        "colossal",
        "gentle",
        "mammoth",
        "salty",
        "gifted",
        "scary",
        "gigantic",
        "massive",
        "scrawny",
        "glamorous",
        "screeching",
        "whispering",
        "cuddly",
        "messy",
        "shallow",
        "curly",
        "miniature",
        "curved",
        "great",
        "modern",
        "shy",
        "wide-eyed",
        "witty",
        "damp",
        "grumpy",
        "mysterious",
        "skinny",
        "wooden",
        "handsome",
        "narrow",
        "worried",
        "deafening",
        "happy",
        "nerdy",
        "heavy",
        "soft",
        "helpful",
        "noisy",
        "sparkling",
        "young",
        "delicious"
    );
      
    $Name = @(
        "apple",
        "seashore",
        "badge",
        "flock",
        "sidewalk",
        "basket",
        "basketball",
        "furniture",
        "smoke",
        "battle",
        "geese",
        "bathtub",
        "beast",
        "ghost",
        "nose",
        "beetle",
        "giraffe",
        "sidewalk",
        "beggar",
        "governor",
        "honey",
        "stage",
        "bubble",
        "hope",
        "station",
        "bucket",
        "income",
        "cactus",
        "island",
        "throne",
        "cannon",
        "cow",
        "judge",
        "toothbrush",
        "celery",
        "lamp",
        "turkey",
        "cellar",
        "lettuce",
        "umbrella",
        "marble",
        "underwear",
        "coach",
        "month",
        "vacation",
        "coast",
        "vegetable",
        "crate",
        "ocean",
        "plane",
        "donkey",
        "playground",
        "visitor",
        "voyage"
    )      
    return "$(Get-Random -inputObject $Prefix)$(Get-Random -inputObject $Name)"
}

# Provider Functions
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
function Get-Providers() {
    Send-Update -content "Gathering provider options... " -t 1 -a
    $providerList.Clear()
    # AZURE
    if ($useAzure) {
        Send-Update -content "Azure:" -t 1 -a
        if (get-command 'az' -ea SilentlyContinue) {
            $azureSignedIn = az ad signed-in-user show 2>$null 
        }
        else { Send-Update -content "NA " -t 1 -a }
        if ($azureSignedIn) {
            #Azure connected, get current subscription
            $currentAccount = az account show --query '{name:name,email:user.name,id:id}' | Convertfrom-Json
            $allAccounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
            foreach ($i in $allAccounts) {
                $Params = @{}
                if ($i.id -eq $currentAccount.id) { $Params['d'] = $true }
                Add-Provider @Params -p "Azure" -n "subscription: $($i.name)" -i $i.id -u (($currentAccount.email).split("@")[0]).replace(".", "").ToLower()
            }
        }
        Send-Update -content "$($allAccounts.count) " -a -t 1
    }
    # AWS
    if ($useAWS) {
        Send-Update -content "AWS:" -t 1 -a
        if (get-command 'aws' -ea SilentlyContinue) {
            # below doesn't work for non-admin accounts
            # instead, check environment variables for a region
            $awsRegion = $env:AWS_REGION
            if (-not $awsRegion) {
                # No region in environment variables, trying pulling from local config
                $awsRegion = aws configure get region
            }
            if ($awsRegion) {
                # For workshops, using ARN maybe?
                $arnCheck = (aws sts get-caller-identity --output json 2>$null | Convertfrom-JSon).Arn
                if ($arnCheck) {
                    $awsSignedIn = $arnCheck.split("/")[1]
                }
                # Old Method with Email- switched to ARN
                # (aws sts get-caller-identity --output json 2>$null | Convertfrom-JSon).UserId -match "-(.+)\.(.+)@" 1>$null
                # if ($Matches.count -eq 3) {
                #     $awsSignedIn = "$($Matches[1])$($Matches[2])"
                # }
                else {
                    # No Email- try alternate method to get a unique identifier
                    $awsSts = aws sts get-caller-identity --output json 2>$null | Convertfrom-JSon
                    if ($awsSts) {
                        $awsSignedIn = $awsSts.UserId.subString(0, 6)
                    }
                }
            }
            if ($awsSignedIn) {
                Add-Provider -d -p "AWS" -n "$awsRegion/$($awsSignedIn.ToLower())" -i $awsRegion -u $($awsSignedIn.ToLower())
                Send-Update -c "1 " -a -t 1
            }
            else {
                # Total for AWS is just 1 or 0 for now so use this toggle
                Send-Update -c "0 " -a -t 1
            }
        }
        else { Send-Update -c "NA " -t 1 -a }
    }
    # GCP
    if ($useGCP) {
        Send-Update -c "GCP:" -t 1 -a
        if (get-command 'gcloud' -ea SilentlyContinue) {
            $accounts = gcloud auth list --format="json" | ConvertFrom-Json 
        }
        else { Send-Update -content "NA " -t 1 -a }
        if ($accounts.count -gt 0) {
            foreach ($i in $accounts) {
                $Params = @{}
                if ($i.status -eq "ACTIVE") { $Params['d'] = $true } 
                Add-Provider @Params -p "GCP" -n "account: $($i.account)" -i $i.account -u (($i.account).split("@")[0]).replace(".", "").ToLower()
            }
        }
        Send-Update -c "$($accounts.count) " -a -t 1
        
    }
    # Done getting options
    Send-Update -c "Done!" -type 1
    #Take action based on # of providers
    if ($providerList.count -eq 0) { write-output "`nCouldn't find a valid target cloud environment. `nLogin to Azure (az login), AWS, or GCP (gcloud auth login) and retry.`n"; exit }
    #If there's one default, set it as the current option
    $providerDefault = $providerList | Where-Object default -eq $true
    if ($providerDefault.count -eq 1) {
        # One provider- preload it
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
        write-output $providerList | sort-object -property Option | format-table $providerColumns | Out-Host
        $newProvider = read-host -prompt "Which environment to use? <enter> to cancel"
        if (-not($newProvider)) {
            return
        }
        $providerSelected = $providerList | Where-Object { $_.Option -eq $newProvider } | Select-Object  -first 1
        if (-not $providerSelected) {
            write-host -ForegroundColor red "`r`nY U no pick valid option?" 
        }
    }
    $functionProperties = @{provider = $providerSelected.Provider; id = $providerSelected.identifier.tolower(); userid = $providerSelected.userid.tolower() }

    # Reset choices
    # Add option to change destination again
    Add-Choice -k "TARGET" -d "Switch Cloud Provider" -c "$($providerSelected.Provider) $($providerSelected.Name)" -f "Set-Provider" -p $functionProperties
    # build options for specified provider
    switch ($providerSelected.Provider) {
        "Azure" {
            # Set the Azure subscription
            Send-Update -t 1 -c "Azure: Set Subscription" -r "az account set --subscription $($providerSelected.identifier)"
            Add-AzureSteps 
        }
        "AWS" {
            Send-Update -t 1 -c "AWS: Set region"
            Add-AWSSteps 
        }
        "GCP" { 
            # set the GCP Project
            Send-Update -t 1 -c "GCP: Set Project" -r "gcloud config set account '$($providerSelected.identifier)'"
            Add-GCPSteps 
        }
    }
}

# Azure Functions
function Add-AzureSteps() {
    # Get Azure specific properties from current choice
    $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
    #Resource Group Check
    $targetGroup = "scw-group-$($userProperties.userid)"; $SubId = $userProperties.id
    $groupExists = Send-Update -t 1 -content "Azure: Resource group exists?" -run "az group exists -g $targetGroup --subscription $SubId" -append
    if ($groupExists -eq "true") {
        Send-Update -content "yes" -type 1
        Add-Choice -k "AZRG" -d "Delete Resource Group & all content" -c $targetGroup -f "Remove-AzureResourceGroup $targetGroup"
    }
    else {
        Send-Update -content "no" -type 1
        Add-Choice -k "AZRG" -d "Required: Create Resource Group" -c "" -f "Add-AzureResourceGroup $targetGroup"
        return
    }
    #AKS Cluster Check
    $targetCluster = "scw-AKS-$($userProperties.userid)"
    $aksExists = Send-Update -t 1 -e -content "Azure: AKS Cluster exists?" -run "az aks show -n $targetCluster -g $targetGroup --query id" -append
    if ($aksExists) {
        send-Update -content "yes" -type 1
        Add-Choice -k "AZAKS" -d "Delete AKS Cluster" -c $targetCluster -f "Remove-AKSCluster -c $targetCluster -g $targetGroup"
        #Add-Choice -k "AZCRED" -d "Refresh k8s credential" -f "Get-AKSCluster -c $targetCluster -g $targetGroup"
        #Refresh cluster credentials
        Get-AKSCluster -g $targetGroup -c $targetCluster
        #We have a cluster so add common things to do with it
        Add-CommonSteps
    }
    else {
        send-Update -content "no" -type 1
        Add-Choice -k "AZAKS" -d "Required: Create AKS Cluster" -c "" -f "Add-AKSCluster -g $targetGroup -c $targetCluster"
    }
}
function Add-AzureResourceGroup($targetGroup) {
    $azureLocations = Send-Update -t 1 -content "Azure: Available resource group locations?" -run "az account list-locations --query ""[?metadata.regionCategory=='Recommended']. { name:displayName, id:name }""" | Convertfrom-Json
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
    Send-Update -t 1 -c "Azure: Create Resource Group" -run "az group create --name $targetGroup --location $locationId -o none"
    Add-AzureSteps
}
function Remove-AzureResourceGroup($targetGroup) {
    Send-Update -t 1 -content "Azure: Remove Resource Group" -run "az group delete -n $targetGroup"
    Add-AzureSteps
}
function Add-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -t 1 -content "Azure: Create AKS Cluster" -run "az aks create -g $g -n $c --node-count 1 --node-vm-size 'Standard_D4s_v5' --generate-ssh-keys"
    Get-AKSCluster -g $g -c $c
    Add-AzureSteps
    Add-CommonSteps
} 
function Remove-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -t 1 -content "Azure: Remove AKS Cluster" -run "az aks delete -g $g -n $c"
    Add-AzureSteps
}
function Get-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -t 1 -o -e -c "Azure: Get AKS Crendentials" -run "az aks get-credentials --admin -g $g -n $c --overwrite-existing"
}

# AWS Multi-User Functions
function Add-AWSUsers() {
    # Generate User Accounts
    Foreach ($user in $config.Users.Keys) {
        if (-not $config.Users.$user.userID) {
            $userID = Send-Update -r "aws iam create-user --user-name $user" -c "Create $user" -t 1 --output json | ConvertFrom-Json
            Set-Prefs -u $user -k userId -v $($userID.User.UserId)
            # Use standard password
            Send-Update -r "aws iam create-login-profile --user-name $user --password 1Dynatrace#" -c "Add Password $user" -t 1 -o
            # Assign to group(s)
            Send-Update -r "aws iam add-user-to-group --group-name Attendees --user-name $user" -c "Add group $user" -t 1 -o
        }
    }
}
function Add-AWSMultiBits() {
    Foreach ($user in $config.Users.Keys) {
        Set-Prefs -u $user -k AWSregion -v $($config.AWSregion)
        Set-Prefs -u $user -k AWSroleName -v "scw-awsrole-$user"
        set-Prefs -u $user -k AWSnodeRoleName -v "scw-awsngrole-$user"
        set-prefs -u $user -k AWScfstack -v "scw-AWSstack-$user"
        Add-AWSComponents -u $user
        $roleExists = Send-Update -t 1 -e -c "Checking for AWS Component: cluster role" -r "aws iam get-role --region $($config.Users.$user.AWSregion) --role-name $($config.Users.$user.AWSroleName) --output json" -a | Convertfrom-Json
        if ($roleExists) { Set-Prefs -u $user -k AWSclusterRoleArn -v $($roleExists.Role.Arn) }
        $nodeRoleExists = Send-Update -t 1 -e -c "Checking for AWS Component: node role" -r "aws iam get-role --region $($config.Users.$user.AWSregion) --role-name $($config.Users.$user.AWSnodeRoleName) --output json" -a | Convertfrom-Json
        if ($nodeRoleExists) { Set-Prefs -u $user -k AWSnodeRoleArn -v $($nodeRoleExists.Role.Arn) }
        $cfstackExists = Send-Update -a -e -t 1 -c "Checking for Cloudformation Stack (4 items)" -r "aws cloudformation describe-stacks --region $($config.Users.$user.AWSregion) --stack-name $($config.Users.$user.AWScfstack) --output json" | Convertfrom-Json
        if ($cfstackExists.Stacks) {
            Set-Prefs -u $user -k AWScfstackArn -v $($cfstackExists.Stacks.StackId)
            # $cfSecurityGroup = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SecurityGroups" } | Select-Object -expandproperty OutputValue
            # $cfSubnets = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SubnetIds" } | Select-Object -expandproperty OutputValue
            # $cfVpicId = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "VpcId" } | Select-Object -ExpandProperty OutputValue
 
        }

    }
}
function Remove-AWSMultiBIts() {
    Foreach ($user in $config.Users.Keys) {
        Remove-AWSComponents -u $user
    }
}
function Add-AWSEverything() {
    Write-Host "Running attendee setup"
    $AWScfStack = "scw-AWSstack"
    aws cloudformation create-stack --stack-name $awsCFStack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml
    While ($cfstackReady -ne "CREATE_COMPLETE") {
        $cfstackReady = aws cloudformation describe-stacks --stack-name $awsCFStack --query Stacks[*].StackStatus --output text
        write-host "CloudFormation Stack: $cfstackReady"
        Start-Sleep -s 5
    }
    # Kick off process for all users
    $config.Users.Keys | Foreach-Object -Parallel {
        # Every parallel process runs in a separate shell, so defining everything in-line for now.
        if ($IsWindows) {
            # Build a multi-cloud/multi-OS script they said.  It will be FUN, they said...
            $ekspolicy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"eks.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
            $ec2policy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"ec2.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
        }
        else {
            $ekspolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["eks.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
            $ec2policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
        }
        # Get Cloudformation stack info
        $AWScfStack = "scw-AWSstack"
        $cfstackExists = aws cloudformation describe-stacks --stack-name $AWScfstack --output json | Convertfrom-Json
        $AWScfstackArn = $cfstackExists.Stacks.StackId
        $AWSsecurityGroup = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SecurityGroups" } | Select-Object -expandproperty OutputValue
        $AWSsubnets = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SubnetIds" } | Select-Object -expandproperty OutputValue
        $AWSvpcId = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "VpcId" } | Select-Object -ExpandProperty OutputValue
        $user = $_
        # Set variables
        $AWSRoleName = "scw-awsrole-$user"
        $AWSNodeRoleName = "scw-awsngrole-$user"
        $AWScluster = "scw-AWS-$user"
        $AWSnodegroup = "scw-AWSNG-$user"
        # Create User
        aws iam create-user --user-name $user
        aws iam create-login-profile --user-name $user --password 1Dynatrace#
        aws iam add-user-to-group --group-name Attendees --user-name $user
        # Add components for User
        # aws iam create-role --role-name $awsRoleName --assume-role-policy-document ""$ekspolicy"" --output json | ConvertFrom-Json
        # aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $awsRoleName
        # aws iam create-role --role-name $awsNodeRoleName --assume-role-policy-document ""$ec2policy"" --output json | ConvertFrom-Json
        # aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name $awsNodeRoleName
        # aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name $awsNodeRoleName
        # aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name $awsNodeRoleName
        #Add Cloudformation

        # Collect Results
        # $roleExists = aws iam get-role --role-name $AWSroleName --output json | Convertfrom-Json
        # $AWSclusterRoleArn = $roleExists.Role.Arn
        # $nodeRoleExists = aws iam get-role --role-name $AWSnodeRoleName --output json | Convertfrom-Json
        # $AWSnodeRoleArn = $nodeRoleExists.Role.Arn
        # # Create EKS Cluster
        # aws eks create-cluster --name $AWScluster --role-arn $AWSclusterRoleArn --resources-vpc-config "subnetIds=$AWSsubnets,securityGroupIds=$AWSsecurityGroup"
        # While ($clusterExists.cluster.status -ne "ACTIVE") {
        #     $clusterExists = aws eks describe-cluster  --name $AWScluster --output json | ConvertFrom-Json
        #     write-host "$user $($clusterExists.cluster.status)"
        #     Start-Sleep -s 15
        # }
        # # Create NodeGroup
        # $subnets = $AWSsubnets.replace(",", " ")
        # invoke-expression "aws eks create-nodegroup --cluster-name $AWScluster --nodegroup-name $AWSnodegroup --node-role $AWSnodeRoleArn --subnets $subnets --scaling-config minSize=1,maxSize=1,desiredSize=1 --instance-types t3.xlarge"
        # While ($nodeGroupExists.nodegroup.status -ne "ACTIVE") {
        #     $nodeGroupExists = aws eks describe-nodegroup  --cluster-name $AWScluster --nodegroup-name $AWSnodegroup --output json | ConvertFrom-Json
        #     write-host "$user nodegroup $($nodeGroupExists.nodegroup.status)"
        #     Start-Sleep -s 15
        # }
    } -ThrottleLimit 10
    exit
}

# AWS Functions
function Add-AWSSteps() {
    if ($($config.UserCount)) {
        # Parallel Processing is a bit limited.  Using this cludgy process for now.
        Add-AWSEverything
    }
    else {
        # Regular single user session
        $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
        $userid = $userProperties.userid
        # Save region to use in commands
        Set-Prefs -k AWSregion -v $($userProperties.id)
        # Counter to determine how many AWS components are ready.  AWS is really annoying.
        $componentsReady = 0
        $targetComponents = 0
        # Component: AWS cluster role
        $targetComponents++
        Set-Prefs -k AWSroleName -v "scw-awsrole-$userid"
        $roleExists = Send-Update -t 1 -e -c "Checking for AWS Component: cluster role" -r "aws iam get-role --region $($config.AWSregion) --role-name $($config.AWSroleName) --output json" -a | Convertfrom-Json
        if ($roleExists) {
            Send-Update -c "AWS cluster role: exists" -t 1
            Set-Prefs -k AWSclusterRoleArn -v $($roleExists.Role.Arn)
            $componentsReady++
        }
        else {
            Send-Update -c "AWS cluster role: not found" -t 1
            Set-Prefs -k AWSclusterRoleArn
        }
        # Component: AWS node role
        $targetComponents++
        set-Prefs -k AWSnodeRoleName -v "scw-awsngrole-$userid"
        $nodeRoleExists = Send-Update -t 1 -e -c "Checking for AWS Component: node role" -r "aws iam get-role --region $($config.AWSregion) --role-name $($config.AWSnodeRoleName) --output json" -a | Convertfrom-Json
        if ($nodeRoleExists) {
            Send-Update -c "AWS node role: exists" -t 1
            Set-Prefs -k AWSnodeRoleArn -v $($nodeRoleExists.Role.Arn)
            $componentsReady++
        }
        else {
            Send-Update -c "AWS node role: not found" -t 1
            Set-Prefs -k AWSnodeRoleArn
        }
        # Components: Cloudformation, vpc, subnets, and security group
        
        if ($network) {
            # use group Cloudformation VPC
            set-prefs -k AWScfstack -v $network
        }
        else {
            set-prefs -k AWScfstack -v "scw-AWSstack-$userid"
            $targetComponents = $targetComponents + 4

        }
        $cfstackExists = Send-Update -a -e -t 1 -c "Checking for Cloudformation Stack (4 items)" -r "aws cloudformation describe-stacks --region $($config.AWSregion) --stack-name $($config.AWScfstack) --output json" | Convertfrom-Json
        if ($cfstackExists.Stacks) {
            Send-Update -c "Cloudformation: exists" -t 1
            Set-Prefs -k AWScfstackArn -v $($cfstackExists.Stacks.StackId)
            if (-not $network) { $componentsReady++ }
            # Get Outputs needed for cluster creation
            $cfSecurityGroup = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SecurityGroups" } | Select-Object -expandproperty OutputValue
            $cfSubnets = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SubnetIds" } | Select-Object -expandproperty OutputValue
            $cfVpicId = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "VpcId" } | Select-Object -ExpandProperty OutputValue
            # Component: SecurityGroup
            if ($cfSecurityGroup) {
                Send-Update -t 1 -c "CF Security Group: exists"
                Set-Prefs -k AWSsecurityGroup -v $cfSecurityGroup
                if (-not $network) { $componentsReady++ }
            }
            else {
                Send-Update -c "CF Security Group: not found"
                Set-Prefs -k AWSsecurityGroup 
            }
            # Component: Subnets
            if ($cfSubnets) {
                Send-Update -t 1 -c "CF Subnets: exists"
                Set-Prefs -k AWSsubnets -v $cfSubnets
                if (-not $network) { $componentsReady++ }
            }
            else {
                Send-Update -t 1 -c "CF Subnets: not found"
                Set-Prefs -k AWSsubnets
            }
            # Component: VPC
            if ($cfVpicId) {
                Send-Update -t 1 -c "CF VPC Id: exists"
                Set-Prefs -k AWSvpcId -v $cfVpicId
                if (-not $network) { $componentsReady++ }
            }
            else {
                Send-Update -t 1 -c "CF VPC ID: not found"
                Set-Prefs -k AWSvpcId
            }
        }
        else {
            Send-Update -c "Cloudformation: not found" -t 1
            Set-Prefs -k AWScfstackArn
            Set-Prefs -k AWSsecurityGroup
            Set-Prefs -k AWSsubnets
            Set-Prefs -k AWSvpcId
        }
        # Add component choices
        if ($componentsReady -eq $targetComponents) {
            # Need to confirm total components and if enough, provide remove components option and create cluster option
            Add-Choice -k "AWSBITS" -d "Remove AWS Components" -c "$componentsReady/$targetComponents deployed" -f "Remove-AWSComponents"
        }
        elseif ($componentsReady -eq 0) {
            # No components yet.  Add option to create
            Add-Choice -k "AWSBITS" -d "Required: Create AWS Components" -f "Add-AwsComponents"
        }
        else {
            # Some components installed.  Offer removal option
            Add-Choice -k "AWSBITS" -d "Remove Partial Components" -c "$componentsReady/$targetComponents deployed" -f "Remove-AWSComponents"
        }
        # Check for existing cluster.
        Set-Prefs -k AWScluster -v "scw-AWS-$userid"
        Set-Prefs -k AWSnodegroup -v "scw-AWSNG-$userid"
        $clusterExists = Send-Update -t 1 -a -e -c "Check for EKS Cluster" -r "aws eks describe-cluster --name $($config.AWScluster) --output json" | ConvertFrom-Json
        if ($clusterExists) {
            if ($clusterExists.cluster.status -eq "CREATING") { Add-AWSCluster }
            Send-Update -c "AWS Cluster: exists" -t 1
            Set-Prefs -k AWSclusterArn -v $($clusterExists.cluster.arn)
            Add-Choice -k "AWSEKS" -d "Remove EKS Cluster" -c $($config.AWScluster) -f "Remove-AWSCluster"
            Send-Update -c "Updating Cluster Credentials" -r "aws eks update-kubeconfig --name $($config.AWScluster)" -t 1 -o
            if ($componentsReady -eq $targetComponents) {
                # Cluster is ready and all components ready
                Add-CommonSteps
            }
        }
        else {
            Send-Update -c "AWS Cluster: not found" -t 1
            if ($componentsReady -eq $targetComponents) {
                # Add cluster deployment option if all components are ready
                Add-Choice -k "AWSEKS" -d "Required: Deploy EKS Cluster" -f "Add-AWSCluster"
            }
        }
    }
}
function Add-AWSComponents {
    param (
        [string] $userID # override user in multi-deploy scenarios
    )
    if ($userID) {
        #Override main user settings with sub-user list
        $awsRegion = $($config.Users.$userID.AWSregion)
        $awsRoleName = $($config.Users.$userID.AWSroleName)
        $awsNodeRoleName = $($config.Users.$userID.AWSnodeRoleName)
        $awsCFStack = $($config.USers.$userID.AWScfstack)
    }
    else {
        $awsRegion = $($config.AWSregion)
        $awsRoleName = $($config.AWSroleName)
        $awsNodeRoleName = $($config.AWSnodeRoleName)
        $awsCFStack = $($config.AWScfstack)
    }
    # Create the cluster ARN role and add the policy
    if ($IsWindows) {
        # Build a multi-cloud/multi-OS script they said.  It will be FUN, they said...
        $ekspolicy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"eks.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
        $ec2policy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"ec2.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
    }
    else {
        $ekspolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["eks.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
        $ec2policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
    }
    $iamClusterRole = Send-Update -t 1 -c "Create Cluster Role" -r "aws iam create-role --region $awsRegion --role-name $awsRoleName --assume-role-policy-document '$ekspolicy'" | Convertfrom-Json
    if ($iamClusterRole.Role.Arn) {
        Send-Update -t 1 -c "Attach Cluster Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $awsRoleName"
    }
    # Create the node role ARN and add 2 policies.  AWS makes me so sad on the inside.
    $iamNodeRole = Send-Update -c "Create Nodegroup Role" -r "aws iam create-role --region $awsRegion --role-name $awsNodeRoleName --assume-role-policy-document '$ec2policy'" -t 1 | Convertfrom-Json
    if ($iamNodeRole.Role.Arn) {
        Send-Update -c "Attach Worker Node Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name $awsNodeRoleName" -t 1
        Send-Update -c "Attach EC2 Container Registry Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name $awsNodeRoleName" -t 1
        Send-Update -c "Attach CNI Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name $awsNodeRoleName" -t 1
    }
    # Create VPC with Cloudformation
    if (-not  $network) {
        Send-Update -t 1 -c "Create VPC with Cloudformation" -o -r "aws cloudformation create-stack --region $awsRegion --stack-name $awsCFStack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml"
    }
    # Wait for creation
    #$cfstackReady = "CREATE_COMPLETE"
    While ($cfstackReady -ne "CREATE_COMPLETE") {
        $cfstackReady = Send-Update -a -t 1 -c "Check for 'CREATE_COMPLETE'" -r "aws cloudformation describe-stacks --region $awsRegion --stack-name $awsCFStack --query Stacks[*].StackStatus --output text"
        Send-Update -t 1 -c $cfstackReady
        Start-Sleep -s 5
    }
    # Bypass reloading steps for multi-user scenarios
    if (-not $userID) { Add-AwsSteps }
}
function Add-AWSCluster {
    # Create cluster-  wait for 'active' state
    Send-Update -o -c "Create Cluster" -t 1 -r "aws eks create-cluster --region $($config.AWSregion) --name $($config.AWScluster) --role-arn $($config.AWSclusterRoleArn) --resources-vpc-config subnetIds=$($config.AWSsubnets),securityGroupIds=$($config.AWSsecurityGroup)"
    $counter = 0
    While ($clusterExists.cluster.status -ne "ACTIVE") {
        $clusterExists = Send-Update -t 1 -a -e -c "Wait for ACTIVE cluster" -r "aws eks describe-cluster --region $($config.AWSregion) --name $($config.AWScluster) --output json" | ConvertFrom-Json
        Send-Update -t 1 -c "$($clusterExists.cluster.status)"
        $counter++
        if ($counter -eq 11) { Send-Update -t 1 -c "ZZzzzzzz... Taking too long.  Initiating Bad Joke Generator" }
        if ($counter % 12 -eq 0) { $jokeCounter = 0; $joke = Get-Joke }
        if ($joke) {
            if ($joke[$jokeCounter]) {
                Send-Update -t 1 -c "Joke Generator: $($joke[$jokeCounter])"
                $jokeCounter++
            }
            else {
                Clear-Variable joke
            }
        }
        Start-Sleep -s 20
    }
    # Create nodegroup- wait for 'active' state
    Send-Update -o -c "Create nodegroup" -t 1 -r "aws eks create-nodegroup --region $($config.AWSregion) --cluster-name $($config.AWScluster) --nodegroup-name $($config.AWSnodegroup) --node-role $($config.AWSnodeRoleArn) --scaling-config minSize=1,maxSize=1,desiredSize=1 --subnets $($config.AWSsubnets.replace(",", " "))  --instance-types t3.xlarge"
    While ($nodeGroupExists.nodegroup.status -ne "ACTIVE") {
        $nodeGroupExists = Send-Update -t 1 -a -e -c "Wait for ACTIVE nodegroup" -r "aws eks describe-nodegroup --region $($config.AWSregion) --cluster-name $($config.AWScluster) --nodegroup-name $($config.AWSnodegroup) --output json" | ConvertFrom-Json
        Send-Update -t 1 -c "$($nodeGroupExists.nodegroup.status)"
        $counter++
        if ($counter % 12 -eq 0) { $jokeCounter = 0; $joke = Get-Joke }
        if ($joke) {
            if ($joke[$jokeCounter]) {
                Send-Update -t 1 -c "Joke Generator: $($joke[$jokeCounter])"
                $jokeCounter++
            }
            else {
                Clear-Variable joke
            }
        }
        Start-Sleep -s 20
    }
    Add-AWSSteps
}
function Remove-AWSComponents {
    param (
        [string] $userID # override user in multi-deploy scenarios
    )
    # If userID, switch to Users subkey config
    # if ($userID) {
    #     $Params = @{}
    #     $Params['u'] = $userID
    #     $conf = $config.Users.$userID 
    # }
    # else { $conf = $config }
    $AWSregion = $config.AWSregion
    $AWSclusterRoleArn = $config.AWSclusterRoleArn
    $awsRoleName = $config.AWSroleName
    $awsNodeRoleName = $config.AWSnodeRoleName
    $awsCFStack = $config.AWScfstack
    $AWScfstackArn = $config.AWScfstackArn
    $AWSNodeRoleArn = $config.AWSnodeRoleArn

    if ($AWSclusterArn) {
        Remove-AWSCluster -b
    }
    if ($AWSclusterRoleArn) {
        # Get and remove any attached policies
        $attachedPolicies = Send-Update -t 1 -e -c "Get Attached Policies" -r "aws iam list-attached-role-policies --region $AWSregion --role-name $awsRoleName --output json" | Convertfrom-Json
        foreach ($policy in $attachedPolicies.AttachedPolicies) {
            Send-Update -t 1 -c "Remove Policy" -r "aws iam detach-role-policy --region $AWSregion --role-name $awsRoleName --policy-arn $($policy.PolicyArn)"
        }
        # Finally delete the role.  OMG AWS.
        Send-Update -t 1 -c "Delete Role" -r "aws iam delete-role --region $AWSregion --role-name $awsRoleName"
        Set-Prefs @Params -k "AWSclusterRoleArn"
    }
    if ($AWSnodeRoleArn) {
        # Get and remove any attached policies
        $attachedPolicies = Send-Update -t 1 -e -c "Get Attached Policies" -r "aws iam list-attached-role-policies --region $AWSregion --role-name $awsNodeRoleName --output json" | Convertfrom-Json
        foreach ($policy in $attachedPolicies.AttachedPolicies) {
            Send-Update -t 1 -c "Remove Policy" -r "aws iam detach-role-policy --region $AWSregion --role-name $awsNodeRoleName --policy-arn $($policy.PolicyArn)"
        }
        # Finally delete the role.
        Send-Update -t 1 -c "Delete Role" -r "aws iam delete-role --region $AWSregion --role-name $awsNodeRoleName"
        Set-Prefs @Params -k "AWSnodeRoleArn"
    }
    if ($AWScfstackArn -and -not $network) {
        #Send-Update -c "Remove cloudformation stack" -t 1 -r "aws cloudformation delete-stack --region $AWSregion --stack-name $AWScfstack"
        Do {
            $cfstackExists = Send-Update -e -c "Check cloudformation stack" -t 1 -r "aws cloudformation describe-stacks --region $AWSregion --stack-name $AWScfstack --query Stacks[*].StackStatus --output text"
            Send-Update -c $cfstackExists -t 1
            Start-Sleep -s 5
        } While ($cfstackExists)
    }
    Add-AWSSteps
}
function Remove-AWSCluster {
    param (
        [switch] $bypass # skip adding AWS steps when this is part of a larger process
    )
    if ($($config.AWSnodeRoleArn)) {
        # Remove nodegroup
        Send-Update -o -c "Delete EKS nodegroup" -r "aws eks delete-nodegroup --region $($config.AWSregion) --cluster-name $($config.AWScluster) --nodegroup-name $($config.AWSnodegroup)" -t 1
        Do {
            Start-Sleep -s 20
            $nodegroupExists = Send-Update -a -e -c "Check status" -r "aws eks describe-nodegroup --region $($config.AWSregion) --cluster-name $($config.AWScluster) --nodegroup-name $($config.AWSnodegroup)" -t 1 | Convertfrom-Json
            Send-Update -t 1 -c $($nodegroupExists.nodegroup.status)
        } while ($nodegroupExists) 
        Set-Prefs -k AWSnodeRoleArn
    }
    if ($($config.AWSclusterArn)) {
        # Remove cluster
        Send-Update -o -c "Delete EKS CLuster" -r "aws eks delete-cluster --region $($config.AWSregion) --name $($config.AWScluster) --output json" -t 1
        Do {
            Start-Sleep -s 20
            $clusterExists = Send-Update -t 1 -a -e -c "Check status" -r "aws eks describe-cluster --region $($config.AWSregion) --name $($config.AWScluster) --output json" | ConvertFrom-Json
            Send-Update -t 1 -c $($clusterExists.cluster.status)
        } while ($clusterExists)
        Set-Prefs -k AWSclusterArn
    }
    if (-not $bypass) { Add-AWSSteps }
}

# GCP Functions
function Add-GCPSteps() {
    # Add GCP specific steps
    $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
    # get current project
    $currentProject = Send-Update -content "GCP: Get Current Project" -t 0 -r "gcloud config get-value project"
    # if there is one, can the current account access itis it valid for this account?
    if ($currentProject) {
        # project exists, check if current account can access it
        $validProject = Send-Update -c "GCP: Project found, is it valid?" -a -t 0 -r "gcloud projects list --filter $currentProject --format='json' | Convertfrom-Json"
    }
    if ($validProject.count -eq 1) {
        # Exactly one valid project.  Offer option to change it
        Send-Update -content "yes" -type 0
        if ($currentProject -ne $validProject.projectid) {
            Send-Update -c "Switching from Project # to Id" -t 0 -r "gcloud config set project $($validProject.Projectid) "
        }
        Add-Choice -k "GPROJ" -d "Change Project" -c $($validProject.projectId) -f "Set-GCPProject"
    }
    else {
        Add-Choice -k "GPROJ" -d "Required: Select GCP Project" -f "Set-GCPProject"
        return
    }
    # We have a valid project, is there a GCP cluster running?
    $gkeClusterName = "scw-gke-$($userProperties.userid)"
    $existingCluster = Send-Update -t 1 -c "Check for existing cluster" -r "gcloud container clusters list --filter=name=$gkeClusterName --format='json' | Convertfrom-Json"
    if ($existingCluster.count -eq 1) {
        #Cluster already exists
        Add-Choice -k "GKE" -d "Delete GKE cluster & all content" -f "Remove-GCPCluster" -c $gkeClusterName
        Add-Choice -k "GKECRED" -d "Get GKE cluster credentials" -f "Get-GCPCluster" -c $gkeClusterName
        Set-Prefs -k gcpzone -v $existingCluster[0].zone
        Set-Prefs -k gcpclustername -v $gkeClusterName
    }
    else {
        Add-Choice -k "GKE" -d "Required: Create GKE k8s cluster" -f "Add-GCPCluster -c $gkeClusterName"
        return
    }
    # Also run common steps
    Add-CommonSteps
}
function Set-GCPProject {
    # set the default project
    $projectList = gcloud projects list --format='json' --sort-by name | ConvertFrom-Json
    $counter = 0; $projectChoices = Foreach ($i in $projectList) {
        $counter++
        New-object PSCustomObject -Property @{Option = $counter; name = $i.name; projectId = $i.projectId }
    }
    $projectChoices | sort-object -property Option | format-table -Property Option, name, projectId | Out-Host
    while (-not $projectId) {
        $projectSelected = read-host -prompt "Which project? <enter> to cancel"
        if (-not $projectSelected) { return }
        $projectId = $projectChoices | Where-Object -FilterScript { $_.Option -eq $projectSelected } | Select-Object -ExpandProperty projectId -first 1
        if (-not $projectId) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
    }
    Send-Update -t 1 -content "GCP: Select Project" -run "gcloud config set project $projectId"
    Add-GCPSteps

}
function Add-GCPCluster {
    param (
        [string] $clusterName #Name for the new GKE cluster
    )
    # Retrieve zone list
    $zoneList = gcloud compute zones list --format='json' --sort-by name | ConvertFrom-Json
    $counter = 0; $zoneChoices = Foreach ($i in $zoneList) {
        $counter++
        New-object PSCustomObject -Property @{Option = $counter; name = $i.name }
    }
    $zoneChoices | sort-object -property Option | format-table -Property Option, name | Out-Host
    while (-not $zone) {
        $zoneSelected = read-host -prompt "Which zone? <enter> to cancel"
        if (-not $zoneSelected) { return }
        $zone = $zoneChoices | Where-Object -FilterScript { $_.Option -eq $zoneSelected } | Select-Object -ExpandProperty name -first 1
        if (-not $zone) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
    }
    # Create the GKE cluster using name and zone

    Send-Update -content "GCP: Create GKE cluster" -t 1 -run "gcloud container clusters create -m e2-standard-4 --num-nodes=1 --zone=$zone $clusterName"
    Add-GCPSteps
}
function get-GCPCluster {
    # Load the kubectl credentials
    $env:USE_GKE_GCLOUD_AUTH_PLUGIN = True
    Send-Update -c "Get cluster creds" -t 1 -r "gcloud container clusters get-credentials  --zone $($config.gcpzone) $($config.gcpclustername)"
}
function Remove-GCPCluster {
    # Delete the GKE Cluster
    Send-Update -c "Deleting GKE cluster can take up to 10 minutes" -t 1
    Send-Update -c "Delete GKE cluster" -t 1 -r "gcloud container clusters delete --zone $($config.gcpzone) $($config.gcpclustername)"
}

# Kubernetes Functions
function Get-Pods {
    param(
        [string] $namespace #namespace to return pods
    )
    Send-Update -t 1 -c "Showing pod status" -r "kubectl get pods -n $namespace"
    Add-CommonSteps
}
function Restart-Pods {
    param(
        [string] $namespace #namespace to recycle pods
    )
    Send-Update -t 1 -c "Resetting Pods" -r "kubectl -n $namespace delete pods --field-selector=status.phase=Running"
}
function Get-PodReadyCount {
    param(
        [string] $namespace # namespace to count pods
    )
    $totalPods = (kubectl get pods -n $namespace  -ojson | Convertfrom-Json).items.count
    $runningPods = (kubectl get pods -n $namespace --field-selector status.phase=Running -ojson | Convertfrom-Json).items.count
    return "$runningPods/$totalPods pods READY"
}
function Remove-NameSpace {
    param(
        [string] $namespace
    )
    Send-Update -t 1 -c "Delete Namespace" -r "kubectl delete ns $namespace"
    Add-CommonSteps
}

# Dynatrace Functions
function Set-DTConfig() {
    While (-not $k8sToken) {
        # Get Tenant ID
        While (-not $cleantenantID) {
            $tenantID = read-Host -Prompt "Dynatrace Tenant ID <enter> to cancel: "
            if (-not $tenantID) {
                Set-Prefs -k tenantID
                Set-Prefs -k writeToken
                Set-Prefs -k k8stoken
                Add-CommonSteps
                return
            }
            if ($Matches) { Clear-Variable Matches }
            $tenantID -match '\w{8}' | Out-Null
            if ($Matches) {
                $cleanTenantID = $Matches[0]
                
            }
            else {
                write-host "Tenant ID should be at least 8 alphanumeric characters."
            }
        }
        # Get Token
        While (-not $cleanToken) {
            $token = read-Host -Prompt "Token with 'Write API token' permission <enter> to cancel: "
            if (-not $token) {
                return
            }
            if ($Matches) { Clear-Variable Matches }
            $token -match '^dt0c01.{80}' | Out-Null
            if ($Matches) {
                $cleanToken = $Matches[0]
                Set-Prefs -k writeToken -v $cleanToken
            }
            else {
                write-host "Tokens start with 'dt0c01' and are at least 80 characters."
            }
    
        }
        $headers = @{
            accept         = "application/json; charset=utf-8"
            "Content-Type" = "application/json; charset=utf-8"
            Authorization  = "Api-Token $token"
        }
        $data = @{
            scopes              = @("activeGateTokenManagement.create", "entities.read", "settings.read", "settings.write", "DataExport", "InstallerDownload")
            name                = "SCW Token"
            personalAccessToken = $false
        }
        $body = $data | ConvertTo-Json
        Try {
            $response = Invoke-RestMethod -Method Post -Uri "https://$cleanTenantID.live.dynatrace.com/api/v2/apiTokens" -Headers $headers -Body $body
        }
        Catch {
            # The noise, ma'am.  Suppress the noise.
            write-host "Error Code: " $_.Exception.Response.StatusCode.value__
            Write-Host "Description:" $_.Exception.Response.StatusDescription
        }
        if ($response.token) {
            # API Token has to be base64. #PropsDaveThomas<3
            $k8stoken = $response.token
            $base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($k8stoken))
            Set-Prefs -k tenantID -v $cleanTenantID
            Set-Prefs -k writeToken -v $token
            Set-Prefs -k k8stoken -v $k8stoken
            Set-Prefs -k base64Token -v $base64Token
            Add-DynakubeYaml -t $base64Token -u "https://$cleanTenantID.live.dynatrace.com/api" -c "k8s$($choices.callProperties.userid)"
        }
        else {
            write-host "Failed to connect to $cleanTenantID"
            Clear-Variable cleanTenantID
            Clear-Variable cleanToken
            Set-Prefs -k tenantID
            Set-Prefs -k writeToken
            Set-Prefs -k k8stoken
        }
    }
    Add-CommonSteps
}
function Add-DynakubeYaml {
    param (
        [string] $token, # Dynatrace API token
        [string] $url, # URL To Dynatrace tenant
        [string] $clusterName # Name of cluster in Dynatrace
    )
    
    $dynaKubeContent = 
    @"
apiVersion: v1
data:
  apiToken: $base64Token
kind: Secret
metadata:
  name: $clusterName
  namespace: dynatrace
type: Opaque
---
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: $clusterName
  namespace: dynatrace
  annotations:
    feature.dynatrace.com/automatic-kubernetes-api-monitoring: "true"
spec:
  apiUrl: $url
  skipCertCheck: false
  oneAgent:
    classicFullStack:
      tolerations:
        - effect: NoSchedule
          key: node-role.kubernetes.io/master
          operator: Exists
        - effect: NoSchedule
          key: node-role.kubernetes.io/control-plane
          operator: Exists
      env:
        - name: ONEAGENT_ENABLE_VOLUME_STORAGE
          value: "false"
  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1.5Gi
"@
    $dynaKubeContent | out-File -FilePath dynakube.yaml
}
function Add-Dynatrace {
    Send-Update -c "Add Dynatrace Namespace" -t 1 -r "kubectl create ns dynatrace"
    Send-Update -c "Waiting 10s for activation" -a -t 1
    $counter = 0
    While ($namespaceState -ne "Active") {
        if ($counter -ge 10) {
            Send-Update -t 2 -c " Failed to create namespace!"
            break
        }
        $counter++
        Send-Update -c " $counter" -t 1 -a
        Start-Sleep -s 1
        #Query for namespace viability
        $namespaceState = (kubectl get ns dynatrace -ojson | Convertfrom-Json).status.phase
    }
    Send-Update -c " Activated!" -t 1
    Send-Update -c "Loading Operator" -t 1 -r "kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml"
    Send-Update -c "Waiting for pod to activate" -t 1 -r "kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s"
    Send-Update -c "Loading dynakube.yaml" -t 1 -r "kubectl apply -f dynakube.yaml"
    Add-CommonSteps
}

# Application Functions
function Add-CommonSteps() {
    # Get namespaces so we know what's installed or not
    $existingNamespaces = (kubectl get ns -o json 2>$null | Convertfrom-Json).items.metadata.name
    # Option to download yaml files with current status
    [System.Collections.ArrayList]$yamlReady = @()
    foreach ($yaml in $yamlList) {
        [uri]$uri = $yaml
        $yamlName = $uri.Segments[-1]
        $yamlNameSpace = [System.IO.Path]::GetFileNameWithoutExtension($yamlName)
        if (test-path $yamlName) {
            $newYaml = New-Object PSCustomObject -Property @{
                Option    = $yamlReady.count + 1
                name      = $yamlName
                namespace = $yamlNameSpace
            }
            [void]$yamlReady.add($newYaml)
        }
    }
    if ($yamlReady.count -eq 0) {
        $downloadType = "<not done>"
    }
    else {
        $downloadType = "$($yamlReady.count)/$($yamlList.count) downloaded"
    }
    Add-Choice -k "DLAPPS" -d "Download demo apps yaml files" -f Get-Apps -c $downloadType
    # Determine appropriate Dynatrace option
    if ($existingNamespaces.contains("dynatrace")) {
        #1 Dynatrace installed.  Add status and removal options
        Add-Choice -k "STATUSDT" -d "dynatrace : Show Pods" -c $(Get-PodReadyCount -n dynatrace)  -f "Get-Pods -n dynatrace"
        Add-Choice -k "DTCFG" -d "dynatrace : Remove" -f "Remove-NameSpace -n dynatrace" -c "tenant: $($config.tenantID)"
    }
    elseif (test-path dynakube.yaml) {
        #2 Dynatrace not present but dynakube.yaml available.  Add Install Option
        $fileTimeStamp = (Get-ChildItem -path dynakube.yaml | select-object -Property CreationTime).CreationTime | Get-Date -Format g
        # Dynakube file found. Provide install option
        Add-Choice -k "DTCFG" -d "dynatrace: Deploy to k8s" -c "YAML Date: $fileTimeStamp" -function Add-Dynatrace
    }
    else {
        #3 Nothing done for dynatrace yet.  Add option to download YAML
        Add-Choice -k "DTCFG" -d "dynatrace: Create dynakube.yaml"  -f Set-DTConfig
    }
    # Add options to kubectl apply, delete, or get status (show any external svcs here in current)
    foreach ($app in $yamlReady) {
        # check if this app is deployed. Use name of yaml file as namespace (dbic.yaml should have dbic namespace)
        $ns = $app.namespace
        if ($existingNamespaces.contains($ns)) {
            # Namespace exists- add status option
            Add-Choice -k "STATUS$ns" -d "$ns : Refresh/Show Pods" -c "$(Get-PodReadyCount -n $ns)" -f "Get-Pods -n $ns"
            # add restart option
            Add-Choice -k "RESTART$ns" -d "$ns : Reset Pods" -c  $(Get-AppUrls -n $ns ) -f "Restart-Pods -n $ns"
            # add remove option
            Add-Choice -k "DEL$ns" -d "$ns : Remove Pods"  -f "Remove-NameSpace -n $ns"
        }
        else {
            # Yaml is available but not yet applied.  Add option to apply it
            Add-Choice -k "INST$ns" -d "$ns : Deploy App" -f "Add-App -y $($app.name) -n $ns"        
        }
    }
}
function Get-Apps() {
    foreach ($yaml in $yamlList) {
        [uri]$uri = $yaml
        #$yamlName = $uri.Segments[-1]
        #$yamlNameSpace = [System.IO.Path]::GetFileNameWithoutExtension($yamlName)
        Invoke-WebRequest -Uri $uri.OriginalString -OutFile $uri.Segments[-1] | Out-Host
    }
    Send-Update -c "Downloaded $($yamlList.count)" -type 1
    Add-CommonSteps
}
function Get-AppUrls {
    #example: Get-AppUrls -n [namespace]
    param(
        [string] $namespace #namespace to search for ingress
    )
    #Pull services from the requested namespace
    $services = (kubectl get svc -n $namespace -ojson | Convertfrom-Json).items
    #Get any external ingress for this app
    foreach ($service in $services) {
        if ($service.status.loadBalancer.ingress.count -gt 0) {
            if (-not $returnList) { $returnList = "URLS:" }
            # Azure was using IP address.  Switched to hostname for default AWS
            $returnList = "$returnList http://$($service.status.loadBalancer.ingress[0].hostname)"
        }
    }
    #Return list
    return $returnList

}
function Add-App {
    param (
        [string] $yaml, #yaml to apply
        [string] $namespace #namespace to confirm
    )
    Send-Update -c "Adding deployment" -t 1 -r "kubectl apply -f $yaml"
    Send-Update -c "Waiting 10s for namespace [$namespace] to activate" -a -t 1
    $counter = 0
    While ($namespaceState -ne "Active") {
        if ($counter -ge 20) {
            Send-Update -t 2 -c " Failed to create namespace!"
            break
        }
        $counter++
        Send-Update -c " $counter" -t 1 -a
        Start-Sleep -s 1
        #Query for namespace viability
        $namespaceState = (kubectl get ns $namespace -ojson | Convertfrom-Json).status.phase

    }
    Send-Update -c " Activated!" -t 1
    Add-CommonSteps
}

# Startup
Get-Prefs($Myinvocation.MyCommand.Source)
Get-Providers
while ($choices.count -gt 0) {
    $cmd = Get-Choice($choices)
    if ($cmd) {
        Invoke-Expression $cmd.callFunction
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
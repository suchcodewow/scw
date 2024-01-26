# VSCODE: ctrl/cmd+k+1 folds all functions, ctrl/cmd+k+j unfold all functions.
# Check '.vscode/launch.json' for any current parameters
param (
    [switch] $help, # show other command options and exit
    [switch] $verbose, # show debug messages in addition to normal & error messages
    [switch] $cloudCommands, # enable to show commands
    [switch] $log, # enable to log commands executed
    [string] $impersonate, #User Name to use instead of default (not used in multiUser mode)
    [string] $network, # Specify cloudformation stack in AWS (vs default group 'scw-AWSStack')
    [switch] $aws, # use aws
    [switch] $azure, # use azure
    [switch] $gcp, # use gcp
    [switch] $multiUserMode, #Switch to classroom setup mode
    [switch] $quickDeploy #enable option to deploy everything possible (automatically set in multiUserMode)
)

# Core Functions
function Send-Update {
    #muReady
    # Handle output to screen & log, execute commands to cloud systems and return results
    param(
        [string] $content, # Message content to log/write to screen
        [int] $type, # [0/1/2] log levels respectively: debug/info/errors, info/errors, errors
        [string] $run, # Run a command and return result
        [switch] $append, # [$true/false] skip the newline (next entry will be on same line)
        [switch] $errorSuppression, # use this switch to suppress error output (useful for extraneous warnings)
        [switch] $outputSuppression, # use to suppress normal output
        [switch] $whatIf # do NOT run command, just SHOW for troubleshooting
    )
    $Params = @{}
    if (-not (test-path variable:currentLogEntry)) { $script:currentLogEntry = $null }
    if ($whatIf) { $whatIfComment = "!WHATIF! " }
    if ($run) {
        $Params['ForegroundColor'] = "Magenta"; $start = "[$whatIfComment>]"
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
    if ($run -and $config.showCommands) { $showcmd = " [ $run ] " }
    if ($currentLogEntry) { $screenOutput = "$content$showcmd" } else { $screenOutput = "   $start $content$showcmd" }
    if ($append) { $Params['NoNewLine'] = $true; $script:currentLogEntry = "$script:currentLogEntry $content$showcmd"; }
    if (-not $append) {
        #Write to log if option picked
        if ($logFile -and $type -ge 1) {
            "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $currentLogEntry $content$showcmd" | out-file $logFile -Append
        }
        #Reset inline recording
        $script:currentLogEntry = $null
    }
    # output if user wants to see this level of content
    if ($type -ge $config.outputLevel) {
        write-host @Params $screenOutput
    }
    if ($whatIf) { return }
    if ($run -and $errorSuppression -and $outputSuppression) { return invoke-expression $run 1>$null }
    if ($run -and $errorSuppression) { return invoke-expression $run 2>$null }
    if ($run -and $outputSuppression) { return invoke-expression $run 1>$null }
    if ($run) { return invoke-expression $run }
}
function Get-Prefs {
    # Setup default single-user config file
    $script:configFile = "pepper.conf"
    # Ensure clean config if multiUser mode!
    # TODO figure out if we need to delete config?
    # if ((Test-Path $configFile) -and -not $multiUserMode) {
    if (test-path $configFile) {
        $script:config = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable
    }
    else {
        $script:config = @{}
        $config["schemaVersion"] = "3.0"
        $config | ConvertTo-Json | Out-File (new-item -Path $configFile -Force)
    }
    Send-Update -t 0 -c "Config Save File: $configFile"
    # Do the things for the command line switches selected
    if ($help) { Get-Help }
    if ($verbose) { Set-Prefs -k "outputLevel" -v 0 } else { Set-Prefs -k "outputLevel" -v 1 }
    if ($cloudCommands) { Set-Prefs -k "showCommands" -v $true } else { Set-Prefs -k "showCommands" }
    if ($log) { $script:logFile = "pepper.log" }
    if ($aws) { Set-Prefs -k "useAWS" -v $true } else { Set-Prefs -k "useAWS" }
    if ($azure) { Set-Prefs -k "useAzure" -v $true } else { Set-Prefs -k "useAzure" }
    if ($gcp) { Set-Prefs -k "useGCP" -v $true } else { Set-Prefs -k "useGCP" }
    if ($multiUserMode) { Set-Prefs -k "multiUserMode" -v $true } else { Set-Prefs -k "multiUserMode" }
    if ($impersonate) { $script:impersonateUser = $impersonate }
    if ($quickDeploy) { Set-Prefs -k "quickDeploy" -v $true } else { Set-Prefs -k "quickDeploy" -v $false }
    # If no cloud selected, use all
    if ((-not $config.useAWS) -and (-not $config.useAzure) -and (-not $config.useGCP)) { Set-Prefs -k "useAWS" -v $true; Set-Prefs -k "useAzure" -v $true; Set-Prefs -k "useGCP" -v $true }
    # Set Script level variables and housekeeping stuffs
    [System.Collections.ArrayList]$script:providerList = @()
    [System.Collections.ArrayList]$script:choices = @()
    $script:ProgressPreference = "SilentlyContinue"
    # Any yaml here will be available for installation- file should be namespace (i.e. x.yaml = x namescape)
    Set-Prefs -k yamlList -v @("https://raw.githubusercontent.com/suchcodewow/dbic/main/deploy/dbic", "https://raw.githubusercontent.com/suchcodewow/bobbleneers/main/bnos" )
    if ($outputLevel -eq 0) {
        $script:choiceColumns = @("Option", "description", "current", "key", "callFunction", "callProperties")
        $script:providerColumns = @("option", "provider", "name", "identifier", "userid", "default")
    }
    else {
        $script:choiceColumns = @("Option", "description", "current")
        $script:providerColumns = @("option", "provider", "name")
    }
    # Load preferences/settings.  Access with $config variable anywhere.  Set-Prefs automatically updates $config variable and saves to file
    $script:muFunctions = Get-ChildItem Function: | Where-Object { $_.Definition -like '*#muReady*' } | ForEach-Object {
        Get-FunctionAsScriptBlock -Name $_.Name -Definition $_.Definition
    }
    write-host
    Get-Providers
}
function Set-Prefs {
    #muReady
    param(
        [string]$u, #switch to a user context
        [string]$k, # key
        [string]$v # value
    )
    if ($u) {
        # Switch context for multiUser mode
        $script:configFile = "~/scwConfig/$u.conf"
        $importFile = "pepper.conf"
        if (Test-Path $configFile) {
            $script:config = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable
        }
        else {
            $script:config = @{}
            $config["schemaVersion"] = "3.0"
            $config | ConvertTo-Json | Out-File (New-Item -Path $configFile -Force)
        }
        Send-Update -t 0 -c "Config Save File: $configFile"
        # Import preferences from home interface <3 Tony Stark
        if (Test-Path $importFile) {
            $importConfig = Get-Content $importFile -Raw | ConvertFrom-Json -AsHashtable
            $counter = 0
            foreach ($item in $importConfig.GetEnumerator()) {
                Set-Prefs -k $item.Name -v $item.Value
                $counter++
            }
            Send-Update -t 0 -c "Imported $counter values to $configFile"
        }
        Set-Prefs -k "userName" -v $u
        return
    }
    if ($v) {
        $config[$k] = $v
        Send-Update -c "Updated/Created key: $k -> $v" -t 0
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
    # }
    if ($configFile) {
        # $config.GetEnumerator() | sort-object -property Name | ConvertTo-Json | Out-File (New-Item -Path $configFile -Force)
        $config | ConvertTo-Json | Out-File (New-Item -Path $configFile -Force)
    }
    else {
        Send-Update -c "No command name, skipping write" -t 0
    }
}
function Add-Choice {
    #example: Add-Choice -k 'key' -d 'description' -c 'current' -f 'function' -p 'parameters'
    param(
        [string] $key, # key identifying this choice, unique only
        [string] $description, # description of item
        [string] $current, # current selection of item, if applicable
        [string] $function, # function name to call if changing item
        [object] $parameters # parameters needed in the function
    )
    # If this key exists, delete it and anything that followed
    Send-Update -c "Add choice: $key" -t 0
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
function Get-Choice {
    # Present list of options and get selection
    write-output $choices | sort-object -property Option | format-table $choiceColumns | Out-Host
    $cmd_selected = read-host -prompt "Which option to execute? [<enter> to quit]"
    if (-not($cmd_selected)) {

        write-host "buh bye!`r`n" | Out-Host
        exit
    }
    if ($cmd_selected -eq 0) { Get-Quote }
    return $choices | Where-Object { $_.Option -eq $cmd_selected } | Select-Object -first 1 
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
        "I can cut a piece of wood in half just by looking at it.;You might not believe me, but I saw it with my own eyes.",
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
    write-host "                    -l Log events"
    write-host "    -aws, -azure, -gcp Use specific cloud only (can be combined)"
    exit
}
function Get-UserName {
    #muReady
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
    )
      
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
function Get-FunctionAsScriptBlock {
    param(
        [string]$Name,
        [string]$Definition
    )

    $code = @"
    function $Name {
        $Definition
    }
"@

    $sb = [scriptblock]::Create($code)
    return $sb
}
function Set-Resources {
    #muReady
    switch ($config.provider) {
        "azure" {
            Set-Prefs -k "azureGroup" -v "scw-group-$($config.userName)"
            Set-Prefs -k "azureCluster" -v "scw-AKS-$($config.userName)"
            Set-Prefs -k "azureServicePlan" -v "scw-asp-$($config.userName)"
            Set-Prefs -k "azureWebApp" -v "scw-webapp-$($config.userName)"
            Set-Prefs -k "loginEmail" -v "$($config.userName)@suchcodewow.io"
        }
        "aws" {
            Send-Update -t 2 -c "UPDATE AWS"
        }
        "gcp" {
            Send-Update -t 2 -c "UPDATE GCP"
        }
        default {
            Send-Update -t 2 -c "ERROR: NO PROVIDER!"
        }
    }
}

# Provider Functions
function Add-Provider {
    param(
        [string] $p, # provider
        [string] $n, # name of item
        [string] $i, # item unique identifier
        [switch] $d, # [$true/$false] default option
        [string] $u # unique user identifier (for creating groups/clusters)
    )
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
function Get-Providers {
    Send-Update -content "Gathering provider options... " -t 1 -a
    $providerList.Clear()
    # AZURE
    if ($config.useAzure) {
        Send-Update -content "Azure:" -t 1 -a
        # Do we have cli command?
        if (get-command 'az' -ea SilentlyContinue) {
            $azureSignedIn = az ad signed-in-user show 2>$null 
        }
        else { Send-Update -content "NA " -t 1 -a }
        # Do we have a valid Azure connection?
        if ($azureSignedIn) {
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
    if ($config.useAWS) {
        Send-Update -content "AWS:" -t 1 -a
        # Do we have cli command?
        if (get-command 'aws' -ea SilentlyContinue) {
            # ISSUE: check environment variables for a region for non-admin accounts
            $awsRegion = $env:AWS_REGION
            if (-not $awsRegion) {
                # No region in environment variables, trying pulling from local config
                $awsRegion = aws configure get region
            }
            # Do we have a valid region?
            if ($awsRegion) {
                # For workshops, using ARN maybe?
                $arnCheck = (aws sts get-caller-identity --output json 2>$null | Convertfrom-JSon).Arn
                if ($arnCheck) {
                    $awsSignedIn = $arnCheck.split("/")[1]
                }
                if ($awsSignedIn -eq "dtRoleAdvancedUser") {
                    # if on Dynatrace account, sub in name instead of dtRoleAdvancedUser
                    (aws sts get-caller-identity --output json 2>$null | Convertfrom-JSon).UserId -match "-(.+)\.(.+)@" 1>$null
                    if ($Matches.count -eq 3) {
                        $awsSignedIn = "$($Matches[1])$($Matches[2])"
                    }
                }
            }
            # Do we have a valid sign-in?
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
    if ($config.useGCP) {
        Send-Update -c "GCP:" -t 1 -a
        # Do we have access to cli command?
        if (get-command 'gcloud' -ea SilentlyContinue) {
            $accounts = gcloud auth list --format="json" | ConvertFrom-Json 
            # Do we have accessible accounts?
            if ($accounts.count -gt 0) {
                foreach ($i in $accounts) {
                    $Params = @{}
                    if ($i.status -eq "ACTIVE") { $Params['d'] = $true } 
                    Add-Provider @Params -p "GCP" -n "account: $($i.account)" -i $i.account -u (($i.account).split("@")[0]).replace(".", "").ToLower()
                }
                Send-Update -c "$($accounts.count) " -a -t 1
            }
            else {
                # Total for GCP is just 1 or 0 for now so use this toggle
                Send-Update -c "0 " -a -t 1
            }
        }
        else { Send-Update -content "NA " -t 1 -a }
        
    }
    # Done getting options
    Send-Update -c " " -type 1
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
function Set-Provider {
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
        $providerSelected = $providerList | Where-Object { $_.Option -eq $newProvider } | Select-Object -first 1
        if (-not $providerSelected) {
            write-host -ForegroundColor red "`r`nY U no pick valid option?" 
        }
    }
    $functionProperties = @{provider = $providerSelected.Provider; id = $providerSelected.identifier.tolower(); userid = $providerSelected.userid.tolower() }
    # Add option to run this again
    Add-Choice -k "TARGET" -d "Switch Cloud Provider" -c "$($providerSelected.Provider) $($providerSelected.Name)" -f "Set-Provider" -p $functionProperties
    # build options for specified provider
    switch ($providerSelected.Provider) {
        "Azure" {
            # Set the Azure subscription
            Send-Update -t 1 -c "Azure: Set Subscription" -r "az account set --subscription $($providerSelected.identifier)"
            Set-Prefs -k "provider" -v "azure"
            if ($config.multiUserMode) { Add-AzureMultiUserSteps } else { Add-AzureSteps }
        }
        "AWS" {
            Send-Update -t 1 -c "AWS: Set region"
            Set-Prefs -k "provider" -v "aws"
            Add-AWSSteps 
        }
        "GCP" { 
            # set the GCP Project
            Send-Update -OutputSuppression -t 1 -c "GCP: Set Project" -r "gcloud config set account '$($providerSelected.identifier)' --no-user-output-enabled"
            Set-Prefs -k "provider" -v "gcp"
            Add-GCPSteps 
        }
    }
}

# Azure MU Main Functions
function Add-AzureMultiUserSteps {
    if (-not (test-path -Path "~/scwKube/")) { New-Item "~/scwKube/" -ItemType Directory }
    if (-not (test-path -Path "~/scwYaml/")) { New-Item "~/scwYaml/" -ItemType Directory }
    Add-Choice -k "AZMCR" -d "Select Region" -f Get-AzureMultiUserRegion -c $config.muAzureRegion 
    if (-not $config.muAzureRegion) { return }
    ### We have a region, event?
    Add-Choice -k 'AZME' -d "Select/Create Event" -f Get-AzureMultiUserEvent -c $config.muEvent
    if (-not $config.muEvent) { return }
    ### We have a region and event set options & get status
    if (-not $muSetupDone) {
        Set-Prefs -k "muCreateClusters" -v $true
        Set-Prefs -k "muDeployDynatrace" -v $true
        Set-Prefs -k "muCreateWebApp" -v $true
        Set-Prefs -k "muRunning" -v $true
        $script:muSetupDone = $true
    }
    Get-AzureMultiUserCache
    ### Options for events AND Account level
    Add-Choice -k "AZMUR" -d "Delete Event/Accounts/Content" -f Remove-AzureMultiUser -c "RG: $azureGroups k8s: [$azureClustersRunning/$azureClustersStopped] DT: [$dynatraceRunning/$dynatracePartial] Apps: [$azureWebAppsRunning/$azureWebAppsStopped]"
    Add-Choice -k "AZMCS" -d "Refresh Event Status" -f Get-AzureMultiUserStatus
    Add-Choice -k "AZML" -d "List Attendees" -f Get-AzureMultiUser -c "Currently: $attendeeCount"
    if ($config.muEvent -eq "Attendees") { return }
    ### Options for events only
    Add-Choice -k "AZMCU" -d "Create Accounts" -f Add-AzureMultiUser
    Add-Choice -k "AZMCT" -d "[toggle] Auto-create AKS clusters?" -c "$($config.muCreateClusters)" -f Set-AzureMultiUserCreateCluster
    Add-Choice -k "AZMDDT" -d "[toggle] Auto-Deploy Dynatrace?" -c "$($config.muDeployDynatrace)" -f Set-AzureMultiUserDeployDynatrace
    Add-Choice -k "AZMCWA" -d "[toggle] Auto-create Azure Web App?" -c "$($config.muCreateWebApp)" -f Set-AzureMultiUserCreateWebApp
    Add-Choice -k "AZCR" -d "[toggle] Deployed resources running?" -c "$($config.muRunning)" -f Set-AzureMultiUserRunning
    Add-Choice -k "AZMGO" -d "Deploy/Update resources" -c "" -f Update-AzureMultiUser
}
function Get-AzureMultiUserStatus {
    $eventAttendees = Send-Update -t 1 -c "Get Group Attendees" -r "az ad group member list --group $($config.muEvent) --query '[].{displayName:displayName}'" | Convertfrom-Json | Select-Object -expandproperty displayName
    $eventAttendees | ForEach-Object -ThrottleLimit 50 -Parallel {
        $using:muFunctions | ForEach-Object { . $_ }
        Set-Prefs -u $_
        Set-Resources
        Get-AzureStatus
    }
    Add-AzureMultiUserSteps
}
function Get-AzureMultiUserCache {
    # Get available config files
    if (-not (test-path "~/scwConfig/")) { return }
    $configAll = foreach ($i in Get-ChildItem -path "~/scwConfig/*.conf") { $i | Get-Content | Convertfrom-Json }
    $script:configEvent = $configAll | where-object { $_.muEvent -eq $config.muEvent }
    $script:attendeeCount = $configEvent.count
    $script:azureGroups = ($configEvent | where-object { $_.azureGroupStatus -eq $true }).count
    $script:azureClustersRunning = ($configEvent | where-object { $_.azureClusterStatus -eq "Running" }).count
    $script:azureClustersStopped = ($configEvent | where-object { $_.azureClusterStatus -eq "Stopped" }).count
    $script:azureWebAppsRunning = ($configEvent | where-object { $_.azureWebAppStatus -eq "Running" }).count
    $script:azureWebAppsStopped = ($configEvent | where-object { $_.azureWebAppStatus -eq "Stopped" }).count
    $script:DynatraceRunning = ($configEvent | where-object { $_.dynatraceStatus -eq "Running" }).count
    $script:DynatracePartial = ($configEvent | where-object { $_.dynatraceStatus -eq "Partial" }).count
}
function Update-AzureMultiUser {
    $eventAttendees = Send-Update -t 1 -c "Get Group Attendees" -r "az ad group member list --group $($config.muEvent) --query '[].{displayName:displayName}'" | Convertfrom-Json | Select-Object -expandproperty displayName
    $eventAttendees | ForEach-Object -ThrottleLimit 50 -Parallel {
        $using:muFunctions | ForEach-Object { . $_ }
        Set-Prefs -u $_
        Set-Resources
        Get-AzureStatus
        $changes = 0
        ### Deploy resource group, cluster, web app
        if ($config.azureGroupStatus -eq $false) {
            $changes++
            Send-Update -t 1 -c "Azure: Create Resource Group" -run "az group create --name $($config.azureGroup) --location $($config.muAzureRegion) -o none"
        }
        if ($config.azureClusterStatus -eq $false -and $config.muCreateClusters -eq $true) {
            $changes++
            Send-Update -o -t 1 -content "Azure: Create AKS Cluster" -run "az aks create -g $($config.azureGroup) -n $($config.azureCluster) --node-count 1 --node-vm-size 'Standard_D4s_v5' --generate-ssh-keys --only-show-errors"
        }
        if ($config.azureWebAppStatus -eq $false -and $config.muCreateWebApp -eq $true) {
            $changes++
            Send-Update -c "Creating Azure Web App Plan" -t 1 -r "az appservice plan create --name $($config.azureServicePlan) --resource-group $($config.azureGroup) --sku B2" -o
            Send-Update -c "creating Azure Web App" -t 1 -r "az webapp create --resource-group $($config.azureGroup) --name $($config.azureWebApp) --plan $($config.azureServicePlan) --runtime 'dotnet:6'" -o        
        }
        ### If changes made refresh
        if ($changes -gt 0) { Get-AzureStatus;$changes = 0 }
        ### Get cluster credentials, deploy Dynatrace
        if ($config.muDeployDynatrace -eq $true -and $config.dynatraceStatus -ne "Running") {
            if ($config.dynatraceTenant -and $config.dynatraceToken) {
                $changes++
                if ($config.dynatraceTenant.substring(0, 8) = "https://") {
                    $url = $config.dynatraceTenant.substring(8).replace(".sprint.apps",".sprint")
                }
                else {
                    $url = $config.dynatraceTenant.replace(".sprint.apps",".sprint")                
                }
                Add-DynakubeYaml -muUsername $config.userName -c "k8s$($config.userName)" -token $config.dynatraceToken -url $url
                $kubeCmd = "kubectl --kubeconfig ./scwKube/$($config.userName).kube"
                Send-Update -c "Add Dynatrace Namespace" -t 1 -r "$kubeCmd create ns dynatrace"
                Send-Update -c "Waiting 10s for activation" -a -t 1
                $counter = 0
                While ($namespaceState.status.phase -ne "Active") {
                    if ($counter -ge 10) {
                        Send-Update -t 2 -c " Failed to create namespace!"
                        break
                    }
                    $counter++
                    Send-Update -c " $($counter)..." -t 1 -a
                    Start-Sleep -s 1
                    #Query for namespace viability
                    $namespaceState = Send-Update -t 1 -c "Checking namespace state for: $targetCluster" -r "$kubeCmd get ns dynatrace -ojson " | Convertfrom-Json
                }
                Send-Update -c " Activated!" -t 1
                Send-Update -c "Loading Operator" -t 1 -r "$kubeCmd apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml"
                Send-Update -c "Waiting for pod to activate" -t 1 -r "$kubeCmd -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s"
                Send-Update -c "Loading dynakube.yaml" -t 1 -r "$kubeCmd apply -f ./scwYaml/$($config.userName)-dynakube.yaml"
            }
            else {
                Send-Update -t 2 -c "$($config.userName): Dynatrace deploy failed! url: $($url) token: $($config.dynatraceToken)"
            }
        }
        if ($config.azureClusterStatus -eq "Running" -and $config.muRunning -eq $false) {
            $changes++
            $counter = 0
            Do {
                $counter++
                if ($counter -gt 1) {
                    $msgLevel = 2
                    $msgRetry = "RETRY [$counter]: "
                }
                else {
                    $msgLevel = 1
                }
                $success = Send-Update -t $msgLevel -c "$($msgRetry)Putting Cluster $($config.azureCluster) to sleep." -r "az aks stop -g $($config.azureGroup) -n $($config.azureCluster)"
            } until ($success)
        }
        if ($config.azureWebAppStatus -eq "Running" -and $config.muRunning -eq $false) {
            $changes++
            Send-Update -t 1 -c "Putting Web App $($config.azureWebApp) to sleep." -r "az webapp stop -g $($config.azureGroup) -n $($config.azureWebApp)"
        }
        if ($config.azureClusterStatus -eq "Stopped" -and $config.muRunning -eq $true) {
            $changes++
            Send-Update -t 1 -c "Waking $($config.azureCluster) up." -r "az aks start -g $($config.azureGroup) -n $($config.azureCluster)"
        }
        if ($config.azureWebAppStatus -eq "Stopped" -and $config.muRunning -eq $true) {
            $changes++
            Send-Update -t 1 -c "Waking $($config.azureWebApp) up." -r "az webapp start -g $($config.azureGroup) -n $($config.azureWebApp)"
    
        }
        ### If changes made refresh
        if ($changes -gt 0) { Get-AzureStatus;$changes = 0 }
    }
    ### Stop services if option picked

    Add-AzureMultiUserSteps
}
function Add-AzureMultiUser {
    # Create user accounts
    while (-not $addUserCount) {
        $addUserResponse = read-host -prompt "How many attendee accounts to generate? <enter> to cancel"
        if (-not($addUserResponse)) { return }
        try {
            $addUserCount = [convert]::ToInt32($addUserResponse)
        }
        catch {
            write-host "`r`nPositives integers only"            
        }
    }
    $userPrefix = read-host -prompt "Attendee prefix? <enter> for Madlibs style"
    
    # Create user accounts
    1..$addUserCount | ForEach-Object -ThrottleLimit 50 -Parallel {
        $using:muFunctions | ForEach-Object { . $_ }
        $userPrefix = $using:userPrefix
        # Create User
        if ($userPrefix) {
            $newUserName = "$userPrefix$_"
            $user = Send-Update -t 1 -c "Creating user $newUserName" -r "az ad user create --display-name $newUserName --password 1Dynatrace## --force-change-password-next-sign-in false --user-principal-name $newUserName@suchcodewow.io" | ConvertFrom-Json
        }
        else {
            Do {
                $newUserName = Get-UserName
                $user = Send-Update -t 1 -c "Creating user $newUserName" -r "az ad user create --display-name $newUserName --password 1Dynatrace## --force-change-password-next-sign-in false --user-principal-name $newUserName@suchcodewow.io" | ConvertFrom-Json
            } Until ($user)
        }
        Set-Prefs -u $newUserName
        Set-Resources
        Send-Update -t 1 -c "Adding $newUserName to attendees group" -r "az ad group member add --group Attendees --member-id $($user.id)"
        Send-Update -t 1 -c "Adding $newUserName to $($config.muEvent)" -r "az ad group member add --group $($config.muEvent) --member-id $($user.id)"
    }
    Add-AzureMultiUserSteps
}
function Remove-AzureMultiUser {
    $eventAttendees = Send-Update -t 1 -c "Get Group Attendees" -r "az ad group member list --group $($config.muEvent) --query '[].{displayName:displayName}'" | Convertfrom-Json | Select-Object -expandproperty displayName
    $eventAttendees | ForEach-Object -ThrottleLimit 50 -Parallel {
        $using:muFunctions | ForEach-Object { . $_ }
        Set-Prefs -u $_
        # Delete User and all resources
        Send-Update -t 1 -c "$($config.loginEmail) : Remove resource group and content" -r "az group delete --resource-group $($config.azureGroup) -y"
        Send-Update -t 1 -c "$($config.loginEmail) : Remove account" -r "az ad user delete --id $($config.loginEmail)"
        # Confirm Delete
        Do {
            Start-sleep -s 2
            $userExists = Send-Update -t 0 -e -c "Checking if user still exists" -r "az ad user show --id $($config.loginEmail)" | Convertfrom-Json
        } until (-not $userExists)
        #Cleanup config from deleted account
        if (Test-Path $configFile) { Remove-Item $configFile }
    }
    if ($config.muEvent -eq "Attendees") {
        Send-Update -t 1 -c "NOT deleting core group Attendees"
    }
    else {
        Send-Update -t 1 -c "Removing event: $($config.muEvent)" -r "az ad group delete --group $($config.muEvent)"
    }
    Set-Prefs -k "muEvent"
    Add-AzureMultiUserSteps
}
function Get-AzureMultiUserRegion {
    $azureLocations = Send-Update -t 1 -content "Azure: Available resource group locations?" -run "az account list-locations --query ""[?metadata.regionCategory=='Recommended'].{ name:displayName, id:name }""" | Convertfrom-Json
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
    Set-Prefs -k muAzureRegion -v $locationId
    # Send-Update -t 1 -c "Azure: Create Resource Group" -run "az group create --name $targetGroup --location $locationId -o none"
    Add-AzureMultiUserSteps
}
# Azure MU Helpers
function Get-AzureMultiUserEvent {
    ### Get existing groups
    $allGroups = Send-Update -t 0 -content "Azure: Get Events" -run "az ad group list --query '[].{displayName:displayName}'" | Convertfrom-Json | sort-object -property displayName
    $counter = 0; $eventChoices = Foreach ($i in $allGroups) {
        if ($i.displayName.substring(0,6) -eq "event-") {
            $counter++
            New-object PSCustomObject -Property @{Option = $counter; displayName = $i.displayName.substring(6) }
        }
    }
    ### Select event
    $eventChoices | sort-object -property Option | format-table -Property Option, displayName | Out-Host
    while (-not $eventName) {
        $eventSelected = read-host -prompt "Which event? <c> to create <a> for ALL <enter> to cancel"
        if (-not $eventSelected) { return }
        ### Or create a new event
        if ($eventSelected -eq "c") {
            $newName = Read-Host -prompt "New event name?"
            $eventName = ("event-$newName").tolower()
            $eventCreated = Send-Update -t 1 -content "Creating group: $eventName" -r "az ad group create --display-name $eventName --mail-nickname $eventName --only-show-errors"
            if ($eventCreated) { Send-Update -t 1 -content "Event $eventName created!" }
        }
        elseif ($eventSelected -eq "a") {
            ### Special selection for all
            $eventName = "Attendees"
        }
        else {
            $eventName = $eventChoices | Where-Object -FilterScript { $_.Option -eq $eventSelected } | Select-Object -ExpandProperty displayName -first 1
            if ($eventName) { $eventName = "event-$eventName" }
        }
        if ( -not $eventName) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
    }
    Set-Prefs -k "muEvent" -v $eventName
    Add-AzureMultiUserSteps
}
function Get-AzureMultiUser {
    if ($configEvent) {
        $configEvent | format-table muEvent, loginEmail, azureClusterStatus,azureWebAppStatus, dynatraceStatus,DynatraceTenant -wrap
        $configEvent | select-object muEvent, loginEmail, azureCluster,azureClusterStatus,azureWebApp,azureWebAppStatus,DynatraceTenant, dynatraceToken, dynatraceStatus | export-csv "output.csv"
        write-host "csv version saved to: output.csv"
    }
}
function Set-AzureMultiUserRunning {
    if ($config.muRunning -eq $true) {
        Set-Prefs -k "muRunning" -v $false
    }
    else {
        Set-Prefs -k "muRunning" -v $true 
    }
    Add-AzureMultiUserSteps  
}
function Set-AzureMultiUserCreateCluster {
    if ($config.muCreateClusters -eq $true) {
        Set-Prefs -k "muCreateClusters" -v $false
        Set-Prefs -k "muDeployDynatrace" -v $false
    }
    else {
        Set-Prefs -k "muCreateClusters" -v $true 
    }
    Add-AzureMultiUserSteps
}
function Set-AzureMultiUserCreateWebApp {
    if ($config.muCreateWebApp -eq $true) {
        Set-Prefs -k "muCreateWebApp" -v $false
    }
    else {
        Set-Prefs -k "muCreateWebApp" -v $true
    }
    Add-AzureMultiUserSteps
}
function Set-AzureMultiUserDeployDynatrace {
    if ($config.muDeployDynatrace -eq $true) {
        Set-Prefs -k "muDeployDynatrace" -v $false
    }
    else {
        Set-Prefs -k "muDeployDynatrace" -v $true
        Set-Prefs -k "muCreateClusters" -v $true
    }
    Add-AzureMultiUserSteps
}
function Set-AzureMultiUserDoNotDelete {
    $counter = 0; $userChoices = Foreach ($i in $existingUsers) {
        $counter++
        New-object PSCustomObject -Property @{Option = $counter; userName = $i.displayName; userType = $i.type; id = $i.id }
    }
    $userChoices | sort-object -property Option | format-table -Property Option, userName, userType | Out-Host
    while (-not $userId) {
        $userSelected = read-host -prompt "Which user to change?"
        if (-not $userSelected) { return }
        $userId = $userChoices | Where-Object -FilterScript { $_.Option -eq $userSelected } | Select-Object -first 1
        if (-not $userId) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
    }
    if ($userId.userType -eq "normal") {
        Send-Update -t 1 -c "Setting DoNotDelete flag for $($userId.userName)" -r "az ad group member add --group IgnoreAutomation --member-id $($userId.id)"
    }
    else {
        Send-Update -t 1 -c "Removing DoNotDelete flag for $($userId.userName)" -r "az ad group member remove --group IgnoreAutomation --member-id $($userId.id)"
    }
    Add-AzureMultiUserSteps
}

# Azure Functions
function Add-AzureSteps {
    # Get Azure specific properties from current choice
    if ($impersonateUser) {
        Set-Prefs -k "userName" -v $impersonateUser
        Send-Update -t 1 -c "Impersonating $impersonateUser"
    }
    else {
        $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
        Set-Prefs -k "userName" -v $($userProperties.userid)
    }
    Set-Resources
    Get-AzureStatus
    ### Group Actions (Y / N)
    if ($config.azureGroupStatus -eq $true) {
        Add-Choice -k "AZRG" -d "Delete Resource Group & all content" -c $config.azureGroup -f "Remove-AzureGroup"
    }
    else {
        Add-Choice -k "AZRG" -d "Required: Create Resource Group" -c "" -f "Add-AzureGroup"
        return
    }
    ### Cluster Actions (Multiple)
    if ($config.azureClusterStatus -eq "Stopped") {
        Send-Update -t 1 -c "Azure: Starting Cluster. Let's GOO!" -r "az aks start -g $($config.azureGroup) -n $($config.azureCluster)"
        Set-Prefs -k "azureClusterStatus" -v "Running"
    }
    if ($config.azureClusterStatus -eq "Running") {
        Add-Choice -k "AZAKS" -d "Delete AKS Cluster" -c $targetCluster -f "Remove-AKSCluster"
        Send-Update -t 1 -o -e -c "Azure: Get AKS Crendentials" -run "az aks get-credentials --admin -g $($config.azureGroup) -n $($config.azureCluster) --overwrite-existing --only-show-errors"
    }
    if ($config.azureClusterStatus -eq $false) {
        Add-Choice -k "AZAKS" -d "Required: Create AKS Cluster" -c "" -f "Add-AKSCluster"
        if ($config.quickDeploy -eq $true) {
            Add-AKSCluster
        }
        else {
            return
        }
    }
    ### Web Service Plan ( Multiple )
    if ($config.azureWebAppStatus -eq "Stopped") {
        Send-Update -t 1 -c "Azure: Starting Web App." -r "az webapp start -g $($config.azureGroup) -n $($config.AzureWebApp)"
        Set-Prefs -k "azureWebAppStatus" -v "Running"
    }
    if ($config.azureWebAppStatus -eq "Running") {
        Add-Choice -d "Remove Azure Web App/Plan" -c "$($config.azureServicePlan) / $($config.azureWebApp)" -f "Remove-AzureWebApp" -key "AZRWA"
    }
    if ($config.azureWebAppStatus -eq $false) {
        Add-Choice -d "Deploy Azure Web App/Plan" -f "Add-AzureWebApp" -key "AZAWA"
        if ($config.quickDeploy -eq "true") {
            Add-AzureWebApp
        }
    }
    Add-CommonSteps
}
function Add-AzureGroup {
    $azureLocations = Send-Update -t 1 -content "Azure: Available resource group locations?" -run "az account list-locations --query ""[?metadata.regionCategory=='Recommended'].{ name:displayName, id:name }""" | Convertfrom-Json
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
    Send-Update -t 1 -c "Azure: Create Resource Group" -run "az group create --name $($config.azureGroup) --location $locationId -o none"
    Add-AzureSteps
}
function Get-AzureStatus {
    #muReady
    #Group
    $groupExists = Send-Update -t 1 -content "Azure: Resource group $($config.azureGroup) exists?" -run "az group exists -g $($config.azureGroup)" -append
    if ($groupExists -eq "true") {
        Send-Update -t 1 -content " yes."
        set-prefs -k "azureGroupStatus" -v $true
    }
    else {
        Send-Update -t 1 -content " no."
        Set-Prefs -k "azureGroupStatus" -v $false
    }
    #Cluster
    $aksExists = Send-Update -t 1 -e -append -content "Azure: AKS Cluster exists?" -run "az aks show -n $($config.azureCluster) -g $($config.azureGroup) --query '{id:id, location:location, state:powerState.code, provision:provisioningState}'" | ConvertFrom-Json
    if ($aksExists.state) {
        Send-Update -t 1 -content " yes:$($aksExists.state)"
        Set-Prefs -k "azureClusterStatus" -v $aksExists.state
        if ($aksExists.state -eq "Stopped") { Set-Prefs -k "dynatraceStatus" -v $false }
    }
    else {
        Send-Update -t 1 -content " no."
        Set-Prefs -k "azureClusterStatus" -v $false
        Set-Prefs -k "dynatraceStatus" -v $false
    }
    #Dynatrace (tenant/token available)
    if (test-path "scw.csv") {
        $scwCsv = Get-Content "scw.csv" | ConvertFrom-Csv | where-object { $_.user -eq $config.loginEmail }
        if ($scwCsv.tenant.count -eq 1) { Set-Prefs -k "dynatraceTenant" -v $scwCsv.tenant } else { Set-Prefs -k "dynatraceTenant" -v "! $($scwCsv.tenant.count) found" }
        if ($scwCsv.token.count -eq 1) { Set-Prefs -k "dynatraceToken" -v $scwCsv.token } else { Set-Prefs -k "dynatraceToken" -v "! $($scwCsv.token.count) found" }

        Set-PRefs -k "dynatraceToken" -v $scwCsv.token
    }
    else {
        Set-Prefs -k "dynatraceTenant" -v "!csv"
        Set-PRefs -k "dynatraceToken" -v "!csv"
    }
    #ServicePlan
    $planExists = Send-Update -t 1 -append -c "Azure: Web App Plan exists?" -r "az appservice plan list --query ""[?name=='$($config.azureServicePlan)']""" | Convertfrom-Json
    if ($planExists) {
        Send-Update -t 1 -c " yes."
        Set-Prefs -k "azureServicePlanStatus" -v $true
    }
    else {
        Send-Update -t 1 -c " no."
        Set-Prefs -k "azureServicePlanStatus" -v $false
        Set-Prefs -k "azureWebAppStatus" -v $false
    }
    #WebApp
    $webAppExists = Send-Update -t 1 -a -c "Azure: Web App exists?" -r "az webapp list --query ""[?name=='$($config.azureWebApp)'].{ state:state }""" | Convertfrom-Json
    if ($webAppExists.state) {
        Send-Update -t 1 -c " yes:$($webAppExists.state)"
        Set-Prefs -k "azureWebAppStatus" -v $webAppExists.state
    }
    else {
        Send-Update -t 1 -c " no."
        Set-Prefs -k "azureWebAppStatus" -v $false
    }
    #Dynatrace
    if ($config.azureClusterStatus -eq "Running") {
        if ($config.multiUserMode -eq $true) {
            $kubeFile = "--file '~/scwKube/$($config.userName).kube'"
            $kube = "--kubeconfig ./scwKube/$($config.userName).kube"
        }
        Send-Update -t 1 -c "Refresh k8s credentials" -r "az aks get-credentials $kubeFile -g $($config.azureGroup) -n $($config.azureCluster) --overwrite-existing --only-show-errors"
        $allNamespaces = Send-Update -t 1 -c "Get Kubernetes Namespaces" -r "kubectl $kube get ns -ojson" | convertfrom-json | select-object -expandproperty items
        if ($allNamespaces.metadata.name -contains "dynatrace") {
            $allPods = Send-Update -t 1 -c "Dynatrace Namespace exists, check Ready Podcount" -r "kubectl $kube get pods -n dynatrace -ojson" | Convertfrom-Json
            $runningPods = ($allPods.items.status.containerStatuses.ready | Where-Object { $_ -eq "True" }).count
            if ($runningPods -eq 5) {
                Set-Prefs -k "dynatraceStatus" -v "Running"
            }
            else {
                Set-Prefs -k "dynatraceStatus" -v "Partial"
            }
        }
        else {
            Set-Prefs -k "dynatraceStatus" -v $false
        }
    }
}
function Remove-AzureGroup {
    Set-Prefs -k "quickDeploy" -v $false
    Send-Update -t 1 -content "Azure: Remove Resource Group" -run "az group delete -n $($config.azureGroup)"
    Add-AzureSteps
}
function Add-AzureWebApp {
    Send-Update -c "Creating Azure Web App Plan" -t 1 -r "az appservice plan create --name $($config.azureServicePlan) --resource-group $($config.azureGroup) --sku B2" -o
    Send-Update -c "creating Azure Web App" -t 1 -r "az webapp create --resource-group $($config.azureGroup) --name $($config.azureWebApp) --plan $($config.azureServicePlan) --runtime 'dotnet:6'" -o
    Add-AzureSteps
}
function Remove-AzureWebApp {
    Set-Prefs -k "quickDeploy" -v $false
    Send-Update -c "Removing Azure Web App" -t 1 -r "az webapp delete --resource-group $($config.azureGroup) --name $($config.azureWebApp)"
    Send-Update -c "Removing Azure Web App Plan" -t 1 -r "az appservice plan delete --resource-group $($config.azureGroup) --name $($config.azureServicePlan) -y"
    Add-AzureSteps
}
function Add-AKSCluster {
    Send-Update -o -t 1 -content "Azure: Create AKS Cluster" -run "az aks create -g $($config.azureGroup) -n $($config.azureCluster) --node-count 1 --node-vm-size 'Standard_D4s_v5' --generate-ssh-keys --only-show-errors"
    Add-AzureSteps
} 
function Remove-AKSCluster {
    Send-Update -t 1 -content "Azure: Remove AKS Cluster" -run "az aks delete -g $($config.azureGroup) -n $($config.azureCluster)"
    Add-AzureSteps
}

# AWS MU Functions
function Add-AWSMultiUserSteps {
    # Setup Variables
    if ($network) { $stackId = $network } else { $stackId = $config.AWSregion.replace("-", '') }
    Set-Prefs -k AWSroleName -v "scw-awsrole-$stackId"
    set-Prefs -k AWSnodeRoleName -v "scw-awsngrole-$stackId"
    set-prefs -k AWScfstack -v "scw-AWSstack-$stackId"
    $awsRegion = $($config.AWSregion)
    $awsRoleName = $($config.AWSroleName)
    $awsNodeRoleName = $($config.AWSnodeRoleName)
    $awsCFStack = $($config.AWScfstack)
    Add-Choice -k "AWSMCT" -d "[toggle] Auto-create EKS clusters?" -c "Currently: $($muCreateClusters)" -f Set-AWSMultiUserCreateCluster
    $existingUsers = Send-Update -c "Get Attendees" -r "aws iam get-group --group-name Attendees --no-paginate" | Convertfrom-Json
    # Create: cluster role
    $ekspolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["eks.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
    $ec2policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
    $roleExists = Send-Update -t 1 -e -c "Checking for AWS Component: cluster role" -r "aws iam get-role --region $($config.AWSregion) --role-name $($config.AWSroleName) --output json" | Convertfrom-Json
    if (!$roleExists) {
        $iamClusterRole = Send-Update -t 1 -c "Create Cluster Role" -r "aws iam create-role --region $awsRegion --role-name $awsRoleName --assume-role-policy-document '$ekspolicy'" | Convertfrom-Json
        if ($iamClusterRole.Role.Arn) {
            Send-Update -t 1 -c "Attach Cluster Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $awsRoleName"
        }
        $roleExists = $iamClusterRole
    }
    $AWSclusterRoleArn = $roleExists.Role.Arn
    # Create: nodegroup role
    $nodeRoleExists = Send-Update -t 1 -e -c "Checking for AWS Component: node role" -r "aws iam get-role --region $($config.AWSregion) --role-name $($config.AWSnodeRoleName) --output json" | Convertfrom-Json
    if (!$nodeRoleExists) {
        $iamNodeRole = Send-Update -c "Create Nodegroup Role" -r "aws iam create-role --region $awsRegion --role-name $awsNodeRoleName --assume-role-policy-document '$ec2policy'" -t 1 | Convertfrom-Json
        if ($iamNodeRole.Role.Arn) {
            Send-Update -c "Attach Worker Node Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name $awsNodeRoleName" -t 1
            Send-Update -c "Attach EC2 Container Registry Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name $awsNodeRoleName" -t 1
            Send-Update -c "Attach CNI Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name $awsNodeRoleName" -t 1
        }
        $nodeRoleExists = $iamNodeRole
    }
    $AWSnodeRoleArn = $nodeRoleExists.Role.Arn
    #Create: cloudformation stack
    $cfstackExists = Send-Update -e -t 1 -c "Checking for VPC" -r "aws cloudformation describe-stacks --region $awsRegion --stack-name $awsCFStack --output json" | Convertfrom-Json
    if (!$cfstackExists.Stacks) {
        Send-Update -t 1 -c "Create VPC with Cloudformation" -o -r "aws cloudformation create-stack --region $awsRegion --stack-name $awsCFStack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml"
        # Wait for creation
        While ($cfstackReady -ne "CREATE_COMPLETE") {
            $cfstackReady = Send-Update -a -t 1 -c "Check for 'CREATE_COMPLETE'" -r "aws cloudformation describe-stacks --region $awsRegion --stack-name $awsCFStack --query Stacks[*].StackStatus --output text"
            Send-Update -t 1 -c $cfstackReady
            Start-Sleep -s 5
        }
        $cfstackExists = $cfstackReady
    }
    #Get: details from cloudformation stack
    $cfSecurityGroup = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SecurityGroups" } | Select-Object -expandproperty OutputValue
    $cfSubnets = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SubnetIds" } | Select-Object -expandproperty OutputValue
    $cfVpicId = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "VpcId" } | Select-Object -ExpandProperty OutputValue
    # Check status for users
    $parallelResults = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    #   Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()
    $existingUsers.Users | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        if ($using:muCreateClusters) { $script:muCreateClusters = $true }
        $awsRegion = $using:awsRegion
        $AWSclusterRoleArn = $using:AWSclusterRoleArn
        $AWSnodeRoleArn = $using:AWSnodeRoleArn
        $cfSecurityGroup = $using:cfSecurityGroup
        $cfSubnets = $using:cfSubnets
        $cfVpicId = $using:cfVpicId
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
        $user = $_
        $dict = $using:parallelResults
        # Get user details
        $tags = Send-Update -c "Get user tags" -r "aws iam list-user-tags --user-name $($user.Username)" | Convertfrom-json
        foreach ($tag in $tags.Tags) {
            if ($tag.Key -eq "type") { $userType = $tag.Value }
        }
        if (!$userType) { $userType = "ignore" }
        # Check for AKS clusters
        if ($userType -eq "normal" -or $userType -eq "DoNotDelete") {
            $targetCluster = "scw-AWS-$($user.Username)"
            $targetNodeGroup = "scw-AWSNG-$($user.Username)"
            $clusterExists = Send-Update -t 1 -e -c "Check for EKS Cluster" -r "aws eks describe-cluster --region $awsRegion --name $targetCluster --output json" | ConvertFrom-Json
            if (!$clusterExists -and $muCreateClusters) {
                # Create cluster-  wait for 'active' state
                Send-Update -o -c "Create Cluster" -t 1 -r "aws eks create-cluster --region $awsRegion --name $targetCluster --role-arn $AWSclusterRoleArn --resources-vpc-config subnetIds=$cfSubnets,securityGroupIds=$cfSecurityGroup"
                While ($clusterExists.cluster.status -ne "ACTIVE") {
                    $clusterExists = Send-Update -t 1 -e -c "Wait for ACTIVE cluster" -r "aws eks describe-cluster --region $awsRegion --name $targetCluster --output json" | ConvertFrom-Json
                    # Send-Update -t 1 -c "$($clusterExists.cluster.status)"
                    Start-Sleep -s 10
                }
                # Create nodegroup- wait for 'active' state
                Send-Update -o -c "Create nodegroup" -t 1 -r "aws eks create-nodegroup --region $awsRegion --cluster-name $targetCluster --nodegroup-name $targetNodeGroup --node-role $AWSnodeRoleArn --scaling-config minSize=1,maxSize=1,desiredSize=1 --subnets $($cfSubnets.replace(',', ' ')) --instance-types t3.xlarge"
                While ($nodeGroupExists.nodegroup.status -ne "ACTIVE") {
                    $nodeGroupExists = Send-Update -t 1 -e -c "Wait for ACTIVE nodegroup" -r "aws eks describe-nodegroup --region $awsRegion --cluster-name $targetCluster --nodegroup-name $targetNodeGroup --output json" | ConvertFrom-Json
                    # Send-Update -t 1 -c "$($nodeGroupExists.nodegroup.status)"
                    Start-Sleep -s 10
                }
                # Get Credentials
                Send-Update -c "Updating Cluster Credentials" -r "aws eks update-kubeconfig --name $targetCluster --kubeconfig $($user.Username)" -t 1 -o
                # Add user principal the hard way.  Because AWS lives to make you sad.
                $map = Send-Update -c "Export configmap" -t 1 -r "kubectl get configmap aws-auth -n kube-system -o json --kubeconfig $($user.Username)" | Convertfrom-Json
                $adduser = "- groups:`n - system:masters`n rolearn: $($user.Arn)`n username: $($user.Username)`n"
                $map.data.mapRoles = $map.data.mapRoles + $adduser
                $map | convertto-json | kubectl --kubeconfig $($user.Username) replace -f -
            }
            if ($clusterExists) { $clusterCreated = $true } else { $clusterCreated = $false }
            $result = New-Object PSCustomObject -Property @{
                userName        = $user.Username
                userType        = $userType
                targetCluster   = $targetCluster
                targetNodeGroup = $targetNodeGroup
                clusterExists   = $clusterCreated
                awsRegion       = $awsRegion

            }
            $dict.add($result)
        }
    } -ThrottleLimit 8
    $global:muUsers = $parallelResults
    # Now that we have list of everyone, offer options to adjust
    # $existingUsers = Send-Update -c "Get Attendees" -r "aws iam get-group --group-name Attendees --no-paginate" | Convertfrom-Json
    # $attendeeCount = $existingUsers.Users.count - 1
    Add-Choice -k "AWSMCU" -d "Create Attendee Accounts" -f Add-AWSMultiUser -c "Current users: $($muUsers.count)"
    if ($muUsers.count -eq 0) { return }
    # We have attendees.  Provide Options to manage
    Add-Choice -k "AWSMDL" -d " List current Attendee Accounts" -f Get-AWSMultiUser
    Add-Choice -k "AWSMDU" -d " View/Change DoNotDelete users" -f Set-AWSMultiUserDoNotDelete -c "Currently: $($doNotDeleteUsers.count)"
}
function Set-AWSMultiUserDoNotDelete {
    $counter = 0; $userChoices = Foreach ($i in $muUsers) {
        $counter++
        New-object PSCustomObject -Property @{Option = $counter; userName = $i.userName; userType = $i.userType }
    }
    $userChoices | sort-object -property Option | format-table -Property Option, userName, userType | Out-Host
    while (-not $userId) {
        $userSelected = read-host -prompt "Which user to change?"
        if (-not $userSelected) { return }
        $userId = $userChoices | Where-Object -FilterScript { $_.Option -eq $userSelected } | Select-Object -first 1
        if (-not $userId) { write-host -ForegroundColor red "`r`nHey, just what you see pal." }
    }
    if ($userId.userType -eq "normal") {
        Send-Update -t 1 -c "Setting DoNotDelete flag for $($userId.userName)" -r "aws iam tag-user --user-name $($userId.userName) --tags Key=type, Value=DoNotDelete"
    }
    else {
        Send-Update -t 1 -c "Removing DoNotDelete flag for $($userId.userName)" -r "aws iam tag-user --user-name $($userId.userName) --tags Key=type, Value=normal"

    }
    Add-AWSMultiUserSteps
}
function Get-AWSMultiUser {
    # $existingUsers = Send-Update -c "Get Attendees" -r "aws iam get-group --group-name Attendees --no-paginate" | Convertfrom-Json
    write-host ""
    write-host "`rPasswords for accounts is: 1Dynatrace##"
    write-host ""
    $muUsers | Format-table -Property userName, userType, clusterExists
    write-host ""
    $muUsers | Format-table -Property userName
}
function Remove-AWSMultiUser {
    # Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()
    $normalUsers = $muUsers | where-object { $_.userType -eq "normal" }
    # Remove user accounts and all related content
    $normalUsers | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
        $user = $_
        # Remove nodegroup
        Send-Update -o -c "Delete EKS nodegroup" -r "aws eks delete-nodegroup --region $($user.awsRegion) --cluster-name $($user.targetCluster) --nodegroup-name $($user.targetNodeGroup)" -t 1
        Do {
            $nodegroupExists = Send-Update -e -c "Check status" -r "aws eks describe-nodegroup --region $($user.awsRegion) --cluster-name $($user.targetCluster) --nodegroup-name $($user.targetNodeGroup)" -t 1 | Convertfrom-Json
            Start-Sleep -s 10
            Send-Update -t 1 -c $($nodegroupExists.nodegroup.status)
        } while ($nodegroupExists)
        # Remove cluster
        Send-Update -o -c "Delete EKS CLuster" -r "aws eks delete-cluster --region $($user.awsRegion) --name $($user.targetCluster) --output json" -t 1
        Do {
            $clusterExists = Send-Update -t 1 -e -c "Check status" -r "aws eks describe-cluster --region $($user.awsRegion) --name $($user.targetCluster) --output json" | ConvertFrom-Json
            Start-Sleep -s 10
            Send-Update -t 1 -c $($clusterExists.cluster.status)
        } while ($clusterExists)
        # Remove user
        Send-Update -t 1 -c "Removing $($user.Username) from group" -r "aws iam remove-user-from-group --group-name Attendees --user-name $($user.Username)"
        Send-Update -t 1 -c "Remove login profile from $($user.Username)" -r "aws iam delete-login-profile --user-name $($user.Username)"
        Send-Update -t 1 -c "Removing $($user.Username) and all related items" -r "aws iam delete-user --user-name $($user.Username)"
        # Confirm Delete
        # Do {
        #     Start-sleep -s 2
        #     $userExists = Send-Update -t 0 -e -c  "Checking if user still exists" -r "az ad user show --id $($user.Id)" | Convertfrom-Json
        # } until (-not $userExists)
    } -ThrottleLimit 8
    Add-AWSMultiUserSteps
}
function Add-AWSMultiUser {
    # Create user accounts

    while (-not $addUserCount) {
        $addUserResponse = read-host -prompt "How many attendee accounts to generate? to cancel"
        if (-not($addUserResponse)) {
            return
        }
        try {
            $addUserCount = [convert]::ToInt32($addUserResponse)
    
        }
        catch {
            write-host "`r`nPositives integers only"
                
        }
    }
    
    # Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()
    
    # Create user accounts
    1..$addUserCount | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
            
        # Create User
        Do {
            $newUserName = Get-UserName
            $user = Send-Update -t 1 -c "Creating user $newUserName" -r "aws iam create-user --user-name $newUserName" | ConvertFrom-Json

        } Until ($user)
        Send-Update -t 1 -o -c "Add login profile for $newUserName " -r "aws iam create-login-profile --user-name $newUserName --password 1Dynatrace##"
        Send-Update -t 1 -c "Add $newUserName to group" -r "aws iam add-user-to-group --group-name Attendees --user-name $newUserName"
        Send-Update -t 1 -c "Tagging $newUserName" -r "aws iam tag-user --user-name $newUserName --tags Key=type,Value=normal"
    }
    Add-AWSMultiUserSteps
}
function Set-AWSMultiUserCreateCluster {
    if (-not $muCreateClusters) {
        $script:muCreateClusters = $true
    }
    else {
        $script:muCreateClusters = $false
    }
    Add-AWSMultiUserSteps
}

#AWS Functions
function Add-AWSSteps {
    # Get AWS specific properties from current choice
    $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
    # Save region to use in commands
    Set-Prefs -k AWSregion -v $($userProperties.id)
    Set-Prefs -k textUserId -v $($userProperties.userid)
    # -> jump to multi-user mode if selected
    if ($config.multiUserMode) {
        Add-AWSMultiUserSteps
        return
    }
    # Add all components for AWS EKS
    $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
    $userid = $userProperties.userid

    # Counter to determine how many AWS components are ready.  AWS is really annoying.
    $componentsReady = 0
    $targetComponents = 6
    # Use specified network name for CloudFormation- otherwise use default single stack for whole classroom.
    if ($network) { $stackId = $network } else { $stackId = $config.AWSregion.replace("-", '') }
    # Component: AWS cluster role
    #$targetComponents++
    Set-Prefs -k AWSroleName -v "scw-awsrole-$stackId"
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
    #$targetComponents++
    set-Prefs -k AWSnodeRoleName -v "scw-awsngrole-$stackId"
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
    set-prefs -k AWScfstack -v "scw-AWSstack-$stackId" 
    $cfstackExists = Send-Update -a -e -t 1 -c "Checking for Cloudformation Stack (4 items)" -r "aws cloudformation describe-stacks --region $($config.AWSregion) --stack-name $($config.AWScfstack) --output json" | Convertfrom-Json
    if ($cfstackExists.Stacks) {
        $componentsReady++
        Send-Update -c "Cloudformation: exists" -t 1
        Set-Prefs -k AWScfstackArn -v $($cfstackExists.Stacks.StackId)
        
        # Get Outputs needed for cluster creation
        $cfSecurityGroup = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SecurityGroups" } | Select-Object -expandproperty OutputValue
        $cfSubnets = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SubnetIds" } | Select-Object -expandproperty OutputValue
        $cfVpicId = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "VpcId" } | Select-Object -ExpandProperty OutputValue
        # Component: SecurityGroup
        if ($cfSecurityGroup) {
            Send-Update -t 1 -c "CF Security Group: exists"
            Set-Prefs -k AWSsecurityGroup -v $cfSecurityGroup
            $componentsReady++ 
        }
        else {
            Send-Update -c "CF Security Group: not found"
            Set-Prefs -k AWSsecurityGroup 
        }
        # Component: Subnets
        if ($cfSubnets) {
            Send-Update -t 1 -c "CF Subnets: exists"
            Set-Prefs -k AWSsubnets -v $cfSubnets
            $componentsReady++ 
        }
        else {
            Send-Update -t 1 -c "CF Subnets: not found"
            Set-Prefs -k AWSsubnets
        }
        # Component: VPC
        if ($cfVpicId) {
            Send-Update -t 1 -c "CF VPC Id: exists"
            Set-Prefs -k AWSvpcId -v $cfVpicId
            $componentsReady++ 
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
        Add-Choice -k "AWSBITS" -d "Required: Create AWS Components" -f "Add-AwsComponents" -c "$componentsReady/$targetComponents deployed" 
    }
    else {
        # Some components installed- offer removal option
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
function Add-AWSComponents {

    $awsRegion = $($config.AWSregion)
    $awsRoleName = $($config.AWSroleName)
    $awsNodeRoleName = $($config.AWSnodeRoleName)
    $awsCFStack = $($config.AWScfstack)

    # Create the cluster ARN role and add the policy
    #if (-not $IsWindows) {
    # Build a multi-cloud/multi-OS script they said.  It will be FUN, they said...
    # This is now working on Windows- wtf. :*(
    # Send-Update -t 0 -c "Using Windows Json format"
    # $ekspolicy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"eks.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
    # $ec2policy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"ec2.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
    # }
    # else {
    #     Send-Update -t 0 -c "Using Linux/Unix/Mac Json format"
    $ekspolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["eks.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
    $ec2policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
    # }
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
    #if ($network) {
    #Send-Update -t 1 -c "Using pre-built network $awsCFStack"
    Send-Update -t 1 -c "Create VPC with Cloudformation" -o -r "aws cloudformation create-stack --region $awsRegion --stack-name $awsCFStack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml"
    #}
    # Wait for creation
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
        if ($counter -eq 11) { Send-Update -t 1 -c "ZZzzzzzz... Taking too long. Initiating Bad Joke Generator" }
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
    Send-Update -o -c "Create nodegroup" -t 1 -r "aws eks create-nodegroup --region $($config.AWSregion) --cluster-name $($config.AWScluster) --nodegroup-name $($config.AWSnodegroup) --node-role $($config.AWSnodeRoleArn) --scaling-config minSize=1,maxSize=1,desiredSize=1 --subnets $($config.AWSsubnets.replace(",", " ")) --instance-types t3.xlarge"
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
    $AWSregion = $config.AWSregion
    $AWSclusterRoleArn = $config.AWSclusterRoleArn
    $awsRoleName = $config.AWSroleName
    $awsNodeRoleName = $config.AWSnodeRoleName
    # $awsCFStack = $config.AWScfstack
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
    if ($AWScfstackArn) {
        Send-Update -t 1 -c "Leaving CloudFormation: $($config.AWScfstack) for others in class. It's safe to delete in cloud console if you are running this stand alone."
        # Send-Update -c "Remove cloudformation stack" -t 1 -r "aws cloudformation delete-stack --region $AWSregion --stack-name $AWScfstack"
        # Do {
        #     $cfstackExists = Send-Update -e -c "Check cloudformation stack" -t 1 -r "aws cloudformation describe-stacks --region $AWSregion --stack-name $AWScfstack --query Stacks[*].StackStatus --output text"
        #     Send-Update -c $cfstackExists -t 1
        #     Start-Sleep -s 5
        # } While ($cfstackExists)
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

# GCP MU Functions
function Add-GCPMultiUser {
    # Create user accounts
    while (-not $addUserCount) {
        $addUserResponse = read-host -prompt "How many attendee accounts to generate? <enter> to cancel"
        if (-not($addUserResponse)) {
            return
        }
        try {
            $addUserCount = [convert]::ToInt32($addUserResponse)

        }
        catch {
            write-host "`r`nPositives integers only"
            
        }
    }
    # Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()

    # Create user accounts
    1..$addUserCount | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
        # Create User
        Do {
            $newUserName = Get-UserName
            # $user = Send-Update -t 1 -c "Creating user $newUserName" -r "az ad user create --display-name $newUserName --password 1Dynatrace## --force-change-password-next-sign-in false --user-principal-name $newUserName@suchcodewow.io" | ConvertFrom-Json
        } Until ($newUserName)
        write-host $newUserName
        # Send-Update -t 0 -c "Adding $newUserName to attendees group" -r "az ad group member add --group Attendees --member-id $($user.id)"

    }
    Add-GCPMultiUserSteps

}
function Get-GCPMultiUser {
    $existingUsers = Send-Update -c "Get Attendees" -r "gcloud identity groups memberships list --group-email=attendees@suchcodewow.com  --filter='-roles.name:OWNER' --format=json" | Convertfrom-Json
    write-host "`rPasswords for accounts is: 1Dynatrace##"
    write-host ""
    $existingUsers.preferredMemberKey.id

}
function Remove-GCPMultiUser {
    $existingUsers = Send-Update -t 0 -c "Get Attendees" -r "az ad group member list --group Attendees" | Convertfrom-Json
    foreach ($user in $existingUsers) {
        if ($user.userPrincipalName -contains "@suchcodewow.io") {
            # TODO fix whatever... this is
            Send-Update -t 0 -
        }
    }
    # Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()
    
    # Remove user accounts and all related content
    $existingUsers | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
        $user = $_
        # Delete  AKS if it exists
        # Delete Resource group if it exists
        # Delete User
  
        if ($user.userPrincipalName -like "*@suchcodewow.io") {
            Send-Update -t 1 -c "Removing $($user.userPrincipalName) and all related items" -r "az ad user delete --id $($user.id)"
            # Confirm Delete
            Do {
                Start-sleep -s 2
                $userExists = Send-Update -t 0 -e -c "Checking if user still exists" -r "az ad user show --id $($user.Id)" | Convertfrom-Json
            } until (-not $userExists)
        }
        else {
            Send-Update -t 2 -c "The user principal $($user.userPrincipalName) didn't mactch @suchcodewow.io. Skipping!"
        }


    }
    Add-GCPMultiUserSteps
}
function Add-GCPMultiUserCluster {
    $existingUsers = Send-Update -c "Get Attendees" -r "gcloud identity groups memberships list --group-email=attendees@suchcodewow.com --filter='-roles.name:OWNER' --format=json" | Convertfrom-Json 
    $possibleRegions = Send-Update -t 1 -c "Pull valid US Regions" -r "gcloud compute zones list --filter='name ~ us-.*' --sort-by name --format=json" | Convertfrom-Json
    $usedRegions = Send-Update -t 1 -c "Get all existing clusters" -r "gcloud container clusters list --format=json" | Convertfrom-Json
    $targetRegions = @()
    $clusterNames = @()
    write-host "Getting region list"
    foreach ($region in $possibleRegions) {
        if ($usedRegions.location -notcontains $region.name) {
            $targetRegions += $region.name
        }
    }
    write-host "Getting existing existing users"
    foreach ($user in $existingUsers) {
        $clusterName = (($user.preferredMemberKey.id).split("@")[0]).replace(".", "").ToLower()
        $clusterNames += "scw-gke-$clusterName"
    }
    [System.Collections.ArrayList]$clustersToCreate = @()
    $i = 0
    write-host "cluster assignments:"
    foreach ($cluster in $clusterNames) {
        # $clusterExists = gcloud container clusters list --filter="name=$cluster" --format=json | Convertfrom-Json
        if ($usedRegions.name -contains $cluster) {
            Send-Update -t 1 -c "$cluster already exists. Skipping"
        }
        else {
            Send-Update -t 1 -c "$cluster -> $($targetRegions[$i])"
            $newCluster = New-Object PSCustomObject -Property @{
                cluster = $cluster
                region  = $targetRegions[$i]

            }
            [void]$clustersToCreate.add($newCluster)
            $i++
        }
    }
    # Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()
    # Create clusters
    $clustersToCreate | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
        $clusterToCreate = $_
        Send-Update -t 1 -c "Creating $($clusterToCreate.cluster)" -r "gcloud container clusters create -m e2-standard-4 --num-nodes=1 --disk-size=25 --zone=$($clusterToCreate.region) $($clusterToCreate.cluster) --user-output-enabled=false"
    } -ThrottleLimit 10
}
function Remove-GCPMultiUserCluster {
    $items = Send-Update -t 1 -c "Get all clusters" -r "gcloud container clusters list --format=json" | Convertfrom-Json
    # Save functions to string to use in parallel processing
    $GetUsernameDef = ${function:Get-UserName}.ToString()
    $SendUpdateDef = ${function:Send-Update}.ToString()
    # Delete clusters
    $items | ForEach-Object -Parallel {
        # Import functions and variables from main script
        if ($using:showCommands) { $script:showCommands = $true }
        ${function:Get-UserName} = $using:GetUsernameDef
        ${function:Send-Update} = $using:SendUpdateDef
        $item = $_
        Send-Update -t 1 -c "Removing cluster $($item.name)" -r "gcloud container clusters delete $($item.name) --zone=$($item.zone) --quiet"
    } -ThrottleLimit 10
}
function Add-GCPMultiUserSteps {
    # User Options
    $existingUsers = Send-Update -c "Get Attendees" -r "gcloud identity groups memberships list --group-email=attendees@suchcodewow.com --filter='-roles.name:OWNER' --format=json" | Convertfrom-Json
    Add-Choice -k "GCPMCU" -d "Create Attendee Accounts" -f Add-GCPMultiUser -c "Current users: $($existingUsers.count)"
 
    #existingUsers fields: displayName, id, userPrincipalName
    if ($existingUsers.count -gt 0) {
        Add-Choice -k "GCPMDL" -d " Remove Attendee Accounts" -f Remove-GCPMultiUser
    }
    else {
        # End here, no existing users
        return
    }
    Add-Choice -k "GCPMCC" -d "Generate Kubernetes Clusters" -f Add-GCPMultiUserCluster -c "[NEEDS COUNT]"
    Add-Choice -k "GCPMDC" -d "Delete Kubernetes Clusters" -f Remove-GCPMultiUserCluster -c "[NEEDS COUNT]"
}

# GCP Functions
function Add-GCPSteps {
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
    # -> jump to multi-user mode if selected
    if ($config.multiUserMode) {
        add-GCPMultiUserSteps
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
    Send-Update -t 1 -c "Get Kubernetes Credentials" -r "Get-GCPCluster -c $gkeClusterName"
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
    # $env:USE_GKE_GCLOUD_AUTH_PLUGIN = True
    Send-Update -c "Get cluster creds" -t 1 -r "gcloud container clusters get-credentials  --zone $($config.gcpzone) $($config.gcpclustername)"
}
function Remove-GCPCluster {
    # Delete the GKE Cluster
    Send-Update -c "Deleting GKE cluster can take up to 10 minutes" -t 1
    Send-Update -c "Delete GKE cluster" -t 1 -r "gcloud container clusters delete --zone $($config.gcpzone) $($config.gcpclustername)"
    Add-GCPSteps
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
    $allPods = kubectl get pods -n $namespace -ojson | Convertfrom-Json
    $totalPods = $allPods.items.count
    $runningPods = ($allPods.items.status.containerStatuses.ready | Where-Object { $_ -eq "True" }).count
    return "$runningPods/$totalPods pods READY"
}
function Remove-NameSpace {
    param(
        [string] $namespace
    )
    While (!$optionSelected) {
        $userChoice = (read-host -prompt "Remove namespace? (typically NO unless ending workshop!) Y/N?").toUpper()
        if ($userChoice -eq "Y" -or $userChoice -eq "N") {
            $optionSelected = $userChoice
        }
        else {
            write-host "Y or N only please!"
        }
        
    }
    if ($optionSelected -eq "Y") {
        Send-Update -t 1 -c "Delete Namespace" -r "kubectl delete ns $namespace"
        Add-CommonSteps
    }
}

# Dynatrace Functions
function Set-DTConfig {
    While (-not $k8sToken) {
        # Get Tenant ID
        While (-not $cleantenantID) {
            $tenantID = read-Host -Prompt "Dynatrace Tenant ID <enter> to cancel"
            if (-not $tenantID) {
                return
            }
            if ($Matches) { Clear-Variable Matches }
            $tenantID -match '\w{8}' | Out-Null
            if ($Matches) { $cleanTenantID = $Matches[0] }
            else { write-host "Tenant ID should be at least 8 alphanumeric characters." }
        }
        # Add support for sprint tenants
        if ($tenantID -like "*sprint*") {
            # Sprint tenant
            $tenantURL = "$cleanTenantID.sprint.dynatracelabs.com"
        }
        else {
            # Assumne live tenant
            $tenantURL = "$cleanTenantID.live.dynatrace.com"
        }
        # Get Token
        While (-not $cleanToken) {
            $token = read-Host -Prompt "Token with 'Write API token' permission <enter> to cancel"
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
                write-host "Tokens start with 'dt0' and are at least 80 characters."
            }
    
        }
        $headers = @{
            accept         = "application/json; charset=utf-8"
            "Content-Type" = "application/json; charset=utf-8"
            Authorization  = "Api-Token $token"
        }
        $data = @{
            scopes              = @("activeGateTokenManagement.create", "entities.read", "settings.read", "settings.write", "DataExport", "InstallerDownload", "logs.ingest", "openTelemetryTrace.ingest")
            name                = "SCW Token"
            personalAccessToken = $false
        }
        $body = $data | ConvertTo-Json
        Try {
            $response = Invoke-RestMethod -Method Post -Uri "https://$tenantURL/api/v2/apiTokens" -Headers $headers -Body $body
        }
        Catch {
            # The noise, ma'am.  Suppress the noise.
            write-host "Error Code: " $_.Exception.Response.StatusCode.value__
            Write-Host "Description:" $_.Exception.Response.StatusDescription
        }
        if ($response.token) {
            # API Token has to be base64. #PropsDaveThomas<3
            $k8stoken = $response.token
            Set-Prefs -k tenantID -v $tenantURL
            Set-Prefs -k writeToken -v $token
            Set-Prefs -k k8stoken -v $k8stoken
            # Set-Prefs -k base64Token -v $base64Token
            Add-DynakubeYaml -t $k8stoken -u $tenantURL -c "k8s$($choices.callProperties.userid)"
        }
        else {
            write-host "Failed to connect to $tenantURL"
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
    #muReady
    param (
        [string] $token, # Dynatrace API token
        [string] $url, # URL To Dynatrace tenant
        [string] $clusterName, # Name of cluster in Dynatrace
        [string] $muUsername # optional name of MU attendee
    )
    $base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($token))
    $fullURL = "https://$url/api"
    if ($muUsername) {
        $configName = $muUsername
    }
    else {
        $configName = $config.textUserId
    }
    if ($config.provider -eq "GCP") {
        $storage = "true"
    }
    else {
        $storage = "false"
    }
    $dynaKubeContent = 
    @"
apiVersion: v1
kind: ConfigMap
metadata:
    name: scw
data:
    tenantid: $url
    k8stoken: $token
---
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
  apiUrl: $fullURL
  skipCertCheck: true
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
          value: "$storage"
  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
    customProperties:
      value: |
        [azure_monitoring]
        azure_monitoring_enabled=true
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1.5Gi
"@
    if ($config.multiUserMode -eq $true) {
        $dynaKubeContent | out-File -FilePath "~/scwYaml/$($configName)-dynakube.yaml"
    }
    else {
        $dynaKubeContent | out-File -FilePath "dynakube.yaml"
    }
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
        Send-Update -c " $($counter)..." -t 1 -a
        Start-Sleep -s 1
        #Query for namespace viability
        $namespaceState = (kubectl get ns dynatrace -ojson | Convertfrom-Json).status.phase
    }
    Send-Update -c " Activated!" -t 1
    Send-Update -c "Loading Operator" -t 1 -r "kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml"
    Send-Update -c "Waiting for pod to activate" -t 1 -r "kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s"
    Send-Update -c "Loading dynakube.yaml" -t 1 -r "kubectl apply -f $($config.textUserId)-dynakube.yaml"
    Add-CommonSteps
}
function Get-DTconnected {
    # Check if Dynatrace token and url are valid
    Send-Update -c "Checking for valid Dynatrace connection details." -t 1
    # If tenant & token missing, import from Configmap if available
    if (-not $config.tenantID -or -not $config.k8stoken) {
        $configMap = Send-Update -t 0 -c "Importing Dynatrace details from ConfigMap" -r "kubectl get cm -o json" | ConvertFrom-Json
        $scwData = $configMap.items | where-object { $_.metadata.name -eq "scw" }
        if ($scwData.data.tenantid -and $scwData.data.k8stoken) {
            Set-Prefs -k tenantID -v $scwData.data.tenantid
            Set-Prefs -k k8stoken -v $scwData.data.k8stoken
            Send-Update -t 0 -c "Imported!"
        }
    }
    if ($config.tenantID -AND $config.k8stoken) {
        $url = $config.tenantID
        $token = $config.k8stoken
        $headers = @{
            accept         = "application/json; charset=utf-8"
            "Content-Type" = "application/json; charset=utf-8"
            Authorization  = "Api-Token $token"
        }
        # $data = @{
        #     scopes              = @("activeGateTokenManagement.create", "entities.read", "settings.read", "settings.write", "DataExport", "InstallerDownload")
        #     name                = "SCW Token"
        #     personalAccessToken = $false
        # }
        $body = $data | ConvertTo-Json
        Try {
            $response = Invoke-RestMethod -Method Get -Uri "https://$url/api/v1/config/clusterversion" -Headers $headers -Body $body
        }
        Catch {
            # The noise, ma'am.  Suppress the noise.
            write-host "Error Code: " $_.Exception.Response.StatusCode.value__
            Write-Host "Description:" $_.Exception.Response.StatusDescription
        }
        if ($response.version) {
            return $true
        }
        else {
            # We had a token but it didn't work.  Let calling function clean up.
            return $false
        }
        
    }
    else {
        return $false
    }
}
function Get-DynatraceToken {
    $authRule = Send-Update -t 0 -c "Get authorization rules" -r "az eventhubs eventhub authorization-rule keys list --eventhub-name scw-$($config.k8sregion)-ehub --namespace-name scw-$($config.k8sregion)-ehubns --name scw-$($config.k8sregion)-ehubns-auth-rule --resource-group scw-$($config.k8sregion)-common --only-show-errors" | Convertfrom-Json
    write-host ""
    write-host "Dynatrace Environment ID:"
    write-host $config.tenantID.split(".")[0]
    write-host ""
    write-host "Dynatrace API Token:"
    write-host $config.k8stoken
    write-host ""
    if ($config.tenantID -notlike "*live*") {
        write-host "Server URL:"
        write-host "https://$($config.tenantID)/api"
        write-host ""
    }
    if ($config.textUserId.length -gt 15) {
        $logName = $config.textUserId.substring(0, 15)
    }
    else {
        $logName = $config.textUserId
    }
    write-host "export DEPLOYMENT_NAME=log$logName"
    write-host "export TARGET_URL=https://$($config.tenantID)"
    write-host "export TARGET_API_TOKEN=$($config.k8stoken)"
    write-host "export RESOURCE_GROUP=$($config.resourceGroup)"
    write-host "export EVENT_HUB_CONNECTION_STRING=""$($authRule.primaryConnectionString)"""
    write-host ""
    read-host -prompt "Press the <any> key to continue"
}

# Application Functions
function Add-CommonSteps {
    # Get namespaces so we know what's installed or not
    $existingNamespaces = Send-Update -c "Getting Namespaces" -t 0 -r "(kubectl get ns -o json  | Convertfrom-Json).items.metadata.name"
    Send-Update -c "Namespaces: $existingNamespaces" -t 0
    # Check for valid Dynatrace connection
    $DTconnected = Get-DTconnected
    if ($DTconnected) {
        # Determine appropriate Dynatrace optionyamlName
        if ($existingNamespaces.contains("dynatrace")) {
            # Dynatrace installed.  Add status and removal options
            Add-Choice -k "DTCFG" -d "Dynatrace: Remove" -f "Remove-NameSpace -n dynatrace" -c "DT tenant: $($config.tenantID)"
            Add-Choice -k "STATUSDT" -d "Dynatrace: Show Pods" -c $(Get-PodReadyCount -n dynatrace) -f "Get-Pods -n dynatrace"
            Add-Choice -k "TOKENDT" -d "Dynatrace: Token Details" -f Get-DynatraceToken
        }
        elseif (test-path "$($config.textUserId)-dynakube.yaml") {
            Add-Choice -k "DTCFG" -d "dynatrace: Deploy to k8s" -c "Target DT tenant: $($config.tenantID)" -function Add-Dynatrace
        }
        else {
            #3 Nothing done for dynatrace yet.  Add option to download YAML
            Add-Choice -k "DTCFG" -d "dynatrace: Create dynakube.yaml" -f Set-DTConfig
        }
    }
    else {
        if ($existingNamespaces.contains("dynatrace")) {
            # Recommend removing dynatrace since no valid dynakube detected
            While (!$optionSelected) {
                $userChoice = (read-host -prompt "Dynatrace connection missing/invalid, remove dynatrace operator? (recommended!) Y/N ?").toUpper()
                if ($userChoice -eq "Y" -or $userChoice -eq "N") {
                    $optionSelected = $userChoice
                }
                else {
                    write-host "Y or N only please!"
                }
            }
            if ($optionSelected -eq "Y") {
                if ($existingNamespaces.contains("dynatrace")) {
                    Send-Update -c "Dynatrace connection invalid, remove namespace" -r "Remove-NameSpace -n dynatrace" -t 1
                }
                # Yaml files depend on URLs/tokens, remove them
                foreach ($yaml in $config.yamlList) {
                    [uri]$uri = $yaml
                    $yamlName = "$($uri.Segments[-1]).yaml"
                    if (test-path $yamlName) { remove-item $yamlName }
                }
                if (test-path "$($config.textUserId)-dynakube.yaml") { Remove-item "$($config.textUserId)-dynakube.yaml" }
            }
        }
        # Add first Dynatrace option
        Add-Choice -k "DTCFG" -d "dynatrace: Create dynakube.yaml" -f Set-DTConfig
    }
    # If Dynatrace is running, we're able to download yaml and adjust as needed
    if ($DTconnected -and $existingNamespaces.contains("dynatrace")) {
        [System.Collections.ArrayList]$yamlReady = @()
        foreach ($yaml in $config.yamlList) {
            [uri]$uri = $yaml
            $yamlName = "$($uri.Segments[-1]).yaml"
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
            $downloadType = "$($yamlReady.count)/$($config.yamlList.count) downloaded"
        }
        Add-Choice -k "DLAPPS" -d "Download demo apps yaml files" -f Get-Apps -c $downloadType
        # Add options to kubectl apply, delete, or get status (show any external svcs here in current)
        foreach ($app in $yamlReady) {
            # check if this app is deployed. Use name of yaml file as namespace (dbic.yaml should have dbic namespace)
            $ns = $app.namespace
            if ($existingNamespaces.contains($ns)) {
                # Namespace exists- add status option
                Add-Choice -k "STATUS$ns" -d "$($ns): Refresh/Show Pods" -c "$(Get-PodReadyCount -n $ns)" -f "Get-Pods -n $ns"
                # add restart option
                Add-Choice -k "RESTART$ns" -d "$($ns): Reset Pods" -c $(Get-AppUrls -n $ns ) -f "Restart-Pods -n $ns"
                # add remove option
                Add-Choice -k "DEL$ns" -d "$($ns): Remove Pods" -f "Remove-NameSpace -n $ns"
                # parse any custom options
                # Get-CustomSteps -n $ns
            }
            else {
                # Yaml is available but not yet applied.  Add option to apply it
                Add-Choice -k "INST$ns" -d "$($ns): Deploy App" -f "Add-App -y $($app.name) -n $ns"
            }
        }
    }
}
function Get-Apps {
    foreach ($yaml in $config.yamlList) {
        # Get base yaml file for kubernetes
        [uri]$uri = $yaml
        $yamlName = "$($uri.Segments[-1]).yaml"
        Invoke-WebRequest -Uri "$($uri.OriginalString).yaml" -OutFile $yamlName | Out-Host
        ((Get-Content -path $yamlName -Raw) -replace '<dynatraceURL>', $config.tenantID) | Set-Content -Path $yamlName
        ((Get-Content -path $yamlName -Raw) -replace '<dynatraceToken>', $config.k8stoken) | Set-Content -Path $yamlName
        ((Get-Content -path $yamlName -Raw) -replace 'dnsplaceholder', "scw$($config.textUserId)") | Set-Content -Path $yamlName
        # Get config options if they exist
        $jsonName = "$($uri.Segments[-1]).json"
        $jsonFile = Invoke-WebRequest -SkipHttpErrorCheck -Uri "$($uri.OriginalString).json"
        if ($jsonFile.StatusCode -eq 200) {
            $jsonFile.RawContent | Out-file -Filepath $jsonName
        }
    }
    Send-Update -c "Downloaded $($config.yamlList.count)" -type 1
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
            if (-not $returnList) { $returnList = "" }
            # Azure was using IP address.  Switched to hostname for default AWS
            if ($service.status.loadBalancer.ingress[0].hostname) {
                $returnList = "$returnList http://$($service.status.loadBalancer.ingress[0].hostname)"
            }
            if ($namespace -eq "dbic" -and $config.provider -eq "azure") {
                $returnList = "http://scw$($config.textUserId).$($config.k8sregion).cloudapp.azure.com"
            }
            if ($service.status.loadBalancer.ingress[0].ip) {
                $returnList = "$returnList http://$($service.status.loadBalancer.ingress[0].ip)"
            }

            
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
    Send-Update -c "Waiting 10s for namespace [$namespace] to activate:" -a -t 1
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

Get-Prefs
while ($choices.count -gt 0) {
    $cmd = Get-Choice($choices)
    if ($cmd) {
        Invoke-Expression $cmd.callFunction
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
# Example parallel run:
# 1..2 | ForEach-Object -ThrottleLimit 15 -Parallel {
#     $using:muFunctions | ForEach-Object { . $_ }
#     Set-Prefs -u $_
# }

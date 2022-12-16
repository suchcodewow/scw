# VSCODE: ctrl/cmd+k+1 folds all functions, ctrl/cmd+k+j unfold all functions. Check '.vscode/launch.json' for any current parameters
param (
    [switch] $verbose, # default output level is 1 (info/errors), use -v for level 0 (debug/info/errors)
    [switch] $cloudCommands, # enable to show commands
    [switch] $logReset, # enable to reset log between runs
    [switch] $aws, # use aws
    [switch] $azure, # use azure
    [switch] $gcp # use gcp
)

# Core Script Functions
function Send-Update {
    # Handle output to screen & log, execute commands to cloud systems and return results
    param(
        [string] $content, # Message content to log/write to screen
        [int] $type, # [0/1/2] log levels respectively: debug/info/errors, info/errors, errors
        [string] $run, # Run a command and return result
        [switch] $append, # [$true/false] skip the newline (next entry will be on same line)
        [switch] $suppressErrors # use this switch to suppress error output (useful for extraneous warnings) 
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
    if ($run -and $suppressErrors) { return invoke-expression $run 2>$null }
    if ($run) { return invoke-expression $run }
}
function Get-Prefs($scriptPath) {
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
    $script:ProgressPreference = "SilentlyContinue"
    if ($scriptPath) {
        $script:logFile = "$($scriptPath).log"
        Send-Update -c "Log: $logFile"
        if ((test-path $logFile) -and -not $retainLog) {
            Remove-Item $logFile
        }
        $script:configFile = "$($scriptPath).conf"
        Send-Update -c "Config: $configFile"
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
            $config["schemaVersion"] = "1.2"
            if ($MyInvocation.MyCommand.Name) {
                $config | ConvertTo-Json | Out-File $configFile
                Send-Update -c "CREATED config" -t 0
            }
        }
    } 
    write-host

}
function Set-Prefs {
    param(
        $k, # key
        $v # value
    )
    if ($v) {
        Send-Update -c "Updating config key: $k"
        $config[$k] = $v 
    }
    else {
        if ($k -and $config.containsKey($k)
        ) {
            Send-Update -c "Deleting config key: $k"
            $config.remove($k)
        }
        else {
            Send-Update -c "Key didn't exist: $k"
        }
         
    }
    if ($MyInvocation.MyCommand.Name) {
        Send-Update -c "Setting config key: $k value: $v" -t 0
        $config | ConvertTo-Json | Out-File $configFile
    }
    else {
        Send-Update -c "No command name, skipping write" -type 0
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
        $staleOptions | foreach-object { Send-Update -content "Removing $($_.Option) $($_.key)" -type 0; $choices.remove($_) }
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

# Utility Functions
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
            $returnList = "$returnList http://$($service.status.loadBalancer.ingress[0].ip)"
        }
    }
    #Return list
    return $returnList

}
function Add-CommonSteps() {
    # Get namespaces so we know what's installed or not
    $existingNamespaces = (kubectl get ns -o json | Convertfrom-Json).items.metadata.name
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
    # Option to download any needed support files
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
    Add-Choice -k "DLAPPS" -d "Download Sample Apps Yaml" -f Get-Apps -c $downloadType
    # Add options to kubectl apply, delete, or get status (show any external svcs here in current)
    
    foreach ($app in $yamlReady) {
        # check if this app is deployed using main part of filename as namespace
        $ns = $app.namespace
        if ($existingNamespaces.contains($ns)) {
            # Namespace exists- add status option
            Add-Choice -k "STATUS$ns" -d "$ns : Refresh/Show Pods" -c "$(Get-PodReadyCount -n $ns)" -f "Get-Pods -n $ns"
            # add remove option
            Add-Choice -k "DEL$ns" -d "$ns : Remove" -c  $(Get-AppUrls -n $ns ) -f "Remove-NameSpace -n $ns"
        }
        else {
            # Yaml is available but not yet applied.  Add option to apply it
            Add-Choice -k "INST$ns" -d "$ns : Deploy App" -f "Add-App -y $($app.name) -n $ns"        
        }
    }
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
        if ($counter -ge 10) {
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
function Get-Pods {
    param(
        [string] $namespace #namespace to return pods
    )
    Send-Update -t 1 -c "Showing pod status" -r "kubectl get pods -n $namespace"
    Add-CommonSteps
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
    # AZURE
    Send-Update -content "Gathering provider options: " -type 1 -append
    $providerList.Clear()
    if ($useAzure) {
        Send-Update -content "Azure:" -type 1 -append
        if (get-command 'az' -ea SilentlyContinue) {
            $azureSignedIn = az ad signed-in-user show 2>$null 
        }
        else { Send-Update -content "NA " -type 2 -append }
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
        Send-Update -content "$($allAccounts.count) " -append -type 1
    }
    # AWS
    if ($useAWS) {
        Send-Update -content "AWS:" -type 1 -append
        if (get-command 'aws' -ea SilentlyContinue) {
            # below doesn't work for non-admin accounts
            #$awsSignedIn = aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]'
            # instead, check environment variables for a region
            $awsRegion = $env:AWS_REGION
        }
        else { Send-Update -content "NA " -type 2 -append }
        if (-not $awsRegion) {
            # No region in environment variables, trying pulling from local config
            $awsRegion = aws configure get region
        }
        if ($awsRegion) {
            # We have a region- get a userid
            (aws sts get-caller-identity --output json 2>$null | Convertfrom-JSon).UserId -match "-(.+)\.(.+)@" 1>$null
            if ($Matches.count -eq 3) {
                $awsSignedIn = "$($Matches[1])$($Matches[2])"
            }
            else {
                $awsSignedIn = (aws sts get-caller-identity --output json | Convertfrom-JSon).UserId.subString(0, 6)
            }
            #TODO: Handle situation with root/password accounts
        }
        if ($awsSignedIn) {
            # Add-Provider(New-object PSCustomObject -Property @{Provider = "AWS"; Name = "region:  $($awsSignedIn)"; Identifier = $awsSignedIn; default = $true })
            Add-Provider -d -p "AWS" -n "region: $awsRegion" -i $awsSignedIn -u $awsSignedIn
            Send-Update -c "1 " -append -type 1
        }
        else {
            # Total for AWS is just 1 or 0 for now so use this toggle
            Send-Update -c "0 " -append -type 1
        }
    }
    # GCP
    if ($useGCP) {
        Send-Update -content "GCP:" -type 1 -append
        if (get-command 'gcloud' -ea SilentlyContinue) {
            $accounts = gcloud auth list --format="json" | ConvertFrom-Json 
        }
        else { Send-Update -content "NA " -type 2 -append }
        if ($accounts.count -gt 0) {
            #$currentProject = gcloud config get-value project
            #$allProjects = gcloud projects list --format='json' | COnvertfrom-Json
            foreach ($i in $accounts) {
                $Params = @{}
                if ($i.status -eq "ACTIVE") { $Params['d'] = $true } 
                Add-Provider @Params -p "GCP" -n "account: $($i.account)" -i $i.account -u (($i.account).split("@")[0]).replace(".", "")
            }
        }
        Send-Update -content "$($accounts.count) " -append -type 1
        
    }
    # Done getting options
    Send-Update -content "Done!" -type 1
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
    Add-Choice -k "TARGET" -d "Change Target" -c "$($providerSelected.Provider) $($providerSelected.Name)" -f "Set-Provider" -p $functionProperties
    # build options for specified provider
    switch ($providerSelected.Provider) {
        "Azure" {
            # Set the Azure subscription
            Send-Update -content "Azure: Set Subscription" -run "az account set --subscription $($providerSelected.identifier)"
            Add-AzureSteps 
        }
        "AWS" {
            Send-Update -content "AWS: Set region"
            Add-AWSSteps 
        }
        "GCP" { 
            # set the GCP Project
            Send-Update -content "GCP: Set Project" -run "gcloud config set account '$($providerSelected.identifier)'"
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
    $groupExists = Send-Update -content "Azure: Resource group exists?" -run "az group exists -g $targetGroup --subscription $SubId" -append
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
    $targetCluster = "scw-AKS-$($userProperties.userid)"
    $aksExists = Send-Update -content "Azure: AKS Cluster exists?" -run "az aks show -n $targetCluster -g $targetGroup --query id" -append
    if ($aksExists) {
        send-Update -content "yes" -type 0
        Add-Choice -k "AZAKS" -d "Delete AKS Cluster" -c $targetCluster -f "Remove-AKSCluster -c $targetCluster -g $targetGroup"
        Add-Choice -k "AZCRED" -d "Refresh k8s credential" -f "Get-AKSCluster -c $targetCluster -g $targetGroup"
        #We have a cluster so add common things to do with it
        Add-CommonSteps
    }
    else {
        send-Update -content "no" -type 0
        Add-Choice -k "AZAKS" -d "Required: Create AKS Cluster" -c "" -f "Add-AKSCluster -g $targetGroup -c $targetCluster"
    }
}
function Add-AzureResourceGroup($targetGroup) {
    $azureLocations = Send-Update -content "Azure: Available resource group locations?" -run "az account list-locations --query ""[?metadata.regionCategory=='Recommended']. { name:displayName, id:name }""" | Convertfrom-Json
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
    Send-Update -content "Azure: Create Resource Group" -run "az group create --name $targetGroup --location $locationId -o none"
    Add-AzureSteps
}
function Remove-AzureResourceGroup($targetGroup) {
    Send-Update -content "Azure: Remove Resource Group" -run "az group delete -n $targetGroup"
    Add-AzureSteps
}
function Add-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -content "Azure: Create AKS Cluster" -run "az aks create -g $g -n $c --node-count 1 --node-vm-size 'Standard_D2s_v4' --generate-ssh-keys"
    Get-AKSCluster -g $g -c $c
    Add-AzureSteps
    Add-CommonSteps
} 
function Remove-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -content "Azure: Remove AKS Cluster" -run "az aks delete -g $g -n $c"
    Add-AzureSteps
}
function Get-AKSCluster() {
    param(
        [string] $g, #resource group
        [string] $c #cluster name
    )
    Send-Update -content "Azure: Get AKS Crendentials" -run "az aks get-credentials --admin -g $g -n $c --overwrite-existing"
}

# AWS Functions
function Add-AWSSteps() {
    $userProperties = $choices | where-object { $_.key -eq "TARGET" } | select-object -expandproperty callProperties
    $userid = $userProperties.userid
    # Counter to determine how many AWS components are ready.  AWS is really annoying.
    $componentsReady = 0
    $removeString = " "
    # Check if AWS role exists
    $roleName = "scw-awsrole-$userid"
    $roleExists = Send-Update -s -c "Checking for AWS Component: role" -r "aws iam get-role --role-name $roleName" -a
    if ($roleExists) {
        Send-Update -c "exists" -t 1
        $removeString = "$removeString -r $roleName"
        $componentsReady++
    }
    else {
        Send-Update -c "not found" -t 1
    }
    # Check for VPC
    $vpcName = "scw-vpc-$userid"
    $vpcExists = Send-Update -a -c "Checking AWS Component: VPC" -r "aws ec2 describe-vpcs --filters Name=tag:Name,Values=$vpcName --output json" | Convertfrom-Json
    if ($vpcExists.Vpcs) {
        Send-Update -c "exists" -t 1
        $removeString = "$removeString -v $($vpcExists.VPCS.VpcID)"
        $componentsReady++
    }
    else {
        Send-Update -c "not found" -t 1
    }
    $targetComponents = 4
    if ($componentsReady -eq $targetComponents) {
        # Need to confirm total components and if enough, provide remove components option and create cluster option
        Add-Choice -k "AWSBITS" -d "Remove AWS Components" -c "$counter/$targetComponents deployed" -f "Remove-AWSComponents $removeString"
    }
    elseif ($componentsReady -eq 0) {
        # No components yet.  Add option to create
        Add-Choice -k "AWSBITS" -d "Required: Create AWS Components" -f "Add-AwsComponents -r $roleName -v $vpcName"
        return
    }
    else {
        # Some components installed.  Offer removal option
        Add-Choice -k "AWSBITS" -d "Remove Partial Components" -c "$componentsReady/$targetComponents deployed" -f "Remove-AWSComponents $removeString"
        return
    }
    # Passed the Components steps.  Check for existing cluster.
    $clusterName = "scw-AWS-$userid"
    $clusterExists = Send-Update -c "Check for EKS Cluster" -r "aws eks list-clusters --output json" | ConvertFrom-Json
    #TODO: Adjust above to find 1 cluster
    if ($clusterExists.clusters) {
        Add-Choice -k "AWSEKS" -d "Remove EKS Cluster" -c $clusterName -f "Remove-AWSCluster -c $clusterName"
    }
    else {
        Add-Choice -k "AWSEKS" -d "Required: Deploy EKS Cluster" -f "Add-AWSCluster -c $clusterName"
    }
    Add-CommonSteps
}
function Add-AWSComponents {
    param (
        [string] $roleName, # AWS ARN Role
        [string] $vpcName, # VPC Name
        [string] $clusterName # Cluster name
    )
    # Create the ARN role and add the policy
    $policy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"eks.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
    $iamrole = Send-Update -c "Create Role" -r "aws iam create-role --role-name $roleName --assume-role-policy-document '$policy'" -t 1 | Convertfrom-Json
    if ($iamrole.Role.Arn) {
        Set-Prefs -k "AWSEksArn" -v "$($iamrole.Role.Arn)"
        Send-Update -c "Attach Role Policy" -r "aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $roleName"
    }
    # Create a VPC
    $vpcResult = Send-Update -c "Create VPC" -r "aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specification ResourceType=vpc,Tags='[{Key=Name,Value=$vpcName}]' --output json" | Convertfrom-Json
    $vpcId = $vpcResult.Vpc.VpcId
    Set-Prefs -k awsVpcId -v $vpcId
    # Get Availability Zones
    $availabilityZones = (aws ec2 describe-availability-zones --region us-east-2 | Convertfrom-Json).AvailabilityZones.zoneName
    $firstSubnet = Send-Update -c "Add subnet 1" -r "aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.0.0/24 --availability-zone $($availabilityZones[0])"
    Set-Prefs -k awsSubnet1 -v $firstSubnet.Subnet.SubnetId
    $secondSubnet = Send-Update -c "Add subnet 2" -r "aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.1.0/24 --availability-zone $($availabilityZones[1])"
    Set-Prefs -k awsSubnet2 -v $secondSubnet.Subnet.SubnetId
    Add-AwsSteps
}
function Add-AWSCluster {
    param(
        [string] $clusterName,
        [string] $roleArn,
        [string] $vpcConfig
    )

}
function Remove-AWSComponents {
    param (
        [string] $roleName, # User unique identifier
        [string] $vpcId # VPC identifier
    )
    if ($roleName) {
        # Get and remove any attached policies
        $attachedPolicies = Send-Update -c "Get Attached Policies" -r "aws iam list-attached-role-policies --role-name $roleName --output json" | Convertfrom-Json
        foreach ($policy in $attachedPolicies.AttachedPolicies) {
            Send-Update -c "Remove Policy" -r "aws iam detach-role-policy --role-name $roleName --policy-arn $($policy.PolicyArn)"
        }
        # Finally deleted the role.  OMG AWS.
        Send-Update -c "Delete Role" -r "aws iam delete-role --role-name $roleName" 
    }
    if ($vpcId) {
        # Get and remove any dependencies
        $depSubnets = Send-Update -c "Get VPC subnets" -r "aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcId --output json" | Convertfrom-Json
        foreach ($subnet in $depSubnets.Subnets) {
            Send-Update -c "Delete subnet" -r "aws ec2 delete-subnet --subnet-id $($subnet.SubnetId)"
        }
        Send-Update -c "Delete VPC" -r "aws ec2 delete-vpc --vpc-id $vpcId" 
    }
    Add-Awssteps
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
    $existingCluster = Send-Update -c "Check for existing cluster" -r "gcloud container clusters list --filter=name=$gkeClusterName --format='json' | Convertfrom-Json"
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
    Send-Update -content "GCP: Select Project" -run "gcloud config set project $projectId"
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

    Send-Update -content "GCP: Create GKE cluster" -t 1 -run "gcloud container clusters create --zone $zone $clusterName"
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
        cpu: 250m
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

# Startup
Get-Prefs($Myinvocation.MyCommand.Source)
Get-Providers

# Main Menu loop
while ($choices.count -gt 0) {
    $cmd = Get-Choice($choices)
    if ($cmd) {
        Invoke-Expression $cmd.callFunction
    }
    else { write-host -ForegroundColor red "`r`nY U no pick existing option?" }
}
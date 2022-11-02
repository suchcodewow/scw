#region ---Variables
$selectedCLI = $false
[System.Collections.ArrayList]$providerList = @()
[System.Collections.ArrayList]$choices = @()
#endregion

#region ---Functions 
function addChoice($choice) {
    #Adds a choice to the menu
    $choice | Add-Member -MemberType NoteProperty -Name Option -value $($choices.count + 1)
    [void]$choices.add($choice)
}

function addProvider($provider) {
    #---Add an option selector to item then add to provider list
    $provider | Add-Member -MemberType NoteProperty -Name Option -value $($providerList.count + 1)
    [void]$providerList.add($provider)
}
#endregion

# Do we have access to Azure?
if (get-command 'az' -ea SilentlyContinue) { $azureSignedIn = az ad signed-in-user show 2>$null } 
if ($azureSignedIn) {
    #Azure connected, get current subscription
    $currentAccount = az account show --query 'id' | Convertfrom-Json
    $allAccounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
    foreach ($i in $allAccounts) {
        if ($i.id -eq $currentAccount) { $defaultOption = $true } else { $defaultOption = $false }
        addProvider(New-object PSCustomObject -Property @{Provider = "Azure"; Name = $i.name; Identifier = $i.id; default = $defaultOption })
    }
}

#Do we have access to AWS?
if (get-command 'aws' -ea SilentlyContinue) { $awsSignedIn = aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]' 2>$null }
if ($awsSignedIn) {
    addProvider(New-object PSCustomObject -Property @{Provider = "AWS"; Name = $awsSignedIn; default = $true })
}
if ($providerList.count -eq 0) { write-output "`nCouldn't find a valid target cloud environment. `nConfirm you have at least one az, aws, or gcloud command available in your path & you are logged in.`n" }
$providerDefault = $providerList | Where-Object default -eq $true
if ($providerDefault.count -eq 1) {
    addChoice(New-object PSCustomObject -Property @{Key = "target"; Description = "Change Setup Target"; Current = " $($providerDefault[0].Provider) -> $($providerDefault[0].Name)" })
}
#write-output $providerList | sort-object -property Option | format-table -Property Option, Provider, Name, Identifier, default
write-output $choices | sort-object -property Option
#Option, Key, Description, Current, Function, Properties
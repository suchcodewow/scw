Remove-Variable * -ea SilentlyContinue; Remove-Module *; $error.Clear()
$Global:selectedCLI = $false
$Global:providerList = @()
$Global:choices = @()

#region ---Functions 
function addChoice($choice) {
    #Adds a choice to the menu
}

function addProvider($provider) {
    #---Add an option selector to item then add to provider list
    $provider | Add-Member -MemberType NoteProperty -Name Option -value $($ProviderList.count + 1)
    $Global:providerList += $provider
}
#endregion

# Do we have access to Azure?

if (get-command 'az' -ea SilentlyContinue) { $azureSignedIn = az ad signed-in-user show 2>null } 
if ($azureSignedIn) {
    #Azure connected, get current subscription
    $currentAccount = az account show --query 'id' | Convertfrom-Json
    $allAccounts = az account list --query '[].{name:name, id:id}' --only-show-errors | ConvertFrom-Json
    foreach ($i in $allAccounts) {
        if ($i.id -eq $currentAccount) { $defaultOption = $true } else { $defaultOption = $false }
        $provider = New-object PSCustomObject -Property @{Provider = "Azure"; Name = $i.name; Identifier = $i.id; default = $defaultOption }
        addProvider($provider)
    }
}

#Do we have access to AWS?
if (get-command 'aws' -ea SilentlyContinue) { $awsSignedIn = aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]' 2>null }
if ($awsSignedIn) {
    $provider = New-object PSCustomObject -Property @{Provider = "AWS"; Name = $awsSignedIn; default = $true }
    addProvider($provider)
}

write-output $Global:providerList | sort-object -property Option | format-table -Property Option, Provider, Name, Identifier, default



#Option, Key, Choice, Current, Function, Properties
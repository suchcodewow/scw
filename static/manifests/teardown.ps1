$clusters = aws eks list-clusters --output json --query clusters | ConvertFrom-Json
write-host "Removing $($clusters.count) clusters"
$clusters | ForEach-Object -Parallel {
    $cluster = $_
    $nodegroups = aws eks list-nodegroups --cluster-name $cluster --query nodegroups | Convertfrom-Json
    Foreach ($nodegroup in $nodegroups) {
        write-host $nodegroup
        $nodegroupstatus = aws eks delete-nodegroup --cluster-name $cluster --nodegroup-name $nodegroup --output json | ConvertFrom-Json
        While ($nodegroupstatus) {
            $nodegroupstatus = aws eks describe-nodegroup --cluster-name $cluster --nodegroup-name $nodegroup --output json 2>$null | ConvertFrom-Json
            write-host $nodegroupstatus
            Start-sleep -s 5
        }
    }
    $clusterstatus = aws eks delete-cluster --name $cluster --output json | ConvertFrom-Json
    While ($clusterstatus) {
        $clusterstatus = aws eks describe-cluster --cluster-name $cluster --output json | ConvertFrom-Json
        write-host $clusterstatus
        Start-sleep -s 5
    }
} -ThrottleLimit 50

$roles = aws iam list-roles --query Roles[*].RoleName | Convertfrom-Json
write-host "Removing $($roles.count) roles"
$roles | Foreach-Object -ThrottleLimit 10 -Parallel {
    $role = $_
    if ($role.SubString(0, 4) -eq "scw-") {
        write-host "nuke $role"
        $attachedPolicies = aws iam list-attached-role-policies --role-name $role --output json | Convertfrom-Json
        foreach ($policy in $attachedPolicies.AttachedPolicies) {
            aws iam detach-role-policy --role-name $role --policy-arn $($policy.PolicyArn)
        }
        aws iam delete-role --role-name $role
    }
    else {
        write-host "Ignore Role: $role"
    }    
}
$users = aws iam get-group --group-name attendees --query Users[*].UserName | convertfrom-Json
write-host "Removing $($users.count) users"
$users | Foreach-Object -ThrottleLimit 10 -Parallel {
    $user = $_
    if ($user -eq "shyplane" -or $user -eq "consoleadmin") {
        write-host "Ignore User: $user"
    }
    else {
        $groups = aws iam list-groups-for-user --user-name consoleadmin --query Groups[*].GroupName | Convertfrom-Json
        foreach ($group in $groups) {
            aws iam remove-user-from-group --group-name $group --user-name $user
        }
        aws iam delete-login-profile --user-name $user
        aws iam delete-user --user-name $user
    }
}

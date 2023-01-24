$clusters = aws eks list-clusters --output json --query clusters | ConvertFrom-Json
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
        write-host "let it alone $role"
    }
    #$attachedPolicies = Send-Update -t 1 -e -c "Get Attached Policies" -r "aws iam list-attached-role-policies --region $AWSregion --role-name $awsRoleName --output json" | Convertfrom-Json
    #foreach ($policy in $attachedPolicies.AttachedPolicies) {
    #    Send-Update -t 1 -c "Remove Policy" -r "aws iam detach-role-policy --region $AWSregion --role-name $awsRoleName --policy-arn $($policy.PolicyArn)"
    #}
    
}



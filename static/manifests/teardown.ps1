$clusters = aws eks list-clusters --output json --query clusters | ConvertFrom-Json

$cluster = "scw-AWS-livelynose"
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


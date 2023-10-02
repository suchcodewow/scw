$clusters = aws eks list-clusters --output json --query clusters | Convertfrom-Json
remove-item clusters.txt
Foreach ($cluster in $clusters) {
    aws eks update-kubeconfig --name $cluster
    kubectl apply -f .\dbic.yaml
    While (-not $url) {
        $svc = kubectl get svc -n dbic --output json | Convertfrom-Json
        $url = $svc.items.status.loadBalancer.ingress.hostname
        Start-Sleep -s 5
        write-host "waiting on: $cluster"
    }
    "http://$url" | Out-File -FilePath clusters.txt -Append
    Remove-Variable url
}
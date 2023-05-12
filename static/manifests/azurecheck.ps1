#Dynatrace Azure Check Utility

# Replace values with your tenant, appId, and secret VALUE (not secret ID)

$tenantId = "YOUR_TENANT_ID"
$applicationId = "YOUR_APP_ID"
$secret = "SECRET_VALUE"

# Switch this to $true if using Azure Gov

$isAzureGov = $false

# Do not modify below

if ($isAzureGov) {
    $adEndpoint = 'https://login.microsoftonline.us'
    $managementEndpoint = 'https://management.core.usgovcloudapi.net/'
    $resourceEndpoint = 'management.usgovcloudapi.net'
}
else {
    $adEndpoint = 'https://login.microsoftonline.com'
    $managementEndpoint = 'https://management.core.windows.net/'
    $resourceEndpoint = 'management.azure.com'
}

$param = @{
    Uri    = "$adEndpoint/$tenantId/oauth2/token?api-version=2020-06-01";
    Method = 'Post';
    Body   = @{
        grant_type    = 'client_credentials';
        resource      = $managementEndpoint;
        client_id     = $applicationId;
        client_secret = $secret
    }
}

$result = Invoke-RestMethod @param
$token = $result.access_token

if ($token) {
    # List subscriptions
    $param_subList = @{
        Uri         = "https://$resourceEndpoint/subscriptions?api-version=2020-01-01"
        ContentType = 'application/json'
        Method      = 'GET'
        headers     = @{
            authorization = "Bearer $token"
            host          = $resourceEndpoint
        }
    }

    $response = Invoke-RestMethod @param_subList
    if ($response.value.count -gt 0) {
        $response.value
        write-host "Successfully connected and retrieved subscriptions."
    }
    else {
        write-host ""
        write-host "Credentials authenticated, but FAILED to retrieve subscriptions."
        write-host ""
    }

}
else {
    write-host ""
    write-host "FAILED to authenticate. See Error above."
    write-host ""
}
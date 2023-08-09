#!/bin/bash

# Dynatrace Azure Check Utility

echo "Directory (Tenant) Id?"
if [ -v tenantId ]; then
    echo "<enter> to use ${tenantId}"
fi
read tenantIdResponse
if [ ! -z "$tenantIdResponse" ]; then
    echo "saving tenantId: ${tenantIdResponse}"
    export tenantId=$tenantIdResponse
fi

echo "Application (client) ID?"
if [ ! -z "$appId" ]; then
    echo "<enter> to use ${appId}"
fi
read appIdResponse
if [ ! -z "$tenantIdResponse" ]; then
    export appId=$appIdResponse
fi

echo "Secret Value (NOT the ID!)?"
if [ ! -z "$secretValue" ]; then
    echo "<enter> to use ${secretValue}"
fi
read secretValueResponse
if [ ! -z "$secretValueResponse" ]; then
    export secretValue=$secretValueResponse
fi

echo "Connect to Azure GOV? (y for yes, n for no)"
if [ ! -z "$isAzureGov" ]; then
    echo "<enter> to use ${isAzureGov}"
fi
read isAzureGovResponse
if [ ! -z "$isAzureGovResponse" ]; then
    export isAzureGov=$isAzureGovResponse
fi

if [ "$isAzureGov" = y ]; then
    adEndpoint="https://login.microsoftonline.us"
    managementEndpoint="https://management.core.usgovcloudapi.net/"
    resourceEndpoint="management.usgovcloudapi.net"
else
    adEndpoint="https://login.microsoftonline.com"
    managementEndpoint="https://management.core.windows.net/"
    resourceEndpoint="management.azure.com"
fi

# param="{\"grant_type\":\"client_credentials\",\"resource\":\"$managementEndpoint\",\"client_id\":\"${appId}\",\"client_secret\":\"${secretValue}\"}"
param="grant_type=client_credentials&resource=${managementEndpoint}&client_id=${appId}&client_secret=${secretValue}"
# echo $param
result=$(curl --write-out '%{http_code}' -X POST -d "${param}" "${adEndpoint}/${tenantId}/oauth2/token?api-version=2020-06-01")
access_token=$(echo $result | grep -oP '"access_token":"(.*?)"' | sed 's/"//g')
if [ ! -z "$access_token" ]; then
    echo "Successfully retrieved an access token!"
    # List subscriptions
    # paramSubList = @{
    #     Uri         = "https://$resourceEndpoint/subscriptions?api-version=2020-01-01"
    #     ContentType = 'application/json'
    #     Method      = 'GET'
    #     headers     = @{
    #         authorization = "Bearer $token"
    #         host          = $resourceEndpoint
    #     }
    # }
    subscriptresult=$(curl -X GET -H "host: ${resourceEndpoint}" -H "authorization: Bearer ${access_token:13}" -H "ContentType: application/json" "https://${resourceEndpoint}/subscriptions?api-version=2020-01-01")
    echo $subscriptresult
    # $response = Invoke-RestMethod @param_subList
    # if ($response.value.count -gt 0) {
    #     $response.value
    #     write-host "Successfully connected and retrieved subscriptions."
else
    echo "Failed to authenticate."
fi

# echo $result
# token=$(echo "$result" | jq -r '.access_token')

# if [ ! -z "$token" ]; then
#     # List subscriptions
#     param_subList="{\"api-version\":\"2020-01-01\"}"

#     response=$(curl -X GET -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Host: $resourceEndpoint" "$resourceEndpoint/subscriptions?$param_subList")

#     subscription_count=$(echo "$response" | jq '.value | length')
#     if [ "$subscription_count" -gt 0 ]; then
#         echo "$response" | jq '.value'
#         echo "Successfully connected and retrieved subscriptions."
#     else
#         echo ""
#         echo "Credentials authenticated, but FAILED to retrieve subscriptions."
#         echo ""
#     fi
# else
#     echo ""
#     echo "FAILED to authenticate. See Error above."
#     echo ""
# fi

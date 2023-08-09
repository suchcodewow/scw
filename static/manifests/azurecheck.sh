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
result=$(curl -s --write-out '%{http_code}' -X POST -d "${param}" "${adEndpoint}/${tenantId}/oauth2/token?api-version=2020-06-01")
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
    exit
fi
clean_token=$(echo ${access_token:13})
param_subList="{\"api-version\":\"2020-01-01\"}"
sublist=$(curl -s -X GET -H "Authorization: Bearer ${clean_token}" -H "host: ${resourceEndpoint}" "https://${resourceEndpoint}/subscriptions?api-version=2020-01-01")
subscriptions=$(echo $sublist | grep -oP '"id":"(.*?)"' | sed 's/"//g')
if [ ! -z "$subscriptions" ]; then
    echo "And has access to at least one subscription"
    echo $subscriptions
else
    echo "The app registration doesn't seem to have access to any subscriptions?"
fi

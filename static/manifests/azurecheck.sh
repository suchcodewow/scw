#!/bin/bash

# Dynatrace Azure Check Utility

# Replace values with your tenant, appId, and secret VALUE (not secret ID)
tenantId="YOUR_TENANT_ID"
applicationId="YOUR_APP_ID"
secret="SECRET_VALUE"

# Switch this to true if using Azure Gov
isAzureGov=false

# Do not modify below

if [ "$isAzureGov" = true ]; then
    adEndpoint="https://login.microsoftonline.us"
    managementEndpoint="https://management.core.usgovcloudapi.net/"
    resourceEndpoint="management.usgovcloudapi.net"
else
    adEndpoint="https://login.microsoftonline.com"
    managementEndpoint="https://management.core.windows.net/"
    resourceEndpoint="management.azure.com"
fi

param="{\"grant_type\":\"client_credentials\",\"resource\":\"$managementEndpoint\",\"client_id\":\"$applicationId\",\"client_secret\":\"$secret\"}"

result=$(curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "$param" "$adEndpoint/$tenantId/oauth2/token?api-version=2020-06-01")
token=$(echo "$result" | jq -r '.access_token')

if [ ! -z "$token" ]; then
    # List subscriptions
    param_subList="{\"api-version\":\"2020-01-01\"}"

    response=$(curl -X GET -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Host: $resourceEndpoint" "$resourceEndpoint/subscriptions?$param_subList")

    subscription_count=$(echo "$response" | jq '.value | length')
    if [ "$subscription_count" -gt 0 ]; then
        echo "$response" | jq '.value'
        echo "Successfully connected and retrieved subscriptions."
    else
        echo ""
        echo "Credentials authenticated, but FAILED to retrieve subscriptions."
        echo ""
    fi
else
    echo ""
    echo "FAILED to authenticate. See Error above."
    echo ""
fi

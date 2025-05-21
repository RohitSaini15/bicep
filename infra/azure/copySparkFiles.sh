#!/bin/bash

# This script copies Spark files to the storage account
# It should be run after the Bicep deployment

# Parameters
RESOURCE_GROUP_NAME=$1
STORAGE_ACCOUNT_NAME=$2
CONTAINER_NAME="sparkscripts"

# Check if parameters are provided
if [ -z "$RESOURCE_GROUP_NAME" ] || [ -z "$STORAGE_ACCOUNT_NAME" ]; then
  echo "Usage: $0 <resource-group-name> <storage-account-name>"
  exit 1
fi

# Create container if it doesn't exist
echo "Creating container $CONTAINER_NAME if it doesn't exist..."
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --auth-mode login

# Upload Spark files
echo "Uploading Spark files to storage account..."
az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT_NAME \
  --auth-mode login \
  --destination $CONTAINER_NAME \
  --source ../../spark/src \
  --pattern "*.py" \
  --overwrite

echo "Spark files uploaded successfully."
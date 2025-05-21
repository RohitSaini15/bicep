#!/bin/bash

# Script to deploy the Azure Bicep template for Taxi data processing

# Parameters
RESOURCE_GROUP_NAME="taxi-data-processing-rg"
LOCATION="eastus"

# Create resource group if it doesn't exist
echo "Checking if resource group exists..."
if ! az group show --name $RESOURCE_GROUP_NAME &> /dev/null; then
    echo "Creating resource group $RESOURCE_GROUP_NAME in $LOCATION..."
    az group create --name $RESOURCE_GROUP_NAME --location $LOCATION
else
    echo "Resource group $RESOURCE_GROUP_NAME already exists."
fi

# Deploy Bicep template using parameters file
echo "Deploying Bicep template..."
az deployment group create \
  --resource-group $RESOURCE_GROUP_NAME \
  --template-file main.bicep \
  --parameters parameters.json

echo "Deployment completed."
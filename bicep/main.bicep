targetScope = 'resourceGroup'

// Parameters
@description('The environment name. Possible values: dev, staging, prod')
param environmentName string = 'dev'

@description('The Azure region for deploying resources')
param location string = 'centralus'

@description('Project name to be used in resource names')
param projectName string = 'taxidatalake'

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environmentName
  Project: projectName
}

// Variables
var resourceGroupName = 'rgcus-${projectName}-${environmentName}'
var storageAccountName = 'stcus${projectName}${environmentName}'
var synapseWorkspaceName = 'synscus-${projectName}-${environmentName}'
var dataFactoryName = 'adfcus-${projectName}-${environmentName}'
var keyVaultName = 'kvcus-${projectName}-${environmentName}'
var logAnalyticsName = 'logcus-${projectName}-${environmentName}'

// Module deployments
module storage 'modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    tags: tags
  }
}

module synapse 'modules/synapse.bicep' = {
  name: 'synapseDeployment'
  params: {
    location: location
    synapseWorkspaceName: synapseWorkspaceName
    storageAccountName: storage.outputs.storageAccountName
    defaultDataLakeStorageFilesystemName: storage.outputs.bronzeContainerName
    tags: tags
  }
}

module dataFactory 'modules/data-factory.bicep' = {
  name: 'dataFactoryDeployment'
  params: {
    location: location
    dataFactoryName: dataFactoryName
    storageAccountName: storage.outputs.storageAccountName
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    location: location
    keyVaultName: keyVaultName
    tags: tags
  }
}

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    tags: tags
  }
}

// Synapse artifacts will be deployed using a post-deployment script
// instead of through Bicep to avoid deployment issues

// Outputs
output storageAccountName string = storage.outputs.storageAccountName
output synapseWorkspaceName string = synapse.outputs.synapseWorkspaceName
output dataFactoryName string = dataFactory.outputs.dataFactoryName
output keyVaultName string = keyVault.outputs.keyVaultName

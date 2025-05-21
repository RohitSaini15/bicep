targetScope = 'resourceGroup'

// Parameters
param location string
param synapseWorkspaceName string
param storageAccountName string

param defaultDataLakeStorageFilesystemName string
param tags object

// Variables
var synapseDefaultStorageAccountUrl = 'https://${storageAccountName}.dfs.${environment().suffixes.storage}'

// Reference existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' existing = {
  name: storageAccountName
}

// Synapse Workspace
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: synapseDefaultStorageAccountUrl
      filesystem: defaultDataLakeStorageFilesystemName
    }
    sqlAdministratorLogin: 'sqladminuser'
    sqlAdministratorLoginPassword: 'H@Sh1CoR3!' // In production, use Key Vault
  }
}

// Spark Pool
resource sparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  parent: synapseWorkspace
  name: 'SparkPool1'
  location: location
  properties: {
    nodeCount: 3
    nodeSizeFamily: 'MemoryOptimized'
    nodeSize: 'Small'
    autoScale: {
      enabled: true
      minNodeCount: 3
      maxNodeCount: 10
    }
    autoPause: {
      enabled: true
      delayInMinutes: 15
    }
    sparkVersion: '3.3'
  }
}

// Firewall rules
resource allowAll 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'allowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// Role Assignment - Grant Synapse workspace access to storage
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(synapseWorkspace.name, storageAccount.id, 'StorageBlobDataContributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output synapseWorkspaceName string = synapseWorkspace.name
output sparkPoolName string = sparkPool.name
// Azure Bicep template for Spark data processing infrastructure
// Converted from AWS CDK code

// Parameters
@description('Environment name (e.g., dev, test, prod)')
param environmentName string = 'dev'

@description('Azure region for resource deployment')
param location string = 'westus2'

@description('Name prefix for all resources')
param resourceNamePrefix string = 'taxi'

@description('Removal policy for resources (Delete or Retain)')
@allowed([
  'Delete'
  'Retain'
])
param removalPolicy string = 'Delete'

@description('Enable daily scheduling of the Spark job')
param enableDailyScheduling bool = false

@description('Source data paths for yellow taxi data')
param yellowSourcePath string = 'data/NY-Pub/year=2016/month=1/type=yellow'

@description('Source data paths for green taxi data')
param greenSourcePath string = 'data/NY-Pub/year=2016/month=1/type=green'

@description('Target database name')
param targetDatabaseName string = 'spark_data_lake'

@description('Target table name')
param targetTableName string = 'aggregated_trip_distance'

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var storageAccountName = '${resourceNamePrefix}storage${uniqueSuffix}'
var bronzeContainerName = 'bronze'
var silverContainerName = 'silver'
var goldContainerName = 'gold'
var synapseWorkspaceName = '${resourceNamePrefix}-synapse-${uniqueSuffix}'
var sparkPoolName = 'sparkpool'
var dataFactoryName = '${resourceNamePrefix}-adf-${uniqueSuffix}'
var keyVaultName = '${resourceNamePrefix}-kv-${uniqueSuffix}'
var logicAppName = '${resourceNamePrefix}-logic-${uniqueSuffix}'
var managedIdentityName = '${resourceNamePrefix}-identity-${uniqueSuffix}'
var yellowTaxiDestinationPath = 'yellow-trip-data/'
var greenTaxiDestinationPath = 'green-trip-data/'

// Storage Account for Data Lake
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: true // Hierarchical namespace for ADLS Gen2
    minimumTlsVersion: 'TLS1_2'
  }
}

// Bronze container (raw data)
resource bronzeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${bronzeContainerName}'
}

// Silver container (processed data)
resource silverContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${silverContainerName}'
}

// Gold container (aggregated data)
resource goldContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${goldContainerName}'
}

// User-assigned Managed Identity for Spark jobs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

// Role assignment for Storage Blob Data Contributor on silver container (read)
resource silverContainerRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, silverContainer.id, 'reader')
  scope: silverContainer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Storage Blob Data Contributor on gold container (read/write)
resource goldContainerRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, goldContainer.id, 'contributor')
  scope: goldContainer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

// Azure Synapse Analytics workspace
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseWorkspaceName
  location: location
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${storageAccount.name}.dfs.${environment().suffixes.storage}'
      filesystem: goldContainerName
    }
    sqlAdministratorLogin: 'sqladmin'
    sqlAdministratorLoginPassword: 'P@ssw0rd1234!@#$' // In production, use Key Vault reference or parameter
  }
}

// Synapse Spark Pool
resource sparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  name: '${synapseWorkspace.name}/${sparkPoolName}'
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
    sparkVersion: '3.2'
    libraryRequirements: {
      content: 'great_expectations==0.15.50'
      filename: 'requirements.txt'
    }
  }
}

// Azure Data Factory for data movement and orchestration
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

// Linked Service for Azure Storage
resource storageLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: '${dataFactory.name}/AzureStorageLS'
  properties: {
    type: 'AzureBlobStorage'
    typeProperties: {
      connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    }
  }
}

// Linked Service for Synapse
resource synapseLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: '${dataFactory.name}/SynapseLinkedService'
  properties: {
    type: 'AzureSynapseAnalytics'
    typeProperties: {
      connectionString: 'Server=tcp:${synapseWorkspace.name}.sql.azuresynapse.net,1433;Initial Catalog=master;User ID=sqladmin;Password=P@ssw0rd1234!@#$;'
    }
  }
}

// Dataset for Yellow Taxi data
resource yellowTaxiDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: '${dataFactory.name}/YellowTaxiDataset'
  properties: {
    linkedServiceName: {
      referenceName: storageLinkedService.name
      type: 'LinkedServiceReference'
    }
    type: 'Parquet'
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: silverContainerName
        folderPath: yellowTaxiDestinationPath
      }
    }
  }
}

// Dataset for Green Taxi data
resource greenTaxiDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: '${dataFactory.name}/GreenTaxiDataset'
  properties: {
    linkedServiceName: {
      referenceName: storageLinkedService.name
      type: 'LinkedServiceReference'
    }
    type: 'Parquet'
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: silverContainerName
        folderPath: greenTaxiDestinationPath
      }
    }
  }
}

// Copy Pipeline for Yellow Taxi data
resource yellowTaxiPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${dataFactory.name}/YellowTaxiCopyPipeline'
  properties: {
    activities: [
      {
        name: 'CopyYellowTaxiData'
        type: 'Copy'
        typeProperties: {
          source: {
            type: 'ParquetSource'
            storeSettings: {
              type: 'HttpReadSettings'
              requestMethod: 'GET'
            }
          }
          sink: {
            type: 'ParquetSink'
            storeSettings: {
              type: 'AzureBlobStorageWriteSettings'
            }
          }
        }
        inputs: [
          {
            referenceName: 'HttpSourceDataset' // This would need to be defined separately
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: yellowTaxiDataset.name
            type: 'DatasetReference'
          }
        ]
      }
    ]
  }
}

// Copy Pipeline for Green Taxi data
resource greenTaxiPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${dataFactory.name}/GreenTaxiCopyPipeline'
  properties: {
    activities: [
      {
        name: 'CopyGreenTaxiData'
        type: 'Copy'
        typeProperties: {
          source: {
            type: 'ParquetSource'
            storeSettings: {
              type: 'HttpReadSettings'
              requestMethod: 'GET'
            }
          }
          sink: {
            type: 'ParquetSink'
            storeSettings: {
              type: 'AzureBlobStorageWriteSettings'
            }
          }
        }
        inputs: [
          {
            referenceName: 'HttpSourceDataset' // This would need to be defined separately
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: greenTaxiDataset.name
            type: 'DatasetReference'
          }
        ]
      }
    ]
  }
}

// Container for Spark scripts
resource sparkScriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/sparkscripts'
}

// Synapse Notebook for Spark processing that references external script
resource synapseNotebook 'Microsoft.Synapse/workspaces/notebooks@2021-06-01' = {
  name: '${synapseWorkspace.name}/TaxiAggregationNotebook'
  properties: {
    nbformat: 4
    nbformat_minor: 2
    metadata: {
      kernelspec: {
        name: 'pyspark3'
        display_name: 'PySpark3'
      }
    }
    cells: [
      {
        cell_type: 'code'
        source: [
          '# This notebook runs the Spark job by importing the script from the storage account\nimport os\nimport sys\n\n# Set environment variables for the Spark job\nos.environ["YELLOW_SOURCE"] = "abfss://${silverContainerName}@${storageAccountName}.dfs.${environment().suffixes.storage}/${yellowTaxiDestinationPath}"\nos.environ["GREEN_SOURCE"] = "abfss://${silverContainerName}@${storageAccountName}.dfs.${environment().suffixes.storage}/${greenTaxiDestinationPath}"\nos.environ["TARGET_DB"] = "${targetDatabaseName}"\nos.environ["TARGET_TABLE"] = "${targetTableName}"\n\n# Download the script from the storage account\nfrom notebookutils import mssparkutils\nmssparkutils.fs.cp("abfss://sparkscripts@${storageAccountName}.dfs.${environment().suffixes.storage}/agg_trip_distance.py", "file:/tmp/agg_trip_distance.py")\n\n# Add the script directory to the Python path\nsys.path.append("/tmp")\n\n# Import and run the script\nimport agg_trip_distance\n\n# Alternatively, execute the script directly\n# %run /tmp/agg_trip_distance.py\n'
        ]
        metadata: {}
        execution_count: null
        outputs: []
      }
    ]
  }
}

// Synapse Pipeline to run the Spark notebook
resource synapsePipeline 'Microsoft.Synapse/workspaces/pipelines@2021-06-01' = {
  name: '${synapseWorkspace.name}/TaxiAggregationPipeline'
  properties: {
    activities: [
      {
        name: 'RunTaxiAggregationNotebook'
        type: 'SynapseNotebook'
        typeProperties: {
          notebook: {
            referenceName: synapseNotebook.name
            type: 'NotebookReference'
          }
          sparkPool: {
            referenceName: sparkPool.name
            type: 'BigDataPoolReference'
          }
        }
      }
    ]
  }
}

// Logic App for scheduling (equivalent to EventBridge schedule)
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = if (enableDailyScheduling) {
  name: logicAppName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        recurrence: {
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: [
                '0'
              ]
              minutes: [
                '0'
              ]
            }
            timeZone: 'UTC'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        triggerSynapsePipeline: {
          runAfter: {}
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${synapseWorkspace.properties.connectivityEndpoints.dev}pipelines/${synapsePipeline.name}/createRun?api-version=2020-12-01'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
      }
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output synapseWorkspaceName string = synapseWorkspace.name
output synapseWorkspaceId string = synapseWorkspace.id
output dataFactoryName string = dataFactory.name
output dataFactoryId string = dataFactory.id
output silverContainerUrl string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}/${silverContainerName}'
output goldContainerUrl string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}/${goldContainerName}'
output synapsePipelineId string = synapsePipeline.id
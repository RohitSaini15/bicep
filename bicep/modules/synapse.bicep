targetScope = 'resourceGroup'

// Parameters
param location string
param synapseWorkspaceName string
param storageAccountName string

param defaultDataLakeStorageFilesystemName string
param tags object

// Variables
var synapseDefaultStorageAccountUrl = 'https://${storageAccountName}.dfs.${environment().suffixes.storage}'
var scriptsFolderPath = 'scripts'
var sparkJobName = 'TaxiTripDistanceAggregation'

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

// Spark Job Definition
resource sparkJobDefinition 'Microsoft.Synapse/workspaces/sparkJobDefinitions@2021-06-01' = {
  parent: synapseWorkspace
  name: sparkJobName
  properties: {
    targetBigDataPool: {
      referenceName: sparkPool.name
      type: 'BigDataPoolReference'
    }
    requiredSparkVersion: '3.3'
    language: 'python'
    jobProperties: {
      name: sparkJobName
      file: {
        type: 'AbfssFile'
        path: '${scriptsFolderPath}/agg_trip_distance.py'
      }
      args: [
        '--storage_account_name=${storageAccountName}'
      ]
      conf: {
        'spark.dynamicAllocation.enabled': 'false'
        'spark.dynamicAllocation.minExecutors': '1'
        'spark.dynamicAllocation.maxExecutors': '4'
        'spark.autotune.trackingId': '${guid(sparkJobName)}'
      }
      driverSize: 'Small'
      executorSize: 'Small'
      numExecutors: 2
    }
  }
  dependsOn: [
    sparkPool
  ]
}

// Spark Job Scheduled Trigger
resource sparkJobTrigger 'Microsoft.Synapse/workspaces/triggers@2021-06-01' = {
  parent: synapseWorkspace
  name: '${sparkJobName}DailyTrigger'
  properties: {
    annotations: []
    description: 'Daily trigger for Taxi Trip Distance Aggregation'
    type: 'ScheduleTrigger'
    typeProperties: {
      recurrence: {
        frequency: 'Day'
        interval: 1
        startTime: '2025-05-22T00:00:00Z'
        timeZone: 'UTC'
      }
    }
    pipelines: [
      {
        pipelineReference: {
          referenceName: sparkJobPipeline.name
          type: 'PipelineReference'
        },
        parameters: {}
      }
    ]
  }
  dependsOn: [
    sparkJobPipeline
  ]
}

// Pipeline to execute the Spark job
resource sparkJobPipeline 'Microsoft.Synapse/workspaces/pipelines@2021-06-01' = {
  parent: synapseWorkspace
  name: '${sparkJobName}Pipeline'
  properties: {
    activities: [
      {
        name: 'Execute${sparkJobName}'
        type: 'SynapseNotebook'
        dependsOn: []
        policy: {
          timeout: '7.00:00:00'
          retry: 0
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        typeProperties: {
          sparkPool: {
            referenceName: sparkPool.name
            type: 'BigDataPoolReference'
          }
          notebook: {
            referenceName: sparkNotebook.name
            type: 'NotebookReference'
          }
          executorSize: 'Small'
          conf: {
            'spark.dynamicAllocation.enabled': 'false'
            'spark.dynamicAllocation.minExecutors': '1'
            'spark.dynamicAllocation.maxExecutors': '4'
          }
          driverSize: 'Small'
          numExecutors: 2
        }
      }
    ]
  }
  dependsOn: [
    sparkPool
    sparkNotebook
  ]
}

// Notebook to execute the Python script
resource sparkNotebook 'Microsoft.Synapse/workspaces/notebooks@2021-06-01' = {
  parent: synapseWorkspace
  name: '${sparkJobName}Notebook'
  properties: {
    nbformat: 4
    nbformat_minor: 2
    bigDataPool: {
      referenceName: sparkPool.name
    }
    sessionProperties: {
      driverMemory: '28g'
      driverCores: 4
      executorMemory: '28g'
      executorCores: 4
      numExecutors: 2
    }
    metadata: {
      saveOutput: true
      language_info: {
        name: 'python'
      }
      a365ComputeOptions: {
        id: sparkPool.name
        name: sparkPool.name
        type: 'Spark'
        endpoint: 'https://${synapseWorkspaceName}.dev.azuresynapse.net'
        auth: {
          type: 'AAD'
        }
      }
    }
    cells: [
      {
        cell_type: 'code'
        source: [
          '# Run the Taxi Trip Distance Aggregation Spark job\n'
          'import os\n'
          'import sys\n\n'
          '# Add the scripts directory to the Python path\n'
          'scripts_path = "abfss://${defaultDataLakeStorageFilesystemName}@${storageAccountName}.dfs.core.windows.net/scripts"\n'
          'spark.sparkContext.addPyFile(os.path.join(scripts_path, "agg_trip_distance.py"))\n\n'
          '# Import and run the main function from the script\n'
          'from agg_trip_distance import main\n'
          'main()\n'
        ]
        metadata: {}
        outputs: []
        execution_count: 0
      }
    ]
  }
  dependsOn: [
    sparkPool
  ]
}

// Outputs
output synapseWorkspaceName string = synapseWorkspace.name
output sparkPoolName string = sparkPool.name
output sparkJobName string = sparkJobDefinition.name
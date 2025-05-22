// Parameters
param location string
param dataFactoryName string
param storageAccountName string
param tags object

// Data Factory
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

// Integration Runtime
resource integrationRuntime 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: dataFactory
  name: 'DefaultIntegrationRuntime'
  properties: {
    type: 'Managed'
    typeProperties: {
      computeProperties: {
        location: location // Use the same location as the data factory
      }
    }
  }
}

// Source Dataset (HTTP)
resource sourceDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'SourceDataset'
  properties: {
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'HttpServerLocation'
        relativeUrl: 'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-01.parquet'
      }
    }
  }
}

// Sink Dataset (Data Lake)
resource sinkDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'SinkDataset'
  properties: {
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileName: 'yellow_tripdata_2023-01.parquet'
        folderPath: 'raw/taxi'
        fileSystem: 'bronze'
      }
    }
    linkedServiceName: {
      referenceName: datalakeLinkedService.name
      type: 'LinkedServiceReference'
    }
  }
}

// Data Lake Linked Service
resource datalakeLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'AzureDataLakeStorage'
  properties: {
    type: 'AzureBlobFS'
    typeProperties: {
      url: 'https://${storageAccountName}.dfs.core.windows.net'
    }
    connectVia: {
      referenceName: 'DefaultIntegrationRuntime'
      type: 'IntegrationRuntimeReference'
    }
    credentials: {
      type: 'MSI'
    }
  }
}

// Data Copy Pipeline
resource dataCopyPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: 'CopyTaxiData'
  properties: {
    activities: [
      {
        name: 'CopyYellowTaxiData'
        type: 'Copy'
        typeProperties: {
          source: {
            type: 'BinarySource'
            storeSettings: {
              type: 'HttpReadSettings'
              requestMethod: 'GET'
            }
          }
          sink: {
            type: 'BinarySink'
            storeSettings: {
              type: 'AzureBlobFSWriteSettings'
            }
          }
        }
        inputs: [
          {
            referenceName: sourceDataset.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: sinkDataset.name
            type: 'DatasetReference'
          }
        ]
      }
    ]
  }
}

// Trigger (Daily Schedule)
resource scheduleTrigger 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  parent: dataFactory
  name: 'DailyTrigger'
  properties: {
    type: 'ScheduleTrigger'
    typeProperties: {
      recurrence: {
        frequency: 'Day'
        interval: 1
        startTime: '2023-01-01T00:00:00Z'
        timeZone: 'UTC'
      }
    }
    pipelines: [
      {
        pipelineReference: {
          referenceName: dataCopyPipeline.name
          type: 'PipelineReference'
        }
      }
    ]
  }
}

// Synapse Linked Service
resource synapseLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'SynapseLinkedService'
  properties: {
    type: 'AzureSqlDW'
    typeProperties: {
      connectionString: 'Data Source=syn-taxidatalake-dev.sql.azuresynapse.net; Initial Catalog=nyctaxi'
    }
    connectVia: {
      referenceName: 'DefaultIntegrationRuntime'
      type: 'IntegrationRuntimeReference'
    }
    credentials: {
      type: 'MSI'
    }
  }
}

// Copy Activity for Script
resource scriptCopyPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: 'TaxiDataAggregation'
  properties: {
    activities: [
      {
        name: 'CopyScriptToDataLake'
        type: 'Copy'
        typeProperties: {
          source: {
            type: 'BinarySource'
            storeSettings: {
              type: 'HttpReadSettings'
              requestMethod: 'GET'
            }
          }
          sink: {
            type: 'BinarySink'
            storeSettings: {
              type: 'AzureBlobFSWriteSettings'
            }
          }
          enableStaging: false
        }
        inputs: [
          {
            referenceName: scriptSourceDataset.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: scriptSinkDataset.name
            type: 'DatasetReference'
          }
        ]
        policy: {
          timeout: '7.00:00:00'
          retry: 0
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
      }
    ]
  }
}

// Script Source Dataset
resource scriptSourceDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ScriptSource'
  properties: {
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'HttpServerLocation'
        relativeUrl: 'https://raw.githubusercontent.com/KainosSoftwareLtd/agentic-ai-data-migration/main/scripts/agg_trip_distance.py'
      }
    }
  }
}

// Script Sink Dataset
resource scriptSinkDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ScriptSink'
  properties: {
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileName: 'agg_trip_distance.py'
        folderPath: 'scripts'
        fileSystem: 'scripts'
      }
    }
    linkedServiceName: {
      referenceName: datalakeLinkedService.name
      type: 'LinkedServiceReference'
    }
  }
}

// Outputs
output dataFactoryName string = dataFactory.name
output dataCopyPipelineName string = dataCopyPipeline.name
output scriptCopyPipelineName string = scriptCopyPipeline.name
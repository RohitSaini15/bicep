// Parameters
param location string
param storageAccountName string
param tags object

// Variables
var bronzeContainerName = 'bronze'
var silverContainerName = 'silver'
var goldContainerName = 'gold'
var scriptsContainerName = 'scripts'

// Managed Identity for deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'scriptDeploymentIdentity'
  location: location
}

// Role assignment for storage blob data contributor
resource blobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Storage Blob Data Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor role
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for storage account contributor
resource storageAccountContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Storage Account Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor role
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// File Systems (Containers)
resource bronzeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${bronzeContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

resource silverContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${silverContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

resource goldContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${goldContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

// Scripts container
resource scriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: '${storageAccount.name}/default/${scriptsContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

// Deploy script using deployment script
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'deployScript'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '7.0'
    retentionInterval: 'P1D'
    arguments: '-StorageAccountName ${storageAccount.name} -ContainerName ${scriptsContainerName} -ResourceGroupName ${resourceGroup().name} -SubscriptionId ${subscription().subscriptionId}'
    scriptContent: '''
param(
    [string] $StorageAccountName,
    [string] $ContainerName,
    [string] $ResourceGroupName,
    [string] $SubscriptionId
)

# Function to write logs
function Write-Log {
    param (
        [string]$Message
    )
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

# Function to safely create a file
function Create-ScriptFile {
    param (
        [string]$Content,
        [string]$FilePath
    )
    
    try {
        if ([string]::IsNullOrEmpty($FilePath)) {
            Write-Log "ERROR: FilePath is null or empty"
            return $false
        }
        
        Write-Log "Creating directory for script file if it doesn't exist"
        $directory = Split-Path -Path $FilePath -Parent
        if (-not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        Write-Log "Writing content to file: $FilePath"
        Set-Content -Path $FilePath -Value $Content -Encoding UTF8 -Force
        
        if (Test-Path -Path $FilePath) {
            Write-Log "File created successfully: $FilePath"
            return $true
        } else {
            Write-Log "ERROR: File was not created: $FilePath"
            return $false
        }
    }
    catch {
        Write-Log "ERROR creating file: $_"
        return $false
    }
}

# Main script execution
try {
    Write-Log "Script started"
    Write-Log "Connecting to Azure using managed identity"
    Connect-AzAccount -Identity
    
    Write-Log "Setting subscription context to: $SubscriptionId"
    Set-AzContext -Subscription $SubscriptionId
    
    Write-Log "Waiting for role assignments to propagate (30 seconds)"
    Start-Sleep -Seconds 30
    
    # Retry logic for getting storage account
    $maxRetries = 5
    $retryCount = 0
    $success = $false
    $storageAccount = $null
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Write-Log "Attempting to get storage account (Attempt $($retryCount + 1) of $maxRetries)"
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
            $success = $true
            Write-Log "Successfully retrieved storage account"
        }
        catch {
            $retryCount++
            Write-Log "Error retrieving storage account: $_"
            if ($retryCount -lt $maxRetries) {
                $waitTime = 10 * $retryCount
                Write-Log "Waiting $waitTime seconds before retry..."
                Start-Sleep -Seconds $waitTime
            }
            else {
                throw "Failed to retrieve storage account after $maxRetries attempts: $_"
            }
        }
    }
    
    if (-not $storageAccount) {
        throw "Storage account object is null"
    }
    
    $ctx = $storageAccount.Context
    Write-Log "Storage context created"
    
    # Python script content for the new Spark job
    $pythonScript = @'
"""
Spark job to aggregate taxi trip distances by date
"""
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, date_format, avg, sum, count

def main():
    # Initialize Spark session
    spark = SparkSession.builder \
        .appName("TaxiTripDistanceAggregation") \
        .getOrCreate()
    
    # Log the Spark session
    print(f"Spark session created: {spark.version}")
    
    try:
        # Read data from the bronze container
        bronze_path = "abfss://bronze@{storage_account_name}.dfs.core.windows.net/taxi-data/*.parquet"
        print(f"Reading data from: {bronze_path}")
        
        # Read the parquet files
        df = spark.read.parquet(bronze_path)
        
        # Print the schema
        print("Schema of the input data:")
        df.printSchema()
        
        # Perform aggregations
        # 1. Average trip distance by date
        avg_distance_by_date = df \
            .withColumn("trip_date", date_format(col("pickup_datetime"), "yyyy-MM-dd")) \
            .groupBy("trip_date") \
            .agg(
                avg(col("trip_distance")).alias("avg_trip_distance"),
                sum(col("trip_distance")).alias("total_trip_distance"),
                count("*").alias("trip_count")
            ) \
            .orderBy("trip_date")
        
        # Show the results
        print("Average trip distance by date:")
        avg_distance_by_date.show(20)
        
        # Write the results to the silver container
        silver_path = "abfss://silver@{storage_account_name}.dfs.core.windows.net/aggregated-taxi-data"
        print(f"Writing aggregated data to: {silver_path}")
        
        avg_distance_by_date.write \
            .mode("overwrite") \
            .parquet(silver_path)
        
        print("Aggregation job completed successfully!")
        
    except Exception as e:
        print(f"Error in Spark job: {str(e)}")
        raise
    finally:
        # Stop the Spark session
        spark.stop()

if __name__ == "__main__":
    main()
'@
    
    # Create the script file with a guaranteed path
    $tempDir = "/tmp"
    if (-not (Test-Path -Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Created temp directory: $tempDir"
    }
    
    $tempFilePath = "$tempDir/agg_trip_distance.py"
    Write-Log "Temp file path: $tempFilePath"
    
    $fileCreated = Create-ScriptFile -Content $pythonScript -FilePath $tempFilePath
    if (-not $fileCreated) {
        throw "Failed to create script file at $tempFilePath"
    }
    
    # Upload to blob storage
    Write-Log "Uploading script to blob storage container: $ContainerName"
    Set-AzStorageBlobContent -File $tempFilePath -Container $ContainerName -Blob "agg_trip_distance.py" -Context $ctx -Force
    
    # Clean up
    Write-Log "Cleaning up temporary file"
    try {
        if ([string]::IsNullOrEmpty($tempFilePath)) {
            Write-Log "WARNING: tempFilePath is null or empty, nothing to clean up"
        }
        elseif (Test-Path -Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force -ErrorAction Stop
            Write-Log "Temporary file removed successfully"
        }
        else {
            Write-Log "WARNING: Temporary file not found at path: $tempFilePath"
        }
    }
    catch {
        Write-Log "WARNING: Error during cleanup: $_"
        # Continue execution even if cleanup fails
    }
    
    Write-Log "Script completed successfully"
}
catch {
    Write-Log "ERROR: Script failed with exception: $_"
    throw
}
    '''
    cleanupPreference: 'OnSuccess'
  }
  dependsOn: [
    storageAccount
    scriptsContainer
    blobDataContributorRoleAssignment
    storageAccountContributorRoleAssignment
  ]
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output bronzeContainerName string = bronzeContainerName
output silverContainerName string = silverContainerName
output goldContainerName string = goldContainerName
output scriptsContainerName string = scriptsContainerName

# AWS CDK to Azure Bicep Conversion

This directory contains the Azure Bicep template converted from the original AWS CDK code for the Taxi data processing application.

## Overview

The original AWS CDK application deployed a data processing infrastructure using:
- AWS S3 for data storage
- AWS Glue for data catalog
- AWS EMR Serverless for Spark processing
- AWS EventBridge for scheduling
- AWS Athena for querying

The Azure Bicep template implements equivalent functionality using:
- Azure Storage Account (with Blob Storage) for data storage
- Azure Synapse Analytics for data catalog, Spark processing, and querying
- Azure Data Factory for data movement
- Azure Logic Apps for scheduling

## Resource Mapping

| AWS Resource | Azure Equivalent |
|--------------|------------------|
| S3 Buckets (Bronze/Silver/Gold) | Azure Storage Account with Blob Containers |
| Glue Data Catalog | Synapse Analytics Metastore |
| EMR Serverless | Synapse Analytics Spark Pools |
| IAM Roles | Azure Managed Identities and RBAC |
| EventBridge Schedule | Azure Logic Apps with Recurrence Trigger |
| Athena | Synapse Analytics SQL On-demand |
| CodePipeline | Azure DevOps Pipelines (not included in this template) |

## Deployment

To deploy this Bicep template:

1. Ensure you have the Azure CLI installed and are logged in:
   ```
   az login
   ```

2. Make the deployment script executable:
   ```
   chmod +x deploy.sh
   ```

3. Run the deployment script:
   ```
   ./deploy.sh
   ```

4. Alternatively, deploy manually:
   ```
   az group create --name taxi-data-processing-rg --location eastus
   az deployment group create --resource-group taxi-data-processing-rg --template-file main.bicep
   ```

## Parameters

The Bicep template accepts the following parameters:

- `environmentName`: Environment name (e.g., dev, test, prod)
- `location`: Azure region for resource deployment
- `resourceNamePrefix`: Name prefix for all resources
- `removalPolicy`: Removal policy for resources (Delete or Retain)
- `enableDailyScheduling`: Enable daily scheduling of the Spark job
- `yellowSourcePath`: Source data paths for yellow taxi data
- `greenSourcePath`: Source data paths for green taxi data
- `targetDatabaseName`: Target database name
- `targetTableName`: Target table name

## Notes on the Conversion

1. **Data Lake Structure**: The three-tier data lake structure (bronze, silver, gold) is preserved using Azure Storage containers.

2. **Spark Processing**: AWS EMR Serverless is replaced with Azure Synapse Analytics Spark pools, which provide similar serverless Spark capabilities.

3. **Data Catalog**: AWS Glue Data Catalog is replaced with Azure Synapse Analytics metastore.

4. **Data Movement**: S3DataCopy operations are implemented using Azure Data Factory copy activities.

5. **Scheduling**: AWS EventBridge scheduling is replaced with Azure Logic Apps recurrence triggers.

6. **Authentication**: IAM roles are replaced with Azure Managed Identities and RBAC assignments.

7. **CI/CD**: The AWS CodePipeline CI/CD pipeline would need to be implemented separately using Azure DevOps or GitHub Actions.

8. **Spark Code Reuse**: The original Spark code is reused by storing it in a dedicated storage container and referencing it from the Synapse notebook, rather than embedding it directly in the infrastructure code.

## Limitations and Considerations

1. **HTTP Source Dataset**: The template references an 'HttpSourceDataset' that would need to be defined separately to match the source data location.

2. **Secrets Management**: The template includes hardcoded credentials for demonstration purposes. In a production environment, these should be replaced with Key Vault references.

3. **CI/CD Pipeline**: The CI/CD pipeline implementation is not included in this template and would need to be implemented separately using Azure DevOps or GitHub Actions.

4. **Spark Code**: The Spark code is embedded in a Synapse notebook. For more complex applications, consider using Azure Synapse Analytics Git integration to manage code.

5. **Cost Management**: Azure Synapse Analytics and Azure Data Factory have different pricing models compared to AWS services. Review the pricing to ensure it meets your budget requirements.
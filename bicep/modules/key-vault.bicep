// Parameters
param location string
param keyVaultName string
param tags object

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
  }
}

// Outputs
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
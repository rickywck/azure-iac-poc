@description('Resource location')
param location string

@description('Key Vault name')
param keyVaultName string

@description('Secret name for the PostgreSQL admin password')
param postgresPasswordSecretName string = 'postgres-admin-password'

@description('PostgreSQL admin password to store in Key Vault')
@secure()
param postgresAdminPassword string

@description('Resource tags')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

resource postgresPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: postgresPasswordSecretName
  properties: {
    value: postgresAdminPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

output keyVaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
output postgresCredentialName string = postgresPasswordSecret.name

@description('UI Container App identity ID')
param containerAppUIIdentityId string

@description('Agents Container App identity ID')
param containerAppAgentsIdentityId string

@description('Storage account name')
param storageAccountName string

@description('Key Vault name')
param keyVaultName string

// Storage account resource reference
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Assign Storage Blob Data Contributor role to UI app identity
resource uiStorageRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(containerAppUIIdentityId, storageAccount.id, 'storage-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: containerAppUIIdentityId
  }
}

// Assign Storage Blob Data Contributor role to agents app identity
resource agentsStorageRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(containerAppAgentsIdentityId, storageAccount.id, 'storage-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: containerAppAgentsIdentityId
  }
}

resource uiKeyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(containerAppUIIdentityId, keyVault.id, 'key-vault-secrets-user')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: containerAppUIIdentityId
  }
}


@description('UI Container App identity ID')
param containerAppUIIdentityId string

@description('Agents Container App identity ID')
param containerAppAgentsIdentityId string

@description('Storage account name')
param storageAccountName string

@description('Resource group name')
param resourceGroupName string

// Storage account resource reference
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
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

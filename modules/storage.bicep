@description('Resource location')
param location string

@description('Storage account name (lowercase, 3-24 chars)')
param accountName string

@description('Blob container name')
param containerName string

@description('Resource tags')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: accountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: tags
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name = '${storageAccount.name}/default/${containerName}'
  properties: {
    publicAccess: 'None'
  }
}

output name string = storageAccount.name
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
output id string = storageAccount.id

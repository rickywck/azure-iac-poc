@description('Resource location')
param location string

@description('ACR name (must be globally unique, alphanumeric only)')
param acrName string

@description('ACR SKU tier')
param acrSku string = 'Standard'

@description('Resource tags')
param tags object = {}

resource acrResource 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  tags: tags
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

output loginServer string = acrResource.properties.loginServer
output name string = acrName

@secure()
output adminUsername string = acrResource.listCredentials().username
@secure()
output adminPassword string = acrResource.listCredentials().passwords[0].value

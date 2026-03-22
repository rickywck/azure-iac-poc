@description('Resource location')
param location string

@description('Azure AI Foundry account name')
param accountName string

@description('Azure AI Foundry SKU')
param skuName string = 'S0'

@description('Create a model deployment in the Foundry account')
param deployModel bool = true

@description('Foundry model deployment name used by the app')
param modelDeploymentName string = 'gpt-4mini'

@description('Foundry model name (for example: gpt-4o-mini)')
param modelName string = 'gpt-4o-mini'

@description('Deployment SKU name for the model deployment')
param deploymentSkuName string = 'Standard'

@description('Deployment SKU capacity for the model deployment')
param deploymentSkuCapacity int = 10

@description('Resource tags')
param tags object = {}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: skuName
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  tags: tags
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployModel) {
  parent: foundryAccount
  name: modelDeploymentName
  sku: {
    name: deploymentSkuName
    capacity: deploymentSkuCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

output name string = foundryAccount.name
output endpoint string = foundryAccount.properties.endpoint
output modelDeploymentName string = deployModel ? modelDeployment.name : ''

@secure()
output apiKey string = foundryAccount.listKeys().key1

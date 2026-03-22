@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for resource names')
param resourceNamePrefix string

@description('PostgreSQL admin username')
param postgresAdminUsername string

@description('PostgreSQL database name')
param postgresDatabaseName string

@description('PostgreSQL SKU tier')
param postgresSku string

@description('PostgreSQL version')
param postgresVersion string

@description('Storage container name')
param storageContainerName string

@description('ACR SKU tier')
param acrSku string

@description('UI container image')
param uiImage string

@description('Backend container image')
param backendImage string

@description('Agents container image')
param agentsImage string

@description('Deploy Azure AI Foundry/OpenAI account as part of this template')
param deployFoundry bool = true

@description('Foundry account SKU tier')
param foundrySku string = 'S0'

@description('Foundry model/deployment name consumed by agents app')
param foundryModel string = 'gpt-5.1-codex-mini'

@description('Foundry model name to deploy in the account (for example: gpt-5.1-codex-mini)')
param foundryModelName string = 'gpt-5.1-codex-mini'

@description('Deploy a Foundry model deployment when provisioning Foundry account')
param deployFoundryModel bool = true

@description('Foundry model deployment SKU name')
param foundryModelSkuName string = 'Standard'

@description('Foundry model deployment SKU capacity')
param foundryModelSkuCapacity int = 10

@description('PostgreSQL admin password (secure)')
@secure()
param postgresAdminPassword string

@description('Key Vault secret name for the PostgreSQL admin password')
param postgresPasswordSecretName string = 'postgres-admin-password'

@description('Foundry API key (secure)')
@secure()
param foundryApiKey string = ''

@description('Foundry endpoint URL')
param foundryEndpoint string = ''

@description('Deploy Container Apps (set false to deploy infra only before images are pushed)')
param deployContainerApps bool = true

// Unique resource name generation
var acrName = take('${resourceNamePrefix}acr', 50) // ACR max 50 chars, must be alphanumeric
var postgresServerName = take('${resourceNamePrefix}-psql', 63)
var storageAccountName = toLower(take(replace('${resourceNamePrefix}storage', '-', ''), 24))
var keyVaultName = toLower(take('${resourceNamePrefix}kv', 24))
var containerAppsEnvName = '${resourceNamePrefix}-env'
var containerAppUIName = '${resourceNamePrefix}-ui'
var containerAppAgentsName = '${resourceNamePrefix}-agents'
var appInsightsName = '${resourceNamePrefix}-ai'
var foundryAccountName = toLower(take('${resourceNamePrefix}foundry', 24))

// Tags
var tags = {
  Environment: 'dev'
  Project: 'agentic-poc'
  ManagedBy: 'bicep'
}

// Deploy modules
module acrModule 'modules/acr.bicep' = {
  name: 'acrDeployment'
  params: {
    location: location
    acrName: acrName
    acrSku: acrSku
    tags: tags
  }
}

module postgresModule 'modules/postgres.bicep' = {
  name: 'postgresDeployment'
  params: {
    location: location
    serverName: postgresServerName
    adminUsername: postgresAdminUsername
    adminPassword: postgresAdminPassword
    databaseName: postgresDatabaseName
    sku: postgresSku
    version: postgresVersion
    tags: tags
  }
}

module storageModule 'modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    location: location
    accountName: storageAccountName
    containerName: storageContainerName
    tags: tags
  }
}

module keyVaultModule 'modules/keyVault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    location: location
    keyVaultName: keyVaultName
    postgresPasswordSecretName: postgresPasswordSecretName
    postgresAdminPassword: postgresAdminPassword
    tags: tags
  }
}

module monitorModule 'modules/monitor.bicep' = {
  name: 'monitorDeployment'
  params: {
    location: location
    name: appInsightsName
    tags: tags
  }
}

module foundryModule 'modules/foundry.bicep' = if (deployFoundry) {
  name: 'foundryDeployment'
  params: {
    location: location
    accountName: foundryAccountName
    skuName: foundrySku
    deployModel: deployFoundryModel
    modelDeploymentName: foundryModel
    modelName: foundryModelName
    deploymentSkuName: foundryModelSkuName
    deploymentSkuCapacity: foundryModelSkuCapacity
    tags: tags
  }
}

#disable-next-line BCP318
var resolvedFoundryApiKey = deployFoundry ? foundryModule.outputs.apiKey : foundryApiKey
#disable-next-line BCP318
var resolvedFoundryEndpoint = deployFoundry ? foundryModule.outputs.endpoint : foundryEndpoint

module containerAppsModule 'modules/containerApps.bicep' = if (deployContainerApps) {
  name: 'containerAppsDeployment'
  params: {
    location: location
    containerAppUIName: containerAppUIName
    containerAppAgentsName: containerAppAgentsName
    containerAppsEnvironmentName: containerAppsEnvName
    logAnalyticsWorkspaceId: monitorModule.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitorModule.outputs.logAnalyticsSharedKey
    acrLoginServer: acrModule.outputs.loginServer
    acrUsername: acrModule.outputs.adminUsername
    acrPassword: acrModule.outputs.adminPassword
    uiImageName: uiImage
    backendImageName: backendImage
    agentsImageName: agentsImage
    postgresHost: postgresModule.outputs.host
    postgresDatabase: postgresDatabaseName
    postgresUsername: postgresAdminUsername
    keyVaultUrl: keyVaultModule.outputs.vaultUri
    postgresPasswordSecretName: keyVaultModule.outputs.postgresCredentialName
    storageAccountName: storageAccountName
    storageContainerName: storageContainerName
    storageAccountKey: storageModule.outputs.primaryKey
    appInsightsConnectionString: monitorModule.outputs.connectionString
    openaiApiKey: resolvedFoundryApiKey
    foundryEndpoint: resolvedFoundryEndpoint
    foundryModel: foundryModel
    langSmithApiKey: resolvedFoundryApiKey
    tags: tags
  }
}

module managedIdentitiesModule 'modules/managedIdentities.bicep' = if (deployContainerApps) {
  name: 'managedIdentitiesDeployment'
  params: {
    #disable-next-line BCP318
    containerAppUIIdentityId: containerAppsModule.outputs.containerAppUIIdentityId
    #disable-next-line BCP318
    containerAppAgentsIdentityId: containerAppsModule.outputs.containerAppAgentsIdentityId
    storageAccountName: storageAccountName
    keyVaultName: keyVaultModule.outputs.keyVaultName
  }
}

// Outputs
output acrLoginServer string = acrModule.outputs.loginServer
output acrName string = acrName
#disable-next-line BCP318
output uiAppURL string = deployContainerApps ? containerAppsModule.outputs.containerAppUIFqdn : ''
#disable-next-line BCP318
output agentsInternalFqdn string = deployContainerApps ? containerAppsModule.outputs.containerAppAgentsFqdn : ''
output postgresHost string = postgresModule.outputs.host
output keyVaultName string = keyVaultModule.outputs.keyVaultName
output keyVaultUrl string = keyVaultModule.outputs.vaultUri
output postgresCredentialName string = keyVaultModule.outputs.postgresCredentialName
output storageAccountName string = storageAccountName
output appInsightsInstrumentationKey string = monitorModule.outputs.instrumentationKey
output foundryEndpoint string = resolvedFoundryEndpoint
output foundryAccountName string = deployFoundry ? foundryAccountName : 'external-foundry'
output foundryModelDeploymentName string = foundryModel

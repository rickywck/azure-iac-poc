@description('Location for app resources')
param location string = resourceGroup().location

@description('Prefix for resource names')
param resourceNamePrefix string

@description('PostgreSQL admin username')
param postgresAdminUsername string

@description('PostgreSQL database name')
param postgresDatabaseName string

@description('Storage container name')
param storageContainerName string

@description('UI container image')
param uiImage string

@description('Backend container image')
param backendImage string

@description('Agents container image')
param agentsImage string

@description('Deploy/use repo-managed Foundry account')
param deployFoundry bool = true

@description('Foundry deployment/model name consumed by agents app')
param foundryModel string = 'gpt-4mini'

@description('PostgreSQL admin password (secure)')
@secure()
param postgresAdminPassword string

@description('Foundry API key (secure, for external Foundry only)')
@secure()
param foundryApiKey string = ''

@description('Foundry endpoint URL (for external Foundry only)')
param foundryEndpoint string = ''

var acrName = take('${resourceNamePrefix}acr', 50)
var postgresServerName = take('${resourceNamePrefix}-psql', 63)
var storageAccountName = toLower(take(replace('${resourceNamePrefix}storage', '-', ''), 24))
var containerAppsEnvName = '${resourceNamePrefix}-env'
var containerAppUIName = '${resourceNamePrefix}-ui'
var containerAppAgentsName = '${resourceNamePrefix}-agents'
var appInsightsName = '${resourceNamePrefix}-ai'
var logAnalyticsWorkspaceName = '${appInsightsName}-law'
var foundryAccountName = toLower(take('${resourceNamePrefix}foundry', 24))

var tags = {
  Environment: 'dev'
  Project: 'agentic-poc'
  ManagedBy: 'bicep'
}

resource acrResource 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  #disable-next-line BCP334
  name: acrName
}

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' existing = {
  name: postgresServerName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  #disable-next-line BCP334
  name: storageAccountName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (deployFoundry) {
  name: foundryAccountName
}

#disable-next-line BCP422
var resolvedFoundryApiKey = deployFoundry ? foundryAccount.listKeys().key1 : foundryApiKey
#disable-next-line BCP318
var resolvedFoundryEndpoint = deployFoundry ? foundryAccount.properties.endpoint : foundryEndpoint

module containerAppsModule 'modules/containerApps.bicep' = {
  name: 'containerAppsDeployment'
  params: {
    location: location
    containerAppUIName: containerAppUIName
    containerAppAgentsName: containerAppAgentsName
    containerAppsEnvironmentName: containerAppsEnvName
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.properties.customerId
    logAnalyticsSharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
    acrLoginServer: acrResource.properties.loginServer
    acrUsername: acrResource.listCredentials().username
    acrPassword: acrResource.listCredentials().passwords[0].value
    uiImageName: uiImage
    backendImageName: backendImage
    agentsImageName: agentsImage
    postgresHost: postgresServer.properties.fullyQualifiedDomainName
    postgresDatabase: postgresDatabaseName
    postgresUsername: postgresAdminUsername
    postgresPassword: postgresAdminPassword
    storageAccountName: storageAccountName
    storageContainerName: storageContainerName
    storageAccountKey: storageAccount.listKeys().keys[0].value
    appInsightsConnectionString: appInsights.properties.ConnectionString
    openaiApiKey: resolvedFoundryApiKey
    foundryEndpoint: resolvedFoundryEndpoint
    foundryModel: foundryModel
    langSmithApiKey: resolvedFoundryApiKey
    tags: tags
  }
}

module managedIdentitiesModule 'modules/managedIdentities.bicep' = {
  name: 'managedIdentitiesDeployment'
  params: {
    containerAppUIIdentityId: containerAppsModule.outputs.containerAppUIIdentityId
    containerAppAgentsIdentityId: containerAppsModule.outputs.containerAppAgentsIdentityId
    storageAccountName: storageAccountName
  }
}

output acrLoginServer string = acrResource.properties.loginServer
output acrName string = acrName
output uiAppURL string = containerAppsModule.outputs.containerAppUIFqdn
output agentsAppURL string = containerAppsModule.outputs.containerAppAgentsFqdn
output foundryEndpoint string = resolvedFoundryEndpoint
output foundryAccountName string = deployFoundry ? foundryAccountName : 'external-foundry'
output foundryModelDeploymentName string = foundryModel

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

@description('PostgreSQL admin password (secure)')
@secure()
param postgresAdminPassword string

@description('Foundry API key (secure)')
@secure()
param foundryApiKey string

@description('Foundry endpoint URL')
param foundryEndpoint string

// Unique resource name generation
var acrName = take('${resourceNamePrefix}acr', 50) // ACR max 50 chars, must be alphanumeric
var postgresServerName = take('${resourceNamePrefix}-psql', 63)
var storageAccountName = toLower(take(replace('${resourceNamePrefix}storage', '-', ''), 24))
var containerAppsEnvName = '${resourceNamePrefix}-env'
var containerAppUIName = '${resourceNamePrefix}-ui'
var containerAppAgentsName = '${resourceNamePrefix}-agents'
var appInsightsName = '${resourceNamePrefix}-ai'

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

module monitorModule 'modules/monitor.bicep' = {
  name: 'monitorDeployment'
  params: {
    location: location
    name: appInsightsName
    tags: tags
  }
}

module containerAppsModule 'modules/containerApps.bicep' = {
  name: 'containerAppsDeployment'
  params: {
    location: location
    environmentName: containerAppsEnvName
    uiAppName: containerAppUIName
    agentsAppName: containerAppAgentsName
    acrLoginServer: acrModule.outputs.loginServer
    acrName: acrName
    uiImage: uiImage
    backendImage: backendImage
    agentsImage: agentsImage
    postgresHost: postgresModule.outputs.host
    postgresDatabaseName: postgresDatabaseName
    postgresUsername: postgresAdminUsername
    postgresPassword: postgresAdminPassword
    storageAccountName: storageAccountName
    appInsightsConnectionString: monitorModule.outputs.connectionString
    foundryApiKey: foundryApiKey
    foundryEndpoint: foundryEndpoint
    tags: tags
  }
  dependsOn: [
    acrModule
    postgresModule
    storageModule
    monitorModule
  ]
}

module managedIdentitiesModule 'modules/managedIdentities.bicep' = {
  name: 'managedIdentitiesDeployment'
  params: {
    containerAppUIIdentityId: containerAppsModule.outputs.uiIdentityId
    containerAppAgentsIdentityId: containerAppsModule.outputs.agentsIdentityId
    storageAccountName: storageAccountName
    resourceGroupName: resourceGroup().name
  }
  dependsOn: [
    containerAppsModule
    storageModule
  ]
}

// Outputs
output acrLoginServer string = acrModule.outputs.loginServer
output acrName string = acrName
output uiAppURL string = containerAppsModule.outputs.uiAppURL
output agentsAppURL string = containerAppsModule.outputs.agentsAppURL
output postgresHost string = postgresModule.outputs.host
output storageAccountName string = storageAccountName
output appInsightsInstrumentationKey string = monitorModule.outputs.instrumentationKey

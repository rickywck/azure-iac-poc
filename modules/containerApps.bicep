@description('Resource location')
param location string

@description('UI+Backend Container App name')
param containerAppUIName string

@description('Agents Container App name')
param containerAppAgentsName string

@description('Container Apps Environment name')
param containerAppsEnvironmentName string

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@secure()
param logAnalyticsSharedKey string

@description('ACR login server')
param acrLoginServer string

@description('ACR username')
@secure()
param acrUsername string

@description('ACR password')
@secure()
param acrPassword string

@description('PostgreSQL host')
param postgresHost string

@description('PostgreSQL database name')
param postgresDatabase string

@description('PostgreSQL username')
param postgresUsername string

@description('PostgreSQL password')
@secure()
param postgresPassword string

@description('Storage account name')
param storageAccountName string

@description('Storage blob container name')
param storageContainerName string

@description('Storage account key')
@secure()
param storageAccountKey string

@description('Application Insights connection string')
@secure()
param appInsightsConnectionString string

@description('Resource tags')
param tags object = {}

@description('UI image name')
param uiImageName string = 'ui:latest'

@description('Backend image name')
param backendImageName string = 'backend:latest'

@description('Agents image name')
param agentsImageName string = 'agents:latest'

@description('OpenAI API key')
@secure()
param openaiApiKey string

@description('Foundry endpoint URL')
param foundryEndpoint string

@description('Foundry deployment/model name')
param foundryModel string = 'gpt-4mini'

@description('LangSmith API key')
@secure()
param langSmithApiKey string

// Container Apps Environment
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspaceId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
  tags: tags
}

// User-assigned identity for UI+Backend Container App
resource containerAppUIIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${containerAppUIName}-identity'
  location: location
  tags: tags
}

// User-assigned identity for Agents Container App
resource containerAppAgentsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${containerAppAgentsName}-identity'
  location: location
  tags: tags
}

// UI+Backend Container App with 2 containers
resource containerAppUI 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppUIName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppUIIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      secrets: [
        {
          name: 'acr-password'
          value: acrPassword
        }
        {
          name: 'postgres-password'
          value: postgresPassword
        }
        {
          name: 'storage-key'
          value: storageAccountKey
        }
        {
          name: 'appinsights-connection-string'
          value: appInsightsConnectionString
        }
      ]
      registries: [
        {
          server: acrLoginServer
          username: acrUsername
          passwordSecretRef: 'acr-password'
        }
      ]
    }
    template: {
      containers: [
        // UI Container
        {
          name: 'ui'
          image: '${acrLoginServer}/${uiImageName}'
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'BACKEND_UPSTREAM'
              value: 'localhost:8000'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                port: 80
                path: '/'
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                port: 80
                path: '/'
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              timeoutSeconds: 3
              failureThreshold: 3
            }
          ]
        }
        // Backend Container
        {
          name: 'backend'
          image: '${acrLoginServer}/${backendImageName}'
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
          env: [
            {
              name: 'POSTGRES_HOST'
              value: postgresHost
            }
            {
              name: 'POSTGRES_PORT'
              value: '5432'
            }
            {
              name: 'POSTGRES_DB'
              value: postgresDatabase
            }
            {
              name: 'POSTGRES_USER'
              value: postgresUsername
            }
            {
              name: 'POSTGRES_PASSWORD'
              secretRef: 'postgres-password'
            }
            {
              name: 'POSTGRES_SSLMODE'
              value: 'require'
            }
            {
              name: 'AGENT_SERVICE_URL'
              value: 'https://${containerAppAgents.properties.latestRevisionFqdn}'
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccountName
            }
            {
              name: 'STORAGE_CONTAINER_NAME'
              value: storageContainerName
            }
            {
              name: 'STORAGE_ACCOUNT_KEY'
              secretRef: 'storage-key'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                port: 8000
                path: '/health'
              }
              initialDelaySeconds: 30
              periodSeconds: 15
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                port: 8000
                path: '/ready'
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            custom: {
              type: 'http'
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
  tags: tags
}

// Agents Container App
resource containerAppAgents 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppAgentsName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppAgentsIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8000
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      secrets: [
        {
          name: 'acr-password'
          value: acrPassword
        }
        {
          name: 'postgres-password'
          value: postgresPassword
        }
        {
          name: 'storage-key'
          value: storageAccountKey
        }
        {
          name: 'openai-key'
          value: openaiApiKey
        }
        {
          name: 'langsmith-key'
          value: langSmithApiKey
        }
        {
          name: 'appinsights-connection-string'
          value: appInsightsConnectionString
        }
      ]
      registries: [
        {
          server: acrLoginServer
          username: acrUsername
          passwordSecretRef: 'acr-password'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'agents'
          image: '${acrLoginServer}/${agentsImageName}'
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
          env: [
            {
              name: 'FOUNDRY_API_KEY'
              secretRef: 'openai-key'
            }
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-key'
            }
            {
              name: 'FOUNDRY_ENDPOINT'
              value: foundryEndpoint
            }
            {
              name: 'FOUNDRY_MODEL'
              value: foundryModel
            }
            {
              name: 'LANGCHAIN_API_KEY'
              secretRef: 'langsmith-key'
            }
            {
              name: 'LANGCHAIN_TRACING_V2'
              value: 'true'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                port: 8000
                path: '/health'
              }
              initialDelaySeconds: 30
              periodSeconds: 15
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                port: 8000
                path: '/ready'
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            custom: {
              type: 'http'
              metadata: {
                concurrentRequests: '5'
              }
            }
          }
        ]
      }
    }
  }
  tags: tags
}

output containerAppsEnvironmentId string = containerAppsEnv.id
output containerAppUIId string = containerAppUI.id
output containerAppAgentsId string = containerAppAgents.id
output containerAppUIIdentityId string = containerAppUIIdentity.properties.principalId
output containerAppAgentsIdentityId string = containerAppAgentsIdentity.properties.principalId
output containerAppUIFqdn string = containerAppUI.properties.latestRevisionFqdn
output containerAppAgentsFqdn string = containerAppAgents.properties.latestRevisionFqdn

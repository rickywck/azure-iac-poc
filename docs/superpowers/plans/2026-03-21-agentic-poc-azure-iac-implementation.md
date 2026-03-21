# Agentic POC Azure IAC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Plan Version:** Revision 2 - Fixed critical issues (PostgreSQL VNet, Container Apps config, LangChain imports, CORS)

**Goal:** Deploy a complete agentic application POC to Azure Container Apps using Bicep IaC, including a sample React UI, FastAPI backend, and LangChain agents with PostgreSQL, Storage, and Application Insights.

**Architecture:** Two Container Apps (UI+Backend co-located, separate Agents), Azure Container Registry, PostgreSQL Flexible Server (public access with firewall), Storage Account, Application Insights. All provisioned via modular Bicep templates with a sample app for validation.

**Tech Stack:** Bicep, Azure CLI, React (Vite), FastAPI, SQLAlchemy, LangChain, PostgreSQL, Nginx, Docker

---

## File Structure

```
azure-iac/
├── main.bicep                        # Orchestrates all modules
├── modules/
│   ├── containerApps.bicep           # ACA environment + 2 apps
│   ├── acr.bicep                     # Container Registry
│   ├── postgres.bicep                # PostgreSQL + VNet
│   ├── storage.bicep                 # Storage Account
│   ├── monitor.bicep                 # App Insights
│   └── managedIdentities.bicep       # Role assignments
├── config/
│   └── parameters.dev.json           # Deployment parameters
├── scripts/
│   ├── deploy.sh                     # Deployment script
│   └── validate.sh                   # Validation script
├── sample-app/
│   ├── ui/
│   │   ├── src/
│   │   │   ├── App.jsx
│   │   │   ├── components/TasksTab.jsx
│   │   │   ├── components/AgentChatTab.jsx
│   │   │   └── api/client.js
│   │   ├── index.html
│   │   ├── package.json
│   │   ├── vite.config.js
│   │   └── Dockerfile
│   ├── backend/
│   │   ├── main.py
│   │   ├── models.py
│   │   ├── database.py
│   │   ├── routers/tasks.py
│   │   ├── routers/agent.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── agents/
│       ├── main.py
│       ├── agent.py
│       ├── requirements.txt
│       └── Dockerfile
└── README.md
```

---

## Part 1: Project Setup

### Task 1: Initialize project structure and configuration

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `config/parameters.dev.json`

- [ ] **Step 1: Create README.md**

```markdown
# Agentic POC - Azure IAC

Proof of Concept for deploying an agentic application to Azure Container Apps.

## Architecture

- **Container Apps**: 2 apps (UI+Backend co-located, Agents separate)
- **Azure Services**: ACR, PostgreSQL, Storage, Application Insights
- **Sample App**: React UI, FastAPI backend, LangChain agents

## Quick Start

1. Deploy infrastructure:
   ```bash
   az group create -n rg-agentic-poc-dev -l eastus
   ./scripts/deploy.sh
   ```

2. Build and push images:
   ```bash
   az acr login --name <acr-name>
   docker build -t <acr-name>.azurecr.io/ui:latest ./sample-app/ui
   docker build -t <acr-name>.azurecr.io/backend:latest ./sample-app/backend
   docker build -t <acr-name>.azurecr.io/agents:latest ./sample-app/agents
   docker push <acr-name>.azurecr.io/ui:latest
   docker push <acr-name>.azurecr.io/backend:latest
   docker push <acr-name>.azurecr.io/agents:latest
   ```

3. Validate deployment:
   ```bash
   ./scripts/validate.sh
   ```

## Documentation

- Design Spec: `docs/superpowers/specs/2026-03-21-agentic-poc-azure-iac-design.md`
- Implementation Plan: `docs/superpowers/plans/2026-03-21-agentic-poc-azure-iac-implementation.md`
```

- [ ] **Step 2: Create .gitignore**

```gitignore
# Python
__pycache__/
*.py[cod]
*.so
.Python
venv/
.venv/
*.egg-info/

# Node
node_modules/
npm-debug.log*
dist/
.env.local

# IDE
.vscode/
.idea/

# Environment
.env
*.env
secrets.*

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 3: Create parameters.dev.json**

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "eastus" },
    "resourceNamePrefix": { "value": "agenticpocdev" },
    "postgresAdminUsername": { "value": "pocadmin" },
    "postgresDatabaseName": { "value": "agentdb" },
    "postgresSku": { "value": "B_Burstable_B1ms" },
    "postgresVersion": { "value": "15" },
    "storageContainerName": { "value": "agent-data" },
    "acrSku": { "value": "Standard" },
    "uiImage": { "value": "ui:latest" },
    "backendImage": { "value": "backend:latest" },
    "agentsImage": { "value": "agents:latest" }
  }
}
```

- [ ] **Step 4: Commit**

```bash
git init
git add README.md .gitignore config/parameters.dev.json
git commit -m "chore: initialize project structure and configuration"
```

---

## Part 2: Bicep Infrastructure Modules

### Task 2: Create main.bicep entry point

**Files:**
- Create: `main.bicep`

- [ ] **Step 1: Create main.bicep**

```bicep
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
module acrModule = modules/acr.bicep with {
  name: 'acrDeployment'
  params: {
    location: location
    acrName: acrName
    acrSku: acrSku
    tags: tags
  }
}

module postgresModule = modules/postgres.bicep with {
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

module storageModule = modules/storage.bicep with {
  name: 'storageDeployment'
  params: {
    location: location
    accountName: storageAccountName
    containerName: storageContainerName
    tags: tags
  }
}

module monitorModule = modules/monitor.bicep with {
  name: 'monitorDeployment'
  params: {
    location: location
    name: appInsightsName
    tags: tags
  }
}

module containerAppsModule = modules/containerApps.bicep with {
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

module managedIdentitiesModule = modules/managedIdentities.bicep with {
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
```

- [ ] **Step 2: Commit**

```bash
git add main.bicep
git commit -m "feat: add main.bicep entry point"
```

### Task 3: Create ACR module

**Files:**
- Create: `modules/acr.bicep`

- [ ] **Step 1: Create modules/acr.bicep**

```bicep
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
```

- [ ] **Step 2: Commit**

```bash
git add modules/acr.bicep
git commit -m "feat: add ACR module"
```

### Task 4: Create PostgreSQL module

**Files:**
- Create: `modules/postgres.bicep`

- [ ] **Step 1: Create modules/postgres.bicep**

```bicep
@description('Resource location')
param location string

@description('PostgreSQL server name')
param serverName string

@description('Admin username')
param adminUsername string

@description('Admin password (secure)')
@secure()
param adminPassword string

@description('Database name')
param databaseName string

@description('SKU tier')
param sku string

@description('PostgreSQL version')
param version string

@description('Resource tags')
param tags object = {}

@description('Allow Azure services to access PostgreSQL')
param allowAzureServices bool = true

// PostgreSQL Flexible Server with public access (POC - simplified networking)
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: sku
    tier: 'Burstable'
  }
  properties: {
    version: version
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
  tags: tags
}

// Firewall rule to allow Azure services
resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = if (allowAzureServices) {
  name: '${serverName}/AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  name: '${serverName}/${databaseName}'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.UTF8'
  }
}

output host string = postgresServer.properties.fullyQualifiedDomainName
output serverId string = postgresServer.id
```

- [ ] **Step 2: Commit**

```bash
git add modules/postgres.bicep
git commit -m "feat: add PostgreSQL module"
```

### Task 5: Create Storage module

**Files:**
- Create: `modules/storage.bicep`

- [ ] **Step 1: Create modules/storage.bicep**

```bicep
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
```

- [ ] **Step 2: Commit**

```bash
git add modules/storage.bicep
git commit -m "feat: add Storage module"
```

### Task 6: Create Monitor module

**Files:**
- Create: `modules/monitor.bicep`

- [ ] **Step 1: Create modules/monitor.bicep**

```bicep
@description('Resource location')
param location string

@description('Application Insights name')
param name string

@description('Resource tags')
param tags object = {}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    SamplingPercentage: 100
    DisableIpMasking: false
    IngestionMode: 'ApplicationInsights'
  }
}

output instrumentationKey string = appInsights.properties.InstrumentationKey
output connectionString string = appInsights.properties.ConnectionString
```

- [ ] **Step 2: Commit**

```bash
git add modules/monitor.bicep
git commit -m "feat: add Monitor module"
```

### Task 7: Create Container Apps module

**Files:**
- Create: `modules/containerApps.bicep`

- [ ] **Step 1: Create modules/containerApps.bicep**

```bicep
@description('Resource location')
param location string

@description('Container Apps Environment name')
param environmentName string

@description('UI+Backend Container App name')
param uiAppName string

@description('Agents Container App name')
param agentsAppName string

@description('ACR login server')
param acrLoginServer string

@description('ACR name')
param acrName string

@description('UI container image')
param uiImage string

@description('Backend container image')
param backendImage string

@description('Agents container image')
param agentsImage string

@description('PostgreSQL host')
param postgresHost string

@description('PostgreSQL database name')
param postgresDatabaseName string

@description('PostgreSQL username')
param postgresUsername string

@description('PostgreSQL password (secure)')
@secure()
param postgresPassword string

@description('Storage account name')
param storageAccountName string

@description('App Insights connection string')
param appInsightsConnectionString string

@description('Foundry API key (secure)')
@secure()
param foundryApiKey string

@description('Foundry endpoint URL')
param foundryEndpoint string

@description('Resource tags')
param tags object = {}

// Container Apps Environment with system-managed VNet (consumption profile)
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    zoneRedundant: false
  }
}

// UI + Backend Container App
resource uiApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: uiAppName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        traffic: [
          {
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'postgres-password'
          value: postgresPassword
        }
        {
          name: 'foundry-api-key'
          value: foundryApiKey
        }
        {
          name: 'app-insights-connection-string'
          value: appInsightsConnectionString
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        // UI Container - Nginx serving React
        {
          name: 'ui'
          image: '${acrLoginServer}/${uiImage}'
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
        // Backend Container - FastAPI
        {
          name: 'backend'
          image: '${acrLoginServer}/${backendImage}'
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'DATABASE_URL'
              value: 'postgresql://${postgresUsername}:${postgresPassword}@${postgresHost}:5432/${postgresDatabaseName}'
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccountName
            }
            {
              name: 'APP_INSIGHTS_CONNECTION_STRING'
              secretRef: 'app-insights-connection-string'
            }
            {
              name: 'FOUNDRY_API_KEY'
              secretRef: 'foundry-api-key'
            }
            {
              name: 'FOUNDRY_ENDPOINT'
              value: foundryEndpoint
            }
            {
              name: 'AGENT_SERVICE_URL'
              value: 'http://${agentsAppName}'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8000
              }
              initialDelaySeconds: 30
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
        rules: [
          {
            name: 'http-scale'
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
  identity: {
    type: 'SystemAssigned'
  }
}

// Agents Container App
resource agentsApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: agentsAppName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
      }
      secrets: [
        {
          name: 'foundry-api-key'
          value: foundryApiKey
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'agents'
          image: '${acrLoginServer}/${agentsImage}'
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
          env: [
            {
              name: 'FOUNDRY_API_KEY'
              secretRef: 'foundry-api-key'
            }
            {
              name: 'FOUNDRY_ENDPOINT'
              value: foundryEndpoint
            }
            {
              name: 'FOUNDRY_MODEL'
              value: 'gpt-4mini'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8000
              }
              initialDelaySeconds: 30
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scale'
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
  identity: {
    type: 'SystemAssigned'
  }
}

output uiAppURL string = uiApp.properties.configuration.ingress.fqdn
output agentsAppURL string = agentsApp.properties.configuration.ingress.fqdn
output uiIdentityId string = uiApp.identity.principalId
output agentsIdentityId string = agentsApp.identity.principalId
```

- [ ] **Step 2: Commit**

```bash
git add modules/containerApps.bicep
git commit -m "feat: add Container Apps module"
```

### Task 8: Create Managed Identities module

**Files:**
- Create: `modules/managedIdentities.bicep`

- [ ] **Step 1: Create modules/managedIdentities.bicep**

```bicep
@description('UI Container App identity ID')
param containerAppUIIdentityId string

@description('Agents Container App identity ID')
param containerAppAgentsIdentityId string

@description('Storage account name')
param storageAccountName string

@description('Resource group name')
param resourceGroupName string

// Get storage account resource ID
var storageAccountId = resourceId('Microsoft.Storage/storageAccounts', storageAccountName)

// Assign Storage Blob Data Contributor role to UI app identity
resource uiStorageRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(containerAppUIIdentityId, storageAccountId, 'storage-contributor')
  scope: storageAccountId
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: containerAppUIIdentityId
  }
}

// Assign Storage Blob Data Contributor role to agents app identity
resource agentsStorageRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(containerAppAgentsIdentityId, storageAccountId, 'storage-contributor')
  scope: storageAccountId
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: containerAppAgentsIdentityId
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/managedIdentities.bicep
git commit -m "feat: add Managed Identities module"
```

---

## Part 3: Deployment Scripts

### Task 9: Create deployment script

**Files:**
- Create: `scripts/deploy.sh`

- [ ] **Step 1: Create scripts/deploy.sh**

```bash
#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-agentic-poc-dev"
LOCATION="eastus"
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE="config/parameters.dev.json"

# Prompt for secrets if not set
if [ -z "$POSTGRES_PASSWORD" ]; then
    read -sp "Enter PostgreSQL password: " POSTGRES_PASSWORD
    echo
fi

if [ -z "$FOUNDRY_API_KEY" ]; then
    read -sp "Enter Foundry API key: " FOUNDRY_API_KEY
    echo
fi

if [ -z "$FOUNDRY_ENDPOINT" ]; then
    read -p "Enter Foundry endpoint (e.g., https://<resource>.openai.azure.com/): " FOUNDRY_ENDPOINT
fi

# Create resource group
echo "Creating resource group..."
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION

# Deploy infrastructure
echo "Deploying infrastructure..."
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file $TEMPLATE_FILE \
    --parameters @$PARAMETERS_FILE \
    --parameters postgresAdminPassword="$POSTGRES_PASSWORD" \
                    foundryApiKey="$FOUNDRY_API_KEY" \
                    foundryEndpoint="$FOUNDRY_ENDPOINT"

# Extract outputs
echo "Extracting deployment outputs..."
ACR_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.acrName.value -o tsv)
ACR_LOGIN_SERVER=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.acrLoginServer.value -o tsv)
UI_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.uiAppURL.value -o tsv)
AGENTS_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.agentsAppURL.value -o tsv)
POSTGRES_HOST=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.postgresHost.value -o tsv)

echo ""
echo "Deployment complete!"
echo "================================"
echo "ACR Login Server: $ACR_LOGIN_SERVER"
echo "ACR Name: $ACR_NAME"
echo "UI App URL: https://$UI_APP_URL"
echo "Agents App URL: https://$AGENTS_APP_URL"
echo "PostgreSQL Host: $POSTGRES_HOST"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Build and push container images:"
echo "   az acr login --name $ACR_NAME"
echo "   docker build -t $ACR_LOGIN_SERVER/ui:latest ./sample-app/ui"
echo "   docker build -t $ACR_LOGIN_SERVER/backend:latest ./sample-app/backend"
echo "   docker build -t $ACR_LOGIN_SERVER/agents:latest ./sample-app/agents"
echo "   docker push $ACR_LOGIN_SERVER/ui:latest"
echo "   docker push $ACR_LOGIN_SERVER/backend:latest"
echo "   docker push $ACR_LOGIN_SERVER/agents:latest"
echo ""
echo "2. Validate deployment: ./scripts/validate.sh"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/deploy.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/deploy.sh
git commit -m "feat: add deployment script"
```

### Task 10: Create validation script

**Files:**
- Create: `scripts/validate.sh`

- [ ] **Step 1: Create scripts/validate.sh**

```bash
#!/bin/bash
set -e

RESOURCE_GROUP="rg-agentic-poc-dev"

echo "Validating Azure IAC deployment..."
echo ""

# Check resource group exists
echo "Checking resource group..."
az group show --name $RESOURCE_GROUP --output table 2>/dev/null || {
    echo "ERROR: Resource group $RESOURCE_GROUP not found"
    exit 1
}

# Get deployment outputs
ACR_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.acrName.value -o tsv 2>/dev/null)
UI_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.uiAppURL.value -o tsv 2>/dev/null)
AGENTS_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.agentsAppURL.value -o tsv 2>/dev/null)

if [ -z "$ACR_NAME" ]; then
    echo "ERROR: Deployment outputs not found. Run ./scripts/deploy.sh first."
    exit 1
fi

# Validate ACR
echo "✓ ACR: $ACR_NAME"

# Validate Container Apps Environment
ENV_NAME=$(az containerapp env show --name ${ACR_NAME%acr}-env --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Container Apps Environment: $ENV_NAME" || echo "✗ Container Apps Environment not found"

# Validate UI Container App
UI_APP_NAME=$(az containerapp show --name ${ACR_NAME%acr}-ui --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ UI Container App: $UI_APP_NAME (https://$UI_APP_URL)" || echo "✗ UI Container App not found"

# Validate Agents Container App
AGENTS_APP_NAME=$(az containerapp show --name ${ACR_NAME%acr}-agents --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Agents Container App: $AGENTS_APP_NAME (https://$AGENTS_APP_URL)" || echo "✗ Agents Container App not found"

# Validate PostgreSQL
POSTGRES_SERVER=$(az postgres flexible-server show --name ${ACR_NAME%acr}-psql --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ PostgreSQL Server: $POSTGRES_SERVER" || echo "✗ PostgreSQL Server not found"

# Validate Storage Account
STORAGE_ACCOUNT=$(az storage account show --name ${ACR_NAME%acr}storage --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Storage Account: $STORAGE_ACCOUNT" || echo "✗ Storage Account not found"

# Validate Application Insights
APP_INSIGHTS=$(az monitor app-insights show --name ${ACR_NAME%acr}ai --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Application Insights: $APP_INSIGHTS" || echo "✗ Application Insights not found"

# Test endpoints
echo ""
echo "Testing endpoints..."

if [ -n "$UI_APP_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$UI_APP_URL || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo "✓ UI App is responding (HTTP $HTTP_CODE)"
    else
        echo "⚠ UI App returned HTTP $HTTP_CODE"
    fi
fi

if [ -n "$AGENTS_APP_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$AGENTS_APP_URL || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo "✓ Agents App is responding (HTTP $HTTP_CODE)"
    else
        echo "⚠ Agents App returned HTTP $HTTP_CODE"
    fi
fi

echo ""
echo "Validation complete!"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/validate.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/validate.sh
git commit -m "feat: add validation script"
```

---

## Part 4: Sample Application - UI

### Task 11: Create React UI base structure

**Files:**
- Create: `sample-app/ui/package.json`
- Create: `sample-app/ui/vite.config.js`
- Create: `sample-app/ui/index.html`
- Create: `sample-app/ui/src/App.jsx`
- Create: `sample-app/ui/src/main.jsx`
- Create: `sample-app/ui/src/index.css`
- Create: `sample-app/ui/src/api/client.js`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "agentic-poc-ui",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  }
}
```

- [ ] **Step 2: Create vite.config.js**

```javascript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:8000'
    }
  }
})
```

- [ ] **Step 3: Create index.html**

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Agentic POC</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

- [ ] **Step 4: Create src/main.jsx**

```javascript
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
```

- [ ] **Step 5: Create src/index.css**

```css
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background-color: #f5f5f5;
}
```

- [ ] **Step 6: Create src/api/client.js**

```javascript
const API_BASE = '/api';

export const api = {
  // Tasks CRUD
  getTasks: async () => {
    const response = await fetch(`${API_BASE}/tasks`);
    if (!response.ok) throw new Error('Failed to fetch tasks');
    return response.json();
  },

  getTask: async (id) => {
    const response = await fetch(`${API_BASE}/tasks/${id}`);
    if (!response.ok) throw new Error('Failed to fetch task');
    return response.json();
  },

  createTask: async (task) => {
    const response = await fetch(`${API_BASE}/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task)
    });
    if (!response.ok) throw new Error('Failed to create task');
    return response.json();
  },

  updateTask: async (id, task) => {
    const response = await fetch(`${API_BASE}/tasks/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task)
    });
    if (!response.ok) throw new Error('Failed to update task');
    return response.json();
  },

  deleteTask: async (id) => {
    const response = await fetch(`${API_BASE}/tasks/${id}`, {
      method: 'DELETE'
    });
    if (!response.ok) throw new Error('Failed to delete task');
    return response.json();
  },

  // Agent chat
  sendChatMessage: async (message) => {
    const response = await fetch(`${API_BASE}/agent/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message })
    });
    if (!response.ok) throw new Error('Failed to send message');
    return response.json();
  }
};
```

- [ ] **Step 7: Create src/App.jsx (base structure)**

```javascript
import { useState } from 'react'
import TasksTab from './components/TasksTab'
import AgentChatTab from './components/AgentChatTab'
import './index.css'

function App() {
  const [activeTab, setActiveTab] = useState('tasks')

  return (
    <div style={{ maxWidth: '800px', margin: '0 auto', padding: '20px' }}>
      <header style={{ marginBottom: '20px' }}>
        <h1>Agentic POC - Sample App</h1>
      </header>

      <div style={{ marginBottom: '20px', borderBottom: '1px solid #ddd' }}>
        <button
          onClick={() => setActiveTab('tasks')}
          style={{
            padding: '10px 20px',
            border: 'none',
            background: activeTab === 'tasks' ? '#007bff' : 'transparent',
            color: activeTab === 'tasks' ? 'white' : '#007bff',
            cursor: 'pointer',
            marginRight: '10px'
          }}
        >
          Tasks
        </button>
        <button
          onClick={() => setActiveTab('agent')}
          style={{
            padding: '10px 20px',
            border: 'none',
            background: activeTab === 'agent' ? '#007bff' : 'transparent',
            color: activeTab === 'agent' ? 'white' : '#007bff',
            cursor: 'pointer'
          }}
        >
          Agent Chat
        </button>
      </div>

      <div>
        {activeTab === 'tasks' && <TasksTab />}
        {activeTab === 'agent' && <AgentChatTab />}
      </div>
    </div>
  )
}

export default App
```

- [ ] **Step 8: Commit**

```bash
cd sample-app/ui
npm install
cd ../..
git add sample-app/ui
git commit -m "feat: add React UI base structure"
```

### Task 12: Create TasksTab component

**Files:**
- Create: `sample-app/ui/src/components/TasksTab.jsx`
- Create: `sample-app/ui/src/components/TasksTab.css`

- [ ] **Step 1: Create TasksTab.jsx**

```javascript
import { useState, useEffect } from 'react'
import { api } from '../api/client'
import './TasksTab.css'

export default function TasksTab() {
  const [tasks, setTasks] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [showForm, setShowForm] = useState(false)
  const [editingTask, setEditingTask] = useState(null)
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    status: 'pending'
  })

  useEffect(() => {
    loadTasks()
  }, [])

  const loadTasks = async () => {
    try {
      setLoading(true)
      const data = await api.getTasks()
      setTasks(data)
      setError(null)
    } catch (err) {
      setError('Failed to load tasks: ' + err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    try {
      if (editingTask) {
        await api.updateTask(editingTask.id, formData)
      } else {
        await api.createTask(formData)
      }
      setFormData({ title: '', description: '', status: 'pending' })
      setShowForm(false)
      setEditingTask(null)
      loadTasks()
    } catch (err) {
      setError('Failed to save task: ' + err.message)
    }
  }

  const handleEdit = (task) => {
    setEditingTask(task)
    setFormData({
      title: task.title,
      description: task.description || '',
      status: task.status
    })
    setShowForm(true)
  }

  const handleDelete = async (id) => {
    if (!confirm('Are you sure?')) return
    try {
      await api.deleteTask(id)
      loadTasks()
    } catch (err) {
      setError('Failed to delete task: ' + err.message)
    }
  }

  if (loading) return <div>Loading tasks...</div>

  return (
    <div className="tasks-tab">
      {error && <div className="error">{error}</div>}

      <div style={{ marginBottom: '15px' }}>
        <button onClick={() => { setShowForm(true); setEditingTask(null); setFormData({ title: '', description: '', status: 'pending' }) }}>
          + New Task
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleSubmit} className="task-form">
          <h3>{editingTask ? 'Edit Task' : 'New Task'}</h3>
          <input
            type="text"
            placeholder="Title"
            value={formData.title}
            onChange={(e) => setFormData({ ...formData, title: e.target.value })}
            required
          />
          <textarea
            placeholder="Description"
            value={formData.description}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            rows="3"
          />
          <select
            value={formData.status}
            onChange={(e) => setFormData({ ...formData, status: e.target.value })}
          >
            <option value="pending">Pending</option>
            <option value="active">Active</option>
            <option value="done">Done</option>
          </select>
          <div>
            <button type="submit">Save</button>
            <button type="button" onClick={() => { setShowForm(false); setEditingTask(null) }}>Cancel</button>
          </div>
        </form>
      )}

      <div className="tasks-list">
        {tasks.map(task => (
          <div key={task.id} className="task-item">
            <div className="task-header">
              <h4>{task.title}</h4>
              <span className={`status status-${task.status}`}>{task.status}</span>
            </div>
            {task.description && <p className="task-description">{task.description}</p>}
            <div className="task-actions">
              <button onClick={() => handleEdit(task)}>Edit</button>
              <button onClick={() => handleDelete(task.id)}>Delete</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Create TasksTab.css**

```css
.tasks-tab {
  padding: 20px;
}

.error {
  background-color: #fee;
  color: #c33;
  padding: 10px;
  border-radius: 4px;
  margin-bottom: 15px;
}

.task-form {
  background: white;
  padding: 20px;
  border-radius: 8px;
  margin-bottom: 20px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.task-form h3 {
  margin-top: 0;
}

.task-form input,
.task-form textarea,
.task-form select {
  width: 100%;
  padding: 10px;
  margin: 10px 0;
  border: 1px solid #ddd;
  border-radius: 4px;
  box-sizing: border-box;
}

.task-form div {
  margin-top: 10px;
}

.task-form button {
  margin-right: 10px;
  padding: 10px 20px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

.task-form button[type="submit"] {
  background: #007bff;
  color: white;
}

.tasks-list {
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.task-item {
  background: white;
  padding: 15px;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.task-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 10px;
}

.task-header h4 {
  margin: 0;
}

.status {
  padding: 4px 8px;
  border-radius: 12px;
  font-size: 12px;
  text-transform: uppercase;
}

.status-pending {
  background: #fff3cd;
  color: #856404;
}

.status-active {
  background: #d1ecf1;
  color: #0c5460;
}

.status-done {
  background: #d4edda;
  color: #155724;
}

.task-description {
  color: #666;
  margin: 10px 0;
}

.task-actions {
  display: flex;
  gap: 10px;
}

.task-actions button {
  padding: 5px 10px;
  border: 1px solid #ddd;
  background: white;
  border-radius: 4px;
  cursor: pointer;
}

.task-actions button:hover {
  background: #f5f5f5;
}
```

- [ ] **Step 3: Commit**

```bash
git add sample-app/ui/src/components/
git commit -m "feat: add TasksTab component with CRUD"
```

### Task 13: Create AgentChatTab component

**Files:**
- Create: `sample-app/ui/src/components/AgentChatTab.jsx`
- Create: `sample-app/ui/src/components/AgentChatTab.css`

- [ ] **Step 1: Create AgentChatTab.jsx**

```javascript
import { useState, useRef, useEffect } from 'react'
import { api } from '../api/client'
import './AgentChatTab.css'

export default function AgentChatTab() {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const messagesEndRef = useRef(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!input.trim() || loading) return

    const userMessage = input
    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: userMessage }])
    setLoading(true)
    setError(null)

    try {
      const response = await api.sendChatMessage(userMessage)
      setMessages(prev => [...prev, { role: 'agent', content: response.message }])
    } catch (err) {
      setError('Failed to get response: ' + err.message)
      setMessages(prev => [...prev, { role: 'agent', content: 'Sorry, I encountered an error.' }])
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="agent-chat-tab">
      {error && <div className="error">{error}</div>}

      <div className="chat-messages">
        {messages.length === 0 && (
          <div className="chat-empty">
            <p>Start a conversation with the AI agent!</p>
            <p>Ask anything and get a response powered by gpt-4mini.</p>
          </div>
        )}
        {messages.map((msg, idx) => (
          <div key={idx} className={`message message-${msg.role}`}>
            <div className="message-role">{msg.role === 'user' ? 'You' : 'Agent'}</div>
            <div className="message-content">{msg.content}</div>
          </div>
        ))}
        {loading && (
          <div className="message message-agent">
            <div className="message-role">Agent</div>
            <div className="message-content loading">Thinking...</div>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      <form onSubmit={handleSubmit} className="chat-input">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Type your message..."
          disabled={loading}
        />
        <button type="submit" disabled={loading || !input.trim()}>
          Send
        </button>
      </form>
    </div>
  )
}
```

- [ ] **Step 2: Create AgentChatTab.css**

```css
.agent-chat-tab {
  display: flex;
  flex-direction: column;
  height: 500px;
}

.error {
  background-color: #fee;
  color: #c33;
  padding: 10px;
  border-radius: 4px;
  margin-bottom: 10px;
}

.chat-messages {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  background: white;
  border-radius: 8px 8px 0 0;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.chat-empty {
  text-align: center;
  color: #999;
  padding: 40px 20px;
}

.chat-empty p {
  margin: 10px 0;
}

.message {
  margin-bottom: 15px;
  max-width: 80%;
}

.message-user {
  margin-left: auto;
}

.message-role {
  font-size: 12px;
  color: #999;
  margin-bottom: 5px;
}

.message-content {
  padding: 12px 16px;
  border-radius: 12px;
  background: #f1f1f1;
}

.message-user .message-content {
  background: #007bff;
  color: white;
}

.message-agent .message-content {
  background: #f1f1f1;
  color: #333;
}

.message-content.loading {
  font-style: italic;
  color: #999;
}

.chat-input {
  display: flex;
  gap: 10px;
  padding: 10px;
  background: white;
  border-radius: 0 0 8px 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.chat-input input {
  flex: 1;
  padding: 12px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
}

.chat-input button {
  padding: 12px 24px;
  background: #007bff;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

.chat-input button:disabled {
  background: #ccc;
  cursor: not-allowed;
}
```

- [ ] **Step 3: Commit**

```bash
git add sample-app/ui/src/components/
git commit -m "feat: add AgentChatTab component"
```

### Task 14: Create UI Dockerfile

**Files:**
- Create: `sample-app/ui/Dockerfile`
- Create: `sample-app/ui/nginx.conf`

- [ ] **Step 1: Create nginx.conf**

```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Proxy API requests to FastAPI backend
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Serve React app
    location / {
        try_files $uri $uri/ /index.html;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
```

- [ ] **Step 2: Create Dockerfile**

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

- [ ] **Step 3: Commit**

```bash
git add sample-app/ui/
git commit -m "feat: add UI Dockerfile with nginx"
```

---

## Part 5: Sample Application - Backend

### Task 15: Create FastAPI backend structure

**Files:**
- Create: `sample-app/backend/requirements.txt`
- Create: `sample-app/backend/main.py`
- Create: `sample-app/backend/models.py`
- Create: `sample-app/backend/database.py`

- [ ] **Step 1: Create requirements.txt**

```txt
fastapi==0.109.0
uvicorn[standard]==0.27.0
sqlalchemy==2.0.25
asyncpg==0.29.0
pydantic==2.5.3
pydantic-settings==2.1.0
python-multipart==0.0.6
azure-identity==1.15.0
azure-storage-blob==12.19.0
opencensus-ext-azure==1.1.13
opencensus==0.11.0
httpx==0.26.0
```

- [ ] **Step 2: Create models.py**

```python
from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
import uuid

class TaskBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    status: str = Field(default="pending", pattern="^(pending|active|done)$")

class TaskCreate(TaskBase):
    pass

class TaskUpdate(TaskBase):
    pass

class Task(TaskBase):
    id: str
    created_at: datetime

    class Config:
        from_attributes = True

class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)

class ChatResponse(BaseModel):
    message: str
```

- [ ] **Step 3: Create database.py**

```python
from sqlalchemy import create_engine, Column, String, DateTime
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.sql import func
from datetime import datetime
import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://user:pass@localhost/db")

# Configure async engine with connection pooling
engine = create_async_engine(
    DATABASE_URL,
    echo=False,  # Set to True only for debugging
    pool_pre_ping=True,  # Verify connections before use
    pool_size=5,  # Connection pool size
    max_overflow=10  # Additional connections when pool is full
)
async_session_maker = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

Base = declarative_base()

class TaskDB(Base):
    __tablename__ = "tasks"

    id = Column(String, primary_key=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

async def get_db():
    async with async_session_maker() as session:
        yield session

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
```

- [ ] **Step 4: Create main.py (base)**

```python
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from pydantic import BaseModel
import os

from .database import get_db, init_db, TaskDB
from .models import Task, TaskCreate, TaskUpdate
from .routers import tasks, agent

app = FastAPI(
    title="Agentic POC Backend",
    description="Backend API for the Agentic POC application",
    version="0.1.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(tasks.router, prefix="/api/tasks", tags=["tasks"])
app.include_router(agent.router, prefix="/api/agent", tags=["agent"])

@app.on_event("startup")
async def startup_event():
    await init_db()

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.get("/")
async def root():
    return {"message": "Agentic POC Backend API", "version": "0.1.0"}
```

- [ ] **Step 5: Commit**

```bash
git add sample-app/backend/
git commit -m "feat: add FastAPI backend base structure"
```

### Task 16: Create tasks router

**Files:**
- Create: `sample-app/backend/routers/__init__.py`
- Create: `sample-app/backend/routers/tasks.py`

- [ ] **Step 1: Create routers/__init__.py**

```python
# Empty init file
```

- [ ] **Step 2: Create routers/tasks.py**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

from ..database import get_db, TaskDB
from ..models import Task, TaskCreate, TaskUpdate

router = APIRouter()

@router.get("", response_model=list[Task])
async def get_tasks(db: AsyncSession = Depends(get_db)):
    """Get all tasks."""
    result = await db.execute(select(TaskDB).order_by(TaskDB.created_at.desc()))
    tasks = result.scalars().all()
    return [Task.model_validate(task) for task in tasks]

@router.get("/{task_id}", response_model=Task)
async def get_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """Get a specific task by ID."""
    result = await db.execute(select(TaskDB).where(TaskDB.id == task_id))
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return Task.model_validate(task)

@router.post("", response_model=Task, status_code=201)
async def create_task(task: TaskCreate, db: AsyncSession = Depends(get_db)):
    """Create a new task."""
    task_db = TaskDB(
        id=str(uuid.uuid4()),
        title=task.title,
        description=task.description,
        status=task.status
    )
    db.add(task_db)
    await db.commit()
    await db.refresh(task_db)
    return Task.model_validate(task_db)

@router.put("/{task_id}", response_model=Task)
async def update_task(task_id: str, task: TaskUpdate, db: AsyncSession = Depends(get_db)):
    """Update an existing task."""
    result = await db.execute(select(TaskDB).where(TaskDB.id == task_id))
    task_db = result.scalar_one_or_none()
    if not task_db:
        raise HTTPException(status_code=404, detail="Task not found")

    task_db.title = task.title
    task_db.description = task.description
    task_db.status = task.status

    await db.commit()
    await db.refresh(task_db)
    return Task.model_validate(task_db)

@router.delete("/{task_id}")
async def delete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """Delete a task."""
    result = await db.execute(select(TaskDB).where(TaskDB.id == task_id))
    task_db = result.scalar_one_or_none()
    if not task_db:
        raise HTTPException(status_code=404, detail="Task not found")

    await db.delete(task_db)
    await db.commit()
    return {"message": "Task deleted"}
```

- [ ] **Step 3: Update main.py to fix imports**

```python
# Update the import in main.py
from .routers.tasks import router as tasks_router
from .routers.agent import router as agent_router

# Update the include_router calls
app.include_router(tasks_router, prefix="/api/tasks", tags=["tasks"])
app.include_router(agent_router, prefix="/api/agent", tags=["agent"])
```

- [ ] **Step 4: Commit**

```bash
git add sample-app/backend/
git commit -m "feat: add tasks router with CRUD operations"
```

### Task 17: Create agent router

**Files:**
- Create: `sample-app/backend/routers/agent.py`

- [ ] **Step 1: Create routers/agent.py**

```python
from fastapi import APIRouter, HTTPException
import httpx
import os

from ..models import ChatRequest, ChatResponse

router = APIRouter()

# Environment variables
AGENT_SERVICE_URL = os.getenv("AGENT_SERVICE_URL", "http://localhost:8000")

@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Send a message to the agent and get a response."""
    try:
        agent_url = f"{AGENT_SERVICE_URL}/agent"
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                agent_url,
                json={"message": request.message}
            )
            response.raise_for_status()
            return response.json()
    except httpx.HTTPError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to reach agent service: {str(e)}"
        )
```

- [ ] **Step 2: Commit**

```bash
git add sample-app/backend/
git commit -m "feat: add agent router proxy"
```

### Task 18: Create backend Dockerfile

**Files:**
- Create: `sample-app/backend/Dockerfile`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Commit**

```bash
git add sample-app/backend/Dockerfile
git commit -m "feat: add backend Dockerfile"
```

---

## Part 6: Sample Application - Agents

### Task 19: Create LangChain agents service

**Files:**
- Create: `sample-app/agents/requirements.txt`
- Create: `sample-app/agents/agent.py`
- Create: `sample-app/agents/main.py`
- Create: `sample-app/agents/Dockerfile`

- [ ] **Step 1: Create requirements.txt**

```txt
fastapi==0.109.0
uvicorn[standard]==0.27.0
langchain==0.1.0
langchain-openai==0.0.2
langchain-core==0.1.0
pydantic==2.5.3
python-dotenv==1.0.0
```

- [ ] **Step 2: Create agent.py**

```python
from langchain_openai import AzureChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
import os

class FoundryAgent:
    """Simple agent that uses Microsoft Foundry for LLM completions."""

    def __init__(self):
        self.endpoint = os.getenv("FOUNDRY_ENDPOINT", "")
        self.api_key = os.getenv("FOUNDRY_API_KEY", "")
        self.model = os.getenv("FOUNDRY_MODEL", "gpt-4mini")

        # Parse endpoint to get base URL and deployment
        # Expected format: https://<resource>.openai.azure.com/
        base_url = self.endpoint.rstrip("/")
        if not base_url.endswith("/openai"):
            base_url = f"{base_url}/openai"

        self.llm = AzureChatOpenAI(
            azure_endpoint=base_url,
            api_key=self.api_key,
            api_version="2024-02-15-preview",
            deployment_name=self.model,
            temperature=0.7
        )

    async def chat(self, message: str) -> str:
        """Send a message to the LLM and get a response."""
        try:
            response = await self.llm.ainvoke([
                SystemMessage(content="You are a helpful AI assistant. Respond concisely and helpfully."),
                HumanMessage(content=message)
            ])
            return response.content
        except Exception as e:
            return f"Error: Unable to get response from Foundry. Details: {str(e)}"

# Singleton instance
_agent = None

def get_agent() -> FoundryAgent:
    global _agent
    if _agent is None:
        _agent = FoundryAgent()
    return _agent
```

- [ ] **Step 3: Create main.py**

```python
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import os

from agent import get_agent

app = FastAPI(
    title="Agentic POC Agents Service",
    description="LangChain agents service for the Agentic POC",
    version="0.1.0"
)

# CORS middleware - allow calls from backend service
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For POC - restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)

class ChatResponse(BaseModel):
    message: str

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "agents"}

@app.post("/agent", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    """Process a chat message using the LangChain agent."""
    agent = get_agent()
    response = await agent.chat(request.message)
    return ChatResponse(message=response)

@app.get("/")
async def root():
    return {
        "message": "Agentic POC Agents Service",
        "version": "0.1.0",
        "model": os.getenv("FOUNDRY_MODEL", "gpt-4mini")
    }
```

- [ ] **Step 4: Create Dockerfile**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 5: Commit**

```bash
git add sample-app/agents/
git commit -m "feat: add LangChain agents service"
```

---

## Part 7: Final Integration

### Task 20: Fix backend imports for package structure

**Files:**
- Modify: `sample-app/backend/main.py`
- Modify: `sample-app/backend/routers/tasks.py`
- Modify: `sample-app/backend/routers/agent.py`
- Modify: `sample-app/agents/main.py`

- [ ] **Step 1: Create __init__.py files**

```bash
# These files should already exist or be created as empty files
touch sample-app/backend/__init__.py
touch sample-app/backend/routers/__init__.py
touch sample-app/agents/__init__.py
```

- [ ] **Step 2: Update backend/main.py imports**

```python
# In sample-app/backend/main.py, update to use direct imports
from database import get_db, init_db, TaskDB
from models import Task, TaskCreate, TaskUpdate
from routers import tasks, agent
```

- [ ] **Step 3: Update routers/tasks.py imports**

```python
# In sample-app/backend/routers/tasks.py
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import get_db, TaskDB
from models import Task, TaskCreate, TaskUpdate
```

- [ ] **Step 4: Update routers/agent.py imports**

```python
# In sample-app/backend/routers/agent.py
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from models import ChatRequest, ChatResponse
```

- [ ] **Step 5: Update agents/main.py imports**

```python
# In sample-app/agents/main.py
from agent import get_agent
```

- [ ] **Step 6: Commit**

```bash
git add sample-app/
git commit -m "fix: update imports for container execution"
```

### Task 21: Create .dockerignore files

**Files:**
- Create: `sample-app/ui/.dockerignore`
- Create: `sample-app/backend/.dockerignore`
- Create: `sample-app/agents/.dockerignore`

- [ ] **Step 1: Create UI .dockerignore**

```
node_modules
npm-debug.log
dist
.env.local
.DS_Store
```

- [ ] **Step 2: Create backend .dockerignore**

```
__pycache__
*.pyc
*.pyo
*.pyd
venv
.venv
.env
.DS_Store
```

- [ ] **Step 3: Create agents .dockerignore**

```
__pycache__
*.pyc
*.pyo
*.pyd
venv
.venv
.env
.DS_Store
```

- [ ] **Step 4: Commit**

```bash
git add sample-app/
git commit -m "chore: add .dockerignore files"
```

### Task 22: Update README with complete instructions

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README.md**

```markdown
# Agentic POC - Azure IAC

Proof of Concept for deploying an agentic application to Azure Container Apps using Bicep infrastructure as code.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Container Apps Environment             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────┐         ┌──────────────────────┐     │
│  │ Container App #1     │         │ Container App #2     │     │
│  │   React UI (Nginx)   │         │   LangChain Agents   │     │
│  │   FastAPI Backend   │         │   (Python)           │     │
│  └──────────────────────┘         └──────────────────────┘     │
│           │                                  │                    │
└───────────┼──────────────────────────────────┼────────────────┘
            │                                  │
            ▼                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Services                            │
│  ACR │ PostgreSQL │ Storage │ App Insights │ Foundry (AI)      │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed and authenticated
- [Docker](https://docs.docker.com/get-docker/) installed
- Microsoft Foundry API key and endpoint

## Quick Start

### 1. Deploy Infrastructure

```bash
# Set environment variables
export POSTGRES_PASSWORD="YourSecurePassword123!"
export FOUNDRY_API_KEY="your-foundry-api-key"
export FOUNDRY_ENDPOINT="https://your-resource.openai.azure.com/"

# Deploy
./scripts/deploy.sh
```

This creates:
- Resource group: `rg-agentic-poc-dev`
- Azure Container Registry
- PostgreSQL Flexible Server
- Storage Account
- Application Insights
- Container Apps Environment + 2 Container Apps

### 2. Build and Push Images

```bash
# Get ACR name from deployment output
ACR_NAME="agenticpocdevacr"  # Replace with actual name from deployment

# Login to ACR
az acr login --name $ACR_NAME

# Build and push images
docker build -t $ACR_NAME.azurecr.io/ui:latest ./sample-app/ui
docker build -t $ACR_NAME.azurecr.io/backend:latest ./sample-app/backend
docker build -t $ACR_NAME.azurecr.io/agents:latest ./sample-app/agents

docker push $ACR_NAME.azurecr.io/ui:latest
docker push $ACR_NAME.azurecr.io/backend:latest
docker push $ACR_NAME.azurecr.io/agents:latest
```

### 3. Validate Deployment

```bash
./scripts/validate.sh
```

### 4. Access the Application

Get the URLs from the deployment output or run:
```bash
az deployment group show \
  --resource-group rg-agentic-poc-dev \
  --name main.bicep \
  --query properties.outputs.uiAppURL.value \
  --output tsv
```

Open the URL in your browser to access:
- **Tasks Tab**: Create and manage tasks (CRUD)
- **Agent Chat**: Chat with the AI agent powered by gpt-4mini

## Sample Application

### Features

- **Tasks CRUD**: Create, read, update, delete tasks with status tracking
- **Agent Chat**: Real-time chat interface with LangChain agents
- **Azure Integration**: PostgreSQL, Storage, Application Insights

### Tech Stack

- **Frontend**: React + Vite, vanilla CSS
- **Backend**: FastAPI, SQLAlchemy, asyncpg
- **Agents**: LangChain, Azure OpenAI (Foundry)
- **Infrastructure**: Bicep, Azure Container Apps

## Development

### Local Development

```bash
# UI
cd sample-app/ui
npm install
npm run dev

# Backend
cd sample-app/backend
pip install -r requirements.txt
uvicorn main:app --reload

# Agents
cd sample-app/agents
pip install -r requirements.txt
uvicorn main:app --reload
```

### Running Tests

```bash
# Backend tests
cd sample-app/backend
pytest tests/

# Agents tests
cd sample-app/agents
pytest tests/
```

## Cleanup

```bash
# Delete resource group and all resources
az group delete --name rg-agentic-poc-dev --yes --no-wait
```

## Documentation

- [Design Spec](docs/superpowers/specs/2026-03-21-agentic-poc-azure-iac-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-03-21-agentic-poc-azure-iac-implementation.md)

## Cost Estimates (Dev Environment, Monthly)

| Resource | Tier | Est. Cost |
|----------|------|-----------|
| Container Apps | Pay-per-use | $0-50 |
| ACR Standard | Fixed | ~$5 |
| PostgreSQL B1ms | Burstable | $15-20 |
| Storage Account | LRS | <$2 |
| App Insights | Pay-per-use | Minimal |
| **Total** | | ~$25-80/month |

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with complete instructions"
```

---

## Part 8: Final Review and Commit

### Task 23: Final verification and commit

**Files:**
- None (verification task)

- [ ] **Step 1: Verify all files are in place**

```bash
# Check structure
tree -L 3 -I 'node_modules|__pycache__|dist|.git'
```

Expected structure should match the file structure in this plan.

- [ ] **Step 2: Verify Bicep syntax**

```bash
# Validate Bicep files
az bicep build --file main.bicep
az bicep build --file modules/*.bicep
```

- [ ] **Step 3: Verify Python syntax**

```bash
# Check Python files
python -m py_compile sample-app/backend/main.py
python -m py_compile sample-app/backend/routers/tasks.py
python -m py_compile sample-app/backend/routers/agent.py
python -m py_compile sample-app/backend/database.py
python -m py_compile sample-app/backend/models.py
python -m py_compile sample-app/agents/main.py
python -m py_compile sample-app/agents/agent.py
```

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: complete Agentic POC Azure IAC implementation

- Infrastructure: Bicep modules for ACA, ACR, PostgreSQL, Storage, App Insights
- Sample App: React UI, FastAPI backend, LangChain agents
- Features: Tasks CRUD, Agent Chat with Foundry gpt-4mini
- Deployment: Automated deployment and validation scripts"
```

---

## Success Criteria

After completing this plan, you should be able to:

1. ✅ Deploy all Azure resources via `./scripts/deploy.sh`
2. ✅ Build and push all container images to ACR
3. ✅ Access the UI at the Container App URL
4. ✅ Create, read, update, and delete tasks via the UI
5. ✅ Chat with the AI agent and receive responses from Foundry
6. ✅ Verify all resources with `./scripts/validate.sh`
7. ✅ See telemetry in Application Insights

## Troubleshooting

### Container Apps not starting
- Check logs: `az containerapp logs show --name <app-name> --resource-group rg-agentic-poc-dev --follow`
- Verify ACR credentials and image names

### PostgreSQL connection issues
- Verify VNet integration is configured
- Check firewall rules in PostgreSQL

### Agent not responding
- Verify Foundry credentials are correct
- Check AGENT_SERVICE_URL environment variable
- Review agent container logs

---

**Total estimated completion time:** 3-4 hours

**Dependencies:** Azure CLI, Docker, Microsoft Foundry access

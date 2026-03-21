# Agentic POC Azure IAC Design

**Date:** 2026-03-21
**Author:** Claude
**Status:** Approved (Revision 3 - Final)

## Overview

Proof of Concept for deploying an agentic application to Azure Container Apps using Bicep infrastructure as code.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Azure Container Apps Environment        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────┐         ┌──────────────────────┐      │
│  │ Container App #1     │         │ Container App #2     │      │
│  │ ┌──────────────────┐ │         │ ┌──────────────────┐ │      │
│  │ │   React UI       │ │         │ │  LangChain       │ │      │
│  │ │   (Nginx/Proxy)  │ │         │ │  Agents          │ │      │
│  │ └──────────────────┘ │         │ │  (Python)        │ │      │
│  │ ┌──────────────────┐ │         │ └──────────────────┘ │      │
│  │ │   FastAPI        │ │         │                      │      │
│  │ │   Backend        │ │         │                      │      │
│  │ └──────────────────┘ │         │                      │      │
│  │ Managed Identity    │         │ Managed Identity     │      │
│  └──────────────────────┘         └──────────────────────┘      │
│           │                                  │                     │
└───────────┼──────────────────────────────────┼──────────────────┘
            │                                  │
            ▼                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Services                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │    ACR       │  │  PostgreSQL  │  │   Storage    │          │
│  │  (Registry)  │  │   Flexible   │  │   (Blob)     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│  ┌──────────────┐  ┌──────────────┐                         │
│  │   App Insights│ │Microsoft     │                         │
│  │   + Monitor  │  │Foundry (AI)  │                         │
│  └──────────────┘  └──────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

## Application Components

| Component | Technology | Deployment |
|-----------|-----------|------------|
| Frontend UI | React | Container App #1 (with backend) |
| Backend API | FastAPI | Container App #1 (with UI) |
| Agents | LangChain (Python) | Container App #2 (separate) |

## Azure Resources

### Container Apps
- **Environment**: Single dev environment, consumption profile, system-managed VNet
- **App 1 (UI+Backend)**:
  - Container 1: React static files served by Nginx (port 80)
  - Container 2: FastAPI backend (port 8000)
  - Container 3: (none for future use)
  - Single public ingress endpoint
  - Nginx routes `/api/*` to FastAPI container via localhost:8000
  - Authentication: None for sample app (public access)
  - Scaling: Min 1, Max 2, scale on HTTP concurrent requests
- **App 2 (Agents)**:
  - Python LangChain agents
  - Public ingress (can add auth later)
  - Scaling: Min 1, Max 5, scale on HTTP concurrent requests

### Container Registry (ACR)
- Standard tier
- Admin user enabled for CI/CD
- Images:
  - `ui:latest` - React static files + Nginx web server
  - `backend:latest` - FastAPI backend
  - `agents:latest` - Python LangChain agents

### PostgreSQL
- Flexible Server (version 15)
- Burstable B1ms tier
- Authentication: Password-based (admin username/password)
- VNet integration: Private access via Container Apps managed VNet injection
- Network: Delegated subnet within Container Apps Environment VNet
- Database: `agentdb`
- DNS: Azure-managed DNS resolution via VNet integration

### Storage Account
- Standard v2, LRS redundancy
- Blob container: `agent-data`

### Application Insights
- Classic workspace
- Linked to Log Analytics
- Auto-instrumentation for Container Apps

### Managed Identity
- System-assigned for both Container Apps
- Roles:
  - `Storage Blob Data Contributor` on Storage Account
  - `Monitoring Data Reader` on Application Insights (optional)
- Note: PostgreSQL uses password authentication, not Managed Identity

### Microsoft Foundry Integration
- **What it is**: Microsoft's AI model hosting and inference platform
- **Usage**: LangChain agents call Foundry APIs for LLM completions
- **Authentication**: API key stored in Container App secrets
- **Access**: Both FastAPI and Agents containers can call Foundry endpoint
- **Model for sample app**: gpt-4mini

## Sample Application

### Overview

A minimal end-to-end application to validate all provisioned Azure services. No authentication - public access for testing.

### Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| React UI | React + Vite | Simple single-page app with two tabs |
| FastAPI Backend | Python FastAPI | REST API for CRUD and agent proxy |
| LangChain Agents | Python LangChain | Echo agent calling Foundry gpt-4mini |

### Data Model: Agent Tasks

```
Table: tasks
┌─────────────┬─────────┬──────────────────┐
│ Column      │ Type    │ Description      │
├─────────────┼─────────┼──────────────────┤
│ id          │ UUID    │ Primary key      │
│ title       │ TEXT    │ Task title       │
│ description │ TEXT    │ Task details     │
│ status      │ TEXT    │ pending/active/done │
│ created_at  │ TIMESTAMP │ Auto-generated │
└─────────────┴─────────┴──────────────────┘
```

### API Endpoints

**CRUD Operations:**
```
POST   /api/tasks        - Create task
GET    /api/tasks        - List all tasks
GET    /api/tasks/{id}   - Get task by id
PUT    /api/tasks/{id}   - Update task
DELETE /api/tasks/{id}   - Delete task
```

**Agent Operations:**
```
POST   /api/agent/chat   - Send message to agent, get LLM response
```

### Agent Chat Flow

```
User → UI → FastAPI → LangChain Agent → Foundry (gpt-4mini) → Response
```

### Sample App Structure

```
sample-app/
├── ui/                        # React app
│   ├── src/
│   │   ├── App.jsx            # Main app with tabs
│   │   ├── components/
│   │   │   ├── TasksTab.jsx   # CRUD UI for tasks
│   │   │   └── AgentChatTab.jsx  # Chat interface
│   │   └── api/
│   │       └── client.js      # API client
│   ├── package.json
│   ├── vite.config.js
│   └── Dockerfile             # Nginx multi-stage build
├── backend/                   # FastAPI
│   ├── main.py                # App entry point
│   ├── models.py              # Pydantic models
│   ├── database.py            # PostgreSQL connection
│   ├── routers/
│   │   ├── tasks.py           # CRUD endpoints
│   │   └── agent.py           # Agent proxy endpoint
│   ├── requirements.txt
│   └── Dockerfile
└── agents/                    # LangChain agents
    ├── main.py                # FastAPI app (agent service)
    ├── agent.py               # LangChain agent setup
    ├── requirements.txt
    └── Dockerfile
```

### UI Features

- **Tasks Tab**: Create, list, edit, delete tasks
- **Agent Chat Tab**: Send messages, receive AI responses from gpt-4mini
- **Simple styling**: Basic CSS, no external component libraries
- **API client**: Fetch-based client for backend communication

### Container Configuration

**UI Container (Nginx):**
- Image: `ui:latest`
- Port: 80
- Health check: GET /
- Resource limits: 0.5 CPU, 1Gi memory
- Environment: None required

**Backend Container (FastAPI):**
- Image: `backend:latest`
- Port: 8000
- Health check: GET /health
- Resource limits: 0.5 CPU, 1Gi memory
- Environment variables:
  - `DATABASE_URL`: PostgreSQL connection string
  - `STORAGE_ACCOUNT_NAME`: Storage account name
  - `APP_INSIGHTS_CONNECTION_STRING`: For telemetry

**Agents Container (LangChain):**
- Image: `agents:latest`
- Port: 8000
- Health check: GET /health
- Resource limits: 1 CPU, 2Gi memory (LLM processing)
- Environment variables:
  - `FOUNDRY_API_KEY`: Secret reference
  - `FOUNDRY_ENDPOINT`: Secret reference (e.g., `https://<foundry-instance>.openai.azure.com/`)

### Database Initialization

- SQLAlchemy ORM with `models.py` defining the Task model
- `database.py` creates all tables on FastAPI startup using `Base.metadata.create_all()`
- Connection pooling enabled via SQLAlchemy engine
- Async support using `asyncpg` driver

### Inter-Container Communication

Container Apps within the same environment can reach each other using internal DNS:
- FastAPI calls Agents via: `http://<agents-app-name>.azurecontainerapps.io/`
- Internal calls bypass ingress, stay within VNet
- For containers in same app: FastAPI accessible from UI container at `http://localhost:8000`

### Storage Usage

Storage Account is provisioned for sample app validation:
- Agent chat history saved to `agent-data` blob container
- File format: `chat-{timestamp}.json`
- Managed Identity used for authentication (no connection strings in code)

## Module Structure

```
azure-iac/
├── main.bicep                    # Entry point, orchestrates all modules
├── modules/
│   ├── containerApps.bicep       # ACA environment + apps
│   ├── acr.bicep                 # Container Registry
│   ├── postgres.bicep            # PostgreSQL + VNet integration
│   ├── storage.bicep             # Storage Account
│   ├── monitor.bicep             # App Insights
│   └── managedIdentities.bicep   # Identities + RBAC role assignments
├── config/
│   └── parameters.dev.json       # Parameters
├── scripts/
│   ├── deploy.sh                 # Deployment script
│   └── validate.sh               # Post-deployment validation
├── sample-app/                   # Sample application for testing
│   ├── ui/                       # React UI
│   ├── backend/                  # FastAPI backend
│   └── agents/                   # LangChain agents
└── README.md
```

### Module Dependencies
```
main.bicep
├── acr.bicep (no dependencies)
├── postgres.bicep (no dependencies)
├── storage.bicep (no dependencies)
├── monitor.bicep (no dependencies)
├── containerApps.bicep
│   └── depends on: monitor.bicep (for App Insights connection string)
└── managedIdentities.bicep
    └── depends on: containerApps.bicep, storage.bicep (needs resource IDs)
```

### Module Responsibilities

| Module | Creates | Outputs |
|--------|---------|---------|
| `containerApps.bicep` | ACA Environment, 2 Container Apps, Ingress | App URLs, Identity IDs |
| `acr.bicep` | Container Registry | ACR login server, name |
| `postgres.bicep` | PostgreSQL Flexible Server, delegated subnet | DB hostname, admin username |
| `storage.bicep` | Storage Account, blob container | Account name, primary endpoint |
| `monitor.bicep` | Application Insights | Instrumentation key, connection string |
| `managedIdentities.bicep` | Role assignments only | None |

## Networking & Security

### Networking
- **Container Apps**: Public ingress, system-managed VNet with private VNet injection
- **PostgreSQL**: Private access via delegated subnet in Container Apps VNet (no public internet access)
- **Storage**: Public endpoint with Managed Identity authentication
- **DNS**: Azure-managed DNS for PostgreSQL private resolution

### Security
- **User Authentication**: No authentication for sample app (public access for testing)
  - *Note: Production deployment should implement Entra ID integration (FastAPI validates JWT tokens via MSAL)*
- **Service Authentication**: System-assigned Managed Identity for Azure service access
- **HTTPS**: Automatic managed certificates for Container Apps ingress
- **Secrets**: Container Apps secret references (not plain environment variables)

### Required Entra ID Resources (Future)
- App Registration for the frontend (FastAPI backend validates tokens)
- Redirect URI: Container App public endpoint URL
- *Not required for sample app, but documented for future implementation*

## Deployment

### Prerequisites
- Azure CLI installed and authenticated
- Docker (for building images locally during development)

### Parameters
**config/parameters.dev.json:**
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "eastus" },
    "resourceNamePrefix": { "value": "agentic-poc-dev" },
    "postgresAdminUsername": { "value": "pocadmin" },
    "postgresDatabaseName": { "value": "agentdb" },
    "postgresSku": { "value": "B_Burstable_B1ms" },
    "postgresVersion": { "value": "15" },
    "storageContainerName": { "value": "agent-data" },
    "acrSku": { "value": "Standard" }
  }
}
```

**Secrets (passed at deploy time, NOT in git):**
- `postgresAdminPassword` - Secure string, PostgreSQL admin password
- `foundryApiKey` - Secure string, Microsoft Foundry API key
- `foundryEndpoint` - URL for Foundry API endpoint (e.g., `https://<your-resource>.openai.azure.com/`)

### Deployment Steps
1. Create resource group:
   ```bash
   az group create -n rg-agentic-poc-dev -l eastus
   ```

2. Deploy infrastructure:
   ```bash
   az deployment group create \
     -g rg-agentic-poc-dev \
     -f main.bicep \
     -p @config/parameters.dev.json \
     --parameters postgresAdminPassword=$POSTGRES_PASSWORD \
                  foundryApiKey=$FOUNDRY_API_KEY \
                  foundryEndpoint=$FOUNDRY_ENDPOINT
   ```

3. Build and push container images:
   ```bash
   az acr login --name <acr-name>
   docker build -t <acr-name>.azurecr.io/ui:latest ./sample-app/ui
   docker build -t <acr-name>.azurecr.io/backend:latest ./sample-app/backend
   docker build -t <acr-name>.azurecr.io/agents:latest ./sample-app/agents
   docker push <acr-name>.azurecr.io/ui:latest
   docker push <acr-name>.azurecr.io/backend:latest
   docker push <acr-name>.azurecr.io/agents:latest
   ```

### Post-Deployment Validation
Script validates:
- Container Apps are in "Running" state
- PostgreSQL connectivity (connection test)
- Storage Account container exists
- Application Insights receives telemetry
- Public ingress URLs are accessible

## Success Criteria

### Infrastructure
- All Azure resources provision successfully
- Container Apps are in "Running" state
- Container Apps can communicate with PostgreSQL (VNet private access)
- Container Apps can read/write to Storage Account (via MSI)
- Application Insights receives telemetry from both apps
- Public ingress URLs are accessible
- Post-deployment validation script passes all checks

### Sample Application
- Sample app containers build and deploy successfully
- CRUD operations work (create, read, update, delete tasks)
- PostgreSQL persists data correctly
- Agent chat returns responses from Foundry (gpt-4mini)
- End-to-end user flow validates all Azure services

## Tagging Strategy

All resources will be tagged with:
- `Environment`: `dev`
- `Project`: `agentic-poc`
- `ManagedBy`: `bicep`
- `Owner`: `<user-specified>`

## Cost Estimates (Dev Environment, Monthly)

| Resource | Tier | Est. Cost |
|----------|------|-----------|
| Container Apps (consumption) | Pay-per-use | $0-50 depending on usage |
| ACR Standard | Fixed | $0.167/day ~ $5/month |
| PostgreSQL B1ms | Burstable | $15-20/month |
| Storage Account | LRS | Minimal (<$2/month) |
| App Insights | Pay-per-use | Minimal for dev |
| **Total** | | ~$25-80/month |

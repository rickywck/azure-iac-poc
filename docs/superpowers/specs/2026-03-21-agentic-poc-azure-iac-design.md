# Agentic POC Azure IaC Design

**Date:** 2026-03-21
**Author:** Claude
**Status:** Approved (Revision 4 - Aligned to current implementation)

## Overview

Proof of concept for deploying a split-workload agentic application to Azure Container Apps using Bicep, PowerShell deployment automation, Azure Key Vault-backed secret management, and a shared local and remote container-image model.

The design intentionally separates transactional application concerns from agentic workload concerns:

- `UI+Backend` is the public entry point for users.
- `Agents` is an internal-only service called by the backend.
- Azure PostgreSQL stores application data.
- Azure Key Vault stores the PostgreSQL admin password.
- Azure AI Foundry / Azure OpenAI powers the agent service.

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────┐
│                    Azure Container Apps Environment                  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────┐    ┌─────────────────────────────┐  │
│  │ Container App: UI+Backend    │    │ Container App: Agents      │  │
│  │                              │    │                             │  │
│  │  React UI + Nginx            │    │  FastAPI agent service     │  │
│  │  FastAPI backend             │───▶│  Azure OpenAI client       │  │
│  │  User-assigned identity      │    │  User-assigned identity    │  │
│  │  Public ingress              │    │  Internal ingress only     │  │
│  └──────────────────────────────┘    └─────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                    │                    │                    │
                    ▼                    ▼                    ▼
┌────────────────────────┐  ┌────────────────────────┐  ┌──────────────────────┐
│ Azure Database for     │  │ Azure Key Vault        │  │ Azure AI Foundry /   │
│ PostgreSQL Flexible    │  │ postgres-admin-password│  │ Azure OpenAI         │
│ Server                 │  │                        │  │                      │
└────────────────────────┘  └────────────────────────┘  └──────────────────────┘
                    │                    │                    │
                    └────────────┬───────┴────────────┬───────┘
                                 ▼                    ▼
                       ┌──────────────────┐   ┌──────────────────┐
                       │ Azure Storage    │   │ App Insights +   │
                       │ blob container   │   │ Log Analytics    │
                       └──────────────────┘   └──────────────────┘
```

## Design Principles

- Keep the `ui`, `backend`, and `agents` images identical across local and Azure.
- Inject environment-specific configuration at runtime instead of baking `.env` files into images.
- Separate application identity from operator identity.
- Store the PostgreSQL password in Key Vault and use one logical secret-resolution model across environments.
- Use phased deployment so Container Apps are not deployed before images exist in ACR.
- Keep the agents service internal-only and avoid presenting it as a public endpoint.

## Application Components

| Component | Technology | Runtime Placement | Responsibility |
|-----------|------------|-------------------|----------------|
| Frontend UI | React + Vite | `UI+Backend` Container App | Browser UI, task management, chat interface |
| UI web server | Nginx | `UI+Backend` Container App | Serves static assets and proxies API calls to backend |
| Backend API | FastAPI + SQLAlchemy + asyncpg | `UI+Backend` Container App | CRUD, orchestration, agent-service proxy, DB access |
| Agents service | FastAPI + Azure OpenAI client | `Agents` Container App | Foundry/OpenAI integration and agent responses |

## Azure Resources

### Container Apps

- One Container Apps Environment
- Two Container Apps

`UI+Backend` Container App:

- public ingress enabled
- target port `80`
- two containers:
  - `ui` container serves React build through Nginx
  - `backend` container serves FastAPI on port `8000`
- Nginx proxies backend traffic through `BACKEND_UPSTREAM=localhost:8000`
- scaling:
  - min replicas: `1`
  - max replicas: `3`
  - HTTP concurrent request rule: `10`
- user-assigned managed identity

`Agents` Container App:

- internal ingress only
- target port `8000`
- one `agents` container
- scaling:
  - min replicas: `1`
  - max replicas: `5`
  - HTTP concurrent request rule: `5`
- user-assigned managed identity

### Azure Container Registry

- Standard tier
- admin user enabled for current deployment flow
- images pushed by deployment scripts:
  - `ui:latest`
  - `backend:latest`
  - `agents:latest`

### Azure Database for PostgreSQL Flexible Server

- PostgreSQL Flexible Server, version `15`
- default SKU: `B_Burstable_B1ms`
- password authentication using generated admin credentials
- database: `agentdb`
- public network access enabled for this POC
- base firewall rule `AllowAllAzureServices`
- local development adds a `local-dev-client` firewall rule for the developer's current public IP

This is intentionally a simplified POC networking model. It is not a private-network production design.

### Azure Key Vault

- stores the generated PostgreSQL admin password
- RBAC authorization enabled
- soft delete enabled
- public network access enabled
- default secret name: `postgres-admin-password`

### Azure Storage Account

- Standard v2, LRS
- blob container for sample data
- both app identities receive `Storage Blob Data Contributor`

### Monitoring

- Application Insights plus Log Analytics workspace
- Container Apps environment configured to ship logs to Log Analytics
- apps receive Application Insights connection strings via Container App secrets

### Azure AI Foundry / Azure OpenAI

Two supported modes:

- repo-managed Foundry account created by `main.bicep`
- existing external Foundry/OpenAI resource supplied at deploy time

Default repo-managed model settings:

- model deployment name: `gpt-4mini`
- deployed model name: `gpt-4o-mini`

## Identity and Access Model

### Application Identities

`UI+Backend` user-assigned identity:

- reads PostgreSQL password from Key Vault in Azure using `KEY_VAULT_URL` and `POSTGRES_PASSWORD_SECRET_NAME`
- accesses Azure Storage

`Agents` user-assigned identity:

- accesses Azure Storage
- does not currently use Key Vault for Foundry credentials

### Operator Identity

- deployment scripts may need to read existing Key Vault secrets on rerun
- operator secret access is treated as an operational concern, not a permanent IaC-managed role assignment
- PowerShell deployment automation handles operator access checks and recovery where possible

## Secret Management Model

PostgreSQL password handling is intentionally unified across environments.

In Azure:

- deployment generates or reuses the PostgreSQL admin password
- password is stored in Key Vault
- backend receives Key Vault metadata, not the raw password
- backend resolves the password with `DefaultAzureCredential` at runtime

Locally:

- `scripts/setup-local-env.ps1` reads the same secret from Key Vault
- the script writes `POSTGRES_PASSWORD` into `sample-app/backend/.env`
- backend uses the same resolution logic: explicit env value first, Key Vault second

Foundry credentials remain injected into the agents app as Container App secrets for the current implementation.

## Sample Application

### Functional Scope

- task CRUD against PostgreSQL
- backend-to-agents chat flow
- agent responses backed by Azure AI Foundry / Azure OpenAI
- storage and monitoring wiring for Azure validation

### Data Model

Table: `tasks`

| Column | Type | Description |
|--------|------|-------------|
| `id` | string | Primary key |
| `title` | string | Task title |
| `description` | string | Optional details |
| `status` | string | Workflow state |
| `created_at` | datetime | Server-generated timestamp |

### API Surface

CRUD endpoints:

```text
POST   /api/tasks
GET    /api/tasks
GET    /api/tasks/{id}
PUT    /api/tasks/{id}
DELETE /api/tasks/{id}
```

Agent endpoint:

```text
POST   /api/agent/chat
```

### Request Flow

```text
Browser
  -> UI served by Nginx
  -> FastAPI backend
  -> internal Agents Container App
  -> Azure AI Foundry / Azure OpenAI
  -> response back through backend to UI
```

### Application Structure

```text
sample-app/
├── ui/
│   ├── src/
│   │   ├── App.jsx
│   │   ├── components/
│   │   │   ├── TasksTab.jsx
│   │   │   └── AgentChatTab.jsx
│   │   └── api/
│   │       └── client.js
│   ├── Dockerfile
│   └── nginx.conf.template
├── backend/
│   ├── main.py
│   ├── database.py
│   ├── models.py
│   ├── routers/
│   │   ├── tasks.py
│   │   └── agent.py
│   ├── requirements.txt
│   └── Dockerfile
└── agents/
    ├── main.py
    ├── agent.py
    ├── requirements.txt
    └── Dockerfile
```

## Runtime Configuration

### UI Container

- image: `ui:latest`
- port: `80`
- health probes on `/`
- runtime variable:
  - `BACKEND_UPSTREAM`

Local value:

- `backend:8000` when running with Docker Compose

Azure value:

- `localhost:8000` inside the multi-container `UI+Backend` app

### Backend Container

- image: `backend:latest`
- port: `8000`
- liveness: `/health`
- readiness: `/ready`

Key runtime variables:

- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_SSLMODE=require`
- `KEY_VAULT_URL`
- `POSTGRES_PASSWORD_SECRET_NAME`
- `AZURE_CLIENT_ID`
- `AGENT_SERVICE_URL`
- `STORAGE_ACCOUNT_NAME`
- `STORAGE_CONTAINER_NAME`
- `STORAGE_ACCOUNT_KEY`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`

### Agents Container

- image: `agents:latest`
- port: `8000`
- liveness: `/health`
- readiness: `/ready`

Key runtime variables:

- `FOUNDRY_API_KEY`
- `OPENAI_API_KEY`
- `FOUNDRY_ENDPOINT`
- `FOUNDRY_MODEL`
- `LANGCHAIN_API_KEY`
- `LANGCHAIN_TRACING_V2`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`

## Networking

- `UI+Backend` has a public HTTPS endpoint.
- `Agents` has internal ingress only.
- backend calls agents using the internal Container Apps FQDN exposed by the latest revision.
- PostgreSQL is reached over its public FQDN with SSL required.
- local Docker development also targets the Azure PostgreSQL server, not a separate local database container.

Operational consequence:

- local startup depends on `scripts/setup-local-env.ps1` creating or refreshing the `local-dev-client` firewall rule for the current public IP
- if the developer's public IP changes, local setup must be rerun

## Module Structure

```text
azure-iac/
├── main.bicep
├── app-update.bicep
├── modules/
│   ├── acr.bicep
│   ├── containerApps.bicep
│   ├── foundry.bicep
│   ├── keyVault.bicep
│   ├── managedIdentities.bicep
│   ├── monitor.bicep
│   ├── postgres.bicep
│   └── storage.bicep
├── config/
│   └── parameters.dev.json
├── scripts/
│   ├── deploy.ps1
│   ├── deploy-app.ps1
│   ├── setup-local-env.ps1
│   ├── deploy.sh
│   └── validate.sh
└── sample-app/
```

### Module Responsibilities

| Module | Responsibility | Key Outputs |
|--------|----------------|-------------|
| `acr.bicep` | Azure Container Registry | login server, admin credentials |
| `postgres.bicep` | PostgreSQL server, database, Azure-services firewall rule | host |
| `storage.bicep` | storage account and blob container | account name, primary key |
| `keyVault.bicep` | Key Vault and PostgreSQL password secret | vault URI, secret name |
| `monitor.bicep` | Application Insights and Log Analytics | instrumentation and connection details |
| `foundry.bicep` | optional repo-managed Foundry account and model deployment | endpoint, API key |
| `containerApps.bicep` | Container Apps environment, UI+Backend app, Agents app, user-assigned identities | FQDNs, principal IDs |
| `managedIdentities.bicep` | RBAC assignments for storage and Key Vault | none |

## Deployment Model

### Full Deployment

Primary path: `scripts/deploy.ps1`

Phases:

1. preflight validation
2. infrastructure deployment without Container Apps when required
3. image build and push to ACR
4. Container Apps deployment
5. post-deploy output and validation guidance

Key behaviors:

- generates or reuses the PostgreSQL password
- stores it in Key Vault
- supports Foundry soft-delete purge workflows when explicitly requested
- uses generated ARM parameter override files instead of fragile inline secret passing

### App-Only Deployment

Primary path: `scripts/deploy-app.ps1`

Use when infrastructure already exists and only application images or app-layer configuration changed.

Key behaviors:

- rebuilds and pushes `ui`, `backend`, and `agents`
- uses `app-update.bicep`
- preserves existing PostgreSQL and Key Vault state
- updates the Container Apps layer only

### External Foundry Mode

Supported by both deployment paths.

In this mode:

- Bicep does not create a repo-managed Foundry account
- deployment uses provided Foundry endpoint and API key

## Local Development Model

The same application images are intended to run locally and in Azure.

Local workflow:

1. deploy Azure infrastructure and apps
2. run `scripts/setup-local-env.ps1`
3. run `docker compose up --build`

`scripts/setup-local-env.ps1` performs three critical tasks:

- writes `.env` files for backend, agents, and Vite dev mode
- reads PostgreSQL password from Key Vault
- ensures Azure PostgreSQL allows the current public IP through the `local-dev-client` firewall rule

This keeps local development aligned with Azure without requiring separate local-only images.

## Security Notes

- no end-user authentication is implemented in the sample app
- HTTPS is handled by Container Apps ingress
- PostgreSQL password is not emitted as a deployment output
- backend receives Key Vault metadata rather than raw PostgreSQL password in Azure
- agents endpoint is intentionally private to the Container Apps environment

Current POC limitations:

- PostgreSQL uses public networking rather than private networking
- Foundry credentials are still injected as app secrets rather than being read from Key Vault
- operator secret-read access may require RBAC propagation time on reruns

## Validation and Success Criteria

Infrastructure is considered valid when:

- Bicep compiles cleanly
- Azure resources deploy successfully
- required images exist in ACR before Container Apps rollout
- `UI+Backend` is reachable publicly
- backend can connect to PostgreSQL using Key Vault-backed credentials in Azure
- backend can call the internal agents service successfully
- agents service can call Foundry successfully
- local setup can regenerate env files and refresh the PostgreSQL local firewall rule

Sample app success criteria:

- task CRUD works end to end
- task data persists in PostgreSQL
- chat requests flow through backend to agents and return a Foundry response
- local and Azure images remain functionally consistent

## Tagging Strategy

All managed resources use these tags:

- `Environment=dev`
- `Project=agentic-poc`
- `ManagedBy=bicep`

## Cost Estimates (Dev Environment, Monthly)

| Resource | Tier | Est. Cost |
|----------|------|-----------|
| Container Apps | Pay-per-use | $0-50 |
| ACR Standard | Fixed | ~$5 |
| PostgreSQL B1ms | Burstable | $15-20 |
| Storage Account | LRS | <$2 |
| App Insights | Pay-per-use | Minimal |
| Total |  | ~$25-80/month |
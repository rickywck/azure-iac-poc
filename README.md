# Agentic POC - Azure IAC

Proof of concept for deploying a split-workload agentic application to Azure Container Apps using Bicep.

## Architecture

The application is intentionally split into two independently deployable workloads:

- `UI+Backend` Container App
  - React UI served by Nginx
  - FastAPI backend for CRUD and orchestration
  - does not call Foundry directly for agentic work
- `Agents` Container App
  - FastAPI agent service
  - owns Foundry/OpenAI integration
  - can be scaled and deployed independently from the UI+Backend app

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Container Apps Environment             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────┐      ┌──────────────────────────┐  │
│  │ Container App #1        │      │ Container App #2         │  │
│  │ UI + FastAPI Backend    │ ---> │ Agents Service           │  │
│  │ React + Nginx + API     │      │ FastAPI + Foundry/OpenAI │  │
│  └─────────────────────────┘      └──────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Azure Services: ACR, PostgreSQL, Storage, App Insights, Foundry│
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed and authenticated
- [Docker Desktop](https://docs.docker.com/get-docker/) installed for local container runs and local image builds
- Access to an Azure subscription that can deploy:
  - Azure Container Apps
  - Azure Container Registry
  - Azure Database for PostgreSQL Flexible Server
  - Azure AI Foundry / Azure OpenAI

## Deployment Workflows

### Full Infrastructure + App Deployment

Use this when provisioning the environment for the first time or when infrastructure changes are required.

```powershell
cd C:\Users\ricky\poc\azure-iac
.\scripts\deploy.ps1
```

This flow:

- creates or updates the resource group
- deploys infrastructure resources
- builds and pushes the `ui`, `backend`, and `agents` images
- deploys both Container Apps

### App-Only Deployment

Use this when infrastructure is already in place and you only want to push updated application code to Azure Container Apps.

```powershell
cd C:\Users\ricky\poc\azure-iac
.\scripts\deploy-app.ps1
```

This flow:

- rebuilds and pushes the current application images
- updates only the Container Apps layer
- does not redeploy ACR, PostgreSQL, Storage, Monitor, or Foundry infrastructure

### External Foundry Mode

If you want to use an existing Foundry/OpenAI resource instead of the repo-managed one:

```powershell
.\scripts\deploy.ps1 -UseExistingFoundry
```

or

```powershell
.\scripts\deploy-app.ps1 -UseExistingFoundry
```

## Accessing the Azure Application

After deployment, the script prints the Container App URLs.

Use the `UI+Backend URL` as the application entry point.

You can also query outputs manually:

```powershell
az deployment group show `
  --resource-group rg-agentic-poc-dev `
  --name main `
  --query properties.outputs `
  --output json
```

## Local Development

### Generate Local Environment Files

Generate `.env` files from the deployed Azure resources:

```powershell
cd C:\Users\ricky\poc\azure-iac
.\scripts\setup-local-env.ps1 -ResourceGroup rg-agentic-poc-dev -PostgresPassword "YourPostgresPassword"
```

This creates:

- `sample-app/backend/.env`
- `sample-app/agents/.env`
- `sample-app/ui/.env`

### Run the Full App Locally with Docker Compose

This is the preferred local workflow because it mirrors the deployed two-app architecture.

```powershell
cd C:\Users\ricky\poc\azure-iac
docker compose up --build
```

Endpoints:

- UI: `http://localhost:8080`
- Backend API: `http://localhost:8000`
- Agents service: `http://localhost:8001`

Stop the local stack:

```powershell
docker compose down
```

## Sample Application

### Features

- Tasks CRUD with PostgreSQL persistence
- Agent chat routed from backend to dedicated agents service
- Explicit split between transactional/backend workload and agentic workload
- Azure integrations for PostgreSQL, Storage, App Insights, and Foundry

### Tech Stack

- Frontend: React + Vite
- UI container: Nginx
- Backend: FastAPI, SQLAlchemy, asyncpg
- Agents: FastAPI, Azure OpenAI client
- Infrastructure: Bicep, Azure Container Apps

## Operational Notes

- The backend and agents workloads are intentionally separated so they can be:
  - independently updated
  - independently scaled
  - independently troubleshot
- The backend does not depend on LangChain.
- The agentic workload is isolated in the agents service.
- `deploy.ps1` is the full environment deployment path.
- `deploy-app.ps1` is the faster application-only update path.

## Validation and Logs

Validate the Bicep templates:

```powershell
az bicep build --file main.bicep
az bicep build --file app-update.bicep
```

Tail Azure Container App logs:

```powershell
az containerapp logs show --resource-group rg-agentic-poc-dev --name agenticpocdev2-ui --follow
```

```powershell
az containerapp logs show --resource-group rg-agentic-poc-dev --name agenticpocdev2-agents --follow
```

## Cleanup

Delete the Azure environment:

```powershell
az group delete --name rg-agentic-poc-dev --yes --no-wait
```

## Documentation

- [Design Spec](c:/Users/ricky/poc/azure-iac/docs/superpowers/specs/2026-03-21-agentic-poc-azure-iac-design.md)
- [Implementation Plan](c:/Users/ricky/poc/azure-iac/docs/superpowers/plans/2026-03-21-agentic-poc-azure-iac-implementation.md)

## Cost Estimates (Dev Environment, Monthly)

| Resource | Tier | Est. Cost |
|----------|------|-----------|
| Container Apps | Pay-per-use | $0-50 |
| ACR Standard | Fixed | ~$5 |
| PostgreSQL B1ms | Burstable | $15-20 |
| Storage Account | LRS | <$2 |
| App Insights | Pay-per-use | Minimal |
| Total |  | ~$25-80/month |

## License

MIT

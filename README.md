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
- generates or reuses a PostgreSQL admin password and stores it in Azure Key Vault
- deploys infrastructure resources
- builds and pushes the `ui`, `backend`, and `agents` images
- deploys both Container Apps

### App-Only Deployment

Use this when infrastructure is already in place and you only want to push updated application code to Azure Container Apps.

```powershell
cd C:\Users\ricky\poc\azure-iac
.\scripts\deploy-app.ps1
```

For environments where local Docker is unavailable (for example Cloud Shell), use the ACR-build variant:

```powershell
cd C:\Users\ricky\poc\azure-iac
.\scripts\deploy-app-acr.ps1
```

This flow:

- rebuilds and pushes the current application images
- updates only the Container Apps layer
- preserves the existing Key Vault managed PostgreSQL password
- does not redeploy ACR, PostgreSQL, Storage, Monitor, or Foundry infrastructure

### External Foundry Mode

If you want to use an existing Foundry/OpenAI resource instead of the repo-managed one:

```powershell
.\scripts\deploy.ps1 -UseExternalFoundry `
  -ExternalFoundryEndpoint "https://<your-foundry-resource>.openai.azure.com/" `
  -ExternalFoundryApiKey "<your-foundry-api-key>"
```

or

```powershell
.\scripts\deploy-app.ps1 -UseExternalFoundry `
  -ExternalFoundryEndpoint "https://<your-foundry-resource>.openai.azure.com/" `
  -ExternalFoundryApiKey "<your-foundry-api-key>"
```

or

```powershell
.\scripts\deploy-app-acr.ps1 -UseExternalFoundry `
  -ExternalFoundryEndpoint "https://<your-foundry-resource>.openai.azure.com/" `
  -ExternalFoundryApiKey "<your-foundry-api-key>"
```

## Accessing the Azure Application

After deployment, the script prints the public UI URL and the internal agents service FQDN.

Use the `UI+Backend URL` as the application entry point.

Do not expect the agents service FQDN to open in a browser. The agents Container App uses internal ingress only and is intended to be called by the backend, not directly from the public internet.

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
.\scripts\setup-local-env.ps1 -ResourceGroup rg-agentic-poc-dev
```

This creates:

- `sample-app/backend/.env`
- `sample-app/agents/.env`
- `sample-app/ui/.env` for Vite dev mode only

The setup script:

- reads the PostgreSQL password from Azure Key Vault and writes it into the local backend `.env`
- ensures the Azure PostgreSQL firewall allows the current public client IP through a `local-dev-client` rule

In Azure, the backend resolves the same password from Key Vault at runtime using its managed identity.

If your public IP changes, rerun `scripts/setup-local-env.ps1` before starting the local stack so the PostgreSQL firewall rule stays aligned with your current client IP.

### Run the Full App Locally with Docker Compose

This is the preferred local workflow because it mirrors the deployed two-app architecture.

The same `ui`, `backend`, and `agents` images can be used locally and in Azure. Environment-specific values are injected at runtime instead of being baked into the images.

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
- PostgreSQL password managed in Azure Key Vault

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
- The backend code supports both local and Azure secret resolution with the same config logic:
  - local uses `POSTGRES_PASSWORD` from `.env`
  - Azure uses `KEY_VAULT_URL` and `POSTGRES_PASSWORD_SECRET_NAME`
- Local Docker development talks to the Azure PostgreSQL server directly, so successful local startup depends on the `local-dev-client` firewall rule matching your current public IP.
- `deploy.ps1` is the full environment deployment path.
- `deploy-app.ps1` is the faster application-only update path.
- `deploy-app-acr.ps1` is the app-only path that always uses `az acr build` and does not require local Docker.

## POC Learnings For Production Planning

This section captures implementation lessons and precautions from this POC to reuse in the real project.

### Deployment Model

- Keep deployments phased:
  - infra first
  - image build and push second
  - app rollout third
- Avoid inline dynamic Azure CLI parameters for secrets and booleans. Use temporary parameter override files.
- Keep app-only deployment separate from full infra deployment.

### Image Build Strategy

- Local development and Azure deployment are separate workflows:
  - local: `docker compose up --build`
  - Azure: script-driven push to ACR, then Container App update
- `az acr build` does not require Docker on the local machine and is preferred for Cloud Shell and CI execution.
- If running from Cloud Shell, source code must be present in the Cloud Shell filesystem (cloned or uploaded) before running `az acr build`.
- Keep `.dockerignore` strict so build context uploads stay fast and deterministic.

### Secret and Config Strategy

- PostgreSQL password pattern is stable and should be retained:
  - generated or reused by deployment automation
  - stored in Key Vault
  - resolved by backend at runtime in Azure via managed identity
- Foundry secret handling currently differs by mode:
  - repo-managed Foundry: key resolved by template from the managed resource
  - external Foundry: endpoint and key must be provided explicitly to deployment scripts
- For long-term consistency, consider moving external Foundry credentials to Key Vault and resolving them with managed identity as well.

### Networking and Local Development

- Agents app is intentionally internal-only. Its internal FQDN is not a browser entry point.
- Local backend connectivity depends on Azure PostgreSQL firewall alignment with current public IP.
- Always rerun `scripts/setup-local-env.ps1` after IP changes or after recreating the resource group.

### Azure Platform Precautions

- Foundry/OpenAI naming conflicts can persist after resource group deletion due to soft-delete behavior.
- Treat operator access and app identity access as separate concerns.
- Do not assume control-plane admin rights imply Key Vault data-plane secret-read access.

### Script and Tooling Precautions

- Use `-UseExternalFoundry` only when intentionally switching to a different Foundry resource than the repo-managed one.
- Prefer non-interactive parameters for automation and reproducibility.
- Validate Bicep and script changes before reruns to avoid long failure loops.

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

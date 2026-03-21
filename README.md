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

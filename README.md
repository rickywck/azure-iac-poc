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

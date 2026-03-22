# Agentic POC Azure IaC Implementation Plan

> **Plan Version:** Revision 3 - Aligned to current implementation

## Goal

Maintain and evolve a deployable Azure Container Apps proof of concept with:

- one public `UI+Backend` app
- one internal-only `Agents` app
- Azure PostgreSQL for persistence
- Azure Key Vault-backed PostgreSQL secret management
- Azure AI Foundry / Azure OpenAI integration
- local and Azure runtime parity through shared container images

This plan reflects what is already implemented, what is operationally verified, and what remains as follow-up hardening work.

## Current Delivery Status

### Completed Architecture Work

- Split-workload architecture implemented:
  - `UI+Backend` Container App is the public entry point
  - `Agents` Container App is internal-only
- Shared image model implemented:
  - same `ui`, `backend`, and `agents` images run locally and in Azure
  - UI image uses runtime Nginx templating rather than environment-specific builds
- Azure infrastructure modularized in Bicep:
  - `acr.bicep`
  - `postgres.bicep`
  - `storage.bicep`
  - `monitor.bicep`
  - `foundry.bicep`
  - `keyVault.bicep`
  - `containerApps.bicep`
  - `managedIdentities.bicep`
- Full deployment and app-only deployment paths implemented:
  - `scripts/deploy.ps1`
  - `scripts/deploy-app.ps1`
- Local environment bootstrap implemented:
  - `scripts/setup-local-env.ps1`

### Completed Secret and Identity Work

- PostgreSQL admin password is generated or reused by deployment automation
- PostgreSQL password is stored in Azure Key Vault
- backend in Azure resolves PostgreSQL password from Key Vault using managed identity
- local setup reads the same secret from Key Vault and writes local `.env` files
- `UI+Backend` identity has Key Vault secret-read access
- application identities have Storage Blob Data Contributor access

### Completed Runtime and Operations Work

- agents endpoint is no longer treated as a public URL in scripts or docs
- app-only deployment updates Container Apps without redeploying the full infrastructure
- Foundry soft-delete naming conflicts are handled in deployment automation
- deployment automation uses generated ARM parameter override files instead of brittle inline secret and boolean parameter passing
- local setup now creates or refreshes the Azure PostgreSQL `local-dev-client` firewall rule for the current public IP

## Current Repository Shape

```text
azure-iac/
├── main.bicep
├── app-update.bicep
├── config/
│   └── parameters.dev.json
├── docs/
│   ├── iac-generation-instructions.md
│   └── superpowers/
│       ├── plans/
│       │   └── 2026-03-21-agentic-poc-azure-iac-implementation.md
│       └── specs/
│           └── 2026-03-21-agentic-poc-azure-iac-design.md
├── modules/
│   ├── acr.bicep
│   ├── containerApps.bicep
│   ├── foundry.bicep
│   ├── keyVault.bicep
│   ├── managedIdentities.bicep
│   ├── monitor.bicep
│   ├── postgres.bicep
│   └── storage.bicep
├── sample-app/
│   ├── agents/
│   ├── backend/
│   └── ui/
└── scripts/
    ├── deploy.ps1
    ├── deploy-app.ps1
    ├── deploy.sh
    ├── setup-local-env.ps1
    └── validate.sh
```

## Implementation Workstreams

### Workstream 1: Infrastructure Modules

Status: Complete for current POC scope

Delivered:

- ACR deployment
- PostgreSQL deployment with public access and Azure-services firewall rule
- Storage account and blob container
- Application Insights and Log Analytics integration
- optional repo-managed Foundry deployment
- Key Vault and PostgreSQL password secret
- Container Apps environment and both Container Apps
- RBAC role assignments for app identities

Remaining hardening opportunities:

- evaluate removing ACR admin-user dependency from deployment flow
- evaluate moving Foundry secrets to Key Vault-backed runtime access
- evaluate private-network PostgreSQL design for a production-oriented variant

### Workstream 2: Application Runtime

Status: Complete for current POC scope

Delivered:

- React UI for tasks and chat
- FastAPI backend for CRUD and agent-service proxy
- FastAPI agents service using Azure OpenAI client
- SQLAlchemy async PostgreSQL integration
- runtime Nginx proxy configuration using `BACKEND_UPSTREAM`
- health and readiness probes aligned with container ports

Remaining hardening opportunities:

- improve retry and startup diagnostics when PostgreSQL or agents are temporarily unavailable
- add stronger runtime validation for missing Foundry configuration

### Workstream 3: Deployment Automation

Status: Complete for current POC scope

Delivered:

- full deployment path in `scripts/deploy.ps1`
- app-only deployment path in `scripts/deploy-app.ps1`
- external Foundry option
- Foundry soft-delete purge support
- temporary deployment override parameter files for dynamic values
- operator Key Vault access recovery logic where needed

Remaining hardening opportunities:

- expand automatic post-failure Azure deployment diagnostics
- add richer preflight validation summaries before execution
- reduce divergence between PowerShell and shell-script workflows

### Workstream 4: Local Development Experience

Status: Complete for current POC scope

Delivered:

- local `.env` generation from deployed Azure resources
- local PostgreSQL secret retrieval from Key Vault
- local firewall rule automation for Azure PostgreSQL access
- Docker Compose workflow using the same images and runtime model as Azure

Remaining hardening opportunities:

- optionally remove local plaintext PostgreSQL password duplication by supporting a fully Key Vault-driven local path
- add an explicit local validation command that verifies DB connectivity before full stack startup

### Workstream 5: Documentation

Status: Updated

Delivered:

- README aligned to current local and Azure workflows
- design spec aligned to current implemented architecture
- reusable Azure IaC generation guidance captured in `docs/iac-generation-instructions.md`

Remaining hardening opportunities:

- add a troubleshooting guide for common Azure rerun failures
- document expected operator permissions more explicitly

## Phase Plan

### Phase 1: Baseline Maintenance

Status: Complete

Objectives achieved:

- modular Bicep templates in place
- sample application deployed to Container Apps
- shared local and Azure image pattern established

### Phase 2: Secret Management Refactor

Status: Complete

Objectives achieved:

- PostgreSQL password generation moved into deployment automation
- password persisted in Key Vault
- backend secret-resolution logic unified across local and Azure

### Phase 3: Deployment Robustness

Status: Complete for current scope

Objectives achieved:

- phased deployment support
- safer parameter passing
- Foundry soft-delete handling
- operator-access recovery for reruns

### Phase 4: Operational Hardening

Status: Partially complete

Completed:

- corrected agents endpoint semantics
- local PostgreSQL firewall automation
- updated docs to reflect actual runtime behavior

Still open:

- better automated diagnostics on Azure deployment failure
- stronger preflight checks for hidden Azure state
- production-grade network posture as a separate design path

## Verification Checklist

### Infrastructure Verification

- [x] Bicep templates compile cleanly
- [x] Key Vault is part of the deployment model
- [x] Container Apps identities receive required RBAC assignments
- [x] app-only deployment path exists separately from full deployment

### Application Verification

- [x] backend and agents are deployed as separate workloads
- [x] agents ingress is internal-only
- [x] backend uses Key Vault metadata for PostgreSQL in Azure
- [x] local and Azure use the same container images

### Operations Verification

- [x] local setup generates `.env` files from Azure outputs and secrets
- [x] local setup refreshes the PostgreSQL firewall rule for the current IP
- [x] deployment supports existing external Foundry usage
- [x] docs align with the current architecture

### Follow-Up Verification Targets

- [ ] automated deployment-failure diagnostics are comprehensive enough to avoid manual Azure investigation in common cases
- [ ] shell-based deployment path has feature parity with the PowerShell path
- [ ] a production-oriented private-network variant is documented separately from the current POC

## Recommended Next Tasks

1. Add a dedicated troubleshooting document for rerun failures, Key Vault access issues, and Foundry name conflicts.
2. Add stronger preflight validation output to `scripts/deploy.ps1` so hidden Azure state is surfaced before deployment starts.
3. Decide whether local backend development should continue writing `POSTGRES_PASSWORD` into `.env` or move to a stricter Key Vault-only local model.
4. Decide whether Foundry secrets should remain Container App secrets or move to Key Vault-backed retrieval as a follow-up refactor.
5. If a production track is needed, create a separate design and implementation plan for private PostgreSQL networking and tighter secret isolation.

## Success Criteria

The current implementation is considered successful for the POC when all of the following remain true:

- full deployment can provision infrastructure and deploy both apps
- app-only deployment can refresh app code without reprovisioning core infrastructure
- backend can read PostgreSQL credentials securely in Azure
- local setup can regenerate working environment files and restore local database connectivity after IP changes
- the public entry point is the `UI+Backend` app only
- the agents service remains private to the Container Apps environment
- documentation reflects the actual deployed and supported behavior
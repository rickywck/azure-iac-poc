# Azure IaC Generation Instructions

Use this file as reusable prompt guidance when generating or modifying Azure IaC, deployment scripts, or app configuration for this repository and similar projects.

## Purpose

Generate production-shaped Azure infrastructure and deployment automation that is:

- predictable
- preflight-validated
- idempotent where practical
- explicit about ownership of existing resources
- secure by default
- diagnosable when Azure returns nested deployment failures

The goal is to avoid trial-and-error deployment behavior and reduce hidden Azure state surprises.

## Technology Context

Assume the following stack unless the prompt says otherwise:

- Azure Bicep for infrastructure definitions
- PowerShell for Windows deployment automation
- Azure CLI for deployment, validation, and diagnostics
- Azure Container Apps for runtime
- Azure Container Registry for images
- Azure Database for PostgreSQL Flexible Server
- Azure Key Vault for secrets
- Azure Application Insights and Log Analytics for monitoring
- Azure AI Foundry / Azure OpenAI for model access

## Required Design Principles

### 1. Prefer phased deployment over one-shot deployment

Always separate deployment into clear phases when images or runtime dependencies are involved:

1. Infrastructure phase
2. Image build and push phase
3. Application deployment phase
4. Post-deploy verification phase

Do not deploy Container Apps before required images exist in ACR.

### 2. Add explicit preflight checks before deployment

Before deploying, validate:

- Azure CLI is installed and authenticated
- target subscription and resource group are correct
- required parameter file exists and is parseable
- deleted Azure AI Foundry / Cognitive Services accounts do not block the chosen name
- ACR image tags exist before app rollout phase
- Key Vault existence and secret readability assumptions are valid
- required role assignment capability exists if the script needs to grant RBAC
- existing resources are either intentionally adopted or intentionally created

If a check fails, stop early with a concrete action message.

### 3. Never rely on inline CLI parameter quoting for secrets or booleans

When passing dynamic deployment overrides to Azure CLI:

- do not pass secrets or booleans inline when avoidable
- generate a temporary ARM parameters JSON file for runtime overrides
- pass both the baseline parameter file and the generated override file

This avoids PowerShell parsing bugs and accidental coercion of booleans.

### 4. Keep local and remote images identical

Use the same container images for local and Azure.

- inject environment-specific values at runtime
- do not bake `.env` files into images
- exclude local `.env` files from Docker build context
- for frontend containers, prefer runtime templating over environment-specific image variants

### 5. Keep secret resolution logic consistent across environments

Application code should support one logical configuration model across local and Azure:

- local may use plain environment variables from `.env`
- Azure should use managed identity plus Key Vault metadata when possible
- code should resolve the secret from env first, then Key Vault if env is absent

Do not maintain two unrelated configuration code paths if one shared resolution model is possible.

### 6. Separate application identity from operator identity

Treat these as distinct actors:

- application managed identity
- deployment operator identity
- human troubleshooting identity

Do not assume that a user who can deploy infra should automatically read secrets.

Application secret access should be granted explicitly to the application identity.
Operator secret access should be handled deliberately and minimally.

### 7. Keep operator access out of long-lived IaC where possible

Avoid representing transient human troubleshooting access as persistent Bicep-managed RBAC unless there is a strong reason.

Prefer:

- script-side idempotent checks and grants for the current operator when necessary
- stable IaC-managed roles only for application identities and required service identities

This reduces `RoleAssignmentExists` conflicts and avoids mixing operator state with core infrastructure state.

### 8. Be explicit about adopting existing resources

If a deployment may target existing resources, the design must explicitly choose one mode:

- create and manage resource
- reference existing resource without mutating it
- migrate or adopt resource with documented risks

Do not silently take ownership of an existing PostgreSQL server or other stateful resource.

If existing-resource support is needed, add dedicated parameters such as:

- `UseExistingPostgres`
- `ExistingPostgresHost`
- `ExistingKeyVaultName`
- `UseExistingFoundry`

### 9. Treat soft-delete and global naming as first-class Azure concerns

For globally named or custom-subdomain-backed services such as Foundry / OpenAI:

- check deleted resources before creation
- surface purge guidance clearly
- optionally support explicit purge switches
- do not assume deleting a resource group releases the global name immediately

### 10. Outputs must not leak secrets

Do not output:

- passwords
- keys
- secret values

Avoid even naming outputs in ways that trip secret-output lint unless the output is truly non-secret and clearly named.

### 11. Prefer symbolic references in Bicep

Follow Bicep best practices:

- prefer symbolic references over `resourceId()` and `reference()` when possible
- use `existing` resources for adoption scenarios
- use `parent:` for child resources
- avoid unnecessary module `name` fields when not needed
- use `@secure()` on sensitive parameters and outputs

### 12. Do not hide failure details

When deployment fails, scripts must automatically surface:

- the failing top-level deployment phase
- the failing resource name
- the Azure error code
- the nested error message when available
- suggested next actions

Whenever practical, automatically query deployment operations rather than telling the user to investigate manually.

## Deployment Script Requirements

When generating PowerShell deployment scripts:

- support full deployment and app-only deployment separately
- implement preflight functions explicitly
- implement idempotent helper functions for Azure state checks
- use temporary JSON override files for dynamic parameters
- fail fast on ambiguous or unsafe states
- print structured phase headings
- avoid duplicating phase banners or contradictory messages
- avoid destructive actions unless explicitly requested or opt-in

If a script supports auto-remediation, make it opt-in when the action is destructive, such as purging soft-deleted services.

## Key Vault and Secret Handling Rules

When using Key Vault:

- store generated PostgreSQL admin password in Key Vault
- let the app read it with managed identity in Azure
- let local setup scripts retrieve it and write local `.env` files when needed
- keep human secret access minimal and explicit
- account for RBAC propagation delay in troubleshooting guidance

If a rerun depends on reading an existing secret, the script should:

1. detect the unreadable-secret condition
2. check whether the current operator already has the needed data-plane role
3. attempt an idempotent role grant only if appropriate
4. retry after a short delay
5. fail with a precise message if still unreadable

## Container Apps Rules

When generating Container Apps resources:

- do not inject secrets directly if Key Vault plus managed identity is the intended runtime pattern
- use internal ingress for internal-only services
- do not print private internal endpoints as public URLs
- ensure probes match actual ports and health endpoints
- ensure any internal service URL matches the ingress model

## App Configuration Rules

When generating backend configuration code for secrets:

- first use explicit environment variable value if present
- otherwise use Key Vault metadata to fetch the secret
- cache secret lookup when appropriate to avoid repeated round trips
- keep the resulting database URL construction deterministic and testable

## Diagnostics Requirements

Always design deployment tooling so that failures can be understood without guesswork.

At minimum include:

- preflight summary
- phase-based logging
- resource-name echoing for important generated names
- Azure deployment operation details on failure
- separation of model-availability failures from unrelated infrastructure failures

## Anti-Patterns To Avoid

Do not generate solutions that:

- deploy app runtime before images exist
- depend on manual secret entry for every rerun when secrets are supposed to be managed
- mix user-operator RBAC and application RBAC carelessly in Bicep
- assume portal admin implies Key Vault secret read access
- treat Azure nested deployment failures as normal user-facing diagnostics
- rely on deleting a resource group to clear globally reserved service names
- silently mutate existing databases or stateful services without an explicit adoption mode

## Acceptance Criteria For New IaC Changes

Any generated change should satisfy all of the following where relevant:

1. Bicep compiles cleanly
2. PowerShell or shell scripts pass syntax validation
3. preflight checks exist for the major Azure-specific hidden failure modes
4. local and Azure image usage remain aligned
5. secrets are not baked into images
6. secrets are not emitted as outputs
7. app-only deployment path does not require redeploying the full infra
8. existing-resource behavior is explicit, not accidental
9. failure output is actionable
10. documentation reflects the actual architecture and operational model

## Reusable Prompt Template

Use this prompt template for future IaC generation tasks:

```md
Generate or modify Azure IaC and deployment automation for this repository.

Requirements:
- Use phased deployment: infra, image push, app deploy, verification.
- Add explicit preflight validation for Azure hidden state, RBAC, soft-delete, and image existence.
- Use Bicep best practices and symbolic references.
- Do not pass secrets or booleans inline to Azure CLI when dynamic values are involved; use temporary parameter files.
- Keep local and Azure container images identical; inject configuration at runtime.
- Use Key Vault for managed secrets in Azure and support local `.env` generation from the same source when required.
- Keep application identity access separate from operator identity access.
- Avoid storing operator troubleshooting RBAC as long-lived IaC unless explicitly required.
- Treat existing resource adoption as an explicit mode, not an implicit side effect.
- On deployment failure, automatically surface nested deployment diagnostics.
- Do not leak secrets in outputs or logs.

Output expectations:
- minimal, targeted code changes
- updated documentation if operational behavior changes
- validation steps and known risks
```

## Repository-Specific Notes

- The UI and Azure runtime should use the same images locally and remotely.
- The agents service is intentionally internal-only in Azure.
- Foundry naming conflicts can persist after resource group deletion because soft-deleted accounts reserve names.
- Key Vault data-plane access is separate from portal or resource management access.
- Stateful resources such as PostgreSQL need explicit ownership or adoption semantics.
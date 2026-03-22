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
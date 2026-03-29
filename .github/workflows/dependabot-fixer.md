---
name: "Dependabot Helper"
on:
  pull_request:
    types: [opened]

permissions:
  contents: read

# Ensure it only runs for dependabot PRs
if: ${{ github.event.pull_request.user.login == 'dependabot[bot]' }}

safe-outputs:
  create-pull-request:
    draft: false
---

# Dependabot Helper
1. **Analyze:** Look at the dependency being updated.
2. **Sync:** Run the appropriate package manager (e.g., `npm install`) to update the lockfile.
3. **PR:** Use `create-pull-request` to push the updated lockfile to the same PR or a follow-up.
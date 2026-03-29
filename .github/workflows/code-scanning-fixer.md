---
name: "CodeQL Security Fixer"
on:
  # Using workflow_dispatch allows you to trigger it via the UI 
  # or via a standard GH Action that calls this agent.
  workflow_dispatch:
  # If you want it to run on PRs to check for new alerts:
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  pull-requests: write
  security-events: read

safe-outputs:
  create-pull-request:
    draft: true
---

# CodeQL Security Fixer
You are a security engineer. Your task is to investigate and fix CodeQL alerts.

## Instructions
1. **Identify Alert:** Use the `list-code-scanning-alerts` tool to find recent open alerts.
2. **Analyze:** Read the code at the alert location.
3. **Fix:** Apply the fix to the files in your workspace.
4. **Submit:** Call the `create-pull-request` tool to propose the fix.
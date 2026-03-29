---
name: "CodeQL Security Fixer"
on:
  # The agentic engine uses 'security_event' or 'workflow_dispatch' 
  # for scanning-related triggers
  security_event:
    types: [created]

permissions:
  contents: read
  pull-requests: write
  security-events: read

safe-outputs:
  create-pull-request:
    draft: true
    # Remove branch-prefix as it's not supported here
    # Labels must be in the 'allowed-labels' list if restricted
    auto-merge: false 
---

# CodeQL Security Fixer
You are a security engineer. A new CodeQL alert has been detected.

## Instructions
1. **Fetch Alert:** Use the GitHub toolset to retrieve the details of the alert that triggered this workflow.
2. **Analyze:** Read the source code at the reported location.
3. **Fix:** Apply a security patch to the code in your temporary workspace.
4. **Submit:** Use the `create-pull-request` safe output to propose the fix. 
   - Ensure the PR description mentions the CodeQL Rule ID.
---
name: "CodeQL Security Fixer"
on:
  code_scanning_alert:
    types: [created]

permissions:
  contents: read
  pull-requests: write

safe-outputs:
  create-pull-request:
    draft: true
    branch-prefix: "fix/codeql-"
    labels: ["security", "autofix"]
---

# CodeQL Security Fixer
You are a security engineer. A new CodeQL alert has been detected in this repository.

## Instructions
1. **Fetch Alert Details:** Use the `${{ github.event.alert.number }}` to get the alert details.
2. **Analyze Code:** Locate the file `${{ github.event.alert.most_recent_instance.location.path }}` and understand the vulnerability.
3. **Apply Fix:** Rewrite the code to resolve the security issue without changing the intended logic.
4. **Verify:** Check if there are any obvious syntax errors in your change.
5. **Submit PR:** Call the `create-pull-request` tool to submit your fix. 
   - Body: "Fixes CodeQL Alert #${{ github.event.alert.number }}: ${{ github.event.alert.rule.description }}"
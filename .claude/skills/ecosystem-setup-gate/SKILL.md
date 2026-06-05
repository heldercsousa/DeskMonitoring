---
description: "Gate before running setup_update.ps1: verify health and confirm user will run as Administrator"
---

# Ecosystem Setup Gate

Before directing Helder to run `setup_update.ps1`, complete this gate checklist.

## Gate Steps

1. **Run `/project:health`** - all checks must PASS before proceeding. If any check fails:
   - Read the relevant log file first (RULE 2)
   - Diagnose the root cause
   - Fix the issue
   - Re-run `/project:health` until all PASS

2. **Confirm the user will run as Administrator**:
   - `setup_update.ps1` requires `#Requires -RunAsAdministrator`
   - The Claude Code Bash tool runs as regular user `helde`, NOT as Administrator
   - Running without elevation will fail silently on ACL, scheduled task, and NSSM steps
   - Always end with: "Run `setup_update.ps1` as Administrator to apply."

3. **Confirm no production data risk**:
   - If ecosystem is currently running and the change affects active scripts (cloud_sync.ps1, wdog.ps1, auditor.ps1), document the current state first
   - `setup_update.ps1` stops the ecosystem, applies config, then restarts - this is a brief service interruption

## What NOT to do
- Do not suggest running individual scripts (wdog.ps1, start_ecosystem.ps1, install_service.ps1) directly
- `setup_update.ps1` is the single entry point - calling individual scripts skips steps and creates inconsistent state
- Do not run `setup_update.ps1` from the Bash tool without admin elevation - it will fail

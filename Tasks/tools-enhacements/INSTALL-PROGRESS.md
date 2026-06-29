# Install progress tracker - Win11 hardening backlog (T075-T085)

> Single source of truth for the sequential install orchestration. The
> orchestrator owns this file; each subagent owns its task's Backlog row and
> `T###-steps-status.md`. Resume by re-running the orchestrator prompt: rows that
> are Done / Blocked-Hardware / Pending-Manual / Pending-Decision are skipped;
> Pending / In Progress / Blocked-Admin are re-dispatched.
>
> Status words: Pending | In Progress | Done | Blocked-Admin | Blocked-Hardware
> | Pending-Manual | Pending-Decision

| Order | Task | Status | LastUpdate | Next action / blocker |
|-------|------|--------|------------|-----------------------|
| 1 | T078 | Pending | - | Firewall-tamper event IDs into auditor.ps1 + auditpol via setup_update.ps1 |
| 2 | T080 | Pending | - | Add VT/Shodan/CVE MCP servers to .claude/settings.json (needs API keys) |
| 3 | T081 | Pending | - | Python oletools+vt-py triage tool |
| 4 | T076 | Pending | - | Install Sysmon (admin) + stage config + setup_update.ps1 step |
| 5 | T075 | Pending | - | Sysmon Event 1 correlation in auditor.ps1 (depends on T076) |
| 6 | T079 | Pending | - | Autoruns baseline + daily diff |
| 7 | T077 | Pending | - | WEF off-box forwarding (blocked on collector; interim git push) |
| 8 | T083 | Pending | - | Pre-author N100 sensor tc script + EVE parser (deploy on hardware) |
| 9 | T084 | Pending | - | Pre-author Wazuh+Velociraptor notes (deploy on rebuild) |
| 10 | T085 | Pending | - | Managed-EDR decision doc (Huntress vs Defender for Business) |
| 11 | T082 | Pending | - | Offline rescue-scan checklist (manual/physical) |

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
| 1 | T078 | Blocked-Admin | 2026-06-29 | Run setup_update.ps1 as Admin to enable MPSSVC firewall-audit subcategory + restart FolderSyncAuditor; then dummy-rule test |
| 2 | T080 | Pending-Manual | 2026-06-29 | Helder: get free VT+Shodan keys, setx them, clone+pip cve-mcp-server, flip disabled=false, smoke-test |
| 3 | T081 | Done | 2026-06-29 | Tools/file-triage/triage.py built+tested; optional: set VIRUSTOTAL_API_KEY for --vt live lookups |
| 4 | T076 | Blocked-Admin | 2026-06-29 | Run setup_update.ps1 as Admin for live Sysmon install; confirm Event 1/3/22 in Sysmon/Operational |
| 5 | T075 | Blocked-Admin | 2026-06-29 | Code authored; run setup_update.ps1 as Admin (Sysmon+reg auditing Step 16a5), then powercfg-change acceptance test |
| 6 | T079 | Blocked-Admin | 2026-06-29 | Run setup_update.ps1 as Admin (Step 22: download autorunsc64, register task, capture baseline.csv), then commit baseline.csv |
| 7 | T077 | Blocked-Hardware | 2026-06-29 | Interim hourly log git-push done (run setup_update.ps1 as Admin). Full WEF needs a collector host (N100/T083); follow Config/wef/README |
| 8 | T083 | Blocked-Hardware | 2026-06-29 | tc-mirror init + EVE parser pre-authored & tested; deploy needs Intel N100 + AX3000T port-mirror wiring (see Tools/netsensor/README) |
| 9 | T084 | Blocked-Hardware | 2026-06-29 | Wazuh/Velociraptor kit pre-authored (Tools/wazuh-velociraptor/); deploy on clean rebuild + N100 (T083) per README |
| 10 | T085 | Pending | - | Managed-EDR decision doc (Huntress vs Defender for Business) |
| 11 | T082 | Pending | - | Offline rescue-scan checklist (manual/physical) |

# T075 - Sysmon Event 1 correlation in auditor.ps1 - steps status

**Status:** Done (acceptance test PASSED 2026-06-29; bug fix for PowerSchemes pattern also committed)
**Last updated:** 2026-06-29

## Checklist
- [x] Read plan + CLAUDE.md rules
- [x] Added process-correlation helpers to `auditor.ps1`: `Get-EvtData`, `Get-CorrelatedProcesses` (Sysmon Event 1 preferred, fallback Security 4688), `Test-WhitelistedProc`
- [x] Added `$script:LastRegEventTime` watermark + `$script:GuardedRegPatterns` (USB Selective Suspend / sleep subgroups, PowerSchemes catch-all, Run keys)
- [x] Added registry-tamper watcher block in `Check-SystemEvents`: polls Security 4657/4663 on guarded keys, correlates +/-5s, raises `[ALERT] [REG-TAMPER]` (or `[REG-WRITE]` INFO when only own scripts / no telemetry), writes Evidence file + send_alert, watermarked
- [x] ParseFile auditor.ps1 = 0 errors; committed immediately (guarded file)
- [x] Authored `enable_registry_auditing.ps1` (Registry audit subcategory {0CCE921E-...} + SACL on PowerSchemes + HKLM/HKCU Run keys)
- [x] Wired into `setup_update.ps1` Step 16a5 + summary line; ParseFile = 0 errors; committed (guarded file)
- [x] RULE 1: ECOSYSTEM_REPORT.md §5 auditor row updated + new enable_registry_auditing.ps1 row; §15 auditor.ps1 full block re-synced + new enable_registry_auditing.ps1 block + descriptor updated
- [x] Backlog row updated
- [x] LIVE TEST - PASSED 2026-06-29

## ACCEPTANCE TEST RESULT (2026-06-29 19:48:55)
- Set USB Selective Suspend=1 via powercfg; auditor fired [ALERT] [REG-TAMPER] on
  `\REGISTRY\MACHINE\SYSTEM\ControlSet001\Control\Power\User\PowerSchemes` at 19:48:55
  naming bash.exe (parent: claude.exe) as correlated process (via Sysmon-1).
- Revert (USB=0) fired [REG-WRITE] INFO (no processes in +/-5s window) — correct.
- T078 also PASSED same session: dummy BLOCK rule -> [ALERT][FIREWALL-TAMPER] RULE-ADDED
  + RULE-DELETED both detected.
- Bug found+fixed: GuardedRegPatterns had trailing '\' on PowerSchemes pattern but
  ObjectName in 4663 event has no trailing '\'. Fixed pattern in auditor.ps1 + ECOSYSTEM_REPORT.

## Dependency note
T075 depends on T076 (Sysmon) which is Blocked-Admin (not live-installed). Until Sysmon is live, the correlation falls back to Security 4688 (already enabled, Step 16a2). The auditor logs `[REG-WRITE] ... no process-creation telemetry in window` if neither source has data. No live test was run by Claude (requires Sysmon events + Admin).

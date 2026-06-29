# T075 - Sysmon Event 1 correlation in auditor.ps1 - steps status

**Status:** Blocked-Admin (code authored + committed; live test needs Sysmon T076 + Admin setup run)
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
- [ ] LIVE TEST (Blocked-Admin) - see below

## BLOCKER - ACTION FOR HELDER
1. **Run `setup_update.ps1` as Administrator** to: (a) install Sysmon (Step 21, T076) and (b) enable registry auditing + SACLs (new Step 16a5). Both require elevation; the Claude Bash tool runs as non-admin.
2. After that, run the acceptance test (Admin shell): deliberately change USB Selective Suspend, e.g.
   `powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1` then `powercfg /setactive SCHEME_CURRENT`
   Then check `C:\Sync\Logs\security\security_audit_YYYY-MM-DD.log` for a `[REG-TAMPER]` (or `[REG-WRITE]`) line naming the correlated process + parent. (Re-run the power heal afterwards to restore USB=0.)

## Dependency note
T075 depends on T076 (Sysmon) which is Blocked-Admin (not live-installed). Until Sysmon is live, the correlation falls back to Security 4688 (already enabled, Step 16a2). The auditor logs `[REG-WRITE] ... no process-creation telemetry in window` if neither source has data. No live test was run by Claude (requires Sysmon events + Admin).

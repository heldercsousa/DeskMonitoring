# T075 — Sysmon Event 1 correlation in auditor.ps1

**Goal:** When a registry write audit event (4657/4663) fires on a guarded key — primarily the USB Selective Suspend AC value and the FolderSync config/task keys — capture the *true calling process*. Registry writes via the Power service surface as `svchost.exe`; the real culprit is only visible by correlating against process-creation telemetry in the same time window.

**Source:** `Protecao_Win11.md` Layer 2 (on-host telemetry, trust caveat) + existing project hypothesis (USB Selective Suspend re-enabled between corrections by an unknown resident process; see T070).

## Depends on
- T076 (Sysmon installed) — Sysmon Event 1 gives full command line + parent + hashes, richer than 4688. If T076 not yet done, fall back to Security Event 4688 (already enabled per T014).

## Steps
1. In `auditor.ps1`, after a 4657/4663 hit on a guarded key, query the correlation window `eventTime ± 5s` for:
   - Sysmon `Microsoft-Windows-Sysmon/Operational` Event ID 1 (preferred), else Security 4688.
2. Extract: Image, CommandLine, ParentImage, User, ProcessId.
3. Filter out known-good ecosystem processes (powershell running our own scripts, svchost as RPC proxy) and raise `[ALERT] [REG-TAMPER]` with the surviving candidate(s).
4. Log to `Logs\security\security_audit_YYYY-MM-DD.log`; write an Evidence file if a non-whitelisted process is found.

## Acceptance
- A deliberate `powercfg` change to USB Selective Suspend produces a log line naming `powercfg.exe`/`svchost.exe` AND the correlated parent.
- Parses clean (ParseFile 0 errors).

## RULE 1 follow-up
- ECOSYSTEM_REPORT.md §5 + §15 (auditor.ps1).
- CLAUDE.md if new log prefixes/paths.
- setup_update.ps1 if a new audit subcategory must be enabled at install.

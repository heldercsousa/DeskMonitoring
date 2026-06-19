# Evidence: Two defensive scheduled tasks disabled — CONFIRMED tampering

**Date detected:** 2026-06-18 ~19:40 (during a process/startup audit of the laptop)
**Severity:** HIGH — defensive monitoring silenced by a non-interactive resident actor
**Status:** Remediated (tasks re-enabled, auditing enabled, auto-heal extended)
**Supersedes/extends:** `2026-06-18_dailycheck-task-disabled.md`

## What happened

Two FolderSync defensive scheduled tasks were found Disabled within a ~2-minute window
on the evening of 2026-06-18:

| Task | Evidence of disable | Time |
|---|---|---|
| `FolderSync-DailyCheck` | Task XML `C:\Windows\System32\Tasks\FolderSync-DailyCheck` modified | 19:18:32 |
| `FolderSync-CloudBackup` | config_guard.ps1 logged TASK-TAMPER + auto-restored | 19:20:20 |

Both tasks had run normally earlier that day (DailyCheck at 09:00). CloudBackup was
auto-restored by config_guard's existing single-task guard; DailyCheck was NOT guarded
and stayed Disabled until the manual audit found it.

config_guard.ps1 log excerpt:
```
2026-06-18 19:20:20  TASK-TAMPER  FolderSync-CloudBackup disabled - attacker attempt detected, re-enabling
2026-06-18 19:20:20  TASK-AUTO-RESTORED  FolderSync-CloudBackup re-enabled
```

## Attribution — NOT user-initiated (confirmed)

The user explicitly confirmed they were **not toggling any tasks or services**; they were
only taking screenshots of Task Manager / msconfig to record current settings for review.
The disables therefore were not user action.

### Process hunt (Security event 4688) — no interactive actor

Process-creation auditing (event 4688) for the window **19:13:00 - 19:21:30** shows
**no creation** of any of: `schtasks.exe`, `powershell.exe`, `pwsh.exe`, `cmd.exe`,
`wscript/cscript`, `mmc.exe` (Task Scheduler UI), `taskmgr.exe`, `wmic.exe`, `reg.exe`.

Yet two tasks were disabled in exactly that window. The absence of any spawned helper
process means the disable was performed **in-process by an already-running (resident)
process** calling the task API directly — it did not shell out to schtasks or use the
Task Scheduler MMC.

**This corroborates the standing threat-model hypothesis** (CLAUDE.md Live Threat Digest):
"the tampering agent is a process already running on this machine (scheduled task, service,
or WMI subscription), not a remote actor." A resident agent disabling defensive tasks via
API fits that profile precisely.

### No audit trail existed at the time

Scheduled-task change auditing (events 4698-4702) was **disabled** before this incident.
The first 4700/4701/4702 events in the Security log are from 20:55+ — i.e. the controlled
test and remediation performed during this session. The 19:18-19:20 disable produced no
4701, which is why it was unattributable. **This detection gap is now closed (see below).**

## Disabled startup entries reviewed (the "weird disabled initializations")

Enumerated `StartupApproved` keys. All disabled startup entries are benign user apps
toggled off long ago — none are ecosystem/defensive components, none toggled in the
19:18 window:

| Entry | State | Toggled |
|---|---|---|
| Discord | DISABLED | 2025-06-16 |
| Battle.net | DISABLED | 2025-06-16 |
| com.squirrel.Teams.Teams | DISABLED | 2025-11-09 |
| com.todesktop.25020447d4kq915 | DISABLED | 2025-11-09 |
| Docker Desktop | DISABLED | (old) |
| SolutiPlugin.lnk | DISABLED | 2026-06-11 |

All ecosystem autostart entries (`Yawcam`, `YawcamMonitor`, `YawcamCam2Relay`,
`FolderSyncRealTime`) are **ENABLED**. The camera/sync boot chain is intact.

## Remediation applied (this session)

1. **Tasks re-enabled** — `FolderSync-DailyCheck` and `FolderSync-CloudBackup` both Ready/Enabled.
2. **Task-change auditing enabled** — `auditpol /set /subcategory:"{0CCE9227-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable`
   ("Other Object Access Events", locale-independent GUID). Verified live: a controlled
   disable produced Security event **4701** "Uma tarefa agendada foi desabilitada".
   Persisted in `setup_update.ps1` Step 16a3 (survives reinstall).
3. **config_guard.ps1 auto-heal extended** — the 30s keep-alive loop now re-enables ANY of
   the six FolderSync defensive tasks if found Disabled (`$GuardedTasks`), logging
   TASK-TAMPER / TASK-AUTO-RESTORED. Verified live: a test disable of DailyCheck was
   auto-healed within ~40s.
4. **Docs synced** — ECOSYSTEM_REPORT.md (Sec 5 + 15), CLAUDE.md (task table + Live Threat
   Digest), THREAT_MODEL.md (Attack Vector History + Detection Matrix).

## Open follow-ups

- **Identify the resident actor.** Now that 4698-4702 auditing is on, the next disable will
  log a 4701 containing the Subject (account) — cross-reference with the running process set.
  Combine with the still-open SACL/event-4663 analysis on `Config\cloud_sync.ps1` to pin the
  exact process (same suspected agent).
- Consider tightening config_guard task-check cadence below 60s if instant prevention matters.
- Consider write-protecting task definitions (`C:\Windows\System32\Tasks\FolderSync-*`) so a
  disable requires an ACL bypass that itself audits.

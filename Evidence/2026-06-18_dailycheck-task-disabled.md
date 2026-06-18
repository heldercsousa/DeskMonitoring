# Evidence: FolderSync-DailyCheck scheduled task disabled

**Date detected:** 2026-06-18 ~19:40 (during process/startup audit of laptop)
**Severity:** Medium — defensive monitoring task silenced
**Status:** Remediated (re-enabled)

## What was found

The scheduled task `FolderSync-DailyCheck` (runs `C:\Sync\Config\DailySecurityCheck.ps1`,
daily at 09:00) was found in state **Disabled** (`Settings.Enabled = False`).

Timeline:
- Task **ran normally today at 09:00:01** (LastRunTime).
- Task definition file `C:\WINDOWS\System32\Tasks\FolderSync-DailyCheck` was
  **modified at 19:18:32** today — i.e. the task was disabled this evening,
  ~9.5 hours after its last successful run.
- The disable happened during the same window the user was capturing Task Manager /
  msconfig screenshots for review (screenshots 19:20–19:38).

This matches the threat model's documented "silences monitoring" attacker behavior:
a defensive scan being switched off after a clean run.

## Attribution

**Unresolved.** Could not attribute the disable to a process or user:
- `Microsoft-Windows-TaskScheduler/Operational` log returned **zero events** for this task.
- Security log events 4699/4701/4702 (task delete/update) logged **nothing**.

This is itself a **detection gap**: task-definition changes are not being audited, so a
disable of a defensive task leaves no attributable trace. Relates to the open
SACL / Event 4663 work tracked in THREAT_MODEL.md.

It is possible the user disabled it manually while investigating; pending user confirmation.
If not user-initiated, treat as a live tampering event.

### Corroborating event (raises suspicion of tampering)

config_guard.ps1's log shows that at **2026-06-18 19:20:20** - within ~2 minutes of the
DailyCheck XML modification (19:18:32) - `FolderSync-CloudBackup` was **also** found Disabled
and auto-restored by the guard:

```
2026-06-18 19:20:20  TASK-TAMPER  FolderSync-CloudBackup disabled - attacker attempt detected, re-enabling
2026-06-18 19:20:20  TASK-AUTO-RESTORED  FolderSync-CloudBackup re-enabled
```

So **two** defensive scheduled tasks were disabled in the same short window. CloudBackup was
caught and reverted automatically because it was the only task in the old guard list;
DailyCheck was NOT guarded, so its disable persisted until this manual audit. Two
near-simultaneous disables of defensive tasks is more consistent with a tampering action
than incidental user toggling - flagged for the user's confirmation.

## Remediation applied

- `Enable-ScheduledTask -TaskName 'FolderSync-DailyCheck'` → State=Ready, Enabled=True (confirmed).
- **Task-change auditing enabled**: `auditpol /set /subcategory:"{0CCE9227-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable`
  ("Other Object Access Events", language-independent GUID). Confirmed "Êxito e Falha".
  Future task disable/delete now logged as events 4701/4699/4702. Added to
  `setup_update.ps1` Step 16a3 so it survives a reinstall.
- **config_guard.ps1 extended**: the 30s keep-alive loop now iterates `$GuardedTasks`
  (all six FolderSync tasks) and re-enables any found Disabled, logging
  `TASK-TAMPER` / `TASK-AUTO-RESTORED` (previously only FolderSync-CloudBackup was guarded).
  ConfigGuard task restarted to load the new code (START logged 2026-06-18 20:52:44).
- Docs synced: ECOSYSTEM_REPORT.md Section 5 + 15, CLAUDE.md (task table + Live Threat
  Digest), THREAT_MODEL.md (Attack Vector History + Detection Matrix).

## Status: all follow-ups implemented

Both originally-recommended follow-ups (task-change auditing; config_guard assertion +
auto-heal of all defensive tasks) are now in place.

## Other items reviewed in same sweep (no action needed)

- WMI persistence: clean (only stock SCM Event Log Consumer).
- Run keys (HKCU/HKLM/WOW64/RunOnce): all entries accounted for, no rogue autostart.
- Non-Microsoft scheduled tasks: all stock OEM (Acer/NVIDIA/Google/Brave/Mozilla/Zoom/Npcap)
  plus the six FolderSync tasks.
- `CopyFileTo.WS` service (c:\CopyFilesToWS): confirmed by user as their own software (benign).
- "Claude" service = Anthropic CoworkVMService (signed WindowsApps). Benign.
- Fing.Agent / Npcap: user network tooling.

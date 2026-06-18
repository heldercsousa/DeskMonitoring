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

## Remediation applied

- `Enable-ScheduledTask -TaskName 'FolderSync-DailyCheck'` → State=Ready, Enabled=True (confirmed).

## Follow-up recommended

- Enable auditing of scheduled-task object changes (4699/4701/4702) so future
  enable/disable events are attributable.
- Consider having `config_guard.ps1` / `check_status.ps1` assert that all FolderSync
  defensive tasks are Enabled, and alert + auto-heal if any is found Disabled.

## Other items reviewed in same sweep (no action needed)

- WMI persistence: clean (only stock SCM Event Log Consumer).
- Run keys (HKCU/HKLM/WOW64/RunOnce): all entries accounted for, no rogue autostart.
- Non-Microsoft scheduled tasks: all stock OEM (Acer/NVIDIA/Google/Brave/Mozilla/Zoom/Npcap)
  plus the six FolderSync tasks.
- `CopyFileTo.WS` service (c:\CopyFilesToWS): confirmed by user as their own software (benign).
- "Claude" service = Anthropic CoworkVMService (signed WindowsApps). Benign.
- Fing.Agent / Npcap: user network tooling.

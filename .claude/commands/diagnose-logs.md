---
name: diagnose-logs
description: "Token-efficient log scan for today's (or yesterday's) ecosystem logs. Reads only date-stamped log files, greps for error/warning patterns, then escalates to deep investigation only if no cause is found. Use whenever something seems broken but you don't want to load all logs into context."
---

# /project:diagnose-logs — Smart Log Diagnosis

`Logs/` is excluded from `.claudeignore` so logs are never auto-loaded into context.
This command reads logs on demand using the `Grep` and `Read` tools
directly on specific dated files. Only matching lines are loaded — not full files.

---

## Step 1 — Establish the date suffix

Today's date (injected at runtime by CLAUDE.md `currentDate`):

```
TODAY  = YYYY-MM-DD   (e.g. 2026-03-07)
YESTERDAY = YYYY-MM-DD one day prior
```

Log files use this suffix pattern (current layout — subdirectories per component):
```
C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log
C:\Sync\Logs\audit\file_audit_YYYY-MM-DD.log
C:\Sync\Logs\mirror_YYYY-MM-DD.log                     ← no subdir (unlike the others)
C:\Sync\Logs\security\security_audit_YYYY-MM-DD.log
C:\Sync\Logs\security\security_check_YYYY-MM-DD.log
C:\Sync\Logs\security\autoruns_YYYY-MM-DD.log
C:\Sync\Logs\security\config_guard_YYYY-MM-DD.log
C:\Sync\Logs\ecosystem\ecosystem_YYYY-MM-DD.log
C:\Sync\Logs\power_check\power_check_YYYY-MM-DD.log
C:\Sync\Logs\services\watchdog.log          ← no date suffix, single rolling file
```

---

## Step 2 — Grep today's logs for error patterns (token-minimal)

Use the `Grep` tool with `output_mode: "content"` on each file individually.
Do NOT read full files. Only lines matching the error pattern are returned.

**Error pattern to grep:**
```
SYNC-FAIL|FIREWALL|ERROR|Error|error|WARN|ALERT|connectex|socket access forbidden|failed|Failed|FAIL|exception|Exception|unauthorized|Unauthorized|denied|Denied|blocked|Blocked
```

**Files to grep (today's suffix):**

1. `C:\Sync\Logs\cloud_sync\cloud_sync_TODAY.log`
2. `C:\Sync\Logs\audit\file_audit_TODAY.log`
3. `C:\Sync\Logs\mirror_TODAY.log`
4. `C:\Sync\Logs\security\security_audit_TODAY.log`
5. `C:\Sync\Logs\security\security_check_TODAY.log`
6. `C:\Sync\Logs\security\autoruns_TODAY.log`
7. `C:\Sync\Logs\security\config_guard_TODAY.log`
8. `C:\Sync\Logs\ecosystem\ecosystem_TODAY.log`
9. `C:\Sync\Logs\power_check\power_check_TODAY.log`
10. `C:\Sync\Logs\services\watchdog.log`

Grep all 10 in parallel. For each file:
- If the file does not exist → note "(no file for today)"
- If grep returns matches → record them, labeled by source file
- If grep returns nothing → note "(no errors in [file])"

If `security_audit` returns a very large number of `[ALERT]` lines, don't read them all —
grep just the alert-type tag first (pattern `\[ALERT\] \[([A-Z-]+)\]`, `-o: true`) to get a
count/breakdown by type, then sample a few lines per type before applying Step 3.

---

## Step 3 — Evaluate grep results

**Case A — Errors found in today's logs:**

Report a compact summary:
```
ERRORS FOUND in today's logs (TODAY):
  [filename]: [matching line 1]
              [matching line 2]
              ...
```

Map each error to a known cause:

| Error pattern | Likely cause | Next action |
|---|---|---|
| `FIREWALL-PREFLIGHT WARNING` | Attacker re-added block rules before sync ran | Run `C:\Sync\fix_b2_firewall.bat` as Administrator |
| `FIREWALL-DETECT` | Sync blocked mid-run by firewall | Check if FIREWALL-HEAL follows it — if not, re-run bat |
| `FIREWALL-HEAL  Retry SUCCESS` | Self-healed — sync recovered automatically | No action needed; note the attack recurrence |
| `FIREWALL-HEAL  Retry FAILED` | Self-heal tried but sync still broken | Manual firewall investigation required |
| `SYNC-FAIL` | Rclone failed (non-firewall) | Read surrounding lines in cloud_sync log for exact error |
| `connectex\|socket access forbidden` | Direct firewall block evidence | Run `fix_b2_firewall.bat` as Administrator |
| `FAIL` in mirror log | Robocopy error | Check if source folder accessible; check mirror ACLs |
| `exception\|Error` in watchdog | Watchdog crashed | Restart service: `Start-Service FolderSyncWatchdog` |
| `FIREWALL-TAMPER` where `rule=` names a Microsoft Store package (e.g. `Microsoft.DesktopAppInstaller`, `Microsoft.BingWeather`, `Microsoft.WindowsCalculator`, `Microsoft.ZuneMusic`/`ZuneVideo`, `Microsoft.WindowsCamera`, `Microsoft.WindowsSoundRecorder` — versioned, old+new pairs) | Benign — Store app auto-update deleting/re-adding its own firewall rule on a version bump | No action; note as noise unless a non-Store/unversioned rule name appears |
| `FIREWALL-TAMPER` for any other rule name | Unexplained firewall rule deletion | Treat as Step 5 candidate — identify actor via the 4948 event's account and any correlated Sysmon process |
| `REG-TAMPER` on `...\Control\Power\User\PowerSchemes` correlated with `svchost.exe`/`powercfg.exe`/`wsqmcons.exe` | Benign — normal Windows power-plan telemetry write | No action |
| `REG-TAMPER` on any other guarded key, or correlated with an unrecognized process | Possible real tampering | Escalate — open the evidence file named on the following `[FORENSIC]` line |
| `AUTORUN-ALERT  N persistence delta(s)` | Autoruns baseline diff found N changes | Read the alert detail; if deltas trace to known app updates, no action — else escalate |
| `RunKeyUnknown` | New/changed HKCU Run key not in baseline | Check if it matches a known legitimate app (e.g. browser background-update autostart); else escalate |
| `ECOSYSTEM-START WARN Task FolderSync-Watchdog not found` | Stale check in `start_ecosystem.ps1` — current architecture runs the watchdog as NSSM service `FolderSyncWatchdog`, not a scheduled task named `FolderSync-Watchdog` | Not a real failure; confirm via `Get-Service FolderSyncWatchdog`. Flag as a script bug to fix separately, don't chase as an incident |
| `ECOSYSTEM-START WARN Yawcam did not start` / `WARN CAM-2 relay did not start` | Camera component failed during ecosystem start | Live-check `Get-Process Yawcam` / relay process; if absent, camera recording is currently down — escalate to user immediately, do not treat as routine noise |
| `GIT-COMMIT-LOGS SKIP  git index.lock exists` (recurring across multiple hourly runs) | Stale `.git\index.lock` blocking the hourly log auto-commit | Live-check `Test-Path C:\Sync\.git\index.lock`; if true and no git process is actually running, this is the known lock-removal issue documented in CLAUDE.md's ACL Reference section |

For each matched error, apply the listed action or escalate to Step 5.

**Case B — No errors in today's logs:**

If the day just started (before ~06:00) or if it is within the first hour after midnight:
- The ecosystem may not have run yet today
- Proceed to Step 4 (check yesterday's logs)

Otherwise (daytime, logs exist but no errors):
- Report: "No errors found in today's logs. Ecosystem appears clean for TODAY."
- If the user reported a specific symptom that doesn't match logs → proceed to Step 5.

---

## Step 4 — If no today-errors found: grep yesterday's logs

Repeat Step 2 with YESTERDAY's suffix on the same 10 file patterns.

- If errors found in yesterday's logs → report and map them per Step 3 table
- If no errors in yesterday's logs either → proceed to Step 5

---

## Step 5 — Deep investigation (no token-saving, solve at any cost)

Triggered when: logs showed no relevant error AND the reported symptom is real.

Work through each subsystem that could be causing the symptom:

### 5a — FolderSync pipeline

Read each script involved in the failing layer:

```
cloud_sync_helderTest.ps1 → rclone + firewall self-heal logic
wdog.ps1                  → watchdog loop
auditor.ps1                → security monitor
start_ecosystem.ps1        → ecosystem startup sequence (tasks/services/Yawcam/CAM-2)
register_tasks.ps1         → scheduled task registration
```

Check:
- Does the script have correct paths? (`C:\Tools\Rclone\rclone.exe`, etc.)
- Does the firewall rule list (`$MaliciousFirewallRules`) match known attack rules?
- Is the rclone remote name `cloudsync:helder-sync-mirror`?
- Does the script write to the correct log path?

### 5b — System state

Run live checks (only if logs were insufficient):

```powershell
# Task state
Get-ScheduledTask 'FolderSync-CloudBackup' | Select TaskName, State, LastRunTime, LastTaskResult

# Service state
Get-Service FolderSyncWatchdog, FolderSyncAuditor | Select Name, Status, StartType

# Firewall rules (all outbound blocks)
Get-NetFirewallRule -Direction Outbound -Action Block -Enabled True | Select DisplayName, Description
```

### 5c — Firewall deep scan

If the above shows suspicious outbound BLOCK rules:

```powershell
Get-NetFirewallRule -Direction Outbound -Action Block -Enabled True |
    ForEach-Object {
        $addr = ($_ | Get-NetFirewallAddressFilter).RemoteAddress
        [PSCustomObject]@{ Name=$_.DisplayName; RemoteAddress=$addr }
    } | Format-Table -AutoSize
```

Any rule with a remote IP in Backblaze's ranges (`104.153.*`, `149.137.*`, `180.235.*`) is malicious.

### 5d — Escalation

If the cause cannot be determined after Steps 5a–5c:
1. Append to `C:\Sync\Config\known_issues.md` with exact symptoms, log excerpts, and commands tried
2. Note in `C:\Sync\CLAUDE.md` under `## Known Issues (Pending Manual Review)`
3. Report to user: exact steps taken, exact evidence found, what remains unknown

---

## Log reference table

| Log file | Written by | Key events to look for |
|---|---|---|
| `cloud_sync\cloud_sync_YYYY-MM-DD.log` | `cloud_sync_helderTest.ps1` (Task Scheduler) | `SYNC-START`, `SYNC-OK`, `SYNC-FAIL`, `FIREWALL-PREFLIGHT`, `FIREWALL-DETECT`, `FIREWALL-HEAL` |
| `audit\file_audit_YYYY-MM-DD.log` | `auditor.ps1` (FolderSyncAuditor service) | File deletions, remote logins, startup gap forensics |
| `mirror_YYYY-MM-DD.log` (root, no subdir) | `run_mirror.bat` (RealTimeSync trigger) | Robocopy copy/fail lines |
| `security\security_audit_YYYY-MM-DD.log` | `DailySecurityCheck.ps1` / `auditor.ps1` | `[ALERT] [REG-TAMPER]`, `[ALERT] [FIREWALL-TAMPER]`, `[FORENSIC]` evidence pointers, `[TASK-TAMPER]` |
| `security\security_check_YYYY-MM-DD.log` | `DailySecurityCheck.ps1` | Suspicious processes, network anomalies, `RunKeyUnknown` registry-run alerts |
| `security\autoruns_YYYY-MM-DD.log` | `check_autoruns.ps1` (task `FolderSync-AutoRunsCheck`) | `AUTORUN-ALERT  N persistence delta(s)`, `AUTORUN-ALERT-SENT` |
| `security\config_guard_YYYY-MM-DD.log` | `config_guard.ps1` (task `FolderSync-ConfigGuard`) | Reverted edits to guarded scripts, re-enabled/restored tasks |
| `ecosystem\ecosystem_YYYY-MM-DD.log` | `start_ecosystem.ps1` / `stop_ecosystem.ps1` | `ECOSYSTEM-START`/`ECOSYSTEM-STOP` lines, `WARN` on any component that failed to start, `GIT-COMMIT-LOGS SKIP` (from `auto_commit_logs.ps1`) |
| `power_check\power_check_YYYY-MM-DD.log` | `check_power_motion.ps1` (task `FolderSync-PowerCheck`) | Sleep/power-setting auto-heal actions |
| `services\watchdog.log` | `wdog.ps1` (FolderSyncWatchdog service) | Restart events, task re-enable events, errors |

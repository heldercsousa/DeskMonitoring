---
name: diagnose-logs
description: "Token-efficient log scan for today's (or yesterday's) ecosystem logs. Reads only date-stamped log files, greps for error/warning patterns, then escalates to deep investigation only if no cause is found. Use whenever something seems broken but you don't want to load all logs into context."
---

# /project:diagnose-logs — Smart Log Diagnosis

`Logs/` is excluded from `.claudeignore` to save tokens in normal sessions.
This command overrides that exclusion by using the `Grep` and `Read` tools
directly on specific dated files. Only matching lines are loaded — not full files.

---

## Step 1 — Establish the date suffix

Today's date (injected at runtime by CLAUDE.md `currentDate`):

```
TODAY  = YYYY-MM-DD   (e.g. 2026-03-07)
YESTERDAY = YYYY-MM-DD one day prior
```

Log files use this suffix pattern:
```
C:\Sync\Logs\cloud_sync_YYYY-MM-DD.log
C:\Sync\Logs\file_audit_YYYY-MM-DD.log
C:\Sync\Logs\mirror_YYYY-MM-DD.log
C:\Sync\Logs\security_audit_YYYY-MM-DD.log
C:\Sync\Logs\watchdog.log          ← no date suffix, single rolling file
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

1. `C:\Sync\Logs\cloud_sync_TODAY.log`
2. `C:\Sync\Logs\file_audit_TODAY.log`
3. `C:\Sync\Logs\mirror_TODAY.log`
4. `C:\Sync\Logs\security_audit_TODAY.log`
5. `C:\Sync\Logs\watchdog.log`

Grep all 5 in parallel. For each file:
- If the file does not exist → note "(no file for today)"
- If grep returns matches → record them, labeled by source file
- If grep returns nothing → note "(no errors in [file])"

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
| `WARN\|ALERT` in security log | Auditor detected anomaly | Read security_audit log context (±5 lines) |
| `exception\|Error` in watchdog | Watchdog crashed | Restart service: `Start-Service FolderSyncWatchdog` |

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

Repeat Step 2 with YESTERDAY's suffix on the same 5 file patterns.

- If errors found in yesterday's logs → report and map them per Step 3 table
- If no errors in yesterday's logs either → proceed to Step 5

---

## Step 5 — Deep investigation (no token-saving, solve at any cost)

Triggered when: logs showed no relevant error AND the reported symptom is real.

Work through each subsystem that could be causing the symptom:

### 5a — FolderSync pipeline

Read each script involved in the failing layer:

```
cloud_sync.ps1     → rclone + firewall self-heal logic
wdog.ps1           → watchdog loop
auditor.ps1        → security monitor
register_tasks.ps1 → scheduled task registration
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
| `cloud_sync_YYYY-MM-DD.log` | `cloud_sync.ps1` (Task Scheduler) | `SYNC-START`, `SYNC-OK`, `SYNC-FAIL`, `FIREWALL-PREFLIGHT`, `FIREWALL-DETECT`, `FIREWALL-HEAL` |
| `file_audit_YYYY-MM-DD.log` | `auditor.ps1` (FolderSyncAuditor service) | File deletions, remote logins, startup gap forensics |
| `mirror_YYYY-MM-DD.log` | `run_mirror.bat` (RealTimeSync trigger) | Robocopy copy/fail lines |
| `security_audit_YYYY-MM-DD.log` | `DailySecurityCheck.ps1` | Suspicious processes, network anomalies, registry access |
| `watchdog.log` | `wdog.ps1` (FolderSyncWatchdog service) | Restart events, task re-enable events, errors |

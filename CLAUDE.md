<!-- TASK GATE — READ THIS FIRST, EVERY SESSION — APPLIES TO ALL MACHINES -->
## NON-NEGOTIABLE TASK RULES

### 6-Phase Change Lifecycle (applies to ANY Config/ change)

**Phase 0 — Load context**
Before anything else: invoke relevant skills, load project commands, review CLAUDE.md rules.

**Phase 1 — Plan**
EnterPlanMode. Plan must list all RULE 1 follow-up steps explicitly.

**Phase 2 — Apply**
Execute changes. If a step cannot be completed as planned, return to Phase 1.

**Phase 3 — Review compliance**
Re-read every modified file. Confirm content matches intent, no truncation, no encoding anomalies (em dashes etc.).
Any non-compliant point → fix → back to Phase 3.

**Phase 4 — Test**
a) Syntax parse every modified .ps1 via ParseFile (0 errors required):
```powershell
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\SCRIPT.ps1',[ref]$t,[ref]$e);$e.Count
```
b) Execution test: run `setup_update.ps1` as Administrator — all steps print OK with no errors.
Exception: if execution would override production state, document rollback first.
c) If production is running: run `/project:health` and confirm all PASS.
Any failure → Phase 2 for fix. If fix requires plan change → Phase 1.

**Phase 5 — Knowledge base sync (RULE 1)**
Update ECOSYSTEM_REPORT.md Section 5 + Section 15 for every changed .ps1.
Update CLAUDE.md if architecture/paths/task names/log paths changed.
Update setup_update.ps1 so fix survives full reinstall.

**Phase 6 — Commit**
Invoke `/commit` skill. Never raw git commands.

### Post-task gate — run ALL before claiming done or committing
1. **RULE 1a** — Updated `ECOSYSTEM_REPORT.md` Section 5 (inventory row) for every changed `.ps1`?
2. **RULE 1b** — Updated `ECOSYSTEM_REPORT.md` Section 15 (full file contents) for every changed `.ps1`?
3. **RULE 1c** — Updated `CLAUDE.md` if architecture/paths/task names/log paths changed?
4. **RULE 1d** — Updated `setup_update.ps1` so fix survives full reinstall?
5. **RULE 3**  — Invoked `superpowers:verification-before-completion` skill before claiming done?
6. **RULE 4**  — Invoked `/commit` skill (NEVER raw git commands)?

### Hard stop
If you are about to write "Done.", "Complete.", "All good." or similar — **STOP**.
Run steps 1-6 above first. Only then proceed.

### Em dash encoding rule (PowerShell)
NEVER use em dash (U+2014) in double-quoted strings in .ps1 files. The UTF-8 byte 0x94 is read by ParseFile as U+201D (curly right quote), breaking string parsing. Use ` - ` (space-hyphen-space) instead.

See RULE 1, RULE 3, RULE 4 below for full detail.
<!-- END TASK GATE -->

# C:\Sync — FolderSync + Camera Ecosystem

## Project Overview

This is a personal Windows file synchronization, security, and camera/motion-detection ecosystem. It is **not** a software project — there is no application to build, no tests to run, and no package manager. The "codebase" is a collection of PowerShell automation scripts that:

1. Keep a source folder continuously backed up to a local mirror and to Backblaze B2
2. Monitor the system for tampering and security anomalies
3. Run a motion-detection camera system (Yawcam) with auto-recovery monitoring

**Source folder (video recordings + sync target):** `C:\Users\helde\Repos\Bois`

All scripts live in `C:\Sync\Config\`. Camera setup docs live in `C:\Sync\Config\motion\`. Logs are written to `C:\Sync\Logs\`. The local mirror is at `C:\Sync\Mirror\` (gitignored).

---

## Operating Rules

These rules govern how Claude Code must behave in every session for this project. They are mandatory, not optional.

### RULE 1 — Keep All Guides in Sync

**Trigger:** Immediately after completing ANY change to this ecosystem — new script, modified script, new path, new service, new camera, new command.

**Required actions (ALL of them, every time):**

| What changed | What to update |
|---|---|
| New or modified `.ps1` script in `Config/` | `ECOSYSTEM_REPORT.md` Section 5 (File Inventory) + Section 15 (Full File Contents) |
| New or modified script in `C:\Program Files (x86)\Yawcam\` | `ECOSYSTEM_REPORT.md` Section 5 (Camera scripts table) + Section 15 |
| New Claude Code tool (command, skill, settings) | `ECOSYSTEM_REPORT.md` Section 5 (Claude Code tooling table) |
| Any architectural change | `CLAUDE.md` relevant section + `ECOSYSTEM_REPORT.md` |
| New camera added | `CLAUDE.md` Camera Inventory table + `check_camera.ps1` summary section + `camera-ecosystem` skill inventory |
| New health check logic | Corresponding `/project:check` or `/project:camera-check` command baseline table |
| Any fix, new behavior, or security hardening | `setup_all.ps1` — reflect the fix so it survives a full reinstall |

**Do not mark a task complete until all guide updates are done.** ECOSYSTEM_REPORT.md is the disaster-recovery source of truth — if a file is not in Section 15, it cannot be restored after a reinstall.

### RULE 1 — Mandatory Final Step After Any Fix or Behavior Change

After successfully implementing any fix, new behavior, security hardening, or ecosystem change:

1. **Review `setup_all.ps1`** — does the fix need to be reflected there so it survives a full reinstall? If yes, update it.
2. **Review `ECOSYSTEM_REPORT.md`** — update Section 5 (inventory) and Section 15 (full file contents) for any changed scripts.
3. **These two files are the reinstall blueprint** — any fix not reflected in them is lost after a fresh Windows install.

| Scenario | Required update |
|---|---|
| Fixed a script behavior | Update the script content in `ECOSYSTEM_REPORT.md` Section 15 |
| Changed ACL rules | Update `setup_all.ps1` Step 4 to match |
| Added a new folder | Add ACL protection for it in `setup_all.ps1` Step 4 |
| Changed a service/task | Update the relevant step in `setup_all.ps1` |
| Fixed a firewall rule | Add rule removal/addition to `setup_all.ps1` if it should be permanent |

---

### RULE 2 — Read Logs Before Running Live Checks

**Trigger:** Any time a health check reports a failure, a service is not responding, or a diagnosis is needed.

**Protocol — read logs first, run live checks only if logs are insufficient:**

1. **Read today's log file** for the affected component. Use the date suffix `YYYY-MM-dd` where today is the current date.

   | Component failing | Log file pattern |
   |---|---|
   | Cloud sync / rclone | `C:\Sync\Logs\cloud_sync_YYYY-MM-DD.log` |
   | FolderSyncAuditor | `C:\Sync\Logs\file_audit_YYYY-MM-DD.log` |
   | Security scan | `C:\Sync\Logs\security_audit_YYYY-MM-DD.log` |
   | Local mirror | `C:\Sync\Logs\mirror_YYYY-MM-DD.log` |
   | Watchdog | `C:\Sync\Logs\watchdog.log` (no date suffix — single file) |

2. **If today's log has no relevant entry:** read the prior day's log (`YYYY-MM-(DD-1)`).
3. **Repeat** for up to **4 prior days maximum** (stepping back one day at a time), stopping as soon as the relevant error or event is found.
4. **Only after exhausting all relevant logs** (or if the issue is not covered by logs) should you run live process/service checks or execute diagnostic commands.

**Token-efficient approach — prefer Grep over Read:**
Instead of reading full log files, use the `Grep` tool with an error pattern on the specific dated file. This returns only matching lines, costing a fraction of a full file read.

```
Grep pattern: SYNC-FAIL|FIREWALL|ERROR|Error|WARN|ALERT|connectex|socket access forbidden|failed|Failed|FAIL|exception|denied|blocked
File: C:\Sync\Logs\cloud_sync_YYYY-MM-DD.log   (today's date)
```

For multi-component diagnosis, invoke `/project:diagnose-logs` — it greps all 5 log files in parallel for today (and yesterday if needed) and maps results to known causes, escalating to deep investigation only if logs are inconclusive.

**Key log event prefixes written by `cloud_sync.ps1`:**

| Prefix | Meaning |
|---|---|
| `SYNC-START` / `SYNC-END` | Normal run boundaries |
| `SYNC-OK` | Rclone completed successfully |
| `SYNC-FAIL` | Rclone failed for a non-firewall reason |
| `FIREWALL-PREFLIGHT` | Known malicious rule found and removed *before* sync ran |
| `FIREWALL-PREFLIGHT  WARNING` | Attack was active at sync start — high-severity indicator |
| `FIREWALL-DETECT` | Rclone output contained `connectex`/`socket access forbidden` |
| `FIREWALL-HEAL` | Rule removed and sync retried |
| `FIREWALL-HEAL  Retry SUCCESS` | Self-healed — no manual action needed |
| `FIREWALL-HEAL  Retry FAILED` | Manual investigation required |

**Rationale:** The logs often contain the exact error message already. Reading them costs near-zero tokens compared to running PowerShell queries to test live processes.

**Override:** `.claudeignore` excludes `Logs/` to avoid noise during normal development. This rule overrides that exclusion for diagnosis sessions only. The Grep and Read tools can always access ignored files directly — `.claudeignore` only blocks auto-loading into context. When the issue is resolved, return to treating the Logs/ directory as context-noise.

---

### RULE 3 — Verify Before Claiming Complete

**Trigger:** Before saying any task, fix, or change is "done", "complete", "working", or "ready".

**Non-negotiable principle:** Evidence before claims. Expressing satisfaction, using words like "done", "complete", "everything is updated", or "should work now" without fresh verification is a false claim — not efficiency.

**Verification checklist — run EVERY item that applies to the task just completed:**

| Task type | Required verification |
|---|---|
| Created or edited a `.ps1` or `.md` file | Re-read the file with the Read tool — confirm actual content matches intent |
| Created a `/project:` command | Confirm the file exists and the key sections (baseline table, fix steps) are present |
| Updated `ECOSYSTEM_REPORT.md` | Re-read the affected Section 5 table row and Section 15 code block |
| Updated `CLAUDE.md` | Re-read the changed section |
| Health check script created/modified | Run it: `powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\check_*.ps1"` |
| Ecosystem component fixed | Re-run `/project:check` or `/project:camera-check` and confirm PASS |
| RULE 1 triggered (guides in sync) | Confirm every required guide was updated, not just the primary file |

**Red flags — STOP and verify:**
- About to write "Done.", "Complete.", "Everything is updated.", "All good."
- About to move to the next task without re-reading what was just written
- Relying on memory of what was written instead of reading the actual file
- Saying a script "should work" without running it

**After verification:** State the claim **with evidence** — e.g. *"Re-read ECOSYSTEM_REPORT.md Section 5 — `check_camera.ps1` row confirmed present. Re-read CLAUDE.md RULE 3 — content verified correct."*

Use `/project:review` for the full interactive verification checklist (includes self-healing fix loop, max 4 cycles, automatic escalation to `known_issues.md` on persistent failure).

---

### RULE 4 — Auto-Commit and Push After Every Task

**Trigger:** After every task completion — immediately after RULE 3 review finishes, whether review passed or failed.

**Required actions:**

```powershell
cd C:\Sync
git add <all files changed in this task>
git commit -m "<concise description of what changed>"
git push
```

**Constraints:**
- Never commit: `Logs/`, `Mirror/`, `Config/rclone.conf`, `Config/credentials.enc`, `Config/realtime.ffs_real`, `*.tmp.*`
- Commit message must describe the actual change (not "update" or "fix" alone)
- If nothing changed (e.g. review-only session): skip the commit step
- If git push fails due to a stale lock at `.git/index.lock`: alert Helder — run as Administrator: `icacls "C:\Sync\.git" /remove:d "Everyone" /T /Q && del /F "C:\Sync\.git\index.lock"`
- No PR creation — direct push to current branch

**Note on git lock:** The Deny Delete ACL on `C:\Sync` propagates to `.git/`, which can trap lock files when git crashes. The fix above is a one-time admin operation per occurrence.

---

## Known Issues (Pending Manual Review)

*(Populated automatically by the review escalation protocol — see `C:\Sync\Config\known_issues.md` for details)*

---

## Architecture

The ecosystem has four layers that work together continuously:

```
[Source: C:\Users\helde\Repos\Bois]
        |                    |
        v                    v
[RealTimeSync]        [Task Scheduler]
(live mirror          (every 5 min)
 -> C:\Sync\Mirror)          |
        |                    v
        |             [cloud_sync.ps1]
        |              Rclone -> Backblaze B2
        |              + Mirror ACL rotation
        |              + Log cleanup
        v
[FolderSyncWatchdog service (NSSM)]
  Monitors RealTimeSync process + scheduled task health
  Restarts both if they die. Runs every 3 min.

[FolderSyncAuditor service (NSSM)]
  FileSystemWatcher on source folder
  Detects: file deletions, remote logins, service tampering
  Writes forensic reports on startup gap detection
```

### Scheduled Tasks (run as SYSTEM)

| Task | Script | Schedule |
|---|---|---|
| `FolderSync-CloudBackup` | `cloud_sync.ps1` | Every 5 minutes |
| `FolderSync-DailyCheck` | `DailySecurityCheck.ps1` | Daily 09:00 |

### NSSM Services

| Service | Script | Purpose |
|---|---|---|
| `FolderSyncWatchdog` | `wdog.ps1` | Restarts RealTimeSync + re-enables scheduled task if killed |
| `FolderSyncAuditor` | `auditor.ps1` | FileSystemWatcher security monitor |

### Boot Chain (startup order)

| Trigger | Component | Runs as | Fires |
|---|---|---|---|
| NSSM auto-start | FolderSyncWatchdog | SYSTEM | Windows boot (before login) |
| NSSM auto-start | FolderSyncAuditor | SYSTEM | Windows boot (before login) |
| Task Scheduler (at startup) | FolderSync-CloudBackup | SYSTEM | System startup |
| Task Scheduler (at logon) | FolderSync-Watchdog | SYSTEM | User logon |
| HKCU\Run: FolderSyncRealTime | RealTimeSync.exe | Helder | User login |
| HKCU\Run: Yawcam | Yawcam.exe | Helder | User login |
| HKCU\Run: YawcamMonitor | start_monitor.ps1 | Helder | User login |
| HKCU\Run: YawcamCam2Relay | cam2_relay.ps1 | Helder | User login |

NSSM services + Task Scheduler at-startup provide system-level activation before login. Cloud sync, RealTimeSync, and camera components require a user session and are correctly login-triggered.

### Lifecycle Control (/project: commands)

| Command | Script | Credential check |
|---|---|---|
| `/project:start` | `start_ecosystem.ps1` | Yes - admin credentials |
| `/project:stop` | `stop_ecosystem.ps1` | Yes - admin credentials |
| `/project:pause` | `pause_camera.ps1` | Yes - admin credentials |
| `/project:resume` | `resume_camera.ps1` | Yes - admin credentials |
| `/project:health` | read-only checks | No |

### Key Data Paths

| Path | Purpose |
|---|---|
| `C:\Users\helde\Repos\Bois` | Source folder (what gets backed up) |
| `C:\Sync\Mirror\` | Local rolling mirror (7-day retention, date-organized) |
| `C:\Sync\Config\` | All scripts and config files |
| `C:\Sync\Logs\` | All log output (daily rotation, 30-day retention) |
| `C:\Tools\Rclone\rclone.exe` | Rclone binary (external, not in repo) |
| `C:\Tools\NSSM\nssm.exe` | NSSM service manager (external, not in repo) |
| `C:\Program Files\FreeFileSync\RealTimeSync.exe` | RealTimeSync binary (external, not in repo) |

---

## Key Scripts

### Setup and Installation (run once, as Administrator)

| Script | Purpose |
|---|---|
| `setup_update.ps1` | Master setup v3 — state-aware (stops ecosystem if running, reconfigures, restarts). Replaces `setup_all.ps1`. |
| `setup_all.ps1` | Legacy master setup v2 — kept for reference; use `setup_update.ps1` for all new installs |
| `start_ecosystem.ps1` | Starts all components (services, tasks, RealTimeSync, Yawcam, CAM-2 relay); writes `.ecosystem_state = running` |
| `stop_ecosystem.ps1` | Stops all components in reverse order; writes `.ecosystem_state = stopped` |
| `pause_camera.ps1` | Stops Yawcam only; sets `.camera_paused` flag so health checks skip camera checks |
| `resume_camera.ps1` | Starts Yawcam; removes `.camera_paused` flag |
| `register_tasks.ps1` | Registers `FolderSync-CloudBackup` and `FolderSync-Watchdog` scheduled tasks as SYSTEM |
| `install_service.ps1` | Installs `wdog.ps1` as NSSM service `FolderSyncWatchdog` |
| `install_auditor_service.ps1` | Installs `auditor.ps1` as NSSM service `FolderSyncAuditor` |
| `enable_file_auditing.ps1` | Configures `auditpol`, sets SACL on source folder for deletion/write auditing, applies Deny Delete ACL to `C:\Sync` root |

### Continuous Operation (automated)

| Script | Purpose |
|---|---|
| `cloud_sync.ps1` | Main sync: rclone → B2, then 3-phase Mirror ACL rotation + 7-day cleanup + 30-day log cleanup |
| `wdog.ps1` | Watchdog loop (180s sleep): checks RealTimeSync process + scheduled task, restarts if dead |
| `auditor.ps1` | Security monitor: startup gap forensics, FileSystemWatcher, remote session/process/service polling |
| `run_mirror.bat` | Generated by `setup_all.ps1`. Robocopy source → Mirror with daily log rotation |

### Security and Diagnostics (run manually)

| Script | Purpose |
|---|---|
| `DailySecurityCheck.ps1` | Scans for suspicious processes, anomalous network connections, registry location access |
| `AutoCleanup.ps1` | Kills suspicious processes, purges registry entries, exports .reg backup to Desktop first |
| `check_status.ps1` | Read-only health dashboard: tasks, services, rclone version, folder sizes |
| `read_credentials.ps1` | Decrypts `credentials.enc` via DPAPI and prints to stdout (current user only) |
| `fix_watchdog_task.ps1` | One-off repair: re-registers watchdog task if in bad state |

### Config Files

| File | Purpose |
|---|---|
| `rclone.conf` | Rclone remote config — **contains plaintext B2 credentials** |
| `credentials.enc` | DPAPI-encrypted credentials blob (binary, user-scoped) |
| `realtime.ffs_real` | FreeFileSync RealTimeSync job config (binary/XML — edit via GUI only) |

---

## Constraints and Requirements

### Administrator Requirement
Most scripts require an elevated PowerShell session. Scripts that modify ACLs, register scheduled tasks, install NSSM services, or call `auditpol` will fail silently or error without admin rights. Several scripts include `#Requires -RunAsAdministrator`.

### Windows Only
This ecosystem is entirely Windows-specific:
- DPAPI (`System.Security.Cryptography.ProtectedData`)
- Windows ACLs (`icacls`, `Set-Acl`, `FileSystemAccessRule`)
- Windows Scheduled Tasks (`Register-ScheduledTask`, `Get-ScheduledTask`)
- NSSM services, `auditpol.exe`, Windows Event Log, Registry

### External Tool Dependencies
Binaries at hardcoded paths, not managed by this repo:
- `C:\Tools\Rclone\rclone.exe`
- `C:\Tools\NSSM\nssm.exe`
- `C:\Program Files\FreeFileSync\RealTimeSync.exe`

### Hardcoded Paths
Scripts reference `C:\Users\helde\Repos\Bois` as source and `C:\Sync\` as root. On a different machine/user, these must be updated. `setup_all.ps1` detects current user for some operations but not all.

### Execution Policy
Scheduled tasks invoke PowerShell with `-ExecutionPolicy Bypass`. For interactive testing, set policy or use `-ExecutionPolicy Bypass` explicitly.

---

## ACL Reference (Canonical — do not re-read scripts)

`setup_all.ps1` **Step 4** is the **single authority** for all ACL (Deny Delete) rules.
`setup_all.ps1` **Step 16** runs `enable_file_auditing.ps1` — **SACL only** (audit policy on Bois folder).

| Path | Rule | Notes |
|---|---|---|
| `C:\Sync` (root) | Deny Delete **folder-only** (no inherit) | Prevents root deletion; children unaffected |
| `C:\Sync\Config` | Deny Delete + Children (full inherit) | Scripts tamper-proof |
| `C:\Sync\Logs` | Deny Delete + Children (full inherit) | Logs tamper-proof |
| `C:\Sync\Evidence` | Deny Delete + Children (full inherit) | Forensic data tamper-proof |
| `C:\Sync\.git` | **None** — liberated via `icacls /remove:d /T` | git needs full write; liberation is Step 4.5 |
| `C:\Sync\Mirror` | **None** at folder level | `cloud_sync.ps1` manages 7-day per-file Deny Delete internally |
| `C:\Sync\Config\.ecosystem_state` | Inherits Config\ Deny Delete | Runtime state flag: "running" or "stopped". Gitignored. |
| `C:\Sync\Config\.camera_paused` | Inherits Config\ Deny Delete | Camera pause flag. Gitignored. |

**Repair command** (Admin PS): run `setup_all.ps1` as Administrator — Step 4 re-applies all rules idempotently.

**`.git` index.lock trap**: If `index.lock` exists and can't be deleted, run in Admin PS:
```powershell
icacls "C:\Sync\.git" /remove:d "*S-1-1-0" /T /Q
icacls "C:\Sync\.git" /remove:d "*S-1-5-32-545" /T /Q
icacls "C:\Sync\.git" /remove:d "*S-1-5-32-544" /T /Q
Remove-Item -Force "C:\Sync\.git\index.lock"
```
Root cause: only occurs if `setup_all.ps1` was run with an older version that lacked centralized ACL (pre-2026-03-07). Should not recur after current `setup_all.ps1` is run.

---

## What NOT to Modify

| Item | Reason |
|---|---|
| `Config\rclone.conf` | Live Backblaze B2 credentials in plaintext. Never diff, log, or suggest changes to its contents. |
| `Config\credentials.enc` | DPAPI binary blob. Any edit corrupts decryption irreversibly. |
| ACL rules on `C:\Sync\` | See ACL Reference table above. Repair by re-running `setup_all.ps1` Step 4, never freehand. |
| `Config\realtime.ffs_real` | FreeFileSync binary config. Edit only through the FreeFileSync GUI. |
| Scheduled task principals | Both tasks run as `SYSTEM` with `RunLevel Highest`. Changing to a user account breaks ACL and service operations. |
| NSSM service recovery settings | Services are configured to auto-restart. Do not disable recovery or change service identity. |

---

## PowerShell Conventions

**Error handling:**
```powershell
$ErrorActionPreference = 'SilentlyContinue'  # top of orchestration scripts
# Sensitive operations:
try { ... } catch { Write-Fail "..." }  # with -ErrorAction Stop on the cmdlet
```

**Logging pattern** — always use `Add-Content` with `-LiteralPath`:
```powershell
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
```
Two spaces between timestamp and message. Never use `Write-Output` for log entries.

**Console output helpers:**
```powershell
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }
```

**SIDs over names** — use well-known SIDs to ensure scripts work on non-English Windows:
- `S-1-1-0` = Everyone
- `S-1-5-32-544` = Administrators
- `S-1-5-18` = SYSTEM

**Date-stamped log files** — evaluated at runtime, rolls at midnight automatically:
```powershell
$LogFile = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
```

**Backtick line continuation** for multi-line rclone calls:
```powershell
& $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO
```

**Script root** — scripts use absolute paths rooted at `C:\Sync\Config\`, not `$PSScriptRoot`, except where `Split-Path -Parent $MyInvocation.MyCommand.Path` is explicitly used.

---

## Camera / Motion Detection System

### Overview

The Bois source folder is **also** the output target for a motion-detection camera system. Yawcam 0.6.2 (free, Java-based) watches the laptop's built-in webcam and writes `.avi` clip files directly into `C:\Users\helde\Repos\Bois\YYYY-MM-DD\` whenever motion is detected. These clips are then automatically mirrored locally and synced to Backblaze B2 by the FolderSync ecosystem.

### Camera Inventory

| ID | Device | Software | Status |
|---|---|---|---|
| CAM-1 | Built-in laptop webcam — HD User Facing (720p @ 30fps) | Yawcam 0.6.2 | **Active** |
| CAM-2 | TP-LINK Tapo C100 IP camera (LAN, 192.168.0.109) | VLC RTSP→MJPEG relay (`cam2_relay.ps1`) → Yawcam (`http://127.0.0.1:8161/`) | **Active** |

More cameras will be added over time. Each new camera should be integrated as an additional Yawcam input and documented in this table.

### Recording Pattern

```
Motion detected by Yawcam
        ↓
C:\Users\helde\Repos\Bois\YYYY-MM-DD\motion_YYYY-MM-DD_HH.MM.SS_NNN.avi
        ↓ (RealTimeSync, ~5s idle buffer)
C:\Sync\Mirror\  (local robocopy mirror)
        ↓ (cloud_sync.ps1, every 5 min)
Backblaze B2  helder-sync-mirror bucket
```

Files are named: `motion_YYYY-MM-DD_HH.MM.SS_NNN.avi`
Format: AVI, H.264, 640×480 @ 30fps
Retention: 7 days (ACL-protected then cleaned by cloud_sync.ps1)

### Yawcam Key Paths

| Path | Purpose |
|---|---|
| `C:\Program Files (x86)\Yawcam\Yawcam.exe` | Main executable |
| `C:\Sync\Config\yawcam_monitor_v4.ps1` | Active monitor script (recovery loop) — relocated from Yawcam dir |
| `C:\Sync\Config\start_monitor.ps1` | Boot launcher — waits 30s then starts monitor hidden — relocated from Yawcam dir |
| `C:\Users\helde\Repos\Bois\YYYY-MM-DD\` | Recording output (date-stamped subdirectory) |
| `C:\TEMP\motion_videos` | Legacy path watched by monitor v4 — not the actual recording path; may need a symlink |
| `C:\Sync\Config\cam2_relay.ps1` | CAM-2 VLC relay — converts RTSP from C100 to MJPEG HTTP on `127.0.0.1:8161` |
| `C:\Sync\Config\cam2.conf` | CAM-2 credentials (plaintext, ACL-protected, gitignored) |
| `C:\Sync\Config\.ecosystem_state` | Runtime state flag written by start/stop scripts ("running" or "stopped"). Gitignored. |
| `C:\Sync\Config\.camera_paused` | Camera pause flag written by pause_camera.ps1. Gitignored. |

### Yawcam Configuration (key settings)

| Setting | Value |
|---|---|
| Motion sensitivity | 91 (in XML: lower value = less sensitive — **was causing false triggers**) |
| Motion threshold | 3% (in XML: `motionTol` — **was causing false triggers; raise to 15%**) |
| Motion delay | 3 seconds |
| Enable motion detection on startup | Yes |
| Recording format | AVI (H.264) |
| Output path | `C:\Users\helde\Repos\Bois` |
| Auto-start (registry) | `HKCU:\...\Run\Yawcam` |

### Monitor Script (`yawcam_monitor_v4.ps1`) Logic

The monitor runs in an infinite loop (60s interval):
1. Checks `C:\TEMP\motion_videos` for the latest `.avi` file
2. If latest file is **< 5 min old** → OK
3. If latest file is **5–15 min old** → INFO (normal gap, no motion)
4. If latest file is **> 15 min old** → triggers Yawcam restart (with 600s cooldown)
5. Restart sequence: kill Yawcam → disable/enable webcam PnP device → start Yawcam

**Note:** The monitor checks `C:\TEMP\motion_videos` but Yawcam records to `C:\Users\helde\Repos\Bois\YYYY-MM-DD\`. This path mismatch means the monitor may always see "no videos" — a symlink `C:\TEMP\motion_videos → C:\Users\helde\Repos\Bois` would fix this.

### Auto-Start Chain (boot sequence)

```
Windows login
    → Registry Run: Yawcam.exe         (starts Yawcam with motion detection enabled)
    → Registry Run: YawcamMonitor      (start_monitor.ps1, 30s delay, then monitor v4 hidden)
    → Registry Run: YawcamCam2Relay    (cam2_relay.ps1 hidden — VLC RTSP->MJPEG relay for CAM-2)
```

### Critical Power Settings

Webcam drops during screen lock unless these Windows power settings are applied:

| Setting | Required value |
|---|---|
| USB Selective Suspend | **Disabled** |
| Sleep after | **Never** |
| Hibernate after | **Never** |
| Webcam device power management | **Disabled** (Device Manager) |

Full checklist: `C:\Sync\Config\motion\motion-detection-power-settings-quick-reference.md`
Full setup guide: `C:\Sync\Config\motion\acer-nitro5-motion-detection-setup.md`

### Camera Health Check Scripts

| Script | Purpose |
|---|---|
| `Config/check_camera.ps1` | Camera health check — process, device, recordings, startup entries |
| `/project:camera-check` | Per-project command — runs check and auto-diagnoses/fixes failures |

### What NOT to Modify (Camera)

- `C:\Program Files (x86)\Yawcam\` — Do not move or rename; the registry startup entry points to the fixed path
- Yawcam's output path in Settings → Output — must remain `C:\Users\helde\Repos\Bois` to stay integrated with the sync ecosystem
- The `.avi` naming pattern — downstream scripts use glob `motion_*.avi` to identify recordings

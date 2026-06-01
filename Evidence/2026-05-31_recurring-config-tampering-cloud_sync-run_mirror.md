# INCIDENT: Recurring Tampering of cloud_sync.ps1 and run_mirror.bat
**Date:** 2026-05-31  
**First detected this session:** ~15:00 local  
**Recurrence confirmed:** files were re-tampered within minutes of being restored via `git restore`  
**Severity:** CRITICAL — active, automated attack in progress  

---

## Pattern

`Config/cloud_sync.ps1` and `Config/run_mirror.bat` are being modified repeatedly and automatically. Every time they are restored to their committed state, they are re-modified within minutes.

### Confirmed tampering timestamps today
- 31/05/2026 16:12:14 — both files modified (LastWriteTime)
- Subsequent re-tampering after each `git restore` in this session

### Prior tampering history (same files)
- 2026-05-28: first confirmed tampering (see `Evidence/2026-05-28_cloud_sync-tampering-FASE3-removed.md`)
- 2026-05-29: repeat tampering (see `Evidence/2026-05-29_repeat-tampering-cloud_sync-FASE3.md`)
- 2026-05-29: 3rd instance (see `Evidence/2026-05-29_tampering-cloud_sync-run_mirror-restored.diff`)

---

## Investigation Findings

### What the event log shows at 16:12 (Security audit, event 4663)
- Only `javaw.exe` (Yawcam, PID 0x3938) writing/deleting `.avi` files in `C:\Users\helde\Repos\Bois\` — that is **normal camera operation**
- No event 4663 entries for `C:\Sync\Config\` — SACL audit policy is not configured on Config\, only on Bois\
- Process creation events (4688) returned no results for the 16:10–16:15 window — either audit policy not enabled for process creation, or attacker ran existing process

### Suspicious timing correlation
- 16:11:36 — VS Code opened a PowerShell terminal session (pwsh.exe, PID 20920, via shellIntegration.ps1)
- 16:12:14 — both files tampered (38 seconds later)
- 16:13:19 — `cam2_relay.ps1` started (powershell.exe, PID 9928)

The 38-second window between VS Code PowerShell session open and tampering is a strong correlation. However, this could be coincidental if the attacker has a separate persistent mechanism.

### Running processes at time of investigation
All processes appeared legitimate:
- Malwarebytes native messaging (cmd.exe, PIDs 2284, 21676) — browser extension
- Multiple pwsh.exe instances (Claude Code, VS Code terminal, VS Code PowerShell extension)
- `cam2_relay.ps1` — normal ecosystem component
- `playwright-mcp` node processes — Claude Code browser automation

### Scheduled tasks
- `FolderSync-GitCommitLogs` — runs `auto_commit_logs.ps1` daily at 23:30 — **not involved** (only commits Logs/)
- `FolderSync-CloudBackup` and `FolderSync-Watchdog` — shown as `...ed` (disabled/stopped state)

---

## Attack Goal

`cloud_sync.ps1` is the main sync script (rclone → Backblaze B2) and contains:
- Firewall preflight check that detects and removes attacker's blocking rules
- The actual backup operation

`run_mirror.bat` controls local mirror via Robocopy.

By tampering these files, the attacker can:
1. Disable the firewall self-healing (making B2 blocks permanent)
2. Disable or redirect the backup
3. Remove evidence collection logic

---

## Hypothesis: Persistence Mechanism

The attacker likely has one or more of:
- A scheduled task running as SYSTEM or helde that re-applies modifications on a short interval
- A running process (service or hidden script) with a FileSystemWatcher or polling loop that re-tampers on change detection
- A VS Code extension or workspace automation that modifies files on terminal open

**The re-tampering after each `git restore` in this session suggests a watcher-based mechanism** — the attacker may be watching for `git restore` events on these specific files.

---

## Recommended Investigation Steps

1. **Enable SACL on `C:\Sync\Config\`** — currently only `Bois\` has file access auditing. Adding SACL to Config\ would produce event 4663 entries identifying the exact process writing these files.
   ```powershell
   # Run as Administrator
   $acl = Get-Acl "C:\Sync\Config"
   $audit = New-Object System.Security.AccessControl.FileSystemAuditRule("Everyone","Write","ContainerInherit,ObjectInherit","None","Success")
   $acl.AddAuditRule($audit)
   Set-Acl "C:\Sync\Config" $acl
   ```

2. **Review all scheduled tasks** for actions touching `C:\Sync\Config\` — especially tasks running as SYSTEM on short intervals.

3. **Check VS Code workspace settings** — `.vscode/settings.json` or tasks.json for any file modification hooks.

4. **Review installed VS Code extensions** for filesystem write capabilities.

5. **Check registry Run keys** for entries beyond the known ecosystem:
   ```powershell
   Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
   Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
   ```

---

## Countermeasure Deployed

**`config_guard.ps1`** — FileSystemWatcher script deployed at `C:\Sync\Config\config_guard.ps1`  
**Registered as:** `FolderSync-ConfigGuard` scheduled task (runs at logon, elevated, hidden)  
**Started:** 31/05/2026 23:59:28 (running now)  

Behavior: detects any write/create event on `cloud_sync.ps1` or `run_mirror.bat` → immediately removes `index.lock` if present → runs `git restore` → logs to `C:\Sync\Logs\security\config_guard_YYYY-MM-DD.log`

This does not stop the attacker — it undoes their changes automatically. Enabling SACL auditing on Config\ is needed to identify the attacker's mechanism.

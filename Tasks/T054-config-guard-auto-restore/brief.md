# T054 — Config Guard Auto-Restore

## Goal
Extend `config_guard.ps1` so that when a watched file is modified on disk, it automatically
restores it from `git HEAD` unless the change was made by a legitimate actor.

## Problem Being Solved
The attacker runs a scheduled task (or service/WMI) that overwrites `Config/cloud_sync.ps1`
and `Config/run_mirror.bat` nightly with a payload that silences monitoring and disables PHASE 3.
Currently config_guard detects the change and alerts, but does not restore. The fix must already
be in `setup_update.ps1` so it survives a reinstall.

---

## Decision Context (captured from design conversation)

### Auto-restore conditions
Restore automatically when ALL of the following are true:
1. The writing process is NOT `claude.exe` (Claude Code)
2. The foreground window is NOT an editor app (code.exe, notepad.exe, notepad++.exe, sublime_text.exe, vim, etc.)
3. The user session is active but NOT the one who triggered the write via an editor

Detection mechanism: PowerShell P/Invoke to `GetForegroundWindow` + `GetWindowThreadProcessId`
gives the process of the foreground window at the moment FSW fires (within ms of the write).

If session is locked (foreground = winlogon / LogonUI / desktop) → also auto-restore
(attacker's prime window is when Helder steps away).

### Restore mechanism
```powershell
git -C "C:\Sync" checkout HEAD -- "Config/<filename>"
```
Then log: `AUTO-RESTORED Config/<file> — foreground was <process>, writer was <process>`

### Branch discipline convention (complementary, no code change needed)
- Repo idles on `develop` branch when not actively coding
- All work done in git worktrees (branch off develop, merge + delete on completion)
- HEAD on develop = always a known-good restore source
- This means: attacker overwrites file → config_guard restores it in seconds from a clean HEAD

### Identification of attacker process (open investigation)
SACL is deployed on `cloud_sync.ps1`. Read Security EventLog Event 4663 for the file to find
the exact PID + process path. This is a separate investigation but should be done before or
alongside T054 so the allowlist in config_guard can explicitly name the attacker if identified.

---

## Scope

### In scope
- `Config/config_guard.ps1`: add P/Invoke GetForegroundWindow detection + git restore call
- `Config/setup_update.ps1`: ensure the updated config_guard is installed (Step 20 redeploys it)
- `ECOSYSTEM_REPORT.md` Section 5 + Section 15: update config_guard entry
- `CLAUDE.md` Live Threat Digest: update to reflect auto-restore capability added

### Out of scope
- Branch discipline (convention only, no script changes)
- Identifying the attacker process (separate investigation — see Evidence/MUST-CHECK-URGENT.md)
- T051 guard list changes (already done; T054 only adds behavior to existing guard)

---

## Key Files to Read Before Planning
- `C:\Sync\Config\config_guard.ps1` — current implementation (FileSystemWatcher + alert logic)
- `C:\Sync\Config\setup_update.ps1` — Step 20 deploys config_guard; must be updated
- `C:\Sync\ECOSYSTEM_REPORT.md` Section 5 (config_guard row) + Section 15 (full content)

---

## Implementation Notes

### P/Invoke pattern (PowerShell)
```powershell
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@

function Get-ForegroundProcessName {
    $hwnd = [Win32]::GetForegroundWindow()
    $pid = 0
    [Win32]::GetWindowThreadProcessId($hwnd, [ref]$pid) | Out-Null
    if ($pid -gt 0) { (Get-Process -Id $pid -ErrorAction SilentlyContinue).Name } else { "unknown" }
}
```

### Known editor process names (allowlist — do NOT restore if these are foreground)
`code`, `Code`, `notepad`, `notepad++`, `sublime_text`, `vim`, `nvim`, `nano`, `wordpad`, `WINWORD`

### Known safe writers (allowlist — do NOT restore if these wrote the file)
`claude` (claude.exe — Claude Code)
Note: attacker process identity unknown; once Event 4663 reveals it, it should NOT be in this list.

### Restore command
```powershell
& git -C "C:\Sync" checkout HEAD -- "Config\$filename" 2>&1
```
Run from within config_guard's FSW event handler, after the foreground check.

---

## Acceptance Criteria
1. Attacker overwrites cloud_sync.ps1 (simulated via test write) → file restored within 5 seconds
2. Claude Code edits cloud_sync.ps1 → no restore triggered (claude.exe is foreground or writer)
3. Helder edits cloud_sync.ps1 in VS Code → no restore triggered (code.exe is foreground)
4. Session locked + file overwritten → restore triggered
5. Restore event logged to security audit log with AUTO-RESTORED prefix
6. `setup_update.ps1` deploys the updated config_guard on reinstall

---

## Steps Status
See `steps-status.md` (to be created when implementation begins in a fresh session).

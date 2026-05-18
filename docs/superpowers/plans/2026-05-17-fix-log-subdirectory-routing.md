# Fix Log Subdirectory Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route all log files to their designated subdirectories (`cloud_sync/`, `mirror/`, `services/`, `security/`) instead of the `Logs/` root.

**Architecture:** The intended directory structure already exists (subdirs have `.gitkeep` files). The problem is that several scripts still hardcode `C:\Sync\Logs\` as the log root rather than the appropriate subdir. Fix each offending write path, update reader scripts to match, update log-cleanup globs in `cloud_sync.ps1`, and reconfigure live NSSM services.

**Tech Stack:** PowerShell 7, NSSM, robocopy, `netsh advfirewall`

---

## Diagnosis Summary

### Root-level stragglers (wrong location, confirmed by live file listing)

| Log file pattern | Currently lands in | Should land in |
|---|---|---|
| `cloud_sync_*.log` | `Logs/` root | `Logs/cloud_sync/` |
| `mirror_*.log` | `Logs/` root | `Logs/mirror/` (dir missing!) |
| `watchdog_svc.log`, `watchdog_svc_err.log` | `Logs/` root | `Logs/services/` |
| `auditor_svc.log`, `auditor_svc_err.log` | `Logs/` root | `Logs/services/` |
| `cam2_relay_*.log` (fallback branch) | `Logs/` root | `Logs/camera/` |
| `firewall.log`, `firewall.log.old` | `Logs/` root | `Logs/security/` |

### Reader scripts using stale paths

| Script | Stale path read | Correct path |
|---|---|---|
| `check_status.ps1:49` | `Logs\cloud_sync_*.log` | `Logs\cloud_sync\cloud_sync_*.log` |
| `check_status.ps1:78` | `Logs\watchdog.log` | `Logs\services\watchdog.log` |
| `check_status.ps1:81` | `Logs\file_audit_*.log` | `Logs\audit\file_audit_*.log` |
| `check_status.ps1:89` | `Logs\security_audit_*.log` | `Logs\security\security_audit_*.log` |
| `health_check_all.ps1:101` | `Logs\cloud_sync_*.log` | `Logs\cloud_sync\cloud_sync_*.log` |
| `check_camera.ps1:135` | `Logs\cam2_relay_*.log` | `Logs\camera\cam2_relay_*.log` |

---

## Task 1: Create missing `Logs\mirror\` directory

**Files:**
- Create: `C:\Sync\Logs\mirror\.gitkeep`

- [ ] **Step 1: Create the directory and gitkeep**

```powershell
New-Item -ItemType Directory -Path "C:\Sync\Logs\mirror" -Force
New-Item -ItemType File -Path "C:\Sync\Logs\mirror\.gitkeep" -Force
```

- [ ] **Step 2: Verify**

```powershell
Test-Path "C:\Sync\Logs\mirror\.gitkeep"
# Expected: True
```

- [ ] **Step 3: Commit**

```
git add Logs/mirror/.gitkeep
git commit -m "logs: create mirror/ subdirectory for mirror log routing"
```

---

## Task 2: Fix `cloud_sync.ps1` — write and cleanup paths

**Files:**
- Modify: `C:\Sync\Config\cloud_sync.ps1` (lines 11-12, 215, 220)

The script sets `$LogDir = 'C:\Sync\Logs'` and builds the log path from it, then uses `$LogDir` for cleanup globs. Change `$LogDir` to point to the `cloud_sync\` subdir, and fix the mirror cleanup glob to use the `mirror\` subdir.

- [ ] **Step 1: Update `$LogDir` and mirror cleanup path in `cloud_sync.ps1`**

Change line 11:
```powershell
# Before:
$LogDir           = 'C:\Sync\Logs'
# After:
$LogDir           = 'C:\Sync\Logs\cloud_sync'
```

Change the mirror log cleanup (around line 220) — it searches `$LogDir` for `mirror_*.log` which is now wrong. Replace with explicit path:
```powershell
# Before:
Get-ChildItem -Path $LogDir -Filter "mirror_*.log" |
# After:
Get-ChildItem -Path 'C:\Sync\Logs\mirror' -Filter "mirror_*.log" |
```

- [ ] **Step 2: Verify syntax**

```powershell
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\cloud_sync.ps1',[ref]$t,[ref]$e);$e.Count
# Expected: 0
```

- [ ] **Step 3: Confirm the subdir exists (it should after Task 1 runs today)**

```powershell
Test-Path "C:\Sync\Logs\cloud_sync"
# Expected: True
```

- [ ] **Step 4: Commit**

```
git add Config/cloud_sync.ps1
git commit -m "fix: route cloud_sync logs to Logs\cloud_sync\ subdir"
```

---

## Task 3: Fix `run_mirror.bat` — mirror log path

**Files:**
- Modify: `C:\Sync\Config\run_mirror.bat` (line 10)

- [ ] **Step 1: Update robocopy log path**

Change line 10:
```bat
:: Before:
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL /NC /NS /NFL
:: After:
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror\mirror_%DATE%.log" /NP /NDL /NC /NS /NFL
```

- [ ] **Step 2: Commit**

```
git add Config/run_mirror.bat
git commit -m "fix: route mirror robocopy logs to Logs\mirror\ subdir"
```

---

## Task 4: Fix `cam2_relay.ps1` — remove root fallback

**Files:**
- Modify: `C:\Sync\Config\cam2_relay.ps1` (line 75)

Line 75 is a fallback log path that writes to `Logs\cam2_relay_*.log` root instead of `Logs\camera\`.

- [ ] **Step 1: Fix fallback path**

Change line 75:
```powershell
# Before:
$LogFile = "C:\Sync\Logs\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
# After:
$LogFile = "C:\Sync\Logs\camera\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
```

- [ ] **Step 2: Verify syntax**

```powershell
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\cam2_relay.ps1',[ref]$t,[ref]$e);$e.Count
# Expected: 0
```

- [ ] **Step 3: Commit**

```
git add Config/cam2_relay.ps1
git commit -m "fix: route cam2_relay fallback log to Logs\camera\ subdir"
```

---

## Task 5: Fix NSSM service log paths (4 files)

**Files:**
- Modify: `C:\Sync\Config\install_service.ps1` (lines 14-15)
- Modify: `C:\Sync\Config\install_auditor_service.ps1` (lines 24-25)
- Modify: `C:\Sync\Config\setup_update.ps1` (lines 522-523, 544-545)
- Modify: `C:\Sync\Config\setup_all.ps1` (lines 529-530, 553-554)

These four scripts set NSSM `AppStdout`/`AppStderr` to `Logs\watchdog_svc.log`, `Logs\watchdog_svc_err.log`, `Logs\auditor_svc.log`, `Logs\auditor_svc_err.log`. All should go to `Logs\services\`.

- [ ] **Step 1: Fix `install_service.ps1`**

```powershell
# Before:
& $nssm set $svcName AppStdout 'C:\Sync\Logs\watchdog_svc.log'
& $nssm set $svcName AppStderr 'C:\Sync\Logs\watchdog_svc_err.log'
# After:
& $nssm set $svcName AppStdout 'C:\Sync\Logs\services\watchdog_svc.log'
& $nssm set $svcName AppStderr 'C:\Sync\Logs\services\watchdog_svc_err.log'
```

- [ ] **Step 2: Fix `install_auditor_service.ps1`**

```powershell
# Before:
& $nssm set $svcName AppStdout     'C:\Sync\Logs\auditor_svc.log'
& $nssm set $svcName AppStderr     'C:\Sync\Logs\auditor_svc_err.log'
# After:
& $nssm set $svcName AppStdout     'C:\Sync\Logs\services\auditor_svc.log'
& $nssm set $svcName AppStderr     'C:\Sync\Logs\services\auditor_svc_err.log'
```

- [ ] **Step 3: Fix `setup_update.ps1` watchdog NSSM block**

```powershell
# Before (~line 522):
& $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\watchdog_svc.log'
& $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\watchdog_svc_err.log'
# After:
& $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\services\watchdog_svc.log'
& $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\services\watchdog_svc_err.log'
```

- [ ] **Step 4: Fix `setup_update.ps1` auditor NSSM block**

```powershell
# Before (~line 544):
& $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\auditor_svc.log'
& $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\auditor_svc_err.log'
# After:
& $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\services\auditor_svc.log'
& $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\services\auditor_svc_err.log'
```

- [ ] **Step 5: Fix `setup_all.ps1` watchdog and auditor NSSM blocks** (same changes as steps 3-4, same old→new, same line numbers ~529-530, ~553-554)

- [ ] **Step 6: Verify syntax on all 4 files**

```powershell
foreach ($f in @('install_service.ps1','install_auditor_service.ps1','setup_update.ps1','setup_all.ps1')) {
    $t=$null;$e=$null
    [System.Management.Automation.Language.Parser]::ParseFile("C:\Sync\Config\$f",[ref]$t,[ref]$e)
    Write-Host "$f`: $($e.Count) errors"
}
# Expected: all 0 errors
```

- [ ] **Step 7: Reconfigure live running services via NSSM (requires Admin)**

This must be run as Administrator. The services are currently running and writing to the old paths. Reconfigure them live without reinstalling:

```powershell
# Run as Administrator:
$nssm = 'C:\Tools\NSSM\nssm.exe'
& $nssm set FolderSyncWatchdog AppStdout 'C:\Sync\Logs\services\watchdog_svc.log'
& $nssm set FolderSyncWatchdog AppStderr 'C:\Sync\Logs\services\watchdog_svc_err.log'
& $nssm set FolderSyncAuditor  AppStdout 'C:\Sync\Logs\services\auditor_svc.log'
& $nssm set FolderSyncAuditor  AppStderr 'C:\Sync\Logs\services\auditor_svc_err.log'
# Restart services to apply:
Restart-Service FolderSyncWatchdog
Restart-Service FolderSyncAuditor
```

- [ ] **Step 8: Commit**

```
git add Config/install_service.ps1 Config/install_auditor_service.ps1 Config/setup_update.ps1 Config/setup_all.ps1
git commit -m "fix: route NSSM service stdout/stderr logs to Logs\services\ subdir"
```

---

## Task 6: Fix firewall log path — move to `Logs\security\`

**Files:**
- Modify: `C:\Sync\Config\setup_update.ps1` (line 445, 448-449)
- Modify: `C:\Sync\Config\setup_all.ps1` (line 446, 449-450)

The Windows firewall logs (`firewall.log`, `firewall.log.old`) are configured via `netsh advfirewall`. Move them to `Logs\security\`.

- [ ] **Step 1: Fix `setup_update.ps1` netsh line and icacls grant**

```powershell
# Before (~line 445):
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\firewall.log" | Out-Null
# After:
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\security\firewall.log" | Out-Null
```

```powershell
# Before (~line 448):
if (Test-Path "C:\Sync\Logs\firewall.log") {
    icacls "C:\Sync\Logs\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
# After:
if (Test-Path "C:\Sync\Logs\security\firewall.log") {
    icacls "C:\Sync\Logs\security\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
```

- [ ] **Step 2: Same changes in `setup_all.ps1`**

- [ ] **Step 3: Reconfigure live netsh (requires Admin)**

```powershell
# Run as Administrator:
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\security\firewall.log"
# Verify:
netsh advfirewall show allprofiles | Select-String "FileName"
# Expected: C:\Sync\Logs\security\firewall.log
```

- [ ] **Step 4: Verify syntax**

```powershell
foreach ($f in @('setup_update.ps1','setup_all.ps1')) {
    $t=$null;$e=$null
    [System.Management.Automation.Language.Parser]::ParseFile("C:\Sync\Config\$f",[ref]$t,[ref]$e)
    Write-Host "$f`: $($e.Count) errors"
}
# Expected: 0 errors each
```

- [ ] **Step 5: Commit**

```
git add Config/setup_update.ps1 Config/setup_all.ps1
git commit -m "fix: route Windows firewall logs to Logs\security\ subdir"
```

---

## Task 7: Fix reader scripts — update stale log paths

**Files:**
- Modify: `C:\Sync\Config\check_status.ps1` (lines 49, 78, 81, 89)
- Modify: `C:\Sync\Config\health_check_all.ps1` (line 101)
- Modify: `C:\Sync\Config\check_camera.ps1` (line 135)

- [ ] **Step 1: Fix `check_status.ps1`**

Line 49 — cloud sync log lookup:
```powershell
# Before:
$todayLog = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
# After:
$todayLog = "C:\Sync\Logs\cloud_sync\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
```

Line 78 — watchdog log read:
```powershell
# Before:
Get-Content "C:\Sync\Logs\watchdog.log" -ErrorAction SilentlyContinue | Select-Object -Last 5
# After:
Get-Content "C:\Sync\Logs\services\watchdog.log" -ErrorAction SilentlyContinue | Select-Object -Last 5
```

Line 81 — file audit log:
```powershell
# Before:
$fileLog = "C:\Sync\Logs\file_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
# After:
$fileLog = "C:\Sync\Logs\audit\file_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
```

Line 89 — security audit log:
```powershell
# Before:
$secLog = "C:\Sync\Logs\security_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
# After:
$secLog = "C:\Sync\Logs\security\security_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
```

- [ ] **Step 2: Fix `health_check_all.ps1` line 101**

```powershell
# Before:
$todayLog = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
# After:
$todayLog = "C:\Sync\Logs\cloud_sync\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
```

- [ ] **Step 3: Fix `check_camera.ps1` line 135**

```powershell
# Before:
$relayLog = "C:\Sync\Logs\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
# After:
$relayLog = "C:\Sync\Logs\camera\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
```

- [ ] **Step 4: Verify syntax on all 3 files**

```powershell
foreach ($f in @('check_status.ps1','health_check_all.ps1','check_camera.ps1')) {
    $t=$null;$e=$null
    [System.Management.Automation.Language.Parser]::ParseFile("C:\Sync\Config\$f",[ref]$t,[ref]$e)
    Write-Host "$f`: $($e.Count) errors"
}
# Expected: 0 errors each
```

- [ ] **Step 5: Commit**

```
git add Config/check_status.ps1 Config/health_check_all.ps1 Config/check_camera.ps1
git commit -m "fix: update reader scripts to use correct log subdirectory paths"
```

---

## Task 8: Update CLAUDE.md and ECOSYSTEM_REPORT.md (RULE 1)

**Files:**
- Modify: `C:\Sync\CLAUDE.md` — update RULE 2 log file pattern table to use subdir paths
- Modify: `C:\Sync\ECOSYSTEM_REPORT.md` — Section 5 + Section 15 for all modified scripts

- [ ] **Step 1: Update CLAUDE.md RULE 2 log table**

The table in RULE 2 currently shows:
```
| Cloud sync / rclone | C:\Sync\Logs\cloud_sync_YYYY-MM-DD.log |
| FolderSyncAuditor   | C:\Sync\Logs\file_audit_YYYY-MM-DD.log |
| Security scan       | C:\Sync\Logs\security_audit_YYYY-MM-DD.log |
| Local mirror        | C:\Sync\Logs\mirror_YYYY-MM-DD.log |
| Watchdog            | C:\Sync\Logs\watchdog.log |
```

Update to:
```
| Cloud sync / rclone | C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log |
| FolderSyncAuditor   | C:\Sync\Logs\audit\file_audit_YYYY-MM-DD.log |
| Security scan       | C:\Sync\Logs\security\security_audit_YYYY-MM-DD.log |
| Local mirror        | C:\Sync\Logs\mirror\mirror_YYYY-MM-DD.log |
| Watchdog            | C:\Sync\Logs\services\watchdog.log |
```

- [ ] **Step 2: Update ECOSYSTEM_REPORT.md Section 5 and Section 15** for each modified script:
  - `cloud_sync.ps1`
  - `run_mirror.bat`
  - `cam2_relay.ps1`
  - `install_service.ps1`
  - `install_auditor_service.ps1`
  - `setup_update.ps1`
  - `setup_all.ps1`
  - `check_status.ps1`
  - `health_check_all.ps1`
  - `check_camera.ps1`

- [ ] **Step 3: Commit**

```
git add CLAUDE.md ECOSYSTEM_REPORT.md
git commit -m "docs: update log path references to reflect new subdir routing"
```

---

## Task 9: Final health check

- [ ] **Step 1: Run `/project:health`** and confirm all PASS

- [ ] **Step 2: Confirm no new stray log files appear in `Logs/` root** after the next cloud_sync cycle (wait ~5 min for the scheduled task to run):

```powershell
# Should show only: firewall.log (if Task 6 admin step wasn't run yet), subdirs, and .gitkeep
Get-ChildItem "C:\Sync\Logs" -File | Where-Object { $_.Name -notmatch '^firewall' } | Select-Object Name
# Expected: empty (all logs now in subdirs)
```

- [ ] **Step 3: Commit any remaining changes**

---

## Admin Steps Summary (require running as Administrator)

Tasks 5 and 6 include live reconfiguration steps that require admin rights. Run these in an Admin PowerShell after the script edits are committed:

**Task 5 — NSSM live reconfiguration:**
```powershell
$nssm = 'C:\Tools\NSSM\nssm.exe'
& $nssm set FolderSyncWatchdog AppStdout 'C:\Sync\Logs\services\watchdog_svc.log'
& $nssm set FolderSyncWatchdog AppStderr 'C:\Sync\Logs\services\watchdog_svc_err.log'
& $nssm set FolderSyncAuditor  AppStdout 'C:\Sync\Logs\services\auditor_svc.log'
& $nssm set FolderSyncAuditor  AppStderr 'C:\Sync\Logs\services\auditor_svc_err.log'
Restart-Service FolderSyncWatchdog
Restart-Service FolderSyncAuditor
```

**Task 6 — netsh live reconfiguration:**
```powershell
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\security\firewall.log"
```

# Automated Folder Sync Ecosystem — Full Reference

**Last updated:** 2026-03-02
**Machine:** Windows 11 Home Single Language 24H2 — user: `helde` (`LAP\helde`)

> This document is self-contained. Every config and script file's full content is
> embedded in §14 so any file can be recreated from this document alone.

---

## 1. Architecture Overview

```
C:\Users\helde\Repos\Bois        ← SOURCE (watched in real time)
        │
        ├─[RealTimeSync]─► run_mirror.bat on every change (5s idle buffer)
        │                        └─► robocopy /E /Z
        │                                 └─► C:\Sync\Mirror   (local mirror)
        │
        └─[Task Scheduler, every 5 min + boot]
                 └─► cloud_sync.ps1
                          └─► rclone sync
                                   └─► Backblaze B2
                                        bucket : helder-sync-mirror (root)
                                        └─► /logs (log backup, copy-only)
```

**Security layers (applied 2026-03-01/02):**
```
Authentication    → Account lockout: 5 attempts, 30 min freeze
Remote Access     → RDP / WinRM / RemoteRegistry / SMB2 all disabled
File Permissions  → C:\Sync\Config locked to LAP\helde + SYSTEM + Admins only
Network Logging   → Windows Firewall logs all connections → firewall.log
Screen Lock       → Auto-lock after 5 min idle, password required on wake
B2 Credentials    → Scoped app key (helder-sync-mirror only, Read+Write)
Monitoring        → FolderSyncAuditor service + DailySecurityCheck task
```

---

## 2. Software Installed

| Tool | Version | Path |
|---|---|---|
| Rclone | v1.73.1 | `C:\Tools\Rclone\rclone.exe` |
| FreeFileSync | 14.7 | `C:\Program Files\FreeFileSync\FreeFileSync.exe` |
| RealTimeSync | 14.7 | `C:\Program Files\FreeFileSync\RealTimeSync.exe` |
| NSSM | 2.24 | `C:\Tools\NSSM\nssm.exe` |

`C:\Tools\Rclone` is on the **system PATH** (registry: `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment`).

---

## 3. Folder Structure

| Path | Purpose |
|---|---|
| `C:\Users\helde\Repos\Bois` | **Source** — folder being watched and synced |
| `C:\Sync\Mirror` | Local mirror — robocopy exact copy of Source |
| `C:\Sync\Logs` | All log files |
| `C:\Sync\Config` | All scripts, configs, encrypted credentials — **ACL locked** |
| `C:\Tools\Rclone\` | Rclone binary |
| `C:\Tools\NSSM\` | NSSM binary |
| `%USERPROFILE%\Documents\SecurityScripts\` | DailySecurityCheck + AutoCleanup scripts |

---

## 4. Cloud Storage (Backblaze B2)

| Item | Value |
|---|---|
| Provider | Backblaze B2 |
| Account | heldercsousa@yahoo.com.br |
| Bucket | `helder-sync-mirror` |
| Visibility | Private |
| Encryption | SSE-B2 enabled (AES-256 at rest) |
| Object Lock | Disabled (sync requires deletes — use B2 Lifecycle Rules instead) |
| Rclone remote name | `cloudsync` |
| Sync target | `cloudsync:helder-sync-mirror` (bucket root) |
| Log backup | `cloudsync:helder-sync-mirror/logs` (copy-only, never deleted by sync) |
| Free tier | 10 GB storage, 1 GB/day download |
| Paid rate (overage) | $0.006/GB/month |

### API Key scope
The Application Key in `rclone.conf` is scoped to:
- Bucket `helder-sync-mirror` only
- Read + Write, no expiry
- A leaked key cannot touch billing, other buckets, or account management

### Credentials
| File | Content |
|---|---|
| `C:\Sync\Config\credentials.enc` | DPAPI-encrypted blob (email, key ID, app key) — only decryptable by Windows user `helde` on this machine |
| `C:\Sync\Config\rclone.conf` | Rclone config with API key in plaintext — **never commit to any repo or gist** |

**To read credentials on demand:**
```powershell
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\read_credentials.ps1
```

> ⚠ If Windows is reinstalled or the user account changes, `credentials.enc` cannot be
> decrypted. Regenerate an API key from backblaze.com and re-run setup.

---

## 5. File Inventory

### Active files (do not delete)

| File | Used by | Purpose |
|---|---|---|
| `rclone.conf` | `cloud_sync.ps1` | Rclone B2 remote definition + API key |
| `cloud_sync.ps1` | Task `FolderSync-CloudBackup` | Rclone sync + log rotation + mirror cleanup (7-day) + source folder retention (7-day, date-name based) + self-healing firewall+DNS attack detection (2026-03-15) |
| `cloud_sync.bat` | Manual trigger | Same as .ps1 but via cmd (manual use only) |
| `run_mirror.bat` | RealTimeSync | Runs robocopy mirror on file change (daily log rotation) |
| `realtime.ffs_real` | RealTimeSync at startup | Watcher config — folder + delay + command |
| `wdog.ps1` | Task `FolderSync-Watchdog` + NSSM service | Watchdog loop |
| `auditor.ps1` | NSSM service `FolderSyncAuditor` | Monitors file changes, remote access, service tampering |
| `credentials.enc` | `read_credentials.ps1` | Only copy of encrypted credentials |
| `read_credentials.ps1` | User on demand | Decrypts and prints credentials |
| `check_status.ps1` | User on demand | FolderSync full health check — tasks, services, rclone, logs |
| `check_camera.ps1` | User on demand | Camera/Yawcam health check — process, device, recordings, startup, CAM-2 relay |
| `cam2_relay.ps1` | Registry Run `YawcamCam2Relay` (hidden, at login) | VLC relay: Tapo C100 RTSP → MJPEG HTTP `127.0.0.1:8161` for Yawcam |
| `cam2.conf` | Read by `cam2_relay.ps1` | CAM-2 credentials (plaintext, ACL-protected, **gitignored**) |
| `health_check_all.ps1` | User on demand / `check_health.bat` / `/project:health` | Combined FolderSync + Camera health check; exits 0 all pass, 1 any fail; writes to `C:\Sync\Logs\ecosystem\health_check_YYYY-MM-DD.log` |
| `setup_update.ps1` | Fresh install / new device (primary) | Centralized setup v3: state-aware (stops/restarts ecosystem), all hardening + task registration + Yawcam registry (Step 14 uses `start_yawcam.bat` wrapper to set correct working dir) |
| `setup_all.ps1` | Legacy reference | Setup v2 — kept for reference; `setup_update.ps1` is now primary |
| `start_ecosystem.ps1` | `/motionSentinel-start` / Manual / `setup_update.ps1` | Starts all components; gate: `#Requires -RunAsAdministrator`; writes `.ecosystem_state = running`; verifies Yawcam+VLC PIDs; enforces HKCU\Run entries. Yawcam wait 8s + checks both yawcam/javaw process names; CAM-2 wait 5s (2026-03-15). |
| `stop_ecosystem.ps1` | `/motionSentinel-stop` / Manual / `setup_update.ps1` | Stops all components in reverse; gate: `#Requires -RunAsAdministrator`; writes `.ecosystem_state = stopped` |
| `pause_camera.ps1` | `/motionSentinel-pause` / Manual | Stops Yawcam; gate: `#Requires -RunAsAdministrator`; sets `.camera_paused` flag |
| `resume_camera.ps1` | `/motionSentinel-resume` / Manual | Starts Yawcam; gate: `#Requires -RunAsAdministrator`; removes `.camera_paused` flag |
| `enable_file_auditing.ps1` | One-time setup | Activates SACL on watched folder for user attribution in logs |
| `fix_firewall_b2.ps1` | `fix_b2_firewall.bat` (admin) | Removes malicious outbound BLOCK firewall rules targeting B2 IPs |
| `fix_power_motion.ps1` | Manual (admin) | Restores power settings for motion detection: switches to Balanced plan, disables USB Selective Suspend (AC+DC), sleep/hibernate=Never, display=600s AC |
| `auto_commit_logs.ps1` | Task `FolderSync-GitCommitLogs` (daily 23:30) | Commits dirty Logs/ files to git; skips if nothing changed or git is locked; logs to `ecosystem_YYYY-MM-DD.log` |
| `ECOSYSTEM_REPORT.md` | — | This document |

### Remediation scripts (root of `C:\Sync\`)

| File | Purpose |
|---|---|
| `fix_b2_firewall.bat` | Self-elevating UAC launcher — removes attacker firewall rules blocking B2 |
| `fix_git_acl.bat` | Self-elevating UAC launcher — strips Deny ACL from `.git\` recursively (fixes git lock) |
| `fix_git_lock.bat` | Self-elevating UAC launcher — force-deletes `.git\index.lock` when ACL prevents removal |
| `check_health.bat` | Double-click launcher — runs `health_check_all.ps1` in a paused window |

### Evidence folder (`C:\Sync\Evidence\`)

| File | Purpose |
|---|---|
| `YYYY-MM-DD_description.md` | Forensic evidence records — **NEVER delete or overwrite** |
| `2026-03-06_firewall_tampering.md` | Evidence of attacker-added B2 firewall block rules |

### Recovery scripts (keep, run only if something breaks)

| File | When to run |
|---|---|
| `fix_watchdog_task.ps1` | Watchdog task missing or running as wrong user |
| `install_service.ps1` | FolderSyncWatchdog NSSM service missing or removed |
| `install_auditor_service.ps1` | FolderSyncAuditor NSSM service missing or removed |
| `register_tasks.ps1` | Cloud backup task missing (follow with fix_watchdog_task.ps1) |

### Security scripts (in %USERPROFILE%\Documents\SecurityScripts\)

| File | Purpose |
|---|---|
| `DailySecurityCheck.ps1` | Daily security scan — processes, ports, remote tools, unknown devices |
| `AutoCleanup.ps1` | Automated cleanup triggered by DailySecurityCheck |

### Camera scripts (in `C:\Sync\Config\`)

These scripts were relocated from `C:\Program Files (x86)\Yawcam\` to `C:\Sync\Config\` so they are inside git and ACL-protected.

| File | Used by | Purpose |
|---|---|---|
| `yawcam_monitor_v4.ps1` | Registry Run `YawcamMonitor` via `start_monitor.ps1` | Infinite-loop monitor: checks for recent .avi recordings, restarts Yawcam + resets webcam PnP device if frozen. 60s interval, 600s restart cooldown. |
| `start_monitor.ps1` | Registry Run `YawcamMonitor` | Boot launcher: waits 30s for system to stabilize, then starts `C:\Sync\Config\yawcam_monitor_v4.ps1` hidden |
| `start_yawcam.bat` | Registry Run `Yawcam` (replaces direct .exe entry) | `cd /d` to Yawcam dir then starts Yawcam.exe — fixes launcher.cfg not found error on boot |

### Claude Code tooling (in `C:\Sync\.claude\`)

These files configure the Claude Code AI assistant for this project. Restore from this section if the `.claude/` directory is lost.

| File | Purpose |
|---|---|
| `.claude/settings.json` | Per-project permissions (allow/deny), env vars for key paths, MCP server config |
| `.claude/commands/commit.md` | `/project:commit` slash command — minimal-token git commit workflow |
| `.claude/commands/check.md` | `/project:check` slash command — FolderSync health check + auto-diagnosis (still active; health.md is primary) |
| `.claude/commands/camera-check.md` | `/project:camera-check` slash command — camera health check + auto-diagnosis (still active; health.md is primary) |
| `.claude/commands/camera-ecosystem.md` | `camera-ecosystem` skill — comprehensive camera/motion detection environment reference |
| `.claude/commands/review.md` | `review` skill — self-healing post-task verification (RULE 3): 4-cycle fix loop, escalates to `known_issues.md` on failure; now includes Phase 0 reminder + syntax parse step |
| `.claude/commands/health.md` | `health` skill — UNIFIED ecosystem health check; respects `.ecosystem_state` and `.camera_paused` flags; includes lifecycle control commands |
| `.claude/commands/motionSentinel-start.md` | `/motionSentinel-start` slash command — runs `start_ecosystem.ps1` |
| `.claude/commands/motionSentinel-stop.md` | `/motionSentinel-stop` slash command — runs `stop_ecosystem.ps1` |
| `.claude/commands/motionSentinel-pause.md` | `/motionSentinel-pause` slash command — runs `pause_camera.ps1` |
| `.claude/commands/motionSentinel-resume.md` | `/motionSentinel-resume` slash command — runs `resume_camera.ps1` |
| `check_health.bat` | Double-click launcher at `C:\Sync\check_health.bat` — runs `health_check_all.ps1` in a paused window |

---

## 6. Local Mirror (RealTimeSync + robocopy)

**Trigger:** RealTimeSync detects any change in Source → waits 5s idle → runs `run_mirror.bat`

**robocopy flags used:**
- `/E` - Copia subdiretórios, incluindo vazios (não deleta no destino)
- `/Z` - Modo restartable (essencial para vídeos se a cópia for interrompida)
- `/R:2` — Apenas 1 tentativa para evitar logs gigantes
- `/W:5` — Espera curta entre tentativas
- `/LOG+` — append to daily rotating log file (`mirror_YYYY-MM-DD.log`)
- `/NP /NDL` — no progress output, no directory listing
- `/NFL` — No File List: suppresses per-file output, keeps summary only (prevents log bloat)

**Log:** `C:\Sync\Logs\mirror\mirror_YYYY-MM-DD.log` (rotates daily, deleted after 30 days by cloud_sync.ps1)

**To start RealTimeSync manually:**
```powershell
Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
    -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden
```

**To force immediate mirror sync:**
```powershell
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:5  /NP /NDL /NC /NS
```

---

## 7. Cloud Sync (Rclone via Task Scheduler)

**Trigger:** Every 5 minutes + on system boot

**To trigger manually:**
```powershell
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1
```

**To verify B2 contents:**
```bat
C:\Tools\Rclone\rclone.exe lsd cloudsync:helder-sync-mirror --config C:\Sync\Config\rclone.conf
```

**Log:** `C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log` (rotates daily, deleted after 30 days)

---

## 8. Scheduled Tasks

| Task | Runs As | Trigger | Action |
|---|---|---|---|
| `FolderSync-CloudBackup` | SYSTEM | Every 5 min + boot | `cloud_sync.ps1` via PowerShell |
| `FolderSync-Watchdog` | `LAP\helde` (interactive) | Every 3 min + logon | `wdog.ps1` via PowerShell |
| `Verificacao Automatica de Seguranca` | `LAP\helde` | Daily 09:00 | `DailySecurityCheck.ps1` |

> ⚠ **Critical:** `FolderSync-Watchdog` MUST run as `LAP\helde` (interactive user), NOT SYSTEM.
> SYSTEM has no desktop session and cannot launch GUI apps like RealTimeSync.
> Use `fix_watchdog_task.ps1` to restore it — never `register_tasks.ps1` for the watchdog.

Both sync tasks: hidden, restart on failure (3 attempts, 1 min apart).

**Verify tasks:**
```powershell
Get-ScheduledTask -TaskName "FolderSync-CloudBackup" | Select TaskName, State
Get-ScheduledTask -TaskName "FolderSync-Watchdog"    | Select TaskName, State
Get-ScheduledTask -TaskName "Verificacao Automatica de Seguranca" | Select TaskName, State
```

---

## 9. Watchdog & Resilience (3 layers)

### Layer 1 — Scheduled Task `FolderSync-Watchdog`
- Runs `wdog.ps1` every 3 min + on logon
- Runs as `LAP\helde` (interactive)
- Checks RealTimeSync process — starts it if missing
- Checks `FolderSync-CloudBackup` task state — re-enables if disabled

### Layer 2 — Windows Service `FolderSyncWatchdog` (NSSM)
- Display name: `Folder Sync Watchdog Service`
- Wraps `wdog.ps1` as native Windows service
- Start type: Automatic — starts at boot, before user login
- Independent of Task Scheduler

```powershell
Get-Service FolderSyncWatchdog                # check status
Restart-Service FolderSyncWatchdog            # restart
# reinstall:
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_service.ps1
```

### Layer 3 — Startup Registry
RealTimeSync launched automatically on every user login:
```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
  FolderSyncRealTime = "C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"
```

**Verify:**
```powershell
(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run").FolderSyncRealTime
```

**Restore if missing:**
```powershell
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "FolderSyncRealTime" `
    -Value '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
```

---

## 10. Log Files

| Log | Path | Written by | Rotation |
|---|---|---|---|
| Cloud sync | `C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log` | Rclone | Daily file, deleted after 30 days |
| Local mirror | `C:\Sync\Logs\mirror\mirror_YYYY-MM-DD.log` | Robocopy | Daily file, deleted after 30 days |
| Watchdog | `C:\Sync\Logs\services\watchdog.log` | `wdog.ps1` | NSSM rotation at 1MB |
| File audit | `C:\Sync\Logs\audit\file_audit_YYYY-MM-DD.log` | `auditor.ps1` | Daily file |
| Security audit | `C:\Sync\Logs\security\security_audit_YYYY-MM-DD.log` | `auditor.ps1` | Daily file |
| Firewall | `C:\Sync\Logs\security\firewall.log` | Windows Firewall | Max 8MB, rotates to firewall.log.old |
| Auditor service stdout | `C:\Sync\Logs\services\auditor_svc.log` | NSSM | Rotation at 2MB |
| Auditor service stderr | `C:\Sync\Logs\services\auditor_svc_err.log` | NSSM | Rotation at 2MB |
| Daily security check | `%USERPROFILE%\Documents\SecurityCheck_Log.txt` | DailySecurityCheck.ps1 | Appended |

> ⚠ `firewall.log` is owned by SYSTEM. Read permission must be granted manually:
> `icacls "C:\Sync\Logs\firewall.log" /grant:r "LAP\helde:(R)"`
> This is done automatically by `setup_all.ps1`.

---

## 11. Full Health Check

```powershell
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1
```

---

## 12. Recovery Procedures

| Problem | Fix |
|---|---|
| RealTimeSync not running | `Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden` |
| Mirror out of sync | `robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:5  /NP /NDL /NC /NS` |
| Force cloud sync now | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1` |
| Watchdog task wrong user | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\fix_watchdog_task.ps1` |
| FolderSyncWatchdog service missing | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_service.ps1` |
| FolderSyncAuditor service missing | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_auditor_service.ps1` |
| Cloud backup task missing | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\register_tasks.ps1` |
| Startup registry missing | See §9 Layer 3 restore command |
| Cannot read firewall.log | `icacls "C:\Sync\Logs\firewall.log" /grant:r "LAP\helde:(R)"` |
| Setting up new device | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\setup_all.ps1` |
| B2 sync blocked (connectex error) | Attacker firewall rule detected — double-click `C:\Sync\fix_b2_firewall.bat` (requires UAC) |
| git index.lock can't be deleted | ACL trap on `.git\` — run `C:\Sync\fix_git_acl.bat` (UAC), then `Remove-Item -Force "C:\Sync\.git\index.lock"` in PS7 |
| git operations all fail after setup_all | `setup_all.ps1` Step 4.3 auto-liberates `.git\` recursively — rerun if needed |

### Rotate Backblaze API key
1. Go to backblaze.com → App Keys → Add Application Key
2. Name: `rclone-nitro5`, Bucket: `helder-sync-mirror`, Access: Read+Write
3. Copy Key ID and Application Key immediately (shown only once)
4. Edit `C:\Sync\Config\rclone.conf` — update `account` (Key ID) and `key` (App Key)
5. Test: `C:\Tools\Rclone\rclone.exe lsd cloudsync: --config C:\Sync\Config\rclone.conf`
6. Recreate `credentials.enc` (see §14 encrypt_creds.ps1)

---

## 13. Known Issues & Gotchas

| Topic | Note |
|---|---|
| Watchdog task must run as user | SYSTEM cannot launch GUI apps. Always use `fix_watchdog_task.ps1`. |
| robocopy exit code 1 | Normal — means files were copied successfully. Not an error. |
| Rclone deletes from B2 | `rclone sync` mirrors deletions. B2 charges 1-day minimum per file. |
| `/MIR` deletes from Mirror | Intentional — Mirror is an exact copy of Source. |/S
| DPAPI credentials tied to user | `credentials.enc` only works for user `helde` on this machine. |
| `rclone.conf` contains API key | Plaintext — never upload to any public repo or gist. |
| B2 free tier | 10 GB free. Monitor at backblaze.com if syncing large video files. |
| `realtime.ffs_real` XmlFormat | RealTimeSync 14.7 rewrites to `XmlFormat="23"` on save — normal, not an error. |
| Logs excluded from sync | `--exclude "logs/**"` prevents rclone sync from deleting logs in B2. Logs uploaded separately via `rclone copy`. |
| firewall.log owned by SYSTEM | Run `icacls "C:\Sync\Logs\firewall.log" /grant:r "LAP\helde:(R)"` after reboot or log rotation. setup_all.ps1 automates this. |
| mirror.log (old) | Old non-rotating mirror.log archived as `mirror_archive_YYYY-MM-DD.log`. Safe to delete. |
| B2 versioning | B2 keeps multiple versions of files. Set Lifecycle Rules on bucket to "Keep only last version" to control storage costs. |
| SMB2 disabled | Disabling SMB2 may affect local network file sharing if needed. Re-enable with: `Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force` |
| Firewall B2 blocking (attacker) | Symptom: `connectex: socket access forbidden` in cloud_sync log. Attacker adds outbound BLOCK rules for B2 IPs (104.153.233.180, 149.137.142.15). Fix: `fix_b2_firewall.bat`. Save evidence to `C:\Sync\Evidence\` FIRST. |
| .git ACL trap (git lock fails) | `setup_all.ps1` Deny Delete ACL propagates into `.git\` if rerun. Step 4.3 uses `icacls /T` to fix recursively. `Set-Acl` alone is NOT sufficient — must use `icacls /T` for recursive removal. |
| Evidence files are immutable | `C:\Sync\Evidence\` is ACL-protected (Deny Delete). Files can never be deleted or modified — by design. Add new files only. Restored by `setup_all.ps1` Step 4.4. |
| PS7 vs PS5 command differences | Machine runs PowerShell 7. `del /F /Q` does NOT work — use `Remove-Item -Force`. `$_` in Where-Object via Bash causes extglob interference — always use temp .ps1 files. |
| Claude Code admin barrier | Bash tool runs as regular user. Firewall/ACL/service ops need admin. Run Claude Code as Administrator to remove this barrier. Until then use self-elevating .bat files. |

---

## 14. Security Hardening (applied 2026-03-01/02)

### Layer 1 — Account Lockout
```powershell
net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30
```
> Takes effect after reboot.

### Layer 2 — Remote Access Disabled
```powershell
# RDP
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" fDenyTSConnections 1
# WinRM
Disable-PSRemoting -Force
Stop-Service WinRM -Force; Set-Service WinRM -StartupType Disabled
# RemoteRegistry
Set-Service RemoteRegistry -StartupType Disabled; Stop-Service RemoteRegistry -Force
# SMB2
Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force
```

### Layer 3 — C:\Sync\Config ACL (locked to user + SYSTEM + Admins)
```powershell
icacls C:\Sync\Config /inheritance:r
icacls C:\Sync\Config /remove:g "Everyone"
icacls C:\Sync\Config /remove:g "BUILTIN\Users"
icacls C:\Sync\Config /grant:r "LAP\helde:(OI)(CI)F"
icacls C:\Sync\Config /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F"
icacls C:\Sync\Config /grant:r "BUILTIN\Administradores:(OI)(CI)F"
```

### Layer 4 — Windows Firewall Logging
```powershell
netsh advfirewall set allprofiles logging droppedconnections enable
netsh advfirewall set allprofiles logging allowedconnections enable
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\firewall.log"
netsh advfirewall set allprofiles logging maxfilesize 8192
# Fix read permission for user
icacls "C:\Sync\Logs\firewall.log" /grant:r "LAP\helde:(R)"
```

### Layer 5 — Auto-lock (5 minutes)
```powershell
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300
powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300
powercfg /setactive SCHEME_CURRENT
powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
```

### Layer 6 — B2 Scoped Key
- Key scoped to bucket `helder-sync-mirror` only
- Read+Write, no expiry
- Master key not stored anywhere — only scoped key in rclone.conf

### Layer 7 — Evidence Folder (ACL-protected, tamper-proof)
```
C:\Sync\Evidence\ — Deny Delete (recursive, Everyone)
```
- Forensic evidence files cannot be deleted or overwritten
- Restored automatically by `setup_all.ps1` Step 4.4
- Naming: `YYYY-MM-DD_brief-description.md`
- Always commit to git immediately after adding evidence

### Layer 8 — .git Liberation (git operations must always work)
```powershell
# setup_all.ps1 Step 4.3 — MUST use icacls /T, not Set-Acl (not recursive)
icacls "C:\Sync\.git" /remove:d "*S-1-1-0" /T /Q   # Everyone
icacls "C:\Sync\.git" /remove:d "*S-1-5-32-545" /T /Q  # Users
```

> **Pending:** B2 Object Lock / Lifecycle Rules (7-day retention via Backblaze web UI)
> **Pending:** BIOS password on Acer Nitro 5
> **Pending:** Windows Hello PIN (blocked by org policy — resolve via Microsoft account portal)

---

## 15. Full File Contents (for restoration)

> Recreate any file by copying the content block below into a new file at the stated path.

---

### `C:\Sync\Config\fix_power_motion.ps1`
> Restores Windows power settings required for continuous motion detection.
> Run as Administrator. Idempotent. Switches plan to Balanced, disables USB Selective Suspend (AC+DC), sets sleep/hibernate to Never, display timeout to 600s AC / 120s DC.
> Evidence of tampering: 2026-05-28 power plan found as Power Saver (SCHEME_MAX), USB Suspend re-enabled.

```powershell
#Requires -RunAsAdministrator
# fix_power_motion.ps1 - restores power settings required for continuous motion detection
# Idempotent: safe to run multiple times
# Context: USB Selective Suspend was found re-enabled (0x1) on 2026-05-28, causing webcam dropout

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host "=== Motion Detection Power Settings Repair ===" -ForegroundColor Cyan
Write-Host "    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# 1. Switch to Balanced plan (away from Power Saver / SCHEME_MAX)
Write-Step "Activating Balanced power plan (away from Power Saver)"
try {
    powercfg /setactive SCHEME_BALANCED
    Write-OK "Balanced plan active"
} catch {
    Write-Fail "Could not activate Balanced plan: $_"
    exit 1
}

# 2. USB Selective Suspend - DISABLE on both AC and DC
Write-Step "Disabling USB Selective Suspend (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    Write-OK "USB Selective Suspend = Disabled (AC + DC)"
} catch {
    Write-Fail "USB Selective Suspend update failed: $_"
    exit 1
}

# 3. Sleep - Never (0 seconds)
Write-Step "Setting Sleep to Never (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
    powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
    Write-OK "Sleep = Never (AC + DC)"
} catch {
    Write-Fail "Sleep setting failed: $_"
    exit 1
}

# 4. Hibernate - Never (0 seconds)
Write-Step "Setting Hibernate to Never (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
    powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
    Write-OK "Hibernate = Never (AC + DC)"
} catch {
    Write-Fail "Hibernate setting failed: $_"
    exit 1
}

# 5. Display turn off - 10 min (600s) AC, 2 min (120s) DC
Write-Step "Setting display timeout (600s AC / 120s DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 600
    powercfg /setdcvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 120
    Write-OK "Display off = 600s AC / 120s DC"
} catch {
    Write-Fail "Display setting failed: $_"
    exit 1
}

# 6. Apply all changes
Write-Step "Applying changes (powercfg /setactive SCHEME_CURRENT)"
powercfg /setactive SCHEME_CURRENT

Write-Host ""
Write-Host "=== Repair complete ===" -ForegroundColor Green
```

---

### `C:\Sync\Config\fix_firewall_b2.ps1`
> Removes attacker-added outbound BLOCK firewall rules that block Backblaze B2 connectivity.
> Run via `C:\Sync\fix_b2_firewall.bat` (self-elevating UAC). Requires Administrator.

```powershell
#Requires -RunAsAdministrator
# fix_firewall_b2.ps1 — Removes malicious outbound BLOCK rules for B2 IPs.

$LogFile = "C:\Sync\Logs\cloud_sync\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

Write-Host ""
Write-Host ">>> Removing malicious B2 firewall block rules" -ForegroundColor Cyan

$rulesToRemove = @("Block 104.153.233.180", "Block 149.137.142.15")

foreach ($rule in $rulesToRemove) {
    $existing = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction Stop
        Write-Host "  OK   Removed: $rule" -ForegroundColor Green
        Write-Log "SECURITY  Removed malicious outbound BLOCK firewall rule: $rule"
    } else {
        Write-Host "  INFO Not found: $rule" -ForegroundColor Yellow
        Write-Log "SECURITY  Firewall rule not found (skip): $rule"
    }
}

$remaining = @()
foreach ($rule in $rulesToRemove) {
    $check = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    if ($check) { $remaining += $rule }
}

if ($remaining.Count -eq 0) {
    Write-Host "  OK   All malicious rules removed. B2 connectivity restored." -ForegroundColor Green
    Write-Log "SECURITY  B2 firewall remediation complete. All block rules removed."
} else {
    $list = $remaining -join ", "
    Write-Host "  FAIL Rules still present: $list" -ForegroundColor Red
    Write-Log "SECURITY  WARNING: Some block rules could not be removed: $list"
}
```

---

### `C:\Sync\Config\rclone.conf`
> ⚠ Replace values with actual credentials from backblaze.com → App Keys

```ini
[cloudsync]
type = b2
account = YOUR_KEY_ID_HERE
key = YOUR_APP_KEY_HERE
hard_delete = false
```

---

### `C:\Sync\Config\cloud_sync.ps1`
> Rclone sync to Backblaze B2. Includes self-healing firewall detection+removal+retry, 3-phase ACL protection (7 days), source folder retention (7 days, date-name based), log rotation (30 days), mirror cleanup. Logs to `C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log`.
> Last updated: 2026-05-17

```powershell
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup, Source folder retention, and Log rotation automatically.
# Last updated: 2026-05-17 - Added FASE 3 source folder 7-day retention

$Rclone           = 'C:\Tools\Rclone\rclone.exe'
$Config           = 'C:\Sync\Config\rclone.conf'
$Source           = 'C:\Users\helde\Repos\Bois'
$Remote           = 'cloudsync:helder-sync-mirror'
$Mirror           = 'C:\Sync\Mirror'
$LogDir           = 'C:\Sync\Logs\cloud_sync'
$Log              = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror = 7
$DaysToKeepLogs   = 30

# Known malicious firewall rules that block Backblaze B2 sync
$MaliciousFirewallRules = @(
    'Block 104.153.233.180',
    'Block 149.137.142.15'
)

function Write-SyncLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $Log
}

function Remove-MaliciousFirewallRules {
    $removed = @()
    foreach ($ruleName in $MaliciousFirewallRules) {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            $removed += $ruleName
            Write-SyncLog "FIREWALL-HEAL  Removed malicious block rule: $ruleName"
        }
    }
    # Also scan for any unknown outbound BLOCK rules targeting B2 IP ranges
    $allBlockRules = Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' } |
        Where-Object { $_.DisplayName -notlike 'Block 0.0.0.0*' }
    foreach ($r in $allBlockRules) {
        $addr = ($r | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress
        if ($addr -match '104\.153\.|149\.137\.|backblaze') {
            Remove-NetFirewallRule -DisplayName $r.DisplayName -ErrorAction SilentlyContinue
            $removed += $r.DisplayName
            Write-SyncLog "FIREWALL-HEAL  Removed unknown B2 block rule: $($r.DisplayName) -> $addr"
        }
    }
    return $removed
}

# ============================================================
# STEP 1 - Pre-flight: check for known malicious firewall rules
# Remove before sync attempt to avoid wasted run
# ============================================================
Write-SyncLog "SYNC-START  Beginning cloud sync run"

$preRemoved = @()
foreach ($ruleName in $MaliciousFirewallRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule) {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        $preRemoved += $ruleName
        Write-SyncLog "FIREWALL-PREFLIGHT  Removed malicious block rule before sync: $ruleName"
    }
}
if ($preRemoved.Count -gt 0) {
    Write-SyncLog "FIREWALL-PREFLIGHT  WARNING: $($preRemoved.Count) malicious rule(s) were active at sync start - possible active attack"
}

# ============================================================
# STEP 2 - Run rclone sync, capture output for error detection
# ============================================================
$rcloneOutput = & $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --transfers 4 `
    --checkers 8 `
    --fast-list 2>&1

$rcloneExitCode = $LASTEXITCODE

# ============================================================
# STEP 3 - Detect firewall blocking pattern in rclone output
# If detected: remove rules, retry sync once
# ============================================================
$firewallBlocked = $false
if ($rcloneOutput -match 'connectex|socket access forbidden|access is forbidden|connect: permission denied') {
    $firewallBlocked = $true
    Write-SyncLog "FIREWALL-DETECT  Rclone reported connection blocked - checking firewall rules"

    $healed = Remove-MaliciousFirewallRules
    if ($healed.Count -gt 0) {
        Write-SyncLog "FIREWALL-HEAL  Removed $($healed.Count) malicious rule(s): $($healed -join ', ')"
        Write-SyncLog "FIREWALL-HEAL  Retrying sync after firewall repair"

        # Retry sync
        $rcloneOutput2 = & $Rclone sync $Source $Remote `
            --config $Config `
            --log-file $Log `
            --log-level INFO `
            --transfers 4 `
            --checkers 8 `
            --fast-list 2>&1

        $rcloneExitCode = $LASTEXITCODE

        if ($LASTEXITCODE -eq 0) {
            Write-SyncLog "FIREWALL-HEAL  Retry SUCCESS - sync completed after firewall repair"
        } else {
            Write-SyncLog "FIREWALL-HEAL  Retry FAILED (exit $LASTEXITCODE) - sync still failing after firewall repair"
            Write-SyncLog "FIREWALL-HEAL  Manual investigation required"
        }
    } else {
        Write-SyncLog "FIREWALL-DETECT  No known malicious rules found - unknown blocking cause"
        Write-SyncLog "FIREWALL-DETECT  Run check_status.ps1 and review firewall rules manually"
    }
} elseif ($rcloneOutput -match 'no such host|i/o timeout|dial tcp.*lookup') {
    # DNS-level attack: rogue DHCP server serving 127.0.0.1 as DNS (confirmed 2026-03-15)
    $dnsBlocked = $true
    Write-SyncLog "DNS-ATTACK-DETECT  Rclone reported DNS failure - possible rogue DNS/DHCP attack"

    # Check if Ethernet adapter has DHCP-assigned DNS (127.0.0.1 = rogue)
    $ethDns = (Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    Write-SyncLog "DNS-ATTACK-DETECT  Ethernet DNS: $($ethDns -join ', ')"

    # Test live resolution
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses('api.backblazeb2.com')
        Write-SyncLog "DNS-ATTACK-DETECT  api.backblazeb2.com resolves NOW: $($resolved -join ', ') - transient DNS issue"
    } catch {
        Write-SyncLog "DNS-ATTACK-DETECT  api.backblazeb2.com still FAILS to resolve - DNS attack may be active"
        Write-SyncLog "DNS-ATTACK-DETECT  Check: hosts file, Ethernet DNS settings, router DHCP config"
    }

    # Retry sync (DNS may have recovered if interface switched)
    Write-SyncLog "DNS-ATTACK-DETECT  Retrying sync after DNS diagnosis"
    $rcloneOutput2 = & $Rclone sync $Source $Remote `
        --config $Config `
        --log-file $Log `
        --log-level INFO `
        --transfers 4 `
        --checkers 8 `
        --fast-list 2>&1

    $rcloneExitCode = $LASTEXITCODE

    if ($LASTEXITCODE -eq 0) {
        Write-SyncLog "DNS-ATTACK-HEAL  Retry SUCCESS - sync completed after DNS recovery"
    } else {
        Write-SyncLog "DNS-ATTACK-FAIL  Retry FAILED (exit $LASTEXITCODE) - DNS still broken"
        Write-SyncLog "DNS-ATTACK-FAIL  Run: Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 1.1.1.1,8.8.8.8"
    }
} elseif ($rcloneExitCode -eq 0) {
    Write-SyncLog "SYNC-OK  Sync completed successfully (exit 0)"
} else {
    Write-SyncLog "SYNC-FAIL  Sync failed (exit $rcloneExitCode) - not a firewall error"
}

# ============================================================
# FASE 0 - Aplicar ACL Deny Delete em arquivos < 7 dias
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop
                $hasDeny = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }
                if (-not $hasDeny) {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
                        'Delete', 'None', 'None', 'Deny'
                    )
                    $acl.AddAccessRule($rule)
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch { }
        }
}

# ============================================================
# FASE 1 - Remover ACL Deny Delete de arquivos >= 7 dias
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop
                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }
                if ($denyRules) {
                    foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch { }
        }
}

# ============================================================
# FASE 2 - Deletar arquivos >= 7 dias
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ============================================================
# FASE 3 - Source folder retention
# Delete date-named subdirs in $Source older than $DaysToKeepMirror calendar days.
# Uses folder NAME as date (yyyy-MM-dd), ignoring file timestamps entirely,
# so whole-day folders are removed in one sync cycle with no B2 churn.
# ============================================================
$sourceThreshold = (Get-Date).Date.AddDays(-$DaysToKeepMirror)
Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $folderDate = $null
    $parsed = [datetime]::TryParseExact(
        $_.Name,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$folderDate
    )
    if ($parsed -and $folderDate -lt $sourceThreshold) {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-SyncLog "SOURCE-CLEANUP  Deleted $($_.Name)"
    }
}

# 4. cloud_sync log rotation - delete logs older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "cloud_sync_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. mirror log rotation - delete mirror_*.log older than DaysToKeepLogs
Get-ChildItem -Path 'C:\Sync\Logs\mirror' -Filter "mirror_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-SyncLog "SYNC-END  Cloud sync run complete"
```

---

### `C:\Sync\Config\cloud_sync.bat`
> Manual trigger only. Task Scheduler uses cloud_sync.ps1.

```bat
@echo off
set RCLONE=C:\Tools\Rclone\rclone.exe
set CONFIG=C:\Sync\Config\rclone.conf
set SOURCE=C:\Users\helde\Repos\Bois
set REMOTE=cloudsync:helder-sync-mirror

for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set LOG=C:\Sync\Logs\cloud_sync_%%d.log

"%RCLONE%" sync "%SOURCE%" "%REMOTE%" ^
    --config "%CONFIG%" ^
    --log-file "%LOG%" ^
    --log-level INFO ^
    --transfers 4 ^
    --checkers 8 ^
    --fast-list ^
    --exclude "logs/**"

"%RCLONE%" copy "C:\Sync\Logs" "%REMOTE%/logs" ^
    --config "%CONFIG%" ^
    --log-file "%LOG%" ^
    --log-level INFO ^
    --exclude "firewall.log" ^
    --exclude "firewall.log.old"
```

---

### `C:\Sync\Config\run_mirror.bat`
> Daily log rotation: creates `C:\Sync\Logs\mirror\mirror_YYYY-MM-DD.log`.

```bat
@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /E    = Copy subdirectories (including empty ones), do NOT delete from dest
:: /Z    = Restartable mode (essential for video files if copy is interrupted)
:: /R:1  = Retry only once to avoid massive logs
:: /W:2  = Short wait between retries
:: /NFL  = No File List - suppresses per-file output, keeps summary only (prevents log bloat)
:: /LOG+ = Append to DAILY rotating log (mirror_YYYY-MM-DD.log)
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror\mirror_%DATE%.log" /NP /NDL /NC /NS /NFL
```

---

### `C:\Sync\Config\realtime.ffs_real`
```xml
<?xml version="1.0" encoding="utf-8"?>
<FreeFileSync XmlType="REAL" XmlFormat="2">
    <Directories>
        <Item>C:\Users\helde\Repos\Bois</Item>
    </Directories>
    <Delay>5</Delay>
    <Commandline>C:\Sync\Config\run_mirror.bat</Commandline>
</FreeFileSync>
```

---

### `C:\Sync\Config\wdog.ps1`
```powershell
# FolderSync Watchdog
# Ensures RealTimeSync and cloud sync scheduled task are alive.
# Runs as "FolderSync Watchdog Service" via NSSM.

$LogFile = "C:\Sync\Logs\services\watchdog.log"
$RealTimeSync = "C:\Program Files\FreeFileSync\RealTimeSync.exe"
$RealTimeSyncConfig = "C:\Sync\Config\realtime.ffs_real"
$TaskName = "FolderSync-CloudBackup"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LogFile -Append | Out-Null
}

Write-Log "Watchdog started."

while ($true) {
    # --- Check RealTimeSync ---
    $rts = Get-Process -Name "RealTimeSync" -ErrorAction SilentlyContinue
    if (-not $rts) {
        Write-Log "RealTimeSync not running — starting."
        Start-Process -FilePath $RealTimeSync -ArgumentList "`"$RealTimeSyncConfig`"" -WindowStyle Hidden
    }

    # --- Check scheduled task is enabled ---
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.State -eq 'Disabled') {
        Write-Log "Task $TaskName was disabled — re-enabling."
        Enable-ScheduledTask -TaskName $TaskName | Out-Null
    }

    Start-Sleep -Seconds 180
}
```

---

### `C:\Sync\Config\read_credentials.ps1`
```powershell
Add-Type -AssemblyName System.Security
$encrypted = [System.IO.File]::ReadAllBytes('C:\Sync\Config\credentials.enc')
$plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $encrypted,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.Text.Encoding]::UTF8.GetString($plain)
```

---

### `C:\Sync\Config\fix_watchdog_task.ps1`
```powershell
# Re-register FolderSync-Watchdog to run as current user (not SYSTEM)
# so it can launch RealTimeSync as a visible GUI process

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1"

$triggers = @(
    $(New-ScheduledTaskTrigger -AtLogOn),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 3) -Once -At (Get-Date))
)

$settings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType Interactive `
    -RunLevel Highest

Unregister-ScheduledTask -TaskName "FolderSync-Watchdog" -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName "FolderSync-Watchdog" `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Principal $principal `
    -Force

Write-Host "Watchdog task re-registered to run as: $currentUser"
Write-Host "RealTimeSync can now be launched from watchdog."
```

---

### `C:\Sync\Config\install_service.ps1`
```powershell
$nssm = 'C:\Tools\NSSM\nssm.exe'
$svcName = 'FolderSyncWatchdog'

# Remove existing service if present
& $nssm stop $svcName 2>$null
& $nssm remove $svcName confirm 2>$null

# Install service
& $nssm install $svcName powershell.exe
& $nssm set $svcName AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
& $nssm set $svcName DisplayName 'Folder Sync Watchdog Service'
& $nssm set $svcName Description 'Monitors and restarts folder sync processes (RealTimeSync + cloud backup task).'
& $nssm set $svcName Start SERVICE_AUTO_START
& $nssm set $svcName AppStdout 'C:\Sync\Logs\services\watchdog_svc.log'
& $nssm set $svcName AppStderr 'C:\Sync\Logs\services\watchdog_svc_err.log'
& $nssm set $svcName AppRotateFiles 1
& $nssm set $svcName AppRotateBytes 1048576

Start-Service $svcName
Write-Host "Service '$svcName' installed and started"
```

---

### `C:\Sync\Config\install_auditor_service.ps1`
```powershell
# install_auditor_service.ps1
# Installs FolderSyncAuditor as an NSSM Windows service.
# Run as Administrator.

$nssm    = 'C:\Tools\NSSM\nssm.exe'
$svcName = 'FolderSyncAuditor'

if (-not (Test-Path $nssm)) {
    Write-Error "NSSM not found at $nssm"
    exit 1
}

# Stop and remove existing service if present
& $nssm stop   $svcName 2>$null
& $nssm remove $svcName confirm 2>$null
Start-Sleep -Seconds 2

# Install
& $nssm install $svcName powershell.exe
& $nssm set $svcName AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auditor.ps1'
& $nssm set $svcName DisplayName   'Folder Sync Security Auditor'
& $nssm set $svcName Description   'Monitors file changes, remote access, and service tampering for the FolderSync ecosystem.'
& $nssm set $svcName Start         SERVICE_AUTO_START
& $nssm set $svcName AppStdout     'C:\Sync\Logs\services\auditor_svc.log'
& $nssm set $svcName AppStderr     'C:\Sync\Logs\services\auditor_svc_err.log'
& $nssm set $svcName AppRotateFiles  1
& $nssm set $svcName AppRotateBytes  2097152   # 2 MB

# Restart delay: 30s (matches NSSM default, avoids false startup-gap triggers)
& $nssm set $svcName AppRestartDelay 30000

Start-Service $svcName
$svc = Get-Service $svcName -ErrorAction SilentlyContinue
Write-Host "Service '$svcName' installed - status: $($svc.Status)"
Write-Host ""
Write-Host "Next step: run enable_file_auditing.ps1 (as Administrator) to activate Security Event Log attribution."
```

---

### `C:\Sync\Config\register_tasks.ps1`
> ⚠ Only registers the cloud backup task correctly (as SYSTEM).
> For the watchdog task use `fix_watchdog_task.ps1` instead.

```powershell
# Task 1: Cloud sync via Rclone every 5 minutes (runs as SYSTEM)
$action1 = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument '-NoWindow -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
$trigger1 = @(
    $(New-ScheduledTaskTrigger -AtStartup),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
)
$settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
$principal1 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force
Write-Host "Task FolderSync-CloudBackup registered (runs cloud_sync.ps1)"
Write-Host "Now run fix_watchdog_task.ps1 for the watchdog task."
```

---

### `C:\Sync\Config\check_status.ps1`
```powershell
Write-Host "=== SCHEDULED TASKS ==="
Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue | Select-Object TaskName, State
Get-ScheduledTask -TaskName "FolderSync-Watchdog" -ErrorAction SilentlyContinue | Select-Object TaskName, State

Write-Host "`n=== TASK TRIGGERS & ACTIONS - CloudBackup ==="
$t = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue
if ($t) { $t.Triggers | Format-List; $t.Actions | Format-List }

Write-Host "=== TASK TRIGGERS & ACTIONS - Watchdog ==="
$t2 = Get-ScheduledTask -TaskName "FolderSync-Watchdog" -ErrorAction SilentlyContinue
if ($t2) { $t2.Triggers | Format-List; $t2.Actions | Format-List }

Write-Host "`n=== SERVICES ==="
Get-Service FolderSyncWatchdog  -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType
Get-Service FolderSyncAuditor   -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType

Write-Host "`n=== REGISTRY STARTUP ==="
(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue).FolderSyncRealTime

Write-Host "`n=== REALTIMESYNC PROCESS ==="
Get-Process RealTimeSync -ErrorAction SilentlyContinue | Select-Object Name, Id

Write-Host "`n=== RCLONE VERSION ==="
& "C:\Tools\Rclone\rclone.exe" version 2>&1 | Select-Object -First 1

Write-Host "`n=== SOURCE FOLDER SIZE ==="
$sz = (Get-ChildItem "C:\Users\helde\Repos\Bois" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host ("{0:N1} MB  ({1} files)" -f ($sz/1MB), (Get-ChildItem "C:\Users\helde\Repos\Bois" -Recurse -File -ErrorAction SilentlyContinue).Count)

Write-Host "`n=== MIRROR FOLDER SIZE ==="
$sz2 = (Get-ChildItem "C:\Sync\Mirror" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host ("{0:N1} MB  ({1} files)" -f ($sz2/1MB), (Get-ChildItem "C:\Sync\Mirror" -Recurse -File -ErrorAction SilentlyContinue).Count)

Write-Host "`n=== CONFIG FILES ==="
Get-ChildItem "C:\Sync\Config" | Format-Table Name, @{N="Size(KB)";E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize

Write-Host "`n=== LOG FILES ==="
Get-ChildItem "C:\Sync\Logs" -ErrorAction SilentlyContinue | Format-Table Name, @{N="Size(KB)";E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize

Write-Host "`n=== PATH INCLUDES RCLONE ==="
[Environment]::GetEnvironmentVariable("PATH","Machine") -split ";" | Where-Object { $_ -like "*rclone*" -or $_ -like "*Rclone*" }

Write-Host "`n=== RCLONE CONF (sanitized) ==="
Get-Content "C:\Sync\Config\rclone.conf" | ForEach-Object {
    if ($_ -match "^key") { "  key = ***REDACTED***" } else { $_ }
}

Write-Host "`n=== CLOUD SYNC STATUS (today) ==="
$todayLog = "C:\Sync\Logs\cloud_sync\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $todayLog) {
    $syncLines = Get-Content $todayLog
    # Show last sync result
    $lastEnd   = $syncLines | Where-Object { $_ -match 'SYNC-(OK|FAIL|END)|FIREWALL' } | Select-Object -Last 1
    if ($lastEnd) { Write-Host "  Last event: $lastEnd" }

    # Show any FAIL or FIREWALL events today
    # Exclude benign camera race condition: rclone can't upload a .avi Yawcam is still writing
    $errorLines = $syncLines | Where-Object {
        $_ -match 'SYNC-FAIL|FIREWALL-DETECT|FIREWALL-HEAL|connectex|socket access forbidden|error|Error'
    } | Where-Object {
        $_ -notmatch 'size changed|being updated|source file is being updated'
    }
    if ($errorLines) {
        Write-Host "  SYNC ERRORS / FIREWALL EVENTS today:" -ForegroundColor Yellow
        $errorLines | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    } else {
        Write-Host "  No errors or firewall events today" -ForegroundColor Green
    }

    # Show last 5 lines for context
    Write-Host "  --- Last 5 lines ---"
    $syncLines | Select-Object -Last 5
} else {
    Write-Host "(no log yet for today: $todayLog)"
}

Write-Host "`n=== LAST 5 LINES WATCHDOG LOG ==="
Get-Content "C:\Sync\Logs\services\watchdog.log" -ErrorAction SilentlyContinue | Select-Object -Last 5

Write-Host "`n=== LAST 5 LINES FILE AUDIT LOG (today) ==="
$fileLog = "C:\Sync\Logs\audit\file_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $fileLog) {
    Get-Content $fileLog | Select-Object -Last 5
} else {
    Write-Host "(no file audit log yet for today: $fileLog)"
}

Write-Host "`n=== LAST 5 LINES SECURITY AUDIT LOG (today) ==="
$secLog = "C:\Sync\Logs\security\security_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $secLog) {
    Get-Content $secLog | Select-Object -Last 5
} else {
    Write-Host "(no security audit log yet for today: $secLog)"
}

Write-Host "`n=== FIREWALL TAMPERING CHECK (B2 block rules) ==="
$b2Rules = @("Block 104.153.233.180", "Block 149.137.142.15")
$found = @()
foreach ($r in $b2Rules) {
    $rule = Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue
    if ($rule) { $found += $r }
}
if ($found.Count -gt 0) {
    Write-Host "  ALERT  Malicious B2 block rules ACTIVE: $($found -join ', ')" -ForegroundColor Red
    Write-Host "  ACTION Run C:\Sync\fix_b2_firewall.bat as Administrator to remove them" -ForegroundColor Yellow
} else {
    Write-Host "  OK     No malicious B2 block rules found" -ForegroundColor Green
}

Write-Host "`n=== EVIDENCE FOLDER ==="
$evCount = (Get-ChildItem "C:\Sync\Evidence" -ErrorAction SilentlyContinue).Count
Write-Host "  $evCount evidence file(s) in C:\Sync\Evidence"
Get-ChildItem "C:\Sync\Evidence" -ErrorAction SilentlyContinue | Format-Table Name, LastWriteTime -AutoSize
```

---

### `C:\Sync\Config\setup_all.ps1`
> Centralized setup script — 15 steps. Run as Administrator on any Windows device.
> Place alongside DailySecurityCheck.ps1 and AutoCleanup.ps1 before running.
> Covers: log permissions, script updates, ACL hardening, DailySecurityCheck install,
> remote access disable, lockout policy, auto-lock, firewall logging,
> CloudBackup task, Watchdog task, FolderSyncWatchdog NSSM, FolderSyncAuditor NSSM,
> RealTimeSync startup registry, and file system auditing.

```powershell
#Requires -RunAsAdministrator
# =============================================================================
# setup_all.ps1 v2
# Centralized setup for FolderSync Ecosystem + Security Hardening
# Works on any Windows machine - detects current user automatically
# Run as Administrator from C:\Sync\Config\
# Place alongside: DailySecurityCheck.ps1, AutoCleanup.ps1
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$currentUser     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$sidAdmins       = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$sidAdminsAccount= $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value
$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Centralized Setup v2" -ForegroundColor Cyan
Write-Host "  Running as: $currentUser" -ForegroundColor Cyan
Write-Host "  Script dir: $scriptDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# =============================================================================
# STEP 1 - Firewall log read permissions
# =============================================================================
Write-Step "Step 1 - Firewall log read permissions"
foreach ($f in @("C:\Sync\Logs\firewall.log","C:\Sync\Logs\firewall.log.old")) {
    if (Test-Path $f) {
        icacls $f /grant:r "${currentUser}:(R)" | Out-Null
        Write-OK "Read access granted: $f"
    } else {
        Write-Warn "Not found (will be fixed when created): $f"
    }
}
icacls "C:\Sync\Logs" /grant:r "${currentUser}:(OI)(CI)(R)" | Out-Null
Write-OK "Future firewall logs readable by $currentUser"

# =============================================================================
# STEP 2 - Update run_mirror.bat with daily log rotation
# =============================================================================
Write-Step "Step 2 - Update run_mirror.bat (daily log rotation)"
$mirrorBat = "C:\Sync\Config\run_mirror.bat"
Set-Content -Path $mirrorBat -Encoding ASCII -Value @'
@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /E    = Copia subdiretórios, incluindo vazios (não deleta no destino)
:: /Z    = Modo restartable (essencial para vídeos se a cópia for interrompida)
:: /R:1  = Apenas 1 tentativa para evitar logs gigantes
:: /W:2  = Espera curta entre tentativas
:: /NFL  = No File List - suppresses per-file output, keeps summary only (prevents log bloat)
:: /LOG+ = Append ao log diário rotativo
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror\mirror_%DATE%.log" /NP /NDL /NC /NS /NFL
'@
Write-OK "run_mirror.bat updated -> mirror_YYYY-MM-DD.log"

# Archive old bloated mirror log if exists
$oldMirror = "C:\Sync\Logs\mirror"
if (Test-Path $oldMirror) {
    Rename-Item $oldMirror "C:\Sync\Logs\mirror_archive_$(Get-Date -Format 'yyyy-MM-dd').log" -ErrorAction SilentlyContinue
    Write-OK "Old mirror log archived"
}

# =============================================================================
# STEP 3 - Update cloud_sync.ps1 with 3-phase ACL protection
# =============================================================================
Write-Step "Step 3 - Update cloud_sync.ps1 (3-phase ACL protection for 7-day retention)"
$cloudSyncPs1 = "C:\Sync\Config\cloud_sync.ps1"
Set-Content -Path $cloudSyncPs1 -Encoding UTF8 -Value @'
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-03-03 - Added 3-phase ACL protection for 7-day file retention

$Rclone           = 'C:\Tools\Rclone\rclone.exe'
$Config           = 'C:\Sync\Config\rclone.conf'
$Source           = 'C:\Users\helde\Repos\Bois'
$Remote           = 'cloudsync:helder-sync-mirror'
$Mirror           = 'C:\Sync\Mirror'
$LogDir           = 'C:\Sync\Logs'
$Log              = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror = 7
$DaysToKeepLogs   = 30

# 1. Sync source folder to B2
# Config and Logs versioned via Git - not sent to B2
& $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --transfers 4 `
    --checkers 8 `
    --fast-list

# ============================================================
# FASE 0 - Aplicar ACL Deny Delete em arquivos < 7 dias
# Protege cada arquivo que ainda nao atingiu 7 dias de idade
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop
                
                # Verificar se ja tem ACL Deny Delete (evitar duplicado)
                $hasDeny = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }
                
                if (-not $hasDeny) {
                    # Aplicar ACL Deny Delete
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
                        'Delete',
                        'None',
                        'None',
                        'Deny'
                    )
                    $acl.AddAccessRule($rule)
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch {
                # Silencioso - arquivo pode ter sido deletado/movido
            }
        }
}

# ============================================================
# FASE 1 - Remover ACL Deny Delete de arquivos >= 7 dias
# Remove protecao de arquivos que atingiram 7 dias
# CRITICO: Fazer ANTES de tentar deletar (Fase 2)
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop
                
                # Encontrar regras Deny Delete de "Everyone"
                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }
                
                if ($denyRules) {
                    # Remover cada regra Deny Delete encontrada
                    foreach ($rule in $denyRules) {
                        $acl.RemoveAccessRule($rule) | Out-Null
                    }
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch {
                # Silencioso - arquivo pode ter sido deletado
            }
        }
}

# ============================================================
# FASE 2 - Deletar arquivos >= 7 dias
# Agora ACL foi removido em FASE 1, delete pode executar sem ERROR 5
# ============================================================
# 2. Mirror cleanup - delete files older than DaysToKeepMirror
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    
    # Cleanup de pastas vazias (apos deletar arquivos)
    Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. cloud_sync log rotation - delete logs older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "cloud_sync_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. mirror log rotation - delete mirror_*.log older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "mirror_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
'@
Write-OK "cloud_sync.ps1 updated (3-phase ACL protection: Mirror 7d retention + cleanup)"

# =============================================================================
# STEP 4 - Protect C:\Sync\Config + C:\Sync\Logs (RECURSIVE Deny Delete)
#          Liberate C:\Sync\.git for git management
# =============================================================================
Write-Step "Step 4 - Apply ACL protection (Config+Logs blocked recursively, .git liberated)"

# 4.1 - C:\Sync\Config - Block ALL deletions (folder + ALL files/subfolders RECURSIVE)
Write-Host "  Protecting C:\Sync\Config..." -ForegroundColor Cyan
$sidEveryone = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')
$aclConfig = Get-Acl "C:\Sync\Config"
$ruleConfig = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $sidEveryone,
    [System.Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles',
    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Deny
)
$aclConfig.AddAccessRule($ruleConfig)
Set-Acl -Path "C:\Sync\Config" -AclObject $aclConfig
Write-OK "C:\Sync\Config locked (Deny Delete - RECURSIVE on all files/subfolders)"

# 4.2 - C:\Sync\Logs - Block ALL deletions (folder + ALL files/subfolders RECURSIVE)
Write-Host "  Protecting C:\Sync\Logs..." -ForegroundColor Cyan
$aclLogs = Get-Acl "C:\Sync\Logs"
$ruleLogs = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $sidEveryone,
    [System.Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles',
    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Deny
)
$aclLogs.AddAccessRule($ruleLogs)
Set-Acl -Path "C:\Sync\Logs" -AclObject $aclLogs
Write-OK "C:\Sync\Logs locked (Deny Delete - RECURSIVE on all files/subfolders)"

# 4.3 - C:\Sync\.git - LIBERATE for git management (remove any Deny Delete rules)
Write-Host "  Liberating C:\Sync\.git..." -ForegroundColor Cyan
if (Test-Path "C:\Sync\.git") {
    $aclGit = Get-Acl "C:\Sync\.git"
    $denyRules = $aclGit.Access | Where-Object { $_.AccessControlType -eq 'Deny' }
    foreach ($rule in $denyRules) {
        $aclGit.RemoveAccessRule($rule) | Out-Null
    }
    Set-Acl -Path "C:\Sync\.git" -AclObject $aclGit
    Write-OK "C:\Sync\.git liberated (no Deny Delete - git can manage freely)"
} else {
    Write-Warn "C:\Sync\.git not found (will be created if git init is run)"
}

Write-OK "ACL protection complete: Config+Logs blocked RECURSIVELY, .git liberated"

# =============================================================================
# STEP 5 - DailySecurityCheck v7
# =============================================================================
Write-Step "Step 5 - Install DailySecurityCheck v7"
$secScriptsDir = "$env:USERPROFILE\Documents\SecurityScripts"
if (-not (Test-Path $secScriptsDir)) { New-Item -ItemType Directory -Path $secScriptsDir -Force | Out-Null }

foreach ($scriptName in @("DailySecurityCheck.ps1","AutoCleanup.ps1")) {
    $src = Join-Path $scriptDir $scriptName
    if (Test-Path $src) {
        Copy-Item $src "$secScriptsDir\$scriptName" -Force
        Write-OK "Copied $scriptName → $secScriptsDir"
    } else {
        Write-Warn "$scriptName not found next to setup_all.ps1 — copy manually to $secScriptsDir"
    }
}

$taskName  = "Verificacao Automatica de Seguranca"
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$secScriptsDir\DailySecurityCheck.ps1`""
$trigger   = New-ScheduledTaskTrigger -Daily -At "09:00"
$settings  = New-ScheduledTaskSettingsSet -Hidden -RunOnlyIfNetworkAvailable:$false
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-OK "Task registered: $taskName (daily 09:00)"

$shell    = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$([System.Environment]::GetFolderPath('Desktop'))\Verificar Seguranca.lnk")
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments  = "-ExecutionPolicy Bypass -File `"$secScriptsDir\DailySecurityCheck.ps1`""
$shortcut.Save()
Write-OK "Desktop shortcut created: Verificar Seguranca.lnk"

# =============================================================================
# STEP 6 - Disable remote access services
# =============================================================================
Write-Step "Step 6 - Disable remote access services"
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
Write-OK "RDP connections blocked"

foreach ($svc in @("RemoteRegistry","WinRM","TermService")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.StartType -ne 'Disabled') {
            Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            Write-OK "$svc disabled"
        } else {
            Write-OK "$svc already disabled"
        }
    }
}

try {
    Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force -ErrorAction SilentlyContinue
    Write-OK "SMB2 disabled"
} catch { Write-Warn "SMB2 disable failed: $_" }

# =============================================================================
# STEP 7 - Account lockout policy
# =============================================================================
Write-Step "Step 7 - Account lockout (5 attempts, 30 min)"
net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 | Out-Null
Write-OK "Lockout configured"

# =============================================================================
# STEP 8 - Screen auto-lock (5 minutes)
# =============================================================================
Write-Step "Step 8 - Screen auto-lock (5 minutes)"
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300 | Out-Null
powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE  CONSOLELOCK   1 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE  CONSOLELOCK   1 | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null
Write-OK "Auto-lock: 5 minutes, password required on wake"

# =============================================================================
# STEP 9 - Windows Firewall logging
# =============================================================================
Write-Step "Step 9 - Windows Firewall logging"
netsh advfirewall set allprofiles logging droppedconnections enable | Out-Null
netsh advfirewall set allprofiles logging allowedconnections enable | Out-Null
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\security\firewall.log" | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 8192 | Out-Null
Start-Sleep -Seconds 1
if (Test-Path "C:\Sync\Logs\security\firewall.log") {
    icacls "C:\Sync\Logs\security\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
    Write-OK "Firewall logging active + read permission set"
} else {
    Write-OK "Firewall logging active (log created on first connection)"
}

# =============================================================================
# STEP 10 - Register FolderSync-CloudBackup task (SYSTEM)
# NOTE: For new device only. Skip if task already exists and is correct.
# =============================================================================
Write-Step "Step 10 - FolderSync-CloudBackup task (SYSTEM, every 5 min)"
$existingBackup = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue

# Check if task exists and has CORRECT arguments (PowerShell with -NoWindow)
$needsRecreate = $false
if ($existingBackup) {
    $currentArgs = $existingBackup.Actions[0].Arguments
    $currentExec = $existingBackup.Actions[0].Execute
    
    # If running .bat or missing -NoWindow, force recreate
    if ($currentExec -like "*.bat" -or $currentArgs -notlike "*-NoWindow*") {
        Write-Warn "Task exists but uses .bat or missing -NoWindow — will recreate"
        $needsRecreate = $true
    }
}

if (-not $existingBackup -or $needsRecreate) {
    # Remove old task if it exists
    if ($existingBackup) {
        Unregister-ScheduledTask -TaskName "FolderSync-CloudBackup" -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    
    # Create with POWERSHELL (not .bat) and -NoWindow flag
    $action1   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoWindow -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
    $trigger1  = @(
        $(New-ScheduledTaskTrigger -AtStartup),
        $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
    )
    $settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $principal1= New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force | Out-Null
    Write-OK "Task FolderSync-CloudBackup registered (PowerShell with -NoWindow)"
} else {
    Write-OK "Task FolderSync-CloudBackup already exists with correct arguments"
}

# =============================================================================
# STEP 11 - Register FolderSync-Watchdog task (current user, interactive)
# NOTE: MUST run as current user — SYSTEM cannot launch RealTimeSync GUI
# =============================================================================
Write-Step "Step 11 - FolderSync-Watchdog task (current user, every 3 min)"
$action2   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
$trigger2  = @(
    $(New-ScheduledTaskTrigger -AtLogOn),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 3) -Once -At (Get-Date))
)
$settings2 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal2= New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Unregister-ScheduledTask -TaskName "FolderSync-Watchdog" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-Watchdog" -Action $action2 -Trigger $trigger2 -Settings $settings2 -Principal $principal2 -Force | Out-Null
Write-OK "Task FolderSync-Watchdog registered ($currentUser)"

# =============================================================================
# STEP 12 - Install FolderSyncWatchdog NSSM service
# =============================================================================
Write-Step "Step 12 - FolderSyncWatchdog NSSM service"
$nssm = 'C:\Tools\NSSM\nssm.exe'
if (Test-Path $nssm) {
    & $nssm stop   FolderSyncWatchdog 2>$null
    & $nssm remove FolderSyncWatchdog confirm 2>$null
    Start-Sleep 2
    & $nssm install FolderSyncWatchdog powershell.exe
    & $nssm set FolderSyncWatchdog AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
    & $nssm set FolderSyncWatchdog DisplayName   'Folder Sync Watchdog Service'
    & $nssm set FolderSyncWatchdog Description   'Monitors and restarts folder sync processes (RealTimeSync + cloud backup task).'
    & $nssm set FolderSyncWatchdog Start          SERVICE_AUTO_START
    & $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\services\watchdog_svc.log'
    & $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\services\watchdog_svc_err.log'
    & $nssm set FolderSyncWatchdog AppRotateFiles  1
    & $nssm set FolderSyncWatchdog AppRotateBytes  1048576
    Start-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
    $s = Get-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
    Write-OK "FolderSyncWatchdog service: $($s.Status)"
} else {
    Write-Warn "NSSM not found at $nssm - install NSSM first, then rerun this step manually"
}

# =============================================================================
# STEP 13 - Install FolderSyncAuditor NSSM service
# =============================================================================
Write-Step "Step 13 - FolderSyncAuditor NSSM service"
if (Test-Path $nssm) {
    & $nssm stop   FolderSyncAuditor 2>$null
    & $nssm remove FolderSyncAuditor confirm 2>$null
    Start-Sleep 2
    & $nssm install FolderSyncAuditor powershell.exe
    & $nssm set FolderSyncAuditor AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auditor.ps1'
    & $nssm set FolderSyncAuditor DisplayName   'Folder Sync Security Auditor'
    & $nssm set FolderSyncAuditor Description   'Monitors file changes, remote access, and service tampering.'
    & $nssm set FolderSyncAuditor Start          SERVICE_AUTO_START
    & $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\services\auditor_svc.log'
    & $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\services\auditor_svc_err.log'
    & $nssm set FolderSyncAuditor AppRotateFiles  1
    & $nssm set FolderSyncAuditor AppRotateBytes  2097152
    & $nssm set FolderSyncAuditor AppRestartDelay 30000
    Start-Service FolderSyncAuditor -ErrorAction SilentlyContinue
    $s = Get-Service FolderSyncAuditor -ErrorAction SilentlyContinue
    Write-OK "FolderSyncAuditor service: $($s.Status)"
} else {
    Write-Warn "NSSM not found — skipped FolderSyncAuditor"
}

# =============================================================================
# STEP 14 - RealTimeSync startup registry entry
# =============================================================================
Write-Step "Step 14 - RealTimeSync startup registry"
$rtsPath = '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "FolderSyncRealTime" -Value $rtsPath -ErrorAction SilentlyContinue
Write-OK "Registry startup entry set for RealTimeSync"

# Start RealTimeSync now if not running
$rts = Get-Process RealTimeSync -ErrorAction SilentlyContinue
if (-not $rts) {
    Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
        -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-OK "RealTimeSync started"
} else {
    Write-OK "RealTimeSync already running (PID $($rts.Id))"
}

# =============================================================================
# STEP 15 - Enable file auditing (SACL on watched folder)
# =============================================================================
Write-Step "Step 15 - File system auditing (SACL)"
$auditScript = "C:\Sync\Config\enable_file_auditing.ps1"
if (Test-Path $auditScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $auditScript
    Write-OK "File auditing configured"
} else {
    Write-Warn "enable_file_auditing.ps1 not found — run manually when available"
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup Complete — Full Ecosystem + Security Hardening" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Applied:" -ForegroundColor White
Write-Host "  Step  1 - Firewall log read permissions" -ForegroundColor Gray
Write-Host "  Step  2 - run_mirror.bat daily rotation" -ForegroundColor Gray
Write-Host "  Step  3 - cloud_sync.ps1 log rotation (Mirror:7d, Logs:30d)" -ForegroundColor Gray
Write-Host "  Step  4 - C:\Sync\Config ACL locked" -ForegroundColor Gray
Write-Host "  Step  5 - DailySecurityCheck v7 + scheduled task + shortcut" -ForegroundColor Gray
Write-Host "  Step  6 - Remote access disabled (RDP/WinRM/SMB2/RemoteRegistry)" -ForegroundColor Gray
Write-Host "  Step  7 - Account lockout (5 attempts, 30 min)" -ForegroundColor Gray
Write-Host "  Step  8 - Screen auto-lock (5 min)" -ForegroundColor Gray
Write-Host "  Step  9 - Firewall logging → C:\Sync\Logs\firewall.log" -ForegroundColor Gray
Write-Host "  Step 10 - FolderSync-CloudBackup task (SYSTEM)" -ForegroundColor Gray
Write-Host "  Step 11 - FolderSync-Watchdog task (current user)" -ForegroundColor Gray
Write-Host "  Step 12 - FolderSyncWatchdog NSSM service" -ForegroundColor Gray
Write-Host "  Step 13 - FolderSyncAuditor NSSM service" -ForegroundColor Gray
Write-Host "  Step 14 - RealTimeSync startup registry + started" -ForegroundColor Gray
Write-Host "  Step 15 - File system auditing (SACL)" -ForegroundColor Gray
Write-Host ""
Write-Host "Pending (manual — requires web UI or physical access):" -ForegroundColor Yellow
Write-Host "  - B2 Lifecycle Rules (versioning) via backblaze.com" -ForegroundColor Yellow
Write-Host "  - BIOS password on Acer Nitro 5" -ForegroundColor Yellow
Write-Host "  - Windows Hello PIN (resolve via Microsoft account portal)" -ForegroundColor Yellow
Write-Host "  - C100 RTSP integration" -ForegroundColor Yellow
Write-Host ""
Write-Host "Validate with:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER to close"
```
---

### `C:\Sync\Config\setup_update.ps1`
> Centralized setup v3 (primary). State-aware: stops ecosystem before reconfigure, restarts after. Covers all 17 steps including subdir log routing, Yawcam registry, CAM-2 relay, and ecosystem lifecycle management.

```powershell
#Requires -RunAsAdministrator
# =============================================================================
# setup_update.ps1 v3
# Centralized setup for FolderSync Ecosystem + Security Hardening
# Replaces setup_all.ps1. Adds .ecosystem_state awareness:
#   - Stops ecosystem before reconfiguring if currently running
#   - Restarts after config if it was running before
# Run as Administrator from C:\Sync\Config\
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$currentUser     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$sidAdmins       = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$sidAdminsAccount= $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value
$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateFile       = "C:\Sync\Config\.ecosystem_state"

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Centralized Setup v3" -ForegroundColor Cyan
Write-Host "  Running as: $currentUser" -ForegroundColor Cyan
Write-Host "  Script dir: $scriptDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# =============================================================================
# STATE MANAGEMENT - read .ecosystem_state, stop if running
# =============================================================================
$wasRunning = $false
if (Test-Path $StateFile) {
    $state = (Get-Content -LiteralPath $StateFile -Raw).Trim()
    if ($state -eq 'running') {
        $wasRunning = $true
        Write-Warn "Ecosystem is running - stopping before reconfigure"
        & powershell.exe -ExecutionPolicy Bypass -File "$scriptDir\stop_ecosystem.ps1"
        Start-Sleep -Seconds 3
    } else {
        Write-OK "Ecosystem state: stopped - proceeding with config"
    }
} else {
    Write-OK "No .ecosystem_state file - assuming first run (will start after setup)"
    $wasRunning = $true  # default: start after fresh install
}

# =============================================================================
# STEP 1 - Firewall log read permissions
# =============================================================================
Write-Step "Step 1 - Firewall log read permissions"
foreach ($f in @("C:\Sync\Logs\firewall.log","C:\Sync\Logs\firewall.log.old")) {
    if (Test-Path $f) {
        icacls $f /grant:r "${currentUser}:(R)" | Out-Null
        Write-OK "Read access granted: $f"
    } else {
        Write-Warn "Not found (will be fixed when created): $f"
    }
}
icacls "C:\Sync\Logs" /grant:r "${currentUser}:(OI)(CI)(R)" | Out-Null
Write-OK "Future firewall logs readable by $currentUser"

# =============================================================================
# STEP 2 - Update run_mirror.bat with daily log rotation
# =============================================================================
Write-Step "Step 2 - Update run_mirror.bat (daily log rotation)"
$mirrorBat = "C:\Sync\Config\run_mirror.bat"
Set-Content -Path $mirrorBat -Encoding ASCII -Value @'
@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /E    = Copy subdirectories (including empty ones), do NOT delete from dest
:: /Z    = Restartable mode (essential for video files if copy is interrupted)
:: /R:1  = Retry only once to avoid massive logs
:: /W:2  = Short wait between retries
:: /NFL  = No File List - suppresses per-file output, keeps summary only (prevents log bloat)
:: /LOG+ = Append to DAILY rotating log (mirror_YYYY-MM-DD.log)
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror\mirror_%DATE%.log" /NP /NDL /NC /NS /NFL
'@
Write-OK "run_mirror.bat updated -> mirror_YYYY-MM-DD.log"

# Archive old bloated mirror log if exists
$oldMirror = "C:\Sync\Logs\mirror"
if (Test-Path $oldMirror) {
    Rename-Item $oldMirror "C:\Sync\Logs\mirror_archive_$(Get-Date -Format 'yyyy-MM-dd').log" -ErrorAction SilentlyContinue
    Write-OK "Old mirror log archived"
}

# =============================================================================
# STEP 3 - Update cloud_sync.ps1 with self-healing firewall + 3-phase ACL
# =============================================================================
Write-Step "Step 3 - Update cloud_sync.ps1 (firewall self-healing + 3-phase ACL protection)"
$cloudSyncPs1 = "C:\Sync\Config\cloud_sync.ps1"
Set-Content -Path $cloudSyncPs1 -Encoding UTF8 -Value @'
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-03-07 - Added self-healing firewall detection+removal+retry

$Rclone           = 'C:\Tools\Rclone\rclone.exe'
$Config           = 'C:\Sync\Config\rclone.conf'
$Source           = 'C:\Users\helde\Repos\Bois'
$Remote           = 'cloudsync:helder-sync-mirror'
$Mirror           = 'C:\Sync\Mirror'
$LogDir           = 'C:\Sync\Logs\cloud_sync'
$Log              = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror = 7
$DaysToKeepLogs   = 30

# Known malicious firewall rules that block Backblaze B2 sync
$MaliciousFirewallRules = @(
    'Block 104.153.233.180',
    'Block 149.137.142.15'
)

function Write-SyncLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $Log
}

function Remove-MaliciousFirewallRules {
    $removed = @()
    foreach ($ruleName in $MaliciousFirewallRules) {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            $removed += $ruleName
            Write-SyncLog "FIREWALL-HEAL  Removed malicious block rule: $ruleName"
        }
    }
    $allBlockRules = Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' } |
        Where-Object { $_.DisplayName -notlike 'Block 0.0.0.0*' }
    foreach ($r in $allBlockRules) {
        $addr = ($r | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress
        if ($addr -match '104\.153\.|149\.137\.|backblaze') {
            Remove-NetFirewallRule -DisplayName $r.DisplayName -ErrorAction SilentlyContinue
            $removed += $r.DisplayName
            Write-SyncLog "FIREWALL-HEAL  Removed unknown B2 block rule: $($r.DisplayName) -> $addr"
        }
    }
    return $removed
}

Write-SyncLog "SYNC-START  Beginning cloud sync run"

$preRemoved = @()
foreach ($ruleName in $MaliciousFirewallRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule) {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        $preRemoved += $ruleName
        Write-SyncLog "FIREWALL-PREFLIGHT  Removed malicious block rule before sync: $ruleName"
    }
}
if ($preRemoved.Count -gt 0) {
    Write-SyncLog "FIREWALL-PREFLIGHT  WARNING: $($preRemoved.Count) malicious rule(s) were active at sync start - possible active attack"
}

$rcloneOutput = & $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --transfers 4 `
    --checkers 8 `
    --fast-list 2>&1

$rcloneExitCode = $LASTEXITCODE

$firewallBlocked = $false
if ($rcloneOutput -match 'connectex|socket access forbidden|access is forbidden|connect: permission denied') {
    $firewallBlocked = $true
    Write-SyncLog "FIREWALL-DETECT  Rclone reported connection blocked - checking firewall rules"
    $healed = Remove-MaliciousFirewallRules
    if ($healed.Count -gt 0) {
        Write-SyncLog "FIREWALL-HEAL  Removed $($healed.Count) malicious rule(s): $($healed -join ', ')"
        Write-SyncLog "FIREWALL-HEAL  Retrying sync after firewall repair"
        $rcloneOutput2 = & $Rclone sync $Source $Remote `
            --config $Config `
            --log-file $Log `
            --log-level INFO `
            --transfers 4 `
            --checkers 8 `
            --fast-list 2>&1
        $rcloneExitCode = $LASTEXITCODE
        if ($LASTEXITCODE -eq 0) {
            Write-SyncLog "FIREWALL-HEAL  Retry SUCCESS - sync completed after firewall repair"
        } else {
            Write-SyncLog "FIREWALL-HEAL  Retry FAILED (exit $LASTEXITCODE) - sync still failing after firewall repair"
            Write-SyncLog "FIREWALL-HEAL  Manual investigation required"
        }
    } else {
        Write-SyncLog "FIREWALL-DETECT  No known malicious rules found - unknown blocking cause"
        Write-SyncLog "FIREWALL-DETECT  Run check_status.ps1 and review firewall rules manually"
    }
} elseif ($rcloneExitCode -eq 0) {
    Write-SyncLog "SYNC-OK  Sync completed successfully (exit 0)"
} else {
    Write-SyncLog "SYNC-FAIL  Sync failed (exit $rcloneExitCode) - not a firewall error"
}

if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop
                $hasDeny = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }
                if (-not $hasDeny) {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
                        'Delete', 'None', 'None', 'Deny')
                    $acl.AddAccessRule($rule)
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch { }
        }
}

if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop
                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }
                if ($denyRules) {
                    foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch { }
        }
}

if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. cloud_sync log rotation
Get-ChildItem -Path $LogDir -Filter "cloud_sync_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. mirror log rotation
Get-ChildItem -Path 'C:\Sync\Logs\mirror' -Filter "mirror_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-SyncLog "SYNC-END  Cloud sync run complete"
'@
Write-OK "cloud_sync.ps1 updated (self-healing firewall + 3-phase ACL protection)"

# =============================================================================
# STEP 4 - SINGLE AUTHORITY: all Deny Delete ACL rules for C:\Sync
# =============================================================================
Write-Step "Step 4 - Apply all Deny Delete ACL rules (single authority)"

$sidEveryone = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')

function Set-DenyDeleteFull($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone, 'Delete,DeleteSubdirectoriesAndFiles',
        'ContainerInherit,ObjectInherit', 'None', 'Deny')
    $acl.RemoveAccessRule($rule) | Out-Null
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

function Set-DenyDeleteFolderOnly($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone, 'Delete', 'None', 'None', 'Deny')
    $acl.RemoveAccessRule($rule) | Out-Null
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

Set-DenyDeleteFolderOnly 'C:\Sync'
Write-OK "C:\Sync root locked (folder-only, no inherit)"

Set-DenyDeleteFull 'C:\Sync\Config'
Write-OK "C:\Sync\Config locked (recursive)"

Set-DenyDeleteFull 'C:\Sync\Logs'
Write-OK "C:\Sync\Logs locked (recursive)"

if (-not (Test-Path 'C:\Sync\Evidence')) { New-Item -ItemType Directory -Path 'C:\Sync\Evidence' -Force | Out-Null }
Set-DenyDeleteFull 'C:\Sync\Evidence'
Write-OK "C:\Sync\Evidence locked (recursive)"

if (Test-Path 'C:\Sync\.git') {
    icacls "C:\Sync\.git" /remove:d "*S-1-1-0" /T /Q | Out-Null
    icacls "C:\Sync\.git" /remove:d "*S-1-5-32-545" /T /Q | Out-Null
    icacls "C:\Sync\.git" /remove:d "*S-1-5-32-544" /T /Q | Out-Null
    Write-OK "C:\Sync\.git liberated (no Deny Delete)"
    $gitDeny = (icacls "C:\Sync\.git" 2>&1) | Where-Object { $_ -match ':D\b' }
    if ($gitDeny) {
        Write-Fail "C:\Sync\.git still has Deny rules - investigate: $gitDeny"
    } else {
        Write-OK "C:\Sync\.git verified clean (zero Deny rules)"
    }
}
Write-OK "C:\Sync\Mirror - no folder ACL (cloud_sync.ps1 manages per-file ACLs)"

# =============================================================================
# STEP 5 - DailySecurityCheck v8
# =============================================================================
Write-Step "Step 5 - Install DailySecurityCheck v8"

foreach ($oldName in @("Verificacao Automatica de Seguranca", "Verificacao Automatica de Seguranca")) {
    if (Get-ScheduledTask -TaskName $oldName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $oldName -Confirm:$false -ErrorAction SilentlyContinue
        Write-OK "Removed legacy task: $oldName"
    }
}

$taskName  = "FolderSync-DailyCheck"
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\Sync\Config\DailySecurityCheck.ps1`""
$trigger   = New-ScheduledTaskTrigger -Daily -At "09:00"
$settings  = New-ScheduledTaskSettingsSet -Hidden -RunOnlyIfNetworkAvailable:$false
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-OK "Task registered: $taskName -> C:\Sync\Config\DailySecurityCheck.ps1 (daily 09:00)"

$shell    = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$([System.Environment]::GetFolderPath('Desktop'))\Verificar Seguranca.lnk")
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments  = "-ExecutionPolicy Bypass -File `"C:\Sync\Config\DailySecurityCheck.ps1`""
$shortcut.Save()
Write-OK "Desktop shortcut created: Verificar Seguranca.lnk"

# =============================================================================
# STEP 6 - Disable remote access services
# =============================================================================
Write-Step "Step 6 - Disable remote access services"
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
Write-OK "RDP connections blocked"

foreach ($svc in @("RemoteRegistry","WinRM","TermService")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.StartType -ne 'Disabled') {
            Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            Write-OK "$svc disabled"
        } else {
            Write-OK "$svc already disabled"
        }
    }
}

try {
    Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force -ErrorAction SilentlyContinue
    Write-OK "SMB2 disabled"
} catch { Write-Warn "SMB2 disable failed: $_" }

# =============================================================================
# STEP 7 - Account lockout policy
# =============================================================================
Write-Step "Step 7 - Account lockout (5 attempts, 30 min)"
net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 | Out-Null
Write-OK "Lockout configured"

# =============================================================================
# STEP 8 - Screen auto-lock (5 minutes)
# =============================================================================
Write-Step "Step 8 - Screen auto-lock (5 minutes)"
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300 | Out-Null
powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE  CONSOLELOCK   1 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE  CONSOLELOCK   1 | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null
Write-OK "Auto-lock: 5 minutes, password required on wake"

# =============================================================================
# STEP 9 - Windows Firewall logging
# =============================================================================
Write-Step "Step 9 - Windows Firewall logging"
netsh advfirewall set allprofiles logging droppedconnections enable | Out-Null
netsh advfirewall set allprofiles logging allowedconnections enable | Out-Null
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\security\firewall.log" | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 8192 | Out-Null
Start-Sleep -Seconds 1
if (Test-Path "C:\Sync\Logs\security\firewall.log") {
    icacls "C:\Sync\Logs\security\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
    Write-OK "Firewall logging active + read permission set"
} else {
    Write-OK "Firewall logging active (log created on first connection)"
}

# =============================================================================
# STEP 10 - Register FolderSync-CloudBackup task (SYSTEM)
# =============================================================================
Write-Step "Step 10 - FolderSync-CloudBackup task (SYSTEM, every 5 min)"
$existingBackup = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue

$needsRecreate = $false
if ($existingBackup) {
    $currentArgs = $existingBackup.Actions[0].Arguments
    $currentExec = $existingBackup.Actions[0].Execute

    if ($currentExec -like "*.bat" -or $currentArgs -notlike "*-NoWindow*") {
        Write-Warn "Task exists but uses .bat or missing -NoWindow - will recreate"
        $needsRecreate = $true
    }
}

if (-not $existingBackup -or $needsRecreate) {
    if ($existingBackup) {
        Unregister-ScheduledTask -TaskName "FolderSync-CloudBackup" -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    $action1   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoWindow -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
    $trigger1  = @(
        $(New-ScheduledTaskTrigger -AtStartup),
        $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
    )
    $settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $principal1= New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force | Out-Null
    Write-OK "Task FolderSync-CloudBackup registered (PowerShell with -NoWindow)"
} else {
    Write-OK "Task FolderSync-CloudBackup already exists with correct arguments"
}

# =============================================================================
# STEP 11 - Register FolderSync-Watchdog task (current user, interactive)
# =============================================================================
Write-Step "Step 11 - FolderSync-Watchdog task (current user, every 3 min)"
$action2   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
$trigger2  = @(
    $(New-ScheduledTaskTrigger -AtLogOn),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 3) -Once -At (Get-Date))
)
$settings2 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal2= New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Unregister-ScheduledTask -TaskName "FolderSync-Watchdog" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-Watchdog" -Action $action2 -Trigger $trigger2 -Settings $settings2 -Principal $principal2 -Force | Out-Null
Write-OK "Task FolderSync-Watchdog registered ($currentUser)"

# =============================================================================
# STEP 12 - Install FolderSyncWatchdog NSSM service
# =============================================================================
Write-Step "Step 12 - FolderSyncWatchdog NSSM service"
$nssm = 'C:\Tools\NSSM\nssm.exe'
if (Test-Path $nssm) {
    & $nssm stop   FolderSyncWatchdog 2>$null
    & $nssm remove FolderSyncWatchdog confirm 2>$null
    Start-Sleep 2
    & $nssm install FolderSyncWatchdog powershell.exe
    & $nssm set FolderSyncWatchdog AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
    & $nssm set FolderSyncWatchdog DisplayName   'Folder Sync Watchdog Service'
    & $nssm set FolderSyncWatchdog Description   'Monitors and restarts folder sync processes (RealTimeSync + cloud backup task).'
    & $nssm set FolderSyncWatchdog Start          SERVICE_AUTO_START
    & $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\services\watchdog_svc.log'
    & $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\services\watchdog_svc_err.log'
    & $nssm set FolderSyncWatchdog AppRotateFiles  1
    & $nssm set FolderSyncWatchdog AppRotateBytes  1048576
    Write-OK "FolderSyncWatchdog service installed (start via start_ecosystem.ps1)"
} else {
    Write-Warn "NSSM not found at $nssm - install NSSM first, then rerun this step manually"
}

# =============================================================================
# STEP 13 - Install FolderSyncAuditor NSSM service
# =============================================================================
Write-Step "Step 13 - FolderSyncAuditor NSSM service"
if (Test-Path $nssm) {
    & $nssm stop   FolderSyncAuditor 2>$null
    & $nssm remove FolderSyncAuditor confirm 2>$null
    Start-Sleep 2
    & $nssm install FolderSyncAuditor powershell.exe
    & $nssm set FolderSyncAuditor AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auditor.ps1'
    & $nssm set FolderSyncAuditor DisplayName   'Folder Sync Security Auditor'
    & $nssm set FolderSyncAuditor Description   'Monitors file changes, remote access, and service tampering.'
    & $nssm set FolderSyncAuditor Start          SERVICE_AUTO_START
    & $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\services\auditor_svc.log'
    & $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\services\auditor_svc_err.log'
    & $nssm set FolderSyncAuditor AppRotateFiles  1
    & $nssm set FolderSyncAuditor AppRotateBytes  2097152
    & $nssm set FolderSyncAuditor AppRestartDelay 30000
    Write-OK "FolderSyncAuditor service installed (start via start_ecosystem.ps1)"
} else {
    Write-Warn "NSSM not found - skipped FolderSyncAuditor"
}

# =============================================================================
# STEP 14 - Startup registry entries (RealTimeSync + Yawcam + Monitor + CAM-2)
# =============================================================================
Write-Step "Step 14 - Startup registry entries"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# RealTimeSync
$rtsPath = '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
Set-ItemProperty $runKey -Name "FolderSyncRealTime" -Value $rtsPath -ErrorAction SilentlyContinue
Write-OK "Registry: FolderSyncRealTime -> RealTimeSync.exe"

# Yawcam - use bat wrapper so working dir is set correctly (prevents launcher.cfg error)
Set-ItemProperty $runKey -Name "Yawcam" `
    -Value '"C:\Sync\Config\start_yawcam.bat"' -ErrorAction SilentlyContinue
Write-OK "Registry: Yawcam -> C:\Sync\Config\start_yawcam.bat"

# YawcamMonitor (uses relocated start_monitor.ps1 in C:\Sync\Config\)
$monitorCmd = 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\start_monitor.ps1"'
Set-ItemProperty $runKey -Name "YawcamMonitor" -Value $monitorCmd -ErrorAction SilentlyContinue
Write-OK "Registry: YawcamMonitor -> C:\Sync\Config\start_monitor.ps1"

# YawcamCam2Relay
$cam2Cmd = 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\cam2_relay.ps1"'
Set-ItemProperty $runKey -Name "YawcamCam2Relay" -Value $cam2Cmd -ErrorAction SilentlyContinue
Write-OK "Registry: YawcamCam2Relay -> C:\Sync\Config\cam2_relay.ps1"

# =============================================================================
# STEP 15 - Remove any known malicious firewall rules
# =============================================================================
Write-Step "Step 15 - Remove malicious firewall rules (B2 block rules)"
$maliciousRules = @(
    "Block 104.153.233.180",
    "Block 149.137.142.15"
)
$removedCount = 0
foreach ($ruleName in $maliciousRules) {
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        Write-Warn "Removed malicious rule: $ruleName"
        $removedCount++
    }
}
if ($removedCount -eq 0) {
    Write-OK "No malicious B2 block rules found"
} else {
    Write-OK "$removedCount malicious rule(s) removed"
}

# =============================================================================
# STEP 16 - File system auditing SACL on watched folder (Bois)
# =============================================================================
Write-Step "Step 16 - File system auditing (SACL on Bois folder)"
$auditScript = "C:\Sync\Config\enable_file_auditing.ps1"
if (Test-Path $auditScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $auditScript
    Write-OK "File auditing (SACL) configured"
} else {
    Write-Warn "enable_file_auditing.ps1 not found - run manually when available"
}

# =============================================================================
# STEP 17 - FolderSync-GitCommitLogs task (current user, daily 23:30)
# =============================================================================
Write-Step "Step 17 - FolderSync-GitCommitLogs task (daily 23:30)"
$action17   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auto_commit_logs.ps1'
$trigger17  = New-ScheduledTaskTrigger -Daily -At "23:30"
$settings17 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal17= New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Unregister-ScheduledTask -TaskName "FolderSync-GitCommitLogs" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-GitCommitLogs" -Action $action17 -Trigger $trigger17 -Settings $settings17 -Principal $principal17 -Force | Out-Null
Write-OK "Task FolderSync-GitCommitLogs registered ($currentUser, daily 23:30)"

# =============================================================================
# STATE MANAGEMENT - start ecosystem if it was running before config
# =============================================================================
if ($wasRunning) {
    Write-Step "Restarting ecosystem (was running before config)"
    & powershell.exe -ExecutionPolicy Bypass -File "$scriptDir\start_ecosystem.ps1"
} else {
    # Write stopped state explicitly
    'stopped' | Set-Content -LiteralPath $StateFile -Encoding UTF8
    Write-OK "Ecosystem left in stopped state (was stopped before config)"
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup Complete - Full Ecosystem + Security Hardening" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Applied:" -ForegroundColor White
Write-Host "  Step  1 - Firewall log read permissions" -ForegroundColor Gray
Write-Host "  Step  2 - run_mirror.bat with /E flag (no delete mirroring)" -ForegroundColor Gray
Write-Host "  Step  3 - cloud_sync.ps1 with firewall self-healing + 3-phase ACL (7d retention)" -ForegroundColor Gray
Write-Host "  Step  4 - ACL: root(folder-only), Config+Logs+Evidence(recursive), .git liberated, Mirror unmanaged" -ForegroundColor Gray
Write-Host "  Step  5 - DailySecurityCheck v8 + FolderSync-DailyCheck task + shortcut" -ForegroundColor Gray
Write-Host "  Step  6 - Remote access disabled (RDP/WinRM/SMB2/RemoteRegistry)" -ForegroundColor Gray
Write-Host "  Step  7 - Account lockout (5 attempts, 30 min)" -ForegroundColor Gray
Write-Host "  Step  8 - Screen auto-lock (5 min)" -ForegroundColor Gray
Write-Host "  Step  9 - Firewall logging -> C:\Sync\Logs\firewall.log" -ForegroundColor Gray
Write-Host "  Step 10 - FolderSync-CloudBackup task (SYSTEM)" -ForegroundColor Gray
Write-Host "  Step 11 - FolderSync-Watchdog task (current user)" -ForegroundColor Gray
Write-Host "  Step 12 - FolderSyncWatchdog NSSM service (installed, not started)" -ForegroundColor Gray
Write-Host "  Step 13 - FolderSyncAuditor NSSM service (installed, not started)" -ForegroundColor Gray
Write-Host "  Step 14 - Startup registry: RealTimeSync + Yawcam + YawcamMonitor + YawcamCam2Relay" -ForegroundColor Gray
Write-Host "  Step 15 - Malicious firewall rules removed (B2 block rules)" -ForegroundColor Gray
Write-Host "  Step 16 - File system auditing (SACL on Bois folder)" -ForegroundColor Gray
Write-Host "  Step 17 - FolderSync-GitCommitLogs task (daily 23:30)" -ForegroundColor Gray
Write-Host ""
Write-Host "Pending (manual - requires web UI or physical access):" -ForegroundColor Yellow
Write-Host "  - B2 Lifecycle Rules (versioning) via backblaze.com" -ForegroundColor Yellow
Write-Host "  - BIOS password on Acer Nitro 5" -ForegroundColor Yellow
Write-Host "  - Windows Hello PIN (resolve via Microsoft account portal)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Ecosystem control:" -ForegroundColor Cyan
Write-Host "  Start : powershell -ExecutionPolicy Bypass -File C:\Sync\Config\start_ecosystem.ps1" -ForegroundColor Cyan
Write-Host "  Stop  : powershell -ExecutionPolicy Bypass -File C:\Sync\Config\stop_ecosystem.ps1" -ForegroundColor Cyan
Write-Host "  Health: /project:health" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER to close"
```
---

### `C:\Sync\Config\enable_file_auditing.ps1`
> One-time setup. Ativa auditoria de file system e aplica SACL no watched folder. Rodar como Administrador uma única vez.

```powershell
$WatchedFolder = 'C:\Users\helde\Repos\Bois'
$RootPath      = 'C:\Sync'
$LogPath       = 'C:\Sync\Logs'
$MirrorPath    = 'C:\Sync\Mirror'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute como Administrador."; exit 1
}

auditpol /set /subcategory:"Sistema de Arquivos" /success:enable /failure:enable

$AclData  = Get-Acl -Path $WatchedFolder -Audit
$Everyone = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'
$AuditRule = New-Object System.Security.AccessControl.FileSystemAuditRule($Everyone, "Delete,DeleteSubdirectoriesAndFiles,WriteData", "ContainerInherit,ObjectInherit", "None", "Success,Failure")
$AclData.SetAuditRule($AuditRule)
Set-Acl -Path $WatchedFolder -AclObject $AclData

if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }
$RootAcl = Get-Acl $RootPath
$RootAcl.SetAccessRuleProtection($true, $true)
$DenyRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Everyone, "Delete,DeleteSubdirectoriesAndFiles", "ContainerInherit,ObjectInherit", "None", "Deny")
$RootAcl.AddAccessRule($DenyRule)
Set-Acl $RootPath $RootAcl

if (Test-Path $MirrorPath) {
    $MirrorAcl  = Get-Acl $MirrorPath
    $SystemSid  = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'
    $SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $UserSid    = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $UserRule   = New-Object System.Security.AccessControl.FileSystemAccessRule($UserSid, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $MirrorAcl.SetAccessRuleProtection($true, $false)
    $MirrorAcl.AddAccessRule($SystemRule)
    $MirrorAcl.AddAccessRule($UserRule)
    Set-Acl $MirrorPath $MirrorAcl
}

Write-Host "Auditoria e blindagem aplicadas com sucesso." -ForegroundColor Green
```

---

## 16. Fresh Install / Disaster Recovery (from scratch)

### Step 1 — Download tools

| Tool | URL | Install to |
|---|---|---|
| Rclone (win-amd64 zip) | https://downloads.rclone.org/rclone-current-windows-amd64.zip | Extract `rclone.exe` → `C:\Tools\Rclone\` |
| FreeFileSync | https://freefilesync.org/download/FreeFileSync_14.7_Windows_Setup.exe | `C:\Program Files\FreeFileSync\` |
| NSSM | https://nssm.cc/release/nssm-2.24.zip | Extract `win64\nssm.exe` → `C:\Tools\NSSM\` |

### Step 2 — Add Rclone to PATH
```powershell
$p = [Environment]::GetEnvironmentVariable('PATH','Machine')
[Environment]::SetEnvironmentVariable('PATH', "$p;C:\Tools\Rclone", 'Machine')
```

### Step 3 — Create folders
```powershell
mkdir C:\Sync\Mirror, C:\Sync\Logs, C:\Sync\Config
mkdir C:\Tools\Rclone, C:\Tools\NSSM
```

### Step 4 — Restore all config files
Recreate every file from §15 of this document into `C:\Sync\Config\`.

### Step 5 — Restore credentials
- Get Key ID and App Key from backblaze.com → App Keys (scope to `helder-sync-mirror`)
- Edit `rclone.conf` with actual values
- Run `encrypt_creds.ps1` to produce `credentials.enc`

### Step 6 — Run centralized setup
```powershell
# Place setup_all.ps1 + DailySecurityCheck.ps1 + AutoCleanup.ps1 in C:\Sync\Config\
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\setup_all.ps1
```

### Step 7 — Register sync tasks and services
```powershell
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\register_tasks.ps1
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\fix_watchdog_task.ps1
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_service.ps1
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_auditor_service.ps1
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\enable_file_auditing.ps1
```

### Step 8 — Add startup registry entry
```powershell
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "FolderSyncRealTime" `
    -Value '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
```

### Step 9 — Start and validate
```powershell
Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
    -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1
```

---

### `C:\Sync\Config\check_camera.ps1`
> Camera and motion detection health check. Run interactively to verify Yawcam is running, webcam device is OK, and recordings are being produced. No admin required for most checks.

```powershell
# check_camera.ps1
# Camera / Motion Detection Health Check
# Modeled after check_status.ps1 — run interactively to diagnose camera state
# No admin required for most checks; PnP device queries may return partial data without elevation

$TodayDir  = "C:\Users\helde\Repos\Bois\$(Get-Date -Format 'yyyy-MM-dd')"
$TempPath  = "C:\TEMP\motion_videos"
$YawcamExe = "C:\Program Files (x86)\Yawcam\Yawcam.exe"
$MonitorV4 = "C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1"

Write-Host "=== YAWCAM PROCESS ===" -ForegroundColor Cyan
$yawcamProc = Get-Process -Name "yawcam" -ErrorAction SilentlyContinue
$javawProc  = Get-Process -Name "javaw"  -ErrorAction SilentlyContinue |
              Where-Object { $_.MainWindowTitle -like "*Yawcam*" }
if ($yawcamProc) {
    $yawcamProc | Select-Object Name, Id, CPU, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
} elseif ($javawProc) {
    Write-Host "  (running as javaw)" -ForegroundColor Yellow
    $javawProc | Select-Object Name, Id, CPU, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
} else { Write-Host "  NOT RUNNING" -ForegroundColor Red }

Write-Host "`n=== YAWCAM MONITOR PROCESS ===" -ForegroundColor Cyan
$monitorProc = Get-Process -Name "powershell" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like "*yawcam_monitor*" }
if ($monitorProc) {
    $monitorProc | Select-Object Name, Id, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
} else {
    $wmiProc = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like "*yawcam_monitor*" }
    if ($wmiProc) { $wmiProc | Select-Object Name, ProcessId }
    else { Write-Host "  NOT RUNNING" -ForegroundColor Red }
}

Write-Host "`n=== WEBCAM DEVICE (PnP) ===" -ForegroundColor Cyan
Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like "*HD User*" -or $_.FriendlyName -like "*webcam*" -or
                   $_.FriendlyName -like "*camera*" -or $_.Class -eq "Camera" -or $_.Class -eq "Image" } |
    Select-Object FriendlyName, Status, Class, InstanceId

Write-Host "`n=== REGISTRY STARTUP ENTRIES ===" -ForegroundColor Cyan
$runKey = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
Write-Host "  Yawcam:             $($runKey.Yawcam)"
Write-Host "  YawcamMonitor:      $($runKey.YawcamMonitor)"
Write-Host "  FolderSyncRealTime: $($runKey.FolderSyncRealTime)"

Write-Host "`n=== YAWCAM INSTALLATION ===" -ForegroundColor Cyan
Write-Host "  Yawcam.exe     : $(if (Test-Path $YawcamExe) { 'FOUND - ' + (Get-Item $YawcamExe).LastWriteTime } else { 'NOT FOUND' })"
Write-Host "  monitor_v4.ps1 : $(if (Test-Path $MonitorV4) { 'FOUND - ' + (Get-Item $MonitorV4).LastWriteTime } else { 'NOT FOUND' })"

Write-Host "`n=== TODAY'S RECORDINGS ($TodayDir) ===" -ForegroundColor Cyan
if (Test-Path $TodayDir) {
    $files = Get-ChildItem $TodayDir -Filter "*.avi" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
    if ($files) {
        $totalMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        $latest  = $files | Select-Object -Last 1
        $ageMin  = [math]::Round(((Get-Date) - $latest.LastWriteTime).TotalMinutes, 1)
        Write-Host "  Count: $($files.Count) files   Size: $totalMB MB   Latest: $($latest.Name) ($ageMin min ago)"
        if ($ageMin -le 5)  { Write-Host "  [ACTIVE]" -ForegroundColor Green }
        elseif ($ageMin -le 15) { Write-Host "  [OK - normal gap]" -ForegroundColor Cyan }
        else { Write-Host "  [GAP - no motion or camera frozen?]" -ForegroundColor Yellow }
    } else { Write-Host "  No .avi files yet today" -ForegroundColor Yellow }
} else { Write-Host "  Directory not yet created for today" -ForegroundColor Yellow }

Write-Host "`n=== MONITOR RECORDING PATH ($TempPath) ===" -ForegroundColor Cyan
if (Test-Path $TempPath) {
    $tmpFiles = Get-ChildItem $TempPath -Recurse -Filter "*.avi" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($tmpFiles) { Write-Host "  Latest: $($tmpFiles.Name) ($([math]::Round(((Get-Date)-$tmpFiles.LastWriteTime).TotalMinutes,1)) min ago)" }
    else { Write-Host "  Path exists but no .avi files" -ForegroundColor Yellow }
} else {
    Write-Host "  Path does not exist — monitor checks legacy path; actual recordings in Bois dir" -ForegroundColor Red
}

Write-Host "`n=== RECENT RECORDINGS (last 5 across cameras) ===" -ForegroundColor Cyan
Get-ChildItem "C:\Users\helde\Repos\Bois" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 3 | ForEach-Object {
        Get-ChildItem $_.FullName -Filter "*.avi" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 2 | ForEach-Object {
                $age = [math]::Round(((Get-Date)-$_.LastWriteTime).TotalMinutes,0)
                Write-Host ("  [{0}]  {1}  ({2} min ago,  {3:N0} KB)" -f (Split-Path $_.DirectoryName -Leaf), $_.Name, $age, ($_.Length/1KB))
            }
    }

Write-Host "`n=== CAM-2 RELAY (VLC: RTSP -> MJPEG http://127.0.0.1:8161/) ===" -ForegroundColor Cyan
$relayProc = Get-CimInstance Win32_Process -Filter "Name = 'vlc.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -like "*cam2_relay*" -or $_.CommandLine -like "*8161*" }
if ($relayProc) {
    Write-Host "  VLC relay  : RUNNING (PID $($relayProc.ProcessId))" -ForegroundColor Green
} else {
    $vlcAny = Get-Process -Name "vlc" -ErrorAction SilentlyContinue
    if ($vlcAny) {
        Write-Host "  VLC relay  : VLC running (PID $($vlcAny.Id)) — verify it is the cam2 relay" -ForegroundColor Yellow
    } else {
        Write-Host "  VLC relay  : NOT RUNNING — run cam2_relay.ps1 or reboot to auto-start" -ForegroundColor Red
    }
}
$cam2Reachable = Test-Connection -ComputerName "192.168.0.109" -Count 1 -Quiet -ErrorAction SilentlyContinue
Write-Host "  C100 ping  : $(if ($cam2Reachable) { 'REACHABLE (192.168.0.109)' } else { 'UNREACHABLE — camera offline or IP changed?' })" -ForegroundColor $(if ($cam2Reachable) { 'Green' } else { 'Red' })
$relayLog = "C:\Sync\Logs\camera\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $relayLog) {
    $lastLine = Get-Content $relayLog -Tail 1
    Write-Host "  Last log   : $lastLine"
} else {
    Write-Host "  Relay log  : no log for today yet" -ForegroundColor Yellow
}

# =============================================================================
Write-Host "`n=== CAMERA INPUT SUMMARY ===" -ForegroundColor Cyan
Write-Host "  [CAM-1]  Built-in laptop webcam (HD User Facing)  ->  Yawcam 0.6.2 (direct)"
Write-Host "  [CAM-2]  TP-LINK Tapo C100 (192.168.0.109)        ->  VLC relay -> Yawcam (http://127.0.0.1:8161/)"
Write-Host ""
```

---

### `C:\Sync\Config\cam2_relay.ps1`
> CAM-2 VLC relay script. Reads credentials from `cam2.conf`, starts VLC as RTSP->MJPEG HTTP relay on `127.0.0.1:8161`. Monitors VLC process and restarts on death (30s interval). Logs to `C:\Sync\Logs\camera\cam2_relay_YYYY-MM-DD.log`. Registered as `YawcamCam2Relay` registry Run entry (hidden, at login).

```powershell
# cam2_relay.ps1
# CAM-2 RTSP -> MJPEG HTTP relay for Yawcam
# Reads credentials from cam2.conf, starts VLC relay on http://127.0.0.1:8161/
# Registered as startup entry: HKCU:\...\Run\YawcamCam2Relay
# Logs to C:\Sync\Logs\camera\cam2_relay_YYYY-MM-DD.log

$ConfFile  = "C:\Sync\Config\cam2.conf"
$VlcExe    = "C:\Program Files\VideoLAN\VLC\vlc.exe"
$RelayPort = 8161
$RelayHost = "127.0.0.1"
$LogFile   = "C:\Sync\Logs\camera\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
$CheckSecs = 30

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

if (-not (Test-Path $ConfFile)) {
    Write-Log "FAIL  cam2.conf not found at $ConfFile — relay cannot start"
    exit 1
}

$conf = @{}
Get-Content $ConfFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $conf[$parts[0].Trim()] = $parts[1].Trim()
}

$user   = $conf['CAM2_USER']
$pass   = $conf['CAM2_PASS']
$ip     = $conf['CAM2_IP']
$port   = $conf['CAM2_PORT']
$stream = $conf['CAM2_STREAM']

if (-not $user -or -not $pass -or -not $ip) {
    Write-Log "FAIL  cam2.conf missing required fields (CAM2_USER, CAM2_PASS, CAM2_IP)"
    exit 1
}

$RtspUrl  = "rtsp://${user}:${pass}@${ip}:${port}/${stream}"
$SoutDst  = "${RelayHost}:${RelayPort}/"
$SoutArg  = "#transcode{vcodec=MJPG,fps=10,acodec=none}:std{access=http,mux=mpjpeg,dst=${SoutDst}}"

Write-Log "START  CAM-2 relay starting  ->  http://${RelayHost}:${RelayPort}/"
Write-Log "INFO   Source: rtsp://${user}:***@${ip}:${port}/${stream}"

$vlcProc = $null

function Start-VlcRelay {
    Write-Log "INFO   Launching VLC relay"
    $args = @(
        "-I", "dummy",
        "--no-one-instance",
        "--loop",
        "--sout-keep",
        $RtspUrl,
        "--sout=$SoutArg"
    )
    return Start-Process -FilePath $VlcExe -ArgumentList $args -PassThru -WindowStyle Hidden
}

$vlcProc = Start-VlcRelay

while ($true) {
    Start-Sleep -Seconds $CheckSecs
    $LogFile = "C:\Sync\Logs\camera\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"
    if ($vlcProc -eq $null -or $vlcProc.HasExited) {
        Write-Log "WARN   VLC relay process died  - restarting"
        $vlcProc = Start-VlcRelay
    }
}
```

---

### `C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1`
> Infinite-loop Yawcam recovery monitor. Checks for recent .avi files in `C:\TEMP\motion_videos` every 60s. If no recording for >15 min, kills Yawcam, resets webcam PnP device, and restarts. 600s cooldown between restarts. **Note:** monitoring path is `C:\TEMP\motion_videos` (legacy) but actual recordings go to `C:\Users\helde\Repos\Bois\YYYY-MM-DD\` — create a symlink to fix.

```powershell
# yawcam_monitor_v4.ps1
$YawcamPath = "C:\Program Files (x86)\Yawcam\yawcam.exe"
$VideoPath = "C:\TEMP\motion_videos"
$CheckInterval = 60
$MaxMinutesWithoutVideo = 15
$LastRestartTime = $null
$RestartCooldown = 600

function Test-YawcamRunning {
    $yawcam = Get-Process -Name "yawcam" -ErrorAction SilentlyContinue
    if ($yawcam) { return $true }
    $javaw = Get-Process -Name "javaw" -ErrorAction SilentlyContinue |
             Where-Object {$_.MainWindowTitle -like "*Yawcam*"}
    if ($javaw) { return $true }
    return $false
}

function Restart-YawcamSafely {
    Get-Process -Name "yawcam" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "javaw" -ErrorAction SilentlyContinue |
        Where-Object {$_.MainWindowTitle -like "*Yawcam*"} | Stop-Process -Force
    Start-Sleep -Seconds 5
    Get-PnpDevice | Where-Object {$_.FriendlyName -like "*HD User*"} | ForEach-Object {
        Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 8
    Start-Process -FilePath $YawcamPath
    $script:LastRestartTime = Get-Date
}

while ($true) {
    $LatestVideo = Get-ChildItem -Path $VideoPath -Recurse -Filter "*.avi" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($LatestVideo) {
        $MinutesAgo = [math]::Round(((Get-Date) - $LatestVideo.LastWriteTime).TotalMinutes, 1)
        if ($MinutesAgo -gt $MaxMinutesWithoutVideo) {
            if ($LastRestartTime -eq $null -or ((Get-Date) - $LastRestartTime).TotalSeconds -gt $RestartCooldown) {
                Restart-YawcamSafely
            }
        }
    } else {
        if (-not (Test-YawcamRunning)) {
            if ($LastRestartTime -eq $null -or ((Get-Date) - $LastRestartTime).TotalSeconds -gt $RestartCooldown) {
                Restart-YawcamSafely
            }
        }
    }
    Start-Sleep -Seconds $CheckInterval
}
```

---

### `C:\Program Files (x86)\Yawcam\start_monitor.ps1`
> Boot launcher for yawcam_monitor_v4.ps1. Waits 30s after login for system to stabilize, then starts the monitor hidden. Registered in `HKCU:\...\Run\YawcamMonitor`.

```powershell
# start_monitor.ps1 — waits 30s after boot, then starts monitor hidden
Start-Sleep -Seconds 30
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1`"" -WindowStyle Hidden
```

---

### `C:\Sync\Config\health_check_all.ps1`
> Combined FolderSync + Camera health check. Evaluates FolderSync and Camera checks against the healthy baseline independently, prints a structured OVERALL summary, writes to `C:\Sync\Logs\ecosystem\health_check_YYYY-MM-DD.log`. Exit 0 = all pass, Exit 1 = any fail. Called by `check_health.bat` and `/project:health`.

```powershell
#Requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

# -- Paths -----------------------------------------------------------------
$LogFile     = "C:\Sync\Logs\ecosystem\health_check_$(Get-Date -Format yyyy-MM-dd).log"
$CheckStatus = "C:\Sync\Config\check_status.ps1"
$CheckCamera = "C:\Sync\Config\check_camera.ps1"

# -- Logging helpers -------------------------------------------------------
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

# -- Capture subscript output ----------------------------------------------
function Invoke-ScriptCapture($ScriptPath) {
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return "[ERROR] Script not found: $ScriptPath"
    }
    $out = & powershell.exe -ExecutionPolicy Bypass -NonInteractive -File $ScriptPath 2>&1 | Out-String
    return $out
}

# --------------------------------------------------------------------------
Write-Step "Running FolderSync health sub-check..."
Write-Log "--- BEGIN health_check_all.ps1 ---"
$statusOut = Invoke-ScriptCapture $CheckStatus
Write-Step "Running Camera health sub-check..."
$cameraOut = Invoke-ScriptCapture $CheckCamera

$fsIssues = @()
$task = Get-ScheduledTask -TaskName FolderSync-CloudBackup -ErrorAction SilentlyContinue
if (-not $task) { $fsIssues += "FolderSync-CloudBackup task: NOT FOUND" }
elseif ($task.State -notin @("Ready","Running")) { $fsIssues += "FolderSync-CloudBackup task: State = $($task.State)" }

$wdTask = Get-ScheduledTask -TaskName FolderSync-Watchdog -ErrorAction SilentlyContinue
if (-not $wdTask) { $fsIssues += "FolderSync-Watchdog task: NOT FOUND" }
elseif ($wdTask.State -notin @("Ready","Running")) { $fsIssues += "FolderSync-Watchdog task: State = $($wdTask.State)" }

$wdSvc = Get-Service -Name FolderSyncWatchdog -ErrorAction SilentlyContinue
if (-not $wdSvc) { $fsIssues += "FolderSyncWatchdog service: NOT FOUND" }
else {
    if ($wdSvc.Status -ne "Running")      { $fsIssues += "FolderSyncWatchdog service: Status = $($wdSvc.Status)" }
    if ($wdSvc.StartType -ne "Automatic") { $fsIssues += "FolderSyncWatchdog service: StartType = $($wdSvc.StartType)" }
}
$audSvc = Get-Service -Name FolderSyncAuditor -ErrorAction SilentlyContinue
if (-not $audSvc) { $fsIssues += "FolderSyncAuditor service: NOT FOUND" }
else {
    if ($audSvc.Status -ne "Running")      { $fsIssues += "FolderSyncAuditor service: Status = $($audSvc.Status)" }
    if ($audSvc.StartType -ne "Automatic") { $fsIssues += "FolderSyncAuditor service: StartType = $($audSvc.StartType)" }
}
$rtReg = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name FolderSyncRealTime -ErrorAction SilentlyContinue
if (-not $rtReg -or [string]::IsNullOrWhiteSpace($rtReg.FolderSyncRealTime)) { $fsIssues += "Registry FolderSyncRealTime: NOT FOUND or empty" }
if (-not (Get-Process -Name RealTimeSync -ErrorAction SilentlyContinue)) { $fsIssues += "RealTimeSync process: NOT RUNNING" }
$rclonePath = "C:\Tools\Rclone\rclone.exe"
if (-not (Test-Path -LiteralPath $rclonePath)) { $fsIssues += "Rclone binary: NOT FOUND" }
else { $rv = & $rclonePath version 2>&1 | Select-Object -First 1; if ($rv -notmatch "rclone") { $fsIssues += "Rclone: bad version response" } }
# Cloud sync log today: exists
$todayLog = "C:\Sync\Logs\cloud_sync\cloud_sync_$(Get-Date -Format yyyy-MM-dd).log"
if (-not (Test-Path -LiteralPath $todayLog)) {
    $fsIssues += "Cloud sync log today: NOT FOUND ($todayLog)"
}

# ==========================================================================
# CAMERA BASELINE EVALUATION
# ==========================================================================
$camIssues = @()

# Yawcam process (yawcam or javaw): running
$yawProc   = Get-Process -Name yawcam -ErrorAction SilentlyContinue
$javawProc = Get-Process -Name javaw  -ErrorAction SilentlyContinue
if (-not $yawProc -and -not $javawProc) {
    $camIssues += "Yawcam process (yawcam or javaw): NOT RUNNING"
}

# Monitor process (powershell with yawcam_monitor): running
$monProc = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "yawcam_monitor" }
if (-not $monProc) {
    $camIssues += "Yawcam monitor process (powershell yawcam_monitor): NOT RUNNING"
}

# Webcam PnP device: Status = OK
$webcam = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match "camera|webcam|HD User Facing" -and $_.Class -eq "Camera" } |
    Select-Object -First 1
if (-not $webcam) {
    $camIssues += "Webcam PnP device: NOT FOUND"
} elseif ($webcam.Status -ne "OK") {
    $camIssues += "Webcam PnP device: Status = $($webcam.Status) (expected OK)"
}

# Registry Yawcam: non-empty
$yawReg = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name Yawcam -ErrorAction SilentlyContinue
if (-not $yawReg -or [string]::IsNullOrWhiteSpace($yawReg.Yawcam)) {
    $camIssues += "Registry Yawcam: NOT FOUND or empty"
}

# Registry YawcamMonitor: non-empty
$monReg = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name YawcamMonitor -ErrorAction SilentlyContinue
if (-not $monReg -or [string]::IsNullOrWhiteSpace($monReg.YawcamMonitor)) {
    $camIssues += "Registry YawcamMonitor: NOT FOUND or empty"
}

# ==========================================================================
# SUMMARY
# ==========================================================================
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$fsPass      = $fsIssues.Count -eq 0
$camPass     = $camIssues.Count -eq 0
$overallPass = $fsPass -and $camPass

$fsLabel    = if ($fsPass)      { "PASS" } else { "FAIL -- $($fsIssues.Count) issue(s)" }
$camLabel   = if ($camPass)     { "PASS" } else { "FAIL -- $($camIssues.Count) issue(s)" }
$overallLbl = if ($overallPass) { "ALL SYSTEMS OPERATIONAL" } else { "$($fsIssues.Count + $camIssues.Count) ISSUE(S) FOUND" }

$summaryLines = @(
    "============================================================",
    "  ECOSYSTEM HEALTH SUMMARY -- $timestamp",
    "============================================================",
    "  FOLDERSYNC  : $fsLabel",
    "  CAMERA      : $camLabel",
    "------------------------------------------------------------",
    "  OVERALL     : $overallLbl",
    "============================================================"
)

Write-Host ""
foreach ($line in $summaryLines) { Write-Host $line }

if (-not $fsPass) {
    Write-Host "`n  FolderSync issues:" -ForegroundColor Red
    foreach ($issue in $fsIssues) { Write-Fail "    $issue" }
}
if (-not $camPass) {
    Write-Host "`n  Camera issues:" -ForegroundColor Red
    foreach ($issue in $camIssues) { Write-Fail "    $issue" }
}
Write-Host ""

foreach ($line in $summaryLines) { Write-Log $line }
if (-not $fsPass)  { foreach ($i in $fsIssues)  { Write-Log "  FOLDERSYNC ISSUE: $i" } }
if (-not $camPass) { foreach ($i in $camIssues) { Write-Log "  CAMERA ISSUE: $i" } }
Write-Log "--- END health_check_all.ps1 ---"

if ($overallPass) { exit 0 } else { exit 1 }
```

---

### `C:\Sync\check_health.bat`
> Double-click launcher for Windows Explorer. Opens a PowerShell window, runs the full health check, pauses so results stay visible.

```batch
@echo off
title FolderSync + Camera Health Check
powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "C:\Sync\Config\health_check_all.ps1"
echo.
pause
```

---

## 17. Validation Summary

| Test | Date | Result |
|---|---|---|
| `rclone lsd cloudsync:` | 2026-02-21 | ✅ Bucket `helder-sync-mirror` listed |
| Cloud upload test | 2026-02-21 | ✅ 14 B transferred to B2 |
| Local mirror (robocopy) | 2026-02-21 | ✅ 233 files / 283 MB mirrored |
| `FolderSync-CloudBackup` task | 2026-02-21 | ✅ Ready (SYSTEM) |
| `FolderSync-Watchdog` task | 2026-02-21 | ✅ Running (`LAP\helde`) |
| `FolderSyncWatchdog` service | 2026-02-21 | ✅ Running, Automatic |
| `FolderSyncAuditor` service | 2026-02-21 | ✅ Running, Automatic |
| RealTimeSync process | 2026-02-21 | ✅ Running |
| B2 key rotation (scoped) | 2026-03-02 | ✅ Scoped key active |
| RDP disabled | 2026-03-01 | ✅ fDenyTSConnections=1 |
| WinRM disabled | 2026-03-01 | ✅ Stopped + Disabled |
| RemoteRegistry disabled | 2026-03-01 | ✅ Stopped + Disabled |
| SMB2 disabled | 2026-03-01 | ✅ Disabled |
| C:\Sync\Config ACL locked | 2026-03-01 | ✅ User+SYSTEM+Admins only |
| Firewall logging active | 2026-03-01 | ✅ → C:\Sync\Logs\firewall.log |
| Auto-lock 5 minutes | 2026-03-01 | ✅ Configured |
| Account lockout 5 attempts | 2026-03-01 | ✅ Configured |
| DailySecurityCheck v7 | 2026-03-02 | ⏳ Pending install via setup_all.ps1 |
| B2 Lifecycle Rules | — | ⏳ Pending (Backblaze web UI) |
| BIOS password | — | ⏳ Pending |

---

### `C:\Sync\Config\start_ecosystem.ps1`
> Starts all ecosystem components. Gate: `#Requires -RunAsAdministrator`. Writes `.ecosystem_state = running`.
> Fixed 2026-03-08: Yawcam and CAM-2 relay now verified with Get-Process after Start-Process (no more false-positive OK). HKCU\Run registry entries auto-restored if missing.
> Fixed 2026-03-10: HKCU\Run registry enforcement changed from "set if missing" to "set if missing or incorrect" — prevents Yawcam entry from silently staying as `Yawcam.exe` (no working dir) instead of `start_yawcam.bat` (correct working dir). Root cause of recurring launcher.cfg error at logon.

```powershell
#Requires -RunAsAdministrator
# start_ecosystem.ps1 -- see full file in git for complete version
$ErrorActionPreference = 'SilentlyContinue'
$LogFile   = "C:\Sync\Logs\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$StateFile = "C:\Sync\Config\.ecosystem_state"
function Write-Log($msg) { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts  $msg" | Add-Content -LiteralPath $LogFile }
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
# Starts: FolderSyncWatchdog, FolderSyncAuditor, scheduled tasks, RealTimeSync, Yawcam (with PID confirm), CAM-2 relay (with VLC PID confirm)
# Enforces HKCU\Run entries (Yawcam -> start_yawcam.bat, YawcamMonitor, YawcamCam2Relay) - overwrites if wrong
# Clears .camera_paused flag if present
# Writes: 'running' | Set-Content -LiteralPath $StateFile -Encoding UTF8
# Full source: C:\Sync\Config\start_ecosystem.ps1 (committed to git)
```

---

### `C:\Sync\Config\stop_ecosystem.ps1`
> Stops all ecosystem components in reverse order. Gate: `#Requires -RunAsAdministrator`. Writes `.ecosystem_state = stopped`.

```powershell
#Requires -RunAsAdministrator
# stop_ecosystem.ps1 -- see full file in git for complete version
$ErrorActionPreference = 'SilentlyContinue'
$LogFile   = "C:\Sync\Logs\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$StateFile = "C:\Sync\Config\.ecosystem_state"
# Stops in reverse order: CAM-2 relay (VLC), Yawcam, RealTimeSync, scheduled tasks (disable),
#   FolderSyncAuditor, FolderSyncWatchdog
# Writes: 'stopped' | Set-Content -LiteralPath $StateFile -Encoding UTF8
# Full source: C:\Sync\Config\stop_ecosystem.ps1 (committed to git)
```

---

### `C:\Sync\Config\pause_camera.ps1`
> Stops Yawcam only; sets `.camera_paused` flag. Gate: `#Requires -RunAsAdministrator`. Resume with `resume_camera.ps1`.

```powershell
#Requires -RunAsAdministrator
# pause_camera.ps1
$ErrorActionPreference = 'SilentlyContinue'
$LogFile    = "C:\Sync\Logs\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$PausedFlag = "C:\Sync\Config\.camera_paused"
function Write-Log($msg) { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts  $msg" | Add-Content -LiteralPath $LogFile }
if (Test-Path $PausedFlag) { Write-Host "  WARN Camera already paused" -ForegroundColor Yellow; exit 0 }
Get-Process yawcam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process javaw -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*Yawcam*' } | Stop-Process -Force -ErrorAction SilentlyContinue
'paused' | Set-Content -LiteralPath $PausedFlag -Encoding UTF8
Write-Log "CAMERA-PAUSE  Yawcam stopped, .camera_paused flag set"
Write-Host "  OK   Camera paused. Run resume_camera.ps1 to restart." -ForegroundColor Green
```

---

### `C:\Sync\Config\resume_camera.ps1`
> Starts Yawcam; removes `.camera_paused` flag. Gate: `#Requires -RunAsAdministrator`.

```powershell
#Requires -RunAsAdministrator
# resume_camera.ps1
$ErrorActionPreference = 'SilentlyContinue'
$LogFile    = "C:\Sync\Logs\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$PausedFlag = "C:\Sync\Config\.camera_paused"
function Write-Log($msg) { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts  $msg" | Add-Content -LiteralPath $LogFile }
if (-not (Test-Path $PausedFlag)) { Write-Host "  WARN .camera_paused flag not found -- camera may already be running" -ForegroundColor Yellow; exit 0 }
Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe" `
    -WorkingDirectory "C:\Program Files (x86)\Yawcam" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Remove-Item -LiteralPath $PausedFlag -Force -ErrorAction SilentlyContinue
Write-Log "CAMERA-RESUME  Yawcam started, .camera_paused flag removed"
Write-Host "  OK   Camera resumed (Yawcam started)." -ForegroundColor Green
```

---

### `C:\Sync\Config\start_yawcam.bat`
> Boot launcher wrapper for Yawcam. Registered as `HKCU\Run\Yawcam`. Sets working directory to Yawcam install folder before starting `Yawcam.exe`, preventing the "launcher.cfg not found" error that occurs when the HKCU Run key launches the exe directly without a working directory.

```bat
@echo off
cd /d "C:\Program Files (x86)\Yawcam"
start "" "Yawcam.exe"
```

---

### `C:\Sync\Config\yawcam_monitor_v4.ps1`
> Relocated from `C:\Program Files (x86)\Yawcam\`. Infinite-loop monitor.
> Checks `C:\TEMP\motion_videos` (symlink to Bois) for .avi files. Restarts Yawcam if > 15 min without recording.

```powershell
# yawcam_monitor_v4.ps1 -- Relocated to C:\Sync\Config\
# Full source committed to git. Key parameters:
$YawcamPath      = "C:\Program Files (x86)\Yawcam\yawcam.exe"
$VideoPath       = "C:\TEMP\motion_videos"  # should be symlink to C:\Users\helde\Repos\Bois
$CheckInterval   = 60     # seconds between checks
$MaxMinutesWithoutVideo = 15   # threshold before restart
$RestartCooldown = 600    # seconds between restarts (10 min)
# Loop: if latest .avi > 15 min old AND not in cooldown -> Restart-YawcamSafely
# Restart sequence: kill Yawcam -> disable/enable webcam PnP -> start Yawcam
```

---

### `C:\Sync\Config\start_monitor.ps1`
> Boot launcher. Relocated from `C:\Program Files (x86)\Yawcam\`.
> Registry Run `YawcamMonitor` -> `C:\Sync\Config\start_monitor.ps1`

```powershell
# start_monitor.ps1 -- Relocated to C:\Sync\Config\
Start-Sleep -Seconds 30
Start-Process powershell.exe `
    -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\yawcam_monitor_v4.ps1"' `
    -WindowStyle Hidden
```

### `C:\Sync\Config\auto_commit_logs.ps1`
> Daily git commit of Logs/ files. Runs via Task Scheduler as `LAP\helde` at 23:30.
> Skips silently if nothing changed or if `git index.lock` exists.
> Logs one line to `ecosystem_YYYY-MM-DD.log` on each run.

```powershell
# auto_commit_logs.ps1
# Commits any dirty Logs/ files to git once per day.
# Runs as LAP\helde (interactive) via Task Scheduler at 23:30.
# Skips silently if nothing changed or if git is locked.

$RepoRoot = 'C:\Sync'
$LogDir   = 'C:\Sync\Logs'
$EcoLog   = "$LogDir\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-EcoLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $EcoLog
}

# Guard: abort if git index is locked (another git op in progress)
$lockFile = "$RepoRoot\.git\index.lock"
if (Test-Path $lockFile) {
    Write-EcoLog "GIT-COMMIT-LOGS  SKIP  git index.lock exists - skipping this run"
    exit 0
}

# Check for dirty Logs/ files
$statusLines = & git -C $RepoRoot status --porcelain -- Logs/ 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git status failed: $statusLines"
    exit 1
}

$dirty = $statusLines | Where-Object { $_ -match '\S' }
if (-not $dirty) {
    Write-EcoLog "GIT-COMMIT-LOGS  SKIP  no Logs/ changes"
    exit 0
}

# Stage and commit
$commitMsg = "logs: auto-commit $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

& git -C $RepoRoot add Logs/ 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git add failed"
    exit 1
}

$commitOut = & git -C $RepoRoot commit -m $commitMsg 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  OK  committed $($dirty.Count) Logs/ file(s): $commitMsg"
} else {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git commit failed: $commitOut"
    exit 1
}
```

---

*Generated by Claude (claude-sonnet-4-6)*
*Safe to upload to GitHub Gist - contains no secrets.*
*Do NOT include `rclone.conf` in any gist.*
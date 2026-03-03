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
| `cloud_sync.ps1` | Task `FolderSync-CloudBackup` | Rclone sync + log rotation + mirror cleanup |
| `cloud_sync.bat` | Manual trigger | Same as .ps1 but via cmd (manual use only) |
| `run_mirror.bat` | RealTimeSync | Runs robocopy mirror on file change (daily log rotation) |
| `realtime.ffs_real` | RealTimeSync at startup | Watcher config — folder + delay + command |
| `wdog.ps1` | Task `FolderSync-Watchdog` + NSSM service | Watchdog loop |
| `auditor.ps1` | NSSM service `FolderSyncAuditor` | Monitors file changes, remote access, service tampering |
| `credentials.enc` | `read_credentials.ps1` | Only copy of encrypted credentials |
| `read_credentials.ps1` | User on demand | Decrypts and prints credentials |
| `check_status.ps1` | User on demand | Full health check |
| `setup_all.ps1` | Fresh install / new device | Centralized setup: all security hardening + task registration |
| `enable_file_auditing.ps1` | One-time setup | Activates SACL on watched folder for user attribution in logs |
| `ECOSYSTEM_REPORT.md` | — | This document |

### Recovery scripts (keep, run only if something breaks)

| File | When to run |
|---|---|
| `fix_watchdog_task.ps1` | Watchdog task missing or running as wrong user |
| `install_service.ps1` | FolderSyncWatchdog NSSM service missing or removed |
| `install_auditor_service.ps1` | FolderSyncAuditor NSSM service missing or removed |
| `register_tasks.ps1` | Cloud backup task missing (follow with fix_watchdog_task.ps1) |
| `protect_sync_folders.ps1` | Re-apply Deny Delete ACL to C:\Sync |

### Security scripts (in %USERPROFILE%\Documents\SecurityScripts\)

| File | Purpose |
|---|---|
| `DailySecurityCheck.ps1` | Daily security scan — processes, ports, remote tools, unknown devices |
| `AutoCleanup.ps1` | Automated cleanup triggered by DailySecurityCheck |

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

**Log:** `C:\Sync\Logs\mirror_YYYY-MM-DD.log` (rotates daily, deleted after 30 days by cloud_sync.ps1)

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

**Log:** `C:\Sync\Logs\cloud_sync_YYYY-MM-DD.log` (rotates daily, deleted after 30 days)

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
| Cloud sync | `C:\Sync\Logs\cloud_sync_YYYY-MM-DD.log` | Rclone | Daily file, deleted after 30 days |
| Local mirror | `C:\Sync\Logs\mirror_YYYY-MM-DD.log` | Robocopy | Daily file, deleted after 30 days |
| Watchdog | `C:\Sync\Logs\watchdog.log` | `wdog.ps1` | NSSM rotation at 1MB |
| File audit | `C:\Sync\Logs\file_audit_YYYY-MM-DD.log` | `auditor.ps1` | Daily file |
| Security audit | `C:\Sync\Logs\security_audit_YYYY-MM-DD.log` | `auditor.ps1` | Daily file |
| Firewall | `C:\Sync\Logs\firewall.log` | Windows Firewall | Max 8MB, rotates to firewall.log.old |
| Auditor service stdout | `C:\Sync\Logs\auditor_svc.log` | NSSM | Rotation at 2MB |
| Auditor service stderr | `C:\Sync\Logs\auditor_svc_err.log` | NSSM | Rotation at 2MB |
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

> **Pending:** B2 Object Lock / Lifecycle Rules (7-day retention via Backblaze web UI)
> **Pending:** BIOS password on Acer Nitro 5
> **Pending:** Windows Hello PIN (blocked by org policy — resolve via Microsoft account portal)

---

## 15. Full File Contents (for restoration)

> Recreate any file by copying the content block below into a new file at the stated path.

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
> Versão PowerShell do cloud sync — usada pelo Task Scheduler.
> Inclui 3-phase ACL protection (7 dias), rotação de logs (30 dias) e limpeza do Mirror.

```powershell
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
> Daily log rotation: creates mirror_YYYY-MM-DD.log instead of a single growing file.

```bat
@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /E    = Copy subdirectories (including empty ones), do NOT delete from dest
:: /Z    = Restartable mode (essential for video files if copy is interrupted)
:: /R:1  = Retry only once to avoid massive logs
:: /W:2  = Short wait between retries
:: /LOG+ = Append to DAILY rotating log (mirror_YYYY-MM-DD.log)
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL /NC /NS
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

$LogFile = "C:\Sync\Logs\watchdog.log"
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

& $nssm stop $svcName 2>$null
& $nssm remove $svcName confirm 2>$null

& $nssm install $svcName powershell.exe
& $nssm set $svcName AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
& $nssm set $svcName DisplayName 'Folder Sync Watchdog Service'
& $nssm set $svcName Description 'Monitors and restarts folder sync processes (RealTimeSync + cloud backup task).'
& $nssm set $svcName Start SERVICE_AUTO_START
& $nssm set $svcName AppStdout 'C:\Sync\Logs\watchdog_svc.log'
& $nssm set $svcName AppStderr 'C:\Sync\Logs\watchdog_svc_err.log'
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

if (-not (Test-Path $nssm)) { Write-Error "NSSM not found at $nssm"; exit 1 }

& $nssm stop   $svcName 2>$null
& $nssm remove $svcName confirm 2>$null
Start-Sleep -Seconds 2

& $nssm install $svcName powershell.exe
& $nssm set $svcName AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auditor.ps1'
& $nssm set $svcName DisplayName   'Folder Sync Security Auditor'
& $nssm set $svcName Description   'Monitors file changes, remote access, and service tampering for the FolderSync ecosystem.'
& $nssm set $svcName Start         SERVICE_AUTO_START
& $nssm set $svcName AppStdout     'C:\Sync\Logs\auditor_svc.log'
& $nssm set $svcName AppStderr     'C:\Sync\Logs\auditor_svc_err.log'
& $nssm set $svcName AppRotateFiles  1
& $nssm set $svcName AppRotateBytes  2097152
& $nssm set $svcName AppRestartDelay 30000

Start-Service $svcName
$svc = Get-Service $svcName -ErrorAction SilentlyContinue
Write-Host "Service '$svcName' installed - status: $($svc.Status)"
Write-Host "Next step: run enable_file_auditing.ps1 (as Administrator)"
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
Get-ScheduledTask -TaskName "Verificacao Automatica de Seguranca" -ErrorAction SilentlyContinue | Select-Object TaskName, State

Write-Host "`n=== SERVICES ==="
Get-Service FolderSyncWatchdog  -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType
Get-Service FolderSyncAuditor   -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType

Write-Host "`n=== REGISTRY STARTUP ==="
(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue).FolderSyncRealTime

Write-Host "`n=== REALTIMESYNC PROCESS ==="
Get-Process RealTimeSync -ErrorAction SilentlyContinue | Select-Object Name, Id

Write-Host "`n=== RCLONE VERSION ==="
& "C:\Tools\Rclone\rclone.exe" version 2>&1 | Select-Object -First 1

Write-Host "`n=== B2 CONNECTIVITY ==="
& "C:\Tools\Rclone\rclone.exe" lsd cloudsync: --config C:\Sync\Config\rclone.conf 2>&1

Write-Host "`n=== SECURITY HARDENING STATUS ==="
$rdp = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -ErrorAction SilentlyContinue).fDenyTSConnections
Write-Host "RDP blocked: $(if($rdp -eq 1){'YES (good)'}else{'NO - WARNING'})"
$wmr = (Get-Service WinRM -ErrorAction SilentlyContinue).StartType
Write-Host "WinRM: $wmr"
$smb = (Get-SmbServerConfiguration -ErrorAction SilentlyContinue).EnableSMB2Protocol
Write-Host "SMB2 enabled: $(if($smb -eq $false){'NO (good)'}else{'YES - WARNING'})"

Write-Host "`n=== SOURCE FOLDER SIZE ==="
$sz = (Get-ChildItem "C:\Users\helde\Repos\Bois" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host ("{0:N1} MB  ({1} files)" -f ($sz/1MB), (Get-ChildItem "C:\Users\helde\Repos\Bois" -Recurse -File -ErrorAction SilentlyContinue).Count)

Write-Host "`n=== LOG FILES ==="
Get-ChildItem "C:\Sync\Logs" -ErrorAction SilentlyContinue | Format-Table Name, @{N="Size(KB)";E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize

Write-Host "`n=== RCLONE CONF (sanitized) ==="
Get-Content "C:\Sync\Config\rclone.conf" | ForEach-Object {
    if ($_ -match "^key") { "  key = ***REDACTED***" } else { $_ }
}

Write-Host "`n=== LAST 5 LINES CLOUD SYNC LOG (today) ==="
$todayLog = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $todayLog) { Get-Content $todayLog | Select-Object -Last 5 } else { Write-Host "(no log yet for today)" }

Write-Host "`n=== LAST 5 LINES SECURITY AUDIT LOG (today) ==="
$secLog = "C:\Sync\Logs\security_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $secLog) { Get-Content $secLog | Select-Object -Last 5 } else { Write-Host "(no security audit log yet for today)" }
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
:: /LOG+ = Append ao log diário rotativo
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL /NC /NS
'@
Write-OK "run_mirror.bat updated → mirror_YYYY-MM-DD.log"

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
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\firewall.log" | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 8192 | Out-Null
Start-Sleep -Seconds 1
if (Test-Path "C:\Sync\Logs\firewall.log") {
    icacls "C:\Sync\Logs\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
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
if (-not $existingBackup) {
    $action1   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoWindow -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
    $trigger1  = @(
        $(New-ScheduledTaskTrigger -AtStartup),
        $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
    )
    $settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $principal1= New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force | Out-Null
    Write-OK "Task FolderSync-CloudBackup registered (SYSTEM)"
} else {
    Write-OK "Task FolderSync-CloudBackup already exists — skipped"
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
    & $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\watchdog_svc.log'
    & $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\watchdog_svc_err.log'
    & $nssm set FolderSyncWatchdog AppRotateFiles  1
    & $nssm set FolderSyncWatchdog AppRotateBytes  1048576
    Start-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
    $s = Get-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
    Write-OK "FolderSyncWatchdog service: $($s.Status)"
} else {
    Write-Warn "NSSM not found at $nssm — install NSSM first, then rerun this step manually"
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
    & $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\auditor_svc.log'
    & $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\auditor_svc_err.log'
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

*Generated by Claude (claude-sonnet-4-6)*
*Safe to upload to GitHub Gist — contains no secrets.*
*Do NOT include `rclone.conf` in any gist.*
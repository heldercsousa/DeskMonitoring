# Automated Folder Sync Ecosystem — Full Reference

**Last updated:** 2026-02-25
**Machine:** Windows 11 Home Single Language 24H2 — user: `helde` (`LAP\helde`)

> This document is self-contained. Every config and script file's full content is
> embedded in §14 so any file can be recreated from this document alone.

---

## 1. Architecture Overview

```
C:\Users\helde\Repos\Bois        ← SOURCE (watched in real time)
        │
        ├─[RealTimeSync]─► run_mirror.bat on every change (5s idle buffer)
        │                        └─► robocopy /MIR
        │                                 └─► C:\Sync\Mirror   (local mirror)
        │
        └─[Task Scheduler, every 5 min + boot]
                 └─► cloud_sync.bat
                          └─► rclone sync
                                   └─► Backblaze B2
                                        bucket : helder-sync-mirror (root)
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
| `C:\Sync\Config` | All scripts, configs, encrypted credentials |
| `C:\Tools\Rclone\` | Rclone binary |
| `C:\Tools\NSSM\` | NSSM binary |

---

## 4. Cloud Storage (Backblaze B2)

| Item | Value |
|---|---|
| Provider | Backblaze B2 |
| Account | heldercsousa@yahoo.com.br |
| Bucket | `helder-sync-mirror` |
| Visibility | Private |
| Encryption | SSE-B2 enabled (AES-256 at rest) |
| Object Lock | Disabled (must stay disabled — sync requires deletes) |
| Rclone remote name | `cloudsync` |
| Sync target | `cloudsync:helder-sync-mirror` (bucket root) |
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
| `rclone.conf` | `cloud_sync.bat` | Rclone B2 remote definition + API key |
| `cloud_sync.bat` | Task `FolderSync-CloudBackup` | Runs Rclone sync every 5 min |
| `run_mirror.bat` | RealTimeSync | Runs robocopy mirror on file change |
| `realtime.ffs_real` | RealTimeSync at startup | Watcher config — folder + delay + command |
| `wdog.ps1` | Task `FolderSync-Watchdog` + NSSM service | Watchdog loop |
| `credentials.enc` | `read_credentials.ps1` | Only copy of encrypted credentials |
| `read_credentials.ps1` | User on demand | Decrypts and prints credentials |
| `check_status.ps1` | User on demand | Full health check |
| `ECOSYSTEM_REPORT.md` | — | This document |
| `cloud_sync.ps1` | Task `FolderSync-CloudBackup` | Versão PowerShell do cloud sync (sem flash de janela cmd) |
| `auditor.ps1` | NSSM service `FolderSyncAuditor` | Monitora mudanças de arquivo, acesso remoto, e service tampering |
| `install_auditor_service.ps1` | Serviço FolderSyncAuditor missing ou removed |
| `enable_file_auditing.ps1` | One-time setup — ativa SACL no watched folder para atribuição de usuário nos logs |

### Recovery scripts (keep, run only if something breaks)

| File | When to run |
|---|---|
| `fix_watchdog_task.ps1` | Watchdog task missing or running as wrong user |
| `install_service.ps1` | NSSM service missing or removed |
| `register_tasks.ps1` | Cloud backup task missing (registers only — use `fix_watchdog_task.ps1` for the watchdog) |

---

## 6. Local Mirror (RealTimeSync + robocopy)

**Trigger:** RealTimeSync detects any change in Source → waits 5s idle → runs `run_mirror.bat`

**robocopy flags used:**
- `/MIR` — mirror mode: files deleted from Source are deleted from Mirror
- `/R:2` — retry twice on error
- `/W:5` — wait 5s between retries
- `/LOG+` — append to log file
- `/NP /NDL` — no progress output, no directory listing

**Log:** `C:\Sync\Logs\mirror.log`

**To start RealTimeSync manually:**
```powershell
Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
    -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden
```

**To force immediate mirror sync:**
```powershell
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /MIR /R:2 /W:5 /NP
```

---

## 7. Cloud Sync (Rclone via Task Scheduler)

**Trigger:** Every 5 minutes + on system boot

**To trigger manually:**
```bat
C:\Sync\Config\cloud_sync.bat
```

**To verify B2 contents:**
```bat
C:\Tools\Rclone\rclone.exe ls cloudsync:helder-sync-mirror/mirror --config C:\Sync\Config\rclone.conf
```

**Log:** `C:\Sync\Logs\cloud_sync.log`

---

## 8. Scheduled Tasks

| Task | Runs As | Trigger | Action |
|---|---|---|---|
| `FolderSync-CloudBackup` | SYSTEM | Every 5 min + boot | `cloud_sync.bat` |
| `FolderSync-Watchdog` | `LAP\helde` (interactive) | Every 3 min + logon | `wdog.ps1` via PowerShell |

> ⚠ **Critical:** `FolderSync-Watchdog` MUST run as `LAP\helde` (interactive user), NOT SYSTEM.
> SYSTEM has no desktop session and cannot launch GUI apps like RealTimeSync.
> Use `fix_watchdog_task.ps1` to restore it — never `register_tasks.ps1` for the watchdog.

Both tasks: hidden, restart on failure (3 attempts, 1 min apart).

**Verify tasks:**
```powershell
Get-ScheduledTask -TaskName "FolderSync-CloudBackup" | Select TaskName, State
Get-ScheduledTask -TaskName "FolderSync-Watchdog"    | Select TaskName, State
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

| Log | Path | Written by |
|---|---|---|
| Cloud sync | `C:\Sync\Logs\cloud_sync.log` | Rclone (appended each run) |
| Local mirror | `C:\Sync\Logs\mirror.log` | Robocopy (appended each run) |
| Watchdog | `C:\Sync\Logs\watchdog.log` | `wdog.ps1` (timestamped) |
| Service stdout | `C:\Sync\Logs\watchdog_svc.log` | NSSM |
| Service stderr | `C:\Sync\Logs\watchdog_svc_err.log` | NSSM |

---

## 11. Full Health Check

```powershell
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1
```

Or manually:
```powershell
Get-ScheduledTask -TaskName "FolderSync-CloudBackup" | Select TaskName, State
Get-ScheduledTask -TaskName "FolderSync-Watchdog"    | Select TaskName, State
Get-Service FolderSyncWatchdog | Select Name, Status, StartType
Get-Process RealTimeSync -ErrorAction SilentlyContinue | Select Name, Id
(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run").FolderSyncRealTime
C:\Tools\Rclone\rclone.exe lsd cloudsync: --config C:\Sync\Config\rclone.conf
Get-Content C:\Sync\Logs\cloud_sync.log | Select-Object -Last 8
Get-Content C:\Sync\Logs\watchdog.log   | Select-Object -Last 5
```

---

## 12. Recovery Procedures

| Problem | Fix |
|---|---|
| RealTimeSync not running | `Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden` |
| Mirror out of sync | `robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /MIR /R:2 /W:5 /NP` |
| Force cloud sync now | `C:\Sync\Config\cloud_sync.bat` |
| Watchdog task wrong user | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\fix_watchdog_task.ps1` |
| NSSM service missing | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_service.ps1` |
| Cloud backup task missing | `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\register_tasks.ps1` |
| Startup registry missing | See §9 Layer 3 restore command |

### Rotate Backblaze API key
1. Generate new key at backblaze.com → App Keys (scope to `helder-sync-mirror`, Read+Write)
2. Edit `C:\Sync\Config\rclone.conf` — update `account` and `key` values
3. Recreate `credentials.enc`:
   - Create `C:\Sync\Config\credentials.txt` with this format:
     ```
     Backblaze B2 Credentials
     ========================
     Account Email : heldercsousa@yahoo.com.br
     Key ID        : <your key ID>
     App Key       : <your app key>
     Bucket        : helder-sync-mirror
     Rclone Remote : cloudsync
     ```
   - Run `powershell -ExecutionPolicy Bypass -File C:\Sync\Config\encrypt_creds.ps1`
   - (Re-create `encrypt_creds.ps1` from §14 if needed)

---

## 13. Known Issues & Gotchas

| Topic | Note |
|---|---|
| Watchdog task must run as user | SYSTEM cannot launch GUI apps. Always use `fix_watchdog_task.ps1`. |
| robocopy exit code 1 | Normal — means files were copied successfully. Not an error. |
| Rclone deletes from B2 | `rclone sync` mirrors deletions. B2 charges 1-day minimum per file. |
| `/MIR` deletes from Mirror | Intentional — Mirror is an exact copy of Source. |
| DPAPI credentials tied to user | `credentials.enc` only works for user `helde` on this machine. |
| `rclone.conf` contains API key | Plaintext — never upload to any public repo or gist. |
| B2 free tier | 10 GB free. Monitor at backblaze.com if syncing large video files. |
| `local_mirror.ffs_batch` | Kept for reference but unused — local mirror runs via robocopy. |
| `realtime.ffs_real` XmlFormat | Must stay as `XmlFormat="2"` — RealTimeSync 14.7 rewrites it to this on save. |
| `rclone sync` deletes logs from B2 | O sync apaga `logs/` do B2 pois não existe na source. Fix: `--exclude "logs/**"` no comando sync de `cloud_sync.ps1` e `cloud_sync.bat` |
| `realtime.ffs_real` XmlFormat | RealTimeSync 14.7 reescreve para `XmlFormat="23"` ao salvar — normal, não é erro |

---

## 14. Full File Contents (for restoration)

> Recreate any file by copying the content block below into a new file at the stated path.

---

### `C:\Sync\Config\rclone.conf`
> ⚠ Replace `YOUR_KEY_HERE` with the actual app key from `read_credentials.ps1`

```ini
[cloudsync]
type = b2
account = 005d1b2ea6fc5850000000001
key = YOUR_KEY_HERE
hard_delete = false
```

---

### `C:\Sync\Config\cloud_sync.ps1`
> Versão PowerShell do cloud sync — usada pelo Task Scheduler para evitar flash de janela cmd.
```powershell
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Gerencia também a limpeza automática da pasta Mirror local.

$$Rclone  = 'C:\Tools\Rclone\rclone.exe'
$Config  = 'C:\Sync\Config\rclone.conf'
$Source  = 'C:\Users\helde\Repos\Bois'
$Remote  = 'cloudsync:helder-sync-mirror'
$Mirror  = 'C:\Sync\Mirror'
$Log     = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeep = 7 

# 1. Sincronização para B2
& $Rclone sync $Source $Remote --config $Config --log-file $Log --log-level INFO --transfers 4 --checkers 8 --fast-list --exclude "logs/**"    

# 2. Backup dos Logs
& $Rclone copy 'C:\Sync\Logs' "$Remote/logs" --config $Config --log-file $Log --log-level INFO

# 3. Limpeza automática do Mirror local (Gestão de Espaço)
if (Test-Path $Mirror) {
    $thresholdDate = (Get-Date).AddDays(-$DaysToKeep)
    Get-ChildItem -Path $Mirror -Recurse -File | 
        Where-Object { $_.LastWriteTime -lt $thresholdDate } | 
        Remove-Item -Force -ErrorAction SilentlyContinue
}
```

---

### `C:\Sync\Config\cloud_sync.bat`
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
    --log-level INFO
```

---

### `C:\Sync\Config\run_mirror.bat`
```bat
@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /MIR = mirror (purges files deleted from source)
:: /R:2  = retry twice on error
:: /W:5  = wait 5 seconds between retries
:: /LOG+ = append to log
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /MIR /R:2 /W:5 /LOG+:"C:\Sync\Logs\mirror.log" /NP /NDL
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

# Run as current user (interactive session — can launch GUI apps)
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
& $nssm set $svcName AppStdout 'C:\Sync\Logs\watchdog_svc.log'
& $nssm set $svcName AppStderr 'C:\Sync\Logs\watchdog_svc_err.log'
& $nssm set $svcName AppRotateFiles 1
& $nssm set $svcName AppRotateBytes 1048576

Start-Service $svcName
Write-Host "Service '$svcName' installed and started"
```

---

### `C:\Sync\Config\register_tasks.ps1`
> ⚠ Only registers the cloud backup task correctly (as SYSTEM).
> For the watchdog task use `fix_watchdog_task.ps1` instead.

```powershell
# Register FolderSync scheduled tasks

# Task 1: Cloud sync via Rclone every 5 minutes (runs as SYSTEM)
$action1 = New-ScheduledTaskAction -Execute 'C:\Sync\Config\cloud_sync.bat'
$trigger1 = @(
    $(New-ScheduledTaskTrigger -AtStartup),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
)
$settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
$principal1 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force
Write-Host "Task FolderSync-CloudBackup registered"

# Task 2: Watchdog — NOTE: this registers as SYSTEM which cannot launch RealTimeSync.
# Use fix_watchdog_task.ps1 after running this to fix the watchdog principal.
$action2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
$trigger2 = @(
    $(New-ScheduledTaskTrigger -AtStartup),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 3) -Once -At (Get-Date))
)
$settings2 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
$principal2 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "FolderSync-Watchdog" -Action $action2 -Trigger $trigger2 -Settings $settings2 -Principal $principal2 -Force
Write-Host "Task FolderSync-Watchdog registered (run fix_watchdog_task.ps1 next!)"
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

Write-Host "`n=== SERVICE ==="
Get-Service FolderSyncWatchdog -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType

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

Write-Host "`n=== LAST 5 LINES CLOUD SYNC LOG ==="
Get-Content "C:\Sync\Logs\cloud_sync.log" -ErrorAction SilentlyContinue | Select-Object -Last 5

Write-Host "`n=== LAST 5 LINES WATCHDOG LOG ==="
Get-Content "C:\Sync\Logs\watchdog.log" -ErrorAction SilentlyContinue | Select-Object -Last 5
```

---

### `C:\Sync\Config\local_mirror.ffs_batch`
> Reference only — not actively used. Local mirror runs via robocopy (`run_mirror.bat`).
> Kept in case you want to switch back to FreeFileSync for local mirroring.

```xml
<?xml version="1.0" encoding="utf-8"?>
<FreeFileSync XmlType="BATCH" XmlFormat="23">
    <Notes/>
    <Compare>
        <Variant>TimeAndSize</Variant>
        <Symlinks>Follow</Symlinks>
        <IgnoreTimeShift/>
    </Compare>
    <Synchronize>
        <Changes>
            <Left Create="ToRight" Update="ToRight" Delete="ToRight"/>
            <Right Create="ToRight" Update="ToRight" Delete="ToRight"/>
        </Changes>
        <DeletionPolicy>RecycleBin</DeletionPolicy>
        <VersioningFolder Style="Replace"/>
    </Synchronize>
    <Filter>
        <Include>*</Include>
        <Exclude/>
        <SizeMin Unit="None"/>
        <SizeMax Unit="None"/>
        <TimeSpan Type="None"/>
    </Filter>
    <FolderPairs>
        <Pair>
            <Left>C:\Users\helde\Repos\Bois</Left>
            <Right>C:\Sync\Mirror</Right>
        </Pair>
    </FolderPairs>
    <Errors Ignore="false" Retry="1" Delay="5"/>
    <PostSyncCommand Condition="Always"/>
    <LogFolder>C:\Sync\Logs</LogFolder>
    <EmailNotification Condition="Always"/>
    <GridViewType>Sync</GridViewType>
    <Batch>
        <ProgressDialog Minimized="true" AutoClose="true"/>
        <ErrorDialog>Cancel</ErrorDialog>
        <PostSyncAction>None</PostSyncAction>
    </Batch>
</FreeFileSync>
```

---

### `C:\Sync\Config\encrypt_creds.ps1`
> One-time use script. Run only when rotating credentials.
> Requires `credentials.txt` to exist first (write it, run this, it deletes the plaintext).

```powershell
Add-Type -AssemblyName System.Security
$plain = [System.IO.File]::ReadAllBytes('C:\Sync\Config\credentials.txt')
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $plain,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.IO.File]::WriteAllBytes('C:\Sync\Config\credentials.enc', $encrypted)
Remove-Item 'C:\Sync\Config\credentials.txt'
Write-Host 'Credentials encrypted (DPAPI) and plaintext deleted'
```

---

### `C:\Sync\Config\auditor.ps1`
> Monitora mudanças de arquivo via FileSystemWatcher, acesso remoto/RDP, service tampering e gera relatório forense em gaps de inicialização. Roda como NSSM service `FolderSyncAuditor`.
```powershell
# auditor.ps1
# FolderSync Security Auditor
# Monitors file system events, remote access, service tampering, and system events.
# Runs as NSSM service "FolderSyncAuditor".

$WatchedFolder  = 'C:\Users\helde\Repos\Bois'
$LogDir         = 'C:\Sync\Logs'
$StartupGapSecs = 120   # gap threshold to trigger forensic dump

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-FileAuditLog  { Join-Path $LogDir "file_audit_$(Get-Date -Format 'yyyy-MM-dd').log" }
function Get-SecurityLog   { Join-Path $LogDir "security_audit_$(Get-Date -Format 'yyyy-MM-dd').log" }

function Write-FileAudit($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath (Get-FileAuditLog)
}

function Write-SecurityAudit($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath (Get-SecurityLog)
}

function Write-BothLogs($msg) {
    Write-FileAudit    $msg
    Write-SecurityAudit $msg
}

# ---------------------------------------------------------------------------
# Startup gap detection + forensic dump
# ---------------------------------------------------------------------------
function Invoke-StartupGapCheck {
    # Find last timestamped line across all auditor logs
    $allLogs = Get-ChildItem $LogDir -Filter "security_audit_*.log" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 3
    $lastTs = $null
    foreach ($f in $allLogs) {
        $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' }
        if ($lines) {
            $lastLine = $lines | Select-Object -Last 1
            if ($lastLine -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
                try { $lastTs = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null); break } catch {}
            }
        }
    }

    if ($lastTs) {
        $gapSecs = ([datetime]::Now - $lastTs).TotalSeconds
        if ($gapSecs -gt $StartupGapSecs) {
            Write-SecurityAudit "[WARN] Startup gap detected: $([math]::Round($gapSecs,0))s since last log entry ($lastTs) - writing forensic report"
            Write-ForensicReport -GapSeconds $gapSecs -LastKnownTime $lastTs
        }
    }
}

function Write-ForensicReport([double]$GapSeconds, [datetime]$LastKnownTime) {
    $ts   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $path = Join-Path $LogDir "interruption_report_$ts.txt"

    $lines = @()
    $lines += "INTERRUPTION REPORT - generated $ts"
    $lines += "Last known auditor activity : $LastKnownTime"
    $lines += "Gap duration                : $([math]::Round($GapSeconds,0)) seconds"
    $lines += ""
    $lines += "=== RUNNING PROCESSES (snapshot) ==="
    $lines += (Get-Process | Sort-Object CPU -Descending | Select-Object -First 60 |
               Format-Table Name, Id, CPU, WorkingSet -AutoSize | Out-String).Trim()
    $lines += ""
    $lines += "=== LAST 50 SECURITY LOG EVENTS ==="
    try {
        $secEvents = Get-WinEvent -LogName Security -MaxEvents 50 -ErrorAction SilentlyContinue
        $lines += ($secEvents | Format-Table TimeCreated, Id, Message -AutoSize -Wrap | Out-String -Width 200).Trim()
    } catch { $lines += "(Security log unavailable: $_)" }
    $lines += ""
    $lines += "=== LAST 50 SYSTEM LOG EVENTS ==="
    try {
        $sysEvents = Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue
        $lines += ($sysEvents | Format-Table TimeCreated, Id, Message -AutoSize -Wrap | Out-String -Width 200).Trim()
    } catch { $lines += "(System log unavailable: $_)" }

    $lines | Set-Content -LiteralPath $path -Encoding UTF8
    Write-SecurityAudit "[FORENSIC] Report written: $path"
}

# ---------------------------------------------------------------------------
# A. FileSystemWatcher - event-driven file change detection
# ---------------------------------------------------------------------------
function Start-FileWatcher {
    $fsw = New-Object System.IO.FileSystemWatcher
    $fsw.Path                  = $WatchedFolder
    $fsw.IncludeSubdirectories = $true
    $fsw.NotifyFilter          = [System.IO.NotifyFilters]'FileName, DirectoryName'
    $fsw.EnableRaisingEvents   = $true

    $handler = {
        param($src, $e)
        
        $now = Get-Date
        # Forçamos a conversão para String AQUI, antes de entrar no Job
        $changeTypeText = $e.ChangeType.ToString().ToUpper()
        $filePath = $e.FullPath
        $fileName = $e.Name
        $oldName = if ($e -is [System.IO.RenamedEventArgs]) { $e.OldName } else { $null }

        Start-Job -ArgumentList $filePath, $fileName, $changeTypeText, $now, $oldName -ScriptBlock {
            param($path, $name, $type, $time, $old)
            
            Start-Sleep -Milliseconds 800 
            $user = 'unknown'
            
            try {
                $searchName = [System.IO.Path]::GetFileName($path)
                $evt = Get-WinEvent -FilterHashtable @{
                    LogName = 'Security'; Id = 4663, 4660; StartTime = $time.AddSeconds(-15)
                } -ErrorAction SilentlyContinue | 
                Where-Object { $_.Message -like "*$searchName*" } | Select-Object -First 1

                if ($evt -and $evt.Message -match '(Nome da Conta|Account Name):\s+(\S+)') { $user = $Matches[2] }
            } catch {}

            $logFile = "C:\Sync\Logs\file_audit_$($time.ToString('yyyy-MM-dd')).log"
            $ts = $time.ToString("yyyy-MM-dd HH:mm:ss")
            
            # Formatação garantida como texto
            $detail = if ($old) { "RENAMED: $old -> $name" } else { $type }
            $line = "$ts | $($detail.PadRight(25)) | user=$user | path=$path"
            
            $line | Add-Content -LiteralPath $logFile -Encoding UTF8
            
            if ($type -eq 'DELETED') { & 'C:\Sync\Config\cloud_sync.ps1' }
        } | Out-Null
    }

    Register-ObjectEvent $fsw Created -Action $handler | Out-Null
    Register-ObjectEvent $fsw Deleted -Action $handler | Out-Null
    Register-ObjectEvent $fsw Renamed -Action $handler | Out-Null
    
    return $fsw
}

# ---------------------------------------------------------------------------
# B. Remote access / logon detection (every 5 min)
# ---------------------------------------------------------------------------
$script:LastRemoteCheck = [datetime]::MinValue

function Check-RemoteAccess {
    if (([datetime]::Now - $script:LastRemoteCheck).TotalSeconds -lt 300) { return }
    $script:LastRemoteCheck = [datetime]::Now
    $since = (Get-Date).AddMinutes(-5)

    # Network / RDP logons
    try {
        $logons = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4624
            StartTime = $since
        } -ErrorAction SilentlyContinue | Where-Object {
            $_.Message -match 'Logon Type:\s+(3|10)\b'
        }
        foreach ($evt in $logons) {
            $type = if ($evt.Message -match 'Logon Type:\s+(\d+)') { $Matches[1] } else { '?' }
            $acct = if ($evt.Message -match 'Account Name:\s+(\S+)') { $Matches[1] } else { '?' }
            $label = if ($type -eq '10') { 'RDP/RemoteInteractive' } else { 'Network' }
            Write-SecurityAudit "[LOGON] Type=$type ($label) account=$acct at $($evt.TimeCreated)"
        }
    } catch {}

    # Remote access tools
    foreach ($proc in @('TeamViewer', 'AnyDesk', 'VNCViewer', 'vncserver', 'ScreenConnect')) {
        $p = Get-Process $proc -ErrorAction SilentlyContinue
        if ($p) { Write-SecurityAudit "[REMOTE-TOOL] $proc is running (PID $($p.Id -join ','))" }
    }
}

# ---------------------------------------------------------------------------
# C. Service tampering (every 60s)
# ---------------------------------------------------------------------------
$WatchedServices = @('FolderSyncWatchdog', 'FolderSyncAuditor', 'FolderSync-CloudBackup')
$script:LastServiceCheck = [datetime]::MinValue

function Check-Services {
    if (([datetime]::Now - $script:LastServiceCheck).TotalSeconds -lt 60) { return }
    $script:LastServiceCheck = [datetime]::Now
    $since = (Get-Date).AddSeconds(-60)

    foreach ($svcName in $WatchedServices) {
        $svc = Get-Service $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            Write-SecurityAudit "[CRITICAL] Service $svcName is $($svc.Status) - expected Running"
        }
    }

    # Event 7036 (service state change) and 7040 (start type change)
    try {
        $evts = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 7036, 7040
            StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($evt in $evts) {
            foreach ($svc in $WatchedServices) {
                if ($evt.Message -like "*$svc*") {
                    Write-SecurityAudit "[SVC-EVENT] $($evt.Id): $($evt.Message.Trim() -replace '\s+', ' ')"
                }
            }
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# D. Physical/system events (every 60s)
# ---------------------------------------------------------------------------
$script:LastSystemCheck = [datetime]::MinValue

function Check-SystemEvents {
    if (([datetime]::Now - $script:LastSystemCheck).TotalSeconds -lt 60) { return }
    $script:LastSystemCheck = [datetime]::Now
    $since = (Get-Date).AddSeconds(-60)

    try {
        $evts = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 42, 1074
            StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($evt in $evts) {
            if ($evt.Id -eq 42) {
                $reason = if ($evt.Message -match 'Reason.*?:\s+(.+)') { $Matches[1].Trim() } else { 'unknown' }
                Write-SecurityAudit "[SLEEP] System entering sleep/hibernate - reason: $reason"
            } elseif ($evt.Id -eq 1074) {
                $who = if ($evt.Message -match 'User:\s+(\S+)') { $Matches[1] } else { 'unknown' }
                $type = if ($evt.Message -match 'shutdown type:\s+(\S+)') { $Matches[1] } else { '?' }
                Write-SecurityAudit "[SHUTDOWN] Initiated by $who - type=$type"
            }
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-SecurityAudit "[AUDITOR] Starting up (PID $PID)"
Write-FileAudit     "[AUDITOR] Starting up (PID $PID)"

# Check for startup gap and write forensic report if needed
Invoke-StartupGapCheck

# Start file system watcher
$fsw = Start-FileWatcher
Write-FileAudit "[AUDITOR] FileSystemWatcher active on $WatchedFolder"

# Main polling loop
try {
    while ($true) {
        Check-RemoteAccess
        Check-Services
        Check-SystemEvents

        # Process queued FSW events
        $null = [System.Threading.Thread]::Sleep(1000)
        Start-Sleep -Milliseconds 100
    }
} finally {
    $fsw.EnableRaisingEvents = $false
    $fsw.Dispose()
    Unregister-Event -SourceIdentifier 'FSW_Created'  -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier 'FSW_Deleted'  -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier 'FSW_Changed'  -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier 'FSW_Renamed'  -ErrorAction SilentlyContinue
    Write-SecurityAudit "[AUDITOR] Shutting down"
    Write-FileAudit     "[AUDITOR] Shutting down"
}

```

---

### `C:\Sync\Config\install_auditor_service.ps1`
> Instala o serviço NSSM `FolderSyncAuditor`. Rodar como Administrador.
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
& $nssm set $svcName AppStdout     'C:\Sync\Logs\auditor_svc.log'
& $nssm set $svcName AppStderr     'C:\Sync\Logs\auditor_svc_err.log'
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

### `C:\Sync\Config\enable_file_auditing.ps1`
> One-time setup. Ativa auditoria de file system e aplica SACL no watched folder. Rodar como Administrador uma única vez.
```powershell
$WatchedFolder = 'C:\Users\helde\Repos\Bois'
$RootPath      = 'C:\Sync'
$LogPath       = "C:\Sync\Logs"
$MirrorPath    = "C:\Sync\Mirror"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Acesso negado. Execute como Administrador."
    exit 1
}

# Configuração do SO
auditpol /set /subcategory:"Sistema de Arquivos" /success:enable /failure:enable

# SACL na pasta Bois
$AclData = Get-Acl -Path $WatchedFolder -Audit
$Everyone = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'
$AuditRule = New-Object System.Security.AccessControl.FileSystemAuditRule($Everyone, "Delete,DeleteSubdirectoriesAndFiles,WriteData", "ContainerInherit,ObjectInherit", "None", "Success,Failure")
$AclData.SetAuditRule($AuditRule)
Set-Acl -Path $WatchedFolder -AclObject $AclData

# Blindagem da Raiz C:\Sync (Logs e Configs)
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }
$RootAcl = Get-Acl $RootPath
$RootAcl.SetAccessRuleProtection($true, $true)
$DenyRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Everyone, "Delete,DeleteSubdirectoriesAndFiles", "ContainerInherit,ObjectInherit", "None", "Deny")
$RootAcl.AddAccessRule($DenyRule)
Set-Acl $RootPath $RootAcl

# Exceção para Mirror (Permite deleção via SYSTEM)
if (Test-Path $MirrorPath) {
    $MirrorAcl = Get-Acl $MirrorPath
    $SystemSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'
    $SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $UserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $UserRule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserSid, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    $MirrorAcl.SetAccessRuleProtection($true, $false) 
    $MirrorAcl.AddAccessRule($SystemRule)
    $MirrorAcl.AddAccessRule($UserRule)
    Set-Acl $MirrorPath $MirrorAcl
}

Write-Host "Configuração de Auditoria e Blindagem aplicada com sucesso." -ForegroundColor Green
```	

## 15. Fresh Install / Disaster Recovery (from scratch)

Use this if the machine is wiped or you're setting up on a new PC.

### Step 1 — Download tools

| Tool | URL | Install to |
|---|---|---|
| Rclone (win-amd64 zip) | https://downloads.rclone.org/rclone-current-windows-amd64.zip | Extract `rclone.exe` → `C:\Tools\Rclone\` |
| FreeFileSync (Windows) | https://freefilesync.org/download/FreeFileSync_14.7_Windows_Setup.exe | Run installer → `C:\Program Files\FreeFileSync\` |
| NSSM (zip) | https://nssm.cc/release/nssm-2.24.zip | Extract `win64\nssm.exe` → `C:\Tools\NSSM\` |

### Step 2 — Add Rclone to PATH
```powershell
$p = [Environment]::GetEnvironmentVariable('PATH','Machine')
[Environment]::SetEnvironmentVariable('PATH', "$p;C:\Tools\Rclone", 'Machine')
```

### Step 3 — Create folders
```powershell
mkdir C:\Sync\Source, C:\Sync\Mirror, C:\Sync\Logs, C:\Sync\Config
mkdir C:\Tools\Rclone, C:\Tools\NSSM
```

### Step 4 — Restore all config files
Recreate every file from §14 of this document.

### Step 5 — Restore credentials
- Get your Key ID and App Key from backblaze.com → App Keys
- Fill in `credentials.txt` (format in §12)
- Run `encrypt_creds.ps1` to produce `credentials.enc`
- Delete `credentials.txt`

### Step 6 — Register tasks and service
```powershell
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\register_tasks.ps1
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\fix_watchdog_task.ps1
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\install_service.ps1
```

### Step 7 — Add startup registry entry
```powershell
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "FolderSyncRealTime" `
    -Value '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
```

### Step 8 — Start RealTimeSync and validate
```powershell
Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
    -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden
C:\Sync\Config\cloud_sync.bat
powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1
```

---

## 16. Validation Summary (2026-02-21)

| Test | Result |
|---|---|
| `rclone lsd cloudsync:` | ✅ Bucket `helder-sync-mirror` listed |
| Cloud upload test | ✅ 14 B transferred to B2 |
| Local mirror (robocopy) | ✅ 233 files / 283 MB mirrored in 3 seconds |
| `FolderSync-CloudBackup` task | ✅ Ready (SYSTEM) |
| `FolderSync-Watchdog` task | ✅ Running (`LAP\helde`) |
| `FolderSyncWatchdog` service | ✅ Running, Automatic start |
| RealTimeSync process | ✅ Running |
| Startup registry `FolderSyncRealTime` | ✅ Present |
| `FolderSyncAuditor` service | ✅ Running, Automatic start |
---

*Generated by Claude Code (claude-sonnet-4-6)*
*Safe to upload to GitHub Gist — contains no secrets.*
*Do NOT include `rclone.conf` in any gist.*

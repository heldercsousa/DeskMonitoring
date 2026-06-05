```powershell
# auditor.ps1
# FolderSync Security Auditor
# Monitors file system events, remote access, service tampering, and system events.
# Runs as NSSM service "FolderSyncAuditor".

$WatchedFolder  = 'C:\Users\helde\Repos\Bois'
$LogDir         = 'C:\Sync\Logs'
$AuditDir       = "$LogDir\audit"
$SecurityDir    = "$LogDir\security"
$StartupGapSecs = 120   # gap threshold to trigger forensic dump

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-FileAuditLog  { Join-Path $AuditDir    "file_audit_$(Get-Date -Format 'yyyy-MM-dd').log" }
function Get-SecurityLog   { Join-Path $SecurityDir "security_audit_$(Get-Date -Format 'yyyy-MM-dd').log" }

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
    $allLogs = Get-ChildItem $SecurityDir -Filter "security_audit_*.log" -ErrorAction SilentlyContinue |
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
    $path = Join-Path $AuditDir "interruption_report_$ts.txt"

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
# Log rotation (T033): delete audit logs older than 30 days
# ---------------------------------------------------------------------------
$script:LastLogRotation = [datetime]::MinValue

function Invoke-AuditLogRotation {
    if (([datetime]::Now - $script:LastLogRotation).TotalHours -lt 24) { return }
    $script:LastLogRotation = [datetime]::Now
    $cutoff = (Get-Date).AddDays(-30)

    foreach ($pattern in @("$SecurityDir\security_audit_*.log", "$AuditDir\file_audit_*.log")) {
        Get-ChildItem -LiteralPath (Split-Path $pattern) -Filter (Split-Path $pattern -Leaf) `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                Write-SecurityAudit "[LOG-ROTATE] Deleted old log: $($_.Name)"
            }
    }
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
        # ForÃ§amos a conversÃ£o para String AQUI, antes de entrar no Job
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

            $logFile = "C:\Sync\Logs\audit\file_audit_$($time.ToString('yyyy-MM-dd')).log"
            $ts = $time.ToString("yyyy-MM-dd HH:mm:ss")

            # T029: distinguish routine AVI aging from suspicious deletions
            # $name includes subdirectory when IncludeSubdirectories=true (e.g. "2026-06-05\motion_*.avi")
            # so extract just the filename before pattern-matching
            if ($type -eq 'DELETED') {
                if (([System.IO.Path]::GetFileName($name)) -like 'motion_*.avi') {
                    $detail = 'DELETED-ROUTINE'
                    $line = "$ts | $($detail.PadRight(25)) | user=$user | path=$path"
                    $line | Add-Content -LiteralPath $logFile -Encoding UTF8
                } else {
                    $detail = 'DELETED-SUSPICIOUS'
                    $line = "$ts | ALERT  $($detail.PadRight(18)) | user=$user | path=$path"
                    $line | Add-Content -LiteralPath $logFile -Encoding UTF8
                    $secLog = "C:\Sync\Logs\security\security_audit_$($time.ToString('yyyy-MM-dd')).log"
                    $line | Add-Content -LiteralPath $secLog -Encoding UTF8
                    & 'C:\Sync\Config\cloud_sync.ps1'
                }
            } else {
                # FormataÃ§Ã£o garantida como texto
                $detail = if ($old) { "RENAMED: $old -> $name" } else { $type }
                $line = "$ts | $($detail.PadRight(25)) | user=$user | path=$path"
                $line | Add-Content -LiteralPath $logFile -Encoding UTF8
            }
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

# T033: rotate old audit logs at startup
Invoke-AuditLogRotation

# Start file system watcher
$fsw = Start-FileWatcher
Write-FileAudit "[AUDITOR] FileSystemWatcher active on $WatchedFolder"

# Main polling loop
$script:LoopIteration = 0
try {
    while ($true) {
        Check-RemoteAccess
        Check-Services
        Check-SystemEvents

        # T028: clean up completed/failed background jobs every 60 iterations (~60s)
        $script:LoopIteration++
        if ($script:LoopIteration % 60 -eq 0) {
            Get-Job | Where-Object { $_.State -in 'Completed', 'Failed' } | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        # T033: daily log rotation check
        Invoke-AuditLogRotation

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
> Security monitor: startup gap forensics, FileSystemWatcher on source folder, remote logon/service/system event polling. Background job cleanup every ~60s (T028); motion AVI vs suspicious delete distinction (T029); 30-day log rotation for audit logs (T033, 2026-06-02). Writes to security_audit_YYYY-MM-DD.log and file_audit_YYYY-MM-DD.log.

**Last updated:** 2026-06-05
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
| `rclone.conf` | `cloud_sync.ps1` | Rclone B2 remote definition (credentials removed — now in `b2_creds.dpapi`) |
| `store_b2_creds.ps1` | Run once by Helder | T048: one-time migration — reads B2 account+key (from rclone.conf or prompt), encrypts with DPAPI LocalMachine scope, writes `b2_creds.dpapi` |
| `b2_creds.dpapi` | `cloud_sync.ps1` at runtime | T048: DPAPI-encrypted B2 account+key blob (LocalMachine scope, SYSTEM-accessible, **gitignored**) |
| `migrate_cam2_creds.ps1` | Run once by Helder | T049: one-time migration — reads cam2.conf, encrypts with DPAPI CurrentUser scope, writes `cam2_creds.dpapi` |
| `cam2_creds.dpapi` | `cam2_relay.ps1` at runtime | T049: DPAPI-encrypted CAM-2 user+pass+ip+port+stream blob (CurrentUser scope, **gitignored**) |
| `cloud_sync.ps1` | Task `FolderSync-CloudBackup` | Rclone sync + DPAPI B2 credential loading (`b2_creds.dpapi`, LocalMachine) + log rotation + mirror cleanup (7-day) + source folder retention (7-day) + self-healing firewall+DNS detection + failure sentinel + B2 lag alert + ACL failure logging + `Import-Module Microsoft.PowerShell.Security` for SYSTEM PS5 compatibility (T026/T030–T032, 2026-06-02; T048, 2026-06-03; T050, 2026-06-05) |
| `cloud_sync.bat` | Manual trigger | Same as .ps1 but via cmd (manual use only) |
| `run_mirror.bat` | RealTimeSync | Runs robocopy mirror on file change (daily log rotation) |
| `realtime.ffs_real` | RealTimeSync at startup | Watcher config — folder + delay + command |
| `wdog.ps1` | Task `FolderSync-Watchdog` + NSSM service | Watchdog loop with WATCHDOG-HEARTBEAT log every cycle (T027, 2026-06-02) |
| `auditor.ps1` | NSSM service `FolderSyncAuditor` | Monitors file changes, remote access, service tampering; job cleanup (T028); motion AVI vs suspicious delete distinction (T029 - fixed: GetFileName to handle subdirectory prefix); 30-day audit log rotation (T033, 2026-06-02) |
| `config_guard.ps1` | Task `FolderSync-ConfigGuard` (at logon, Step 20) | FileSystemWatcher on `Config\` — auto-restores `cloud_sync.ps1` and `run_mirror.bat` from git HEAD on any modification. Keep-alive loop (30s sleep). Logs to `Logs\security\config_guard_YYYY-MM-DD.log` |
| `credentials.enc` | `read_credentials.ps1` | Only copy of encrypted credentials |
| `read_credentials.ps1` | User on demand | Decrypts and prints credentials |
| `check_status.ps1` | User on demand | FolderSync full health check — tasks, services, rclone, logs |
| `check_camera.ps1` | User on demand | Camera/Yawcam health check — process, device, recordings, startup, CAM-2 relay; VLC process + port 8161 + restart sentinel checks added (T025, 2026-06-02) |
| `cam2_relay.ps1` | Registry Run `YawcamCam2Relay` (hidden, at login) | VLC relay: Tapo C100 RTSP → MJPEG HTTP `127.0.0.1:8161` for Yawcam; DPAPI credential loading (`cam2_creds.dpapi`, CurrentUser) with cam2.conf fallback; max 5 restarts/hour circuit breaker; 7-day log rotation; port-listening verification after restart (T024, 2026-06-02; T049, 2026-06-03) |
| `cam2.conf` | Fallback for `cam2_relay.ps1` | CAM-2 credentials (plaintext fallback — migrate with `migrate_cam2_creds.ps1` then delete, **gitignored**) |
| `health_check_all.ps1` | User on demand / `check_health.bat` / `/project:health` | Combined FolderSync + Camera health check; exits 0 all pass, 1 any fail; writes to `C:\Sync\Logs\ecosystem\health_check_YYYY-MM-DD.log` |
| `setup_update.ps1` | Fresh install / new device (primary) | Centralized setup v3 (Steps 1-20): state-aware (stops/restarts ecosystem), all hardening + task registration + Yawcam registry. Step 20: FolderSync-ConfigGuard task (config tamper auto-restore) |
| `setup_all.ps1` | Legacy reference | Setup v2 — kept for reference; `setup_update.ps1` is now primary |
| `start_ecosystem.ps1` | `/motionSentinel-start` / Manual / `setup_update.ps1` | Starts all components; gate: `#Requires -RunAsAdministrator`; writes `.ecosystem_state = running`; verifies Yawcam+VLC PIDs; enforces HKCU\Run entries. Yawcam wait 8s + checks both yawcam/javaw process names; CAM-2 wait 5s (2026-03-15). |
| `stop_ecosystem.ps1` | `/motionSentinel-stop` / Manual / `setup_update.ps1` | Stops all components in reverse; gate: `#Requires -RunAsAdministrator`; writes `.ecosystem_state = stopped` |
| `pause_camera.ps1` | `/motionSentinel-pause` / Manual | Stops Yawcam; gate: `#Requires -RunAsAdministrator`; sets `.camera_paused` flag |
| `resume_camera.ps1` | `/motionSentinel-resume` / Manual | Starts Yawcam; gate: `#Requires -RunAsAdministrator`; removes `.camera_paused` flag |
| `enable_file_auditing.ps1` | One-time setup | Activates SACL on watched folder for user attribution in logs |
| `fix_firewall_b2.ps1` | `fix_b2_firewall.bat` (admin) | Removes malicious outbound BLOCK firewall rules targeting B2 IPs |
| `fix_power_motion.ps1` | Manual (admin) | Restores power settings for motion detection: switches to Balanced plan, disables USB Selective Suspend (AC+DC), sleep/hibernate=Never, display=600s AC |
| `check_power_motion.ps1` | Task `FolderSync-PowerCheck` (every 1h + AtLogon + AtBoot, SYSTEM, RunLevel Highest) | Hourly audit + auto-heal of power settings required for motion detection: checks active plan (no SCHEME_MAX), USB Selective Suspend AC+DC=0, Sleep/Hibernate AC+DC=0, Display timeout AC>=600s; logs to `C:\Sync\Logs\power_check\power_check_YYYY-MM-DD.log`; prefixes: POWER-CHECK-START/OK/ANOMALY/CORRECTED/CHECK-END |
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
| `DailySecurityCheck.ps1` | Daily security scan v9 — processes, ports, remote tools, unknown devices, firewall tamper, hosts file, scheduled task integrity (CloudBackup only), B2 connectivity, Event Log audit, Run key persistence; whitelist expanded (Fing/OneDrive/Docker/Copilot); SYSTEM/SISTEMA principal match; FolderSync-Watchdog removed from task check (post-T022-T034 false-positive fixes, 2026-06-02) |
| `AutoCleanup.ps1` | Automated cleanup triggered by DailySecurityCheck |
| `run_tests.ps1` | Tier 1-4 automated test orchestrator for T010-T034 changes; runs parse checks, safe live executions, sentinel file verification, and behavioral log checks; logs to `C:\Sync\Logs\security\test_results_YYYY-MM-DD.log` (T035, 2026-06-02) |
| `run_parse_check.ps1` | Quick parse-only check for 6 key scripts (DailySecurityCheck, yawcam_monitor_v4, cam2_relay, wdog, auditor, cloud_sync); exits 0 = all pass (T035, 2026-06-02) |

### Camera scripts (in `C:\Sync\Config\`)

These scripts were relocated from `C:\Program Files (x86)\Yawcam\` to `C:\Sync\Config\` so they are inside git and ACL-protected.

| File | Used by | Purpose |
|---|---|---|
| `yawcam_monitor_v4.ps1` | Registry Run `YawcamMonitor` via `start_monitor.ps1` | Infinite-loop monitor: scans Bois dir recursively for latest .avi (T022), timestamped log to `C:\Sync\Logs\services\yawcam_monitor.log` (T023), restart failure sentinel `.camera_restart_failed` (T034). 60s interval, 600s cooldown. |
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

### `C:\Sync\Config\DailySecurityCheck.ps1`
> Daily security scan v9. Checks: suspicious processes, registry location entries, remote access tools, suspicious ports, unknown ARP devices, FolderSync service health, firewall tamper (B2 outbound BLOCK rules), hosts file poisoning, scheduled task integrity (FolderSync-CloudBackup only), B2 connectivity probe, Windows Event Log audit (EventIds 4698/4720/4732 last 24h), HKCU Run key persistence against whitelist (expanded: Fing/OneDrive/Docker/Copilot). SYSTEM/SISTEMA principal match; FolderSync-Watchdog removed from task checks (post-T022-T034 false-positive fixes, 2026-06-02).
> Daily security scan v9. Checks: suspicious processes, registry location entries, remote access tools, suspicious ports, unknown ARP devices, FolderSync service health, firewall tamper (B2 outbound BLOCK rules), hosts file poisoning, scheduled task integrity (FolderSync-CloudBackup only), B2 connectivity probe, Windows Event Log audit (EventIds 4698/4720/4732 last 24h), HKCU Run key persistence against whitelist (expanded: Fing/OneDrive/Docker/Copilot). SYSTEM/SISTEMA principal match; FolderSync-Watchdog removed from task checks (post-T022-T034 false-positive fixes, 2026-06-02).
> Daily security scan v9. Checks: suspicious processes, registry location entries, remote access tools, suspicious ports, unknown ARP devices, FolderSync service health, firewall tamper (B2 outbound BLOCK rules), hosts file poisoning, scheduled task integrity (FolderSync-CloudBackup only), B2 connectivity probe, Windows Event Log audit (EventIds 4698/4720/4732 last 24h), HKCU Run key persistence against whitelist (expanded: Fing/OneDrive/Docker/Copilot). SYSTEM/SISTEMA principal match; FolderSync-Watchdog removed from task checks (post-T022-T034 false-positive fixes, 2026-06-02).

```powershell
# DailySecurityCheck.ps1 - v9
# Security detection: suspicious processes, firewall tampering, DNS/hosts poisoning,
# scheduled task integrity, B2 connectivity, Event Log audit, Run key persistence.
# Scheduled task: "FolderSync-DailyCheck" (daily at 09:00, runs as helde)

$logPath = "C:\Sync\Logs\security\security_check_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $logPath
}

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

$knownDevices = @{
    '192.168.0.1'   = 'Router Humax'
    '192.168.0.106' = 'Samsung TV'
    '192.168.0.109' = 'TP-Link C100 Cam'
    '192.168.0.152' = 'This machine (LAP)'
    '192.168.0.206' = 'Samsung S23 Ultra'
}

$b2IPs = @('104.153.233.180', '149.137.142.15')
$b2Host = 'api.backblazeb2.com'

$knownRunKeys = @(
    'Yawcam',
    'YawcamMonitor',
    'YawcamCam2Relay',
    'FolderSyncRealTime',
    'electron.app.Fing',
    'OneDrive',
    'Docker Desktop'
    # MicrosoftCopilotAutoLaunch_* matched below via wildcard
)

try {
    $locationPath       = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
    $suspiciousPatterns = @("AppMonitor", "CefView")

    $excludePatterns = @(
        "Mbam", "OneDrive", "Malware", "Windows", "Microsoft",
        "msedge", "PackageManager", "svchost", "RuntimeBroker",
        "SearchHost", "StartMenuExperienceHost", "ShellExperienceHost",
        "SystemSettings", "Explorer", "Defender", "SecurityHealth",
        "Update", "Store", "Xbox", "Gaming", "Cortana", "ActionsServer",
        "devenv", "VSCode", "Code", "copilot", "git", "node",
        "dotnet", "msbuild", "ServiceHub", "PerfWatson",
        "WindowsPackageManager"
    )

    $issues = 0

    Write-Log "SCAN-START  DailySecurityCheck v9"

    # -----------------------------------------------------------------------
    # [1] Suspicious processes
    # -----------------------------------------------------------------------
    Write-Step "[1] Suspicious processes"
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $name         = $_.ProcessName
        $isSuspicious = $false
        $isExcluded   = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $isSuspicious = $true; break } }
        if ($isSuspicious) {
            foreach ($e in $excludePatterns) { if ($name -like "*$e*") { $isExcluded = $true; break } }
        }
        $isSuspicious -and -not $isExcluded
    }

    if ($procs) {
        foreach ($proc in $procs) {
            $issues++
            $path    = if ($proc.Path) { $proc.Path } else { "Unknown" }
            $company = if ($proc.Company) { $proc.Company } else { "Unknown" }
            $signed  = "No"
            $signer  = "N/A"
            $risk    = "HIGH"
            $action  = "Investigate and consider terminating"
            if ($proc.Path -and (Test-Path $proc.Path)) {
                $sig = Get-AuthenticodeSignature -FilePath $proc.Path -ErrorAction SilentlyContinue
                if ($sig -and $sig.Status -eq "Valid") {
                    $signed = "Yes"
                    $signer = $sig.SignerCertificate.Subject -replace "CN=", "" -replace ",.*", ""
                }
            }
            $inProgramFiles = $path -like "*Program Files*"
            if ($signed -eq "Yes" -and $inProgramFiles) {
                $risk   = "LOW"
                $action = "Add to exclusions if legitimate"
            } elseif ($signed -eq "Yes" -and -not $inProgramFiles) {
                $risk   = "MEDIUM"
                $action = "Verify path and company before cleanup"
            }
            Write-Log "ALERT  [SuspiciousProcess] Name=$($proc.ProcessName) PID=$($proc.Id) Path=$path Company=$company Signed=$signed Risk=$risk Action=$action"
            Write-Fail "Suspicious process: $($proc.ProcessName) | Risk=$risk | Path=$path"
        }
    } else {
        Write-OK "No suspicious processes"
    }

    # -----------------------------------------------------------------------
    # [2] Registry location entries
    # -----------------------------------------------------------------------
    Write-Step "[2] Registry location access entries"
    $subApps = Get-ChildItem -Path $locationPath -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.PSChildName
        $hit  = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $hit = $true; break } }
        $hit
    }
    if ($subApps) {
        $issues++
        foreach ($r in $subApps) {
            Write-Log "ALERT  [RegistryLocation] Entry=$($r.PSChildName)"
            Write-Fail "Suspicious registry location entry: $($r.PSChildName)"
        }
    } else {
        Write-OK "No suspicious registry location entries"
    }

    # -----------------------------------------------------------------------
    # [3] Remote access tools running
    # -----------------------------------------------------------------------
    Write-Step "[3] Remote access tools"
    $remoteTools = @('AnyDesk', 'VNCViewer', 'vncserver', 'ScreenConnect', 'Ammyy', 'RemoteUtilities', 'Rustdesk')
    foreach ($tool in $remoteTools) {
        $p = Get-Process $tool -ErrorAction SilentlyContinue
        if ($p) {
            $issues++
            Write-Log "ALERT  [RemoteTool] Name=$tool PID=$($p.Id -join ',')"
            Write-Fail "Remote access tool running: $tool (PID $($p.Id -join ','))"
        }
    }

    # -----------------------------------------------------------------------
    # [4] Suspicious listening ports
    # -----------------------------------------------------------------------
    Write-Step "[4] Suspicious listening ports"
    $suspiciousPorts = @(4444, 5900, 5901, 1080, 8443, 31337, 12345, 54321, 9999, 6666)
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $listening) {
        if ($conn.LocalPort -in $suspiciousPorts) {
            $issues++
            $proc     = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
            $procPath = if ($proc -and $proc.Path) { $proc.Path } else { "Unknown" }
            Write-Log "ALERT  [SuspiciousPort] Port=$($conn.LocalPort) PID=$($conn.OwningProcess) Process=$procName Path=$procPath"
            Write-Fail "Suspicious port $($conn.LocalPort) listening - $procName ($procPath)"
        }
    }
    if ($issues -eq 0) { Write-OK "No suspicious ports open" }

    # -----------------------------------------------------------------------
    # [5] Unknown devices on network (ARP table)
    # -----------------------------------------------------------------------
    Write-Step "[5] Unknown network devices (ARP)"
    try {
        $arpOutput = arp -a 2>$null
        $arpLines  = $arpOutput | Where-Object { $_ -match '^\s+\d+\.\d+\.\d+\.\d+' }
        foreach ($line in $arpLines) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([\w-]+)\s+(\w+)') {
                $ip   = $Matches[1]
                $type = $Matches[3]
                if ($type -eq 'dynamic') {
                    if (-not $knownDevices.ContainsKey($ip)) {
                        $issues++
                        Write-Log "ALERT  [UnknownDevice] IP=$ip"
                        Write-Warn "Unknown device on network: $ip"
                    }
                }
            }
        }
    } catch {}

    # -----------------------------------------------------------------------
    # [6] FolderSync services status
    # -----------------------------------------------------------------------
    Write-Step "[6] FolderSync services"
    $watchedSvcs = @('FolderSyncAuditor', 'FolderSyncWatchdog')
    foreach ($svc in $watchedSvcs) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne 'Running') {
            $issues++
            Write-Log "ALERT  [ServiceStopped] Service=$svc Status=$($s.Status) StartType=$($s.StartType)"
            Write-Fail "Service not running: $svc (Status=$($s.Status) StartType=$($s.StartType))"
        } elseif ($s) {
            Write-OK "$svc is running"
        } else {
            $issues++
            Write-Log "ALERT  [ServiceMissing] Service=$svc"
            Write-Fail "Service not found: $svc"
        }
    }

    # -----------------------------------------------------------------------
    # [10] Firewall tamper detection (B2 outbound BLOCK rules)
    # -----------------------------------------------------------------------
    Write-Step "[10] Firewall tamper detection"
    $fwRules = Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' }
    $badRules = @()
    foreach ($rule in $fwRules) {
        $filter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
        if ($filter) {
            $addrs = @($filter.RemoteAddress)
            foreach ($b2ip in $b2IPs) {
                if ($addrs -contains $b2ip -or $addrs -contains "$b2ip/32") {
                    $badRules += $rule.DisplayName
                }
            }
            if ($addrs -contains $b2Host) { $badRules += $rule.DisplayName }
        }
    }
    if ($badRules.Count -gt 0) {
        $issues++
        foreach ($r in ($badRules | Select-Object -Unique)) {
            Write-Log "ALERT  [FirewallTamper] Rule=`"$r`" blocks B2 outbound"
            Write-Fail "Firewall tamper: outbound BLOCK rule targeting B2 - `"$r`""
        }
    } else {
        Write-OK "No outbound BLOCK rules targeting B2 IPs"
    }

    # -----------------------------------------------------------------------
    # [11] Hosts file poisoning check
    # -----------------------------------------------------------------------
    Write-Step "[11] Hosts file check"
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    $hostsLines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
    if ($hostsLines) {
        foreach ($line in $hostsLines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^#' -or $trimmed -eq '') { continue }
            $isPoison = $false
            if ($trimmed -match $b2Host) { $isPoison = $true }
            foreach ($b2ip in $b2IPs) { if ($trimmed -match [regex]::Escape($b2ip)) { $isPoison = $true } }
            if ($isPoison) {
                $issues++
                Write-Log "ALERT  [HostsPoison] Line=`"$trimmed`""
                Write-Fail "Hosts file poisoning detected: `"$trimmed`""
            }
        }
    }
    if ($issues -eq 0) { Write-OK "Hosts file clean" }

    # -----------------------------------------------------------------------
    # [12] Scheduled task integrity check
    # -----------------------------------------------------------------------
    Write-Step "[12] Scheduled task integrity"
    $taskChecks = @(
        @{ Name = 'FolderSync-CloudBackup'; ExpectedPath = 'C:\Sync\Config\cloud_sync.ps1' }
    )
    foreach ($tc in $taskChecks) {
        $task = Get-ScheduledTask -TaskName $tc.Name -ErrorAction SilentlyContinue
        if (-not $task) {
            $issues++
            Write-Log "ALERT  [TaskMissing] Task=$($tc.Name)"
            Write-Fail "Scheduled task missing: $($tc.Name)"
            continue
        }
        $deviations = @()
        if ($task.State -ne 'Ready') { $deviations += "State=$($task.State) (expected Ready)" }
        $principal = $task.Principal
        if ($principal.UserId -notmatch 'S-1-5-18|SYSTEM|SISTEMA') { $deviations += "Principal=$($principal.UserId) (expected SYSTEM)" }
        if ($principal.RunLevel -ne 'Highest') { $deviations += "RunLevel=$($principal.RunLevel) (expected Highest)" }
        $action = $task.Actions | Select-Object -First 1
        if ($action -and $action.Arguments -notmatch [regex]::Escape($tc.ExpectedPath)) {
            $deviations += "Arguments=`"$($action.Arguments)`" (expected to contain $($tc.ExpectedPath))"
        }
        if ($deviations.Count -gt 0) {
            $issues++
            foreach ($d in $deviations) {
                Write-Log "ALERT  [TaskTamper] Task=$($tc.Name) Deviation=$d"
                Write-Fail "Task integrity violation: $($tc.Name) - $d"
            }
        } else {
            Write-OK "$($tc.Name) integrity OK"
        }
    }

    # -----------------------------------------------------------------------
    # [13] Active B2 connectivity probe
    # -----------------------------------------------------------------------
    Write-Step "[13] B2 connectivity probe"
    $conn443 = Test-NetConnection -ComputerName $b2Host -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($conn443 -and $conn443.TcpTestSucceeded) {
        Write-OK "B2 connectivity OK ($b2Host:443)"
        Write-Log "INFO  [B2Connectivity] Host=$b2Host Port=443 Result=OK"
    } else {
        $issues++
        Write-Log "ALERT  [B2Connectivity] Host=$b2Host Port=443 Result=FAIL - B2 outbound blocked or unreachable"
        Write-Fail "B2 connectivity FAILED: $b2Host:443 unreachable"
    }

    # -----------------------------------------------------------------------
    # [14] Windows Event Log audit (last 24h)
    # -----------------------------------------------------------------------
    Write-Step "[14] Windows Event Log audit (last 24h)"
    $since = (Get-Date).AddHours(-24)
    $auditEventIds = @(
        @{ Id = 4698; Desc = 'New scheduled task created' }
        @{ Id = 4720; Desc = 'New user account created' }
        @{ Id = 4732; Desc = 'Member added to security-enabled local group' }
    )
    foreach ($ae in $auditEventIds) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName   = 'Security'
                Id        = $ae.Id
                StartTime = $since
            } -ErrorAction SilentlyContinue
            if ($events) {
                $issues++
                foreach ($ev in $events) {
                    Write-Log "ALERT  [EventLog] EventId=$($ae.Id) Desc=$($ae.Desc) Time=$($ev.TimeCreated) Message=$($ev.Message -replace '\r?\n',' ' -replace '\s+',' ')"
                    Write-Fail "Security event $($ae.Id) ($($ae.Desc)) at $($ev.TimeCreated)"
                }
            } else {
                Write-OK "EventId $($ae.Id) ($($ae.Desc)): none in last 24h"
            }
        } catch {}
    }

    # -----------------------------------------------------------------------
    # [17] HKCU Run key persistence check
    # -----------------------------------------------------------------------
    Write-Step "[17] HKCU Run key persistence check"
    $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $runEntries = Get-ItemProperty -Path $runKeyPath -ErrorAction SilentlyContinue
    if ($runEntries) {
        $runEntries.PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS' } |
            ForEach-Object {
                $entryName = $_.Name
                if ($entryName -notin $knownRunKeys -and $entryName -notmatch '^MicrosoftCopilotAutoLaunch_') {
                    $issues++
                    Write-Log "ALERT  [RunKeyUnknown] Name=`"$entryName`" Value=`"$($_.Value)`""
                    Write-Fail "Unknown HKCU Run key: `"$entryName`" = `"$($_.Value)`""
                } else {
                    Write-OK "Run key `"$entryName`" is whitelisted"
                }
            }
    }

    # -----------------------------------------------------------------------
    # Summary log line
    # -----------------------------------------------------------------------
    Write-Log "SCAN-END  Issues=$issues"

    # -----------------------------------------------------------------------
    # Interactive dialog (skip when running as scheduled task)
    # -----------------------------------------------------------------------
    if (-not [Environment]::UserInteractive) { return }

    Add-Type -AssemblyName System.Windows.Forms

    if ($issues -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "System secure. No threats detected.`n`nChecked at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Security Check",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } else {
        $msg  = "WARNING: $issues issue(s) detected!`n"
        $msg += "Checked at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        $msg += "-------------------------------------------`n"
        $msg += "See log for details: $logPath`n`n"
        $msg += "-------------------------------------------`n"
        $msg += "Run AUTO-CLEANUP?"

        $result = [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Security Alert",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $cleanupScript = "C:\Sync\Config\AutoCleanup.ps1"
            if (Test-Path $cleanupScript) {
                Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$cleanupScript`"" -Verb RunAs
            }
        }
    }

} catch {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  ERROR: $_" | Add-Content -LiteralPath $logPath
}

```

---

### `C:\Sync\Config\check_power_motion.ps1`
> Hourly audit + auto-heal of power settings required for motion detection.
> Run by Task Scheduler (`FolderSync-PowerCheck`) as SYSTEM, every 1h + AtLogon + AtStartup. `#Requires -RunAsAdministrator`.
> Checks: active plan (not SCHEME_MAX), USB Selective Suspend AC+DC=0, Sleep/Hibernate AC+DC=0, Display AC>=600s.
> Logs to `C:\Sync\Logs\power_check\power_check_YYYY-MM-DD.log`.
> Log prefixes: `POWER-CHECK-START`, `POWER-OK`, `POWER-ANOMALY`, `POWER-CORRECTED`, `POWER-CHECK-END`.

```powershell
#Requires -RunAsAdministrator
# check_power_motion.ps1 - hourly audit + auto-heal of power settings required for motion detection
# Idempotent: safe to run multiple times
# Scheduled Task: FolderSync-PowerCheck (every 1h, SYSTEM, RunLevel Highest)

$ErrorActionPreference = 'SilentlyContinue'

$LogDir  = "C:\Sync\Logs\power_check"
$LogFile = "$LogDir\power_check_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

# GUIDs
$USB_SG    = '2a737441-1930-4402-8d77-b2bebba308a3'
$USB_SET   = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$SLEEP_SG  = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$SLEEP_SET = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$HIB_SET   = '9d7815a6-7ee4-497e-8888-515a05f02364'
$DISP_SG   = '7516b95f-f776-4464-8c53-06167f40cc99'
$DISP_SET  = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
$SCHEME_MAX = 'a1841308-3541-4fab-bc81-f71556f20b4a'

Write-Log "POWER-CHECK-START"

$anyAnomaly = $false

function Get-PowerSetting {
    param($SubGroup, $Setting, $AcOrDc)
    $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null
    if (-not $output) { return $null }
    $label = if ($AcOrDc -eq 'AC') { 'Current AC Power Setting Index' } else { 'Current DC Power Setting Index' }
    $line = $output | Where-Object { $_ -match $label }
    if (-not $line) { return $null }
    if ($line -match '0x([0-9a-fA-F]+)') { return [Convert]::ToInt64($Matches[1], 16) }
    return $null
}

$activeLine = powercfg /getactivescheme 2>$null
if ($activeLine -match $SCHEME_MAX) {
    Write-Log "POWER-ANOMALY  Active plan is Power Saver (SCHEME_MAX) - switching to Balanced"
    $anyAnomaly = $true
    powercfg /setactive SCHEME_BALANCED 2>$null
    Write-Log "POWER-CORRECTED  Active plan set to SCHEME_BALANCED"
} else { Write-Log "POWER-OK  Active plan is not Power Saver" }

foreach ($cfg in @(
    @{SG=$USB_SG;  SET=$USB_SET;  AC='AC'; label='USB Selective Suspend AC'; cmd='setacvalueindex'},
    @{SG=$USB_SG;  SET=$USB_SET;  AC='DC'; label='USB Selective Suspend DC'; cmd='setdcvalueindex'},
    @{SG=$SLEEP_SG;SET=$SLEEP_SET;AC='AC'; label='Sleep AC';                 cmd='setacvalueindex'},
    @{SG=$SLEEP_SG;SET=$SLEEP_SET;AC='DC'; label='Sleep DC';                 cmd='setdcvalueindex'},
    @{SG=$SLEEP_SG;SET=$HIB_SET;  AC='AC'; label='Hibernate AC';             cmd='setacvalueindex'},
    @{SG=$SLEEP_SG;SET=$HIB_SET;  AC='DC'; label='Hibernate DC';             cmd='setdcvalueindex'}
)) {
    $val = Get-PowerSetting -SubGroup $cfg.SG -Setting $cfg.SET -AcOrDc $cfg.AC
    if ($val -ne $null -and $val -ne 0) {
        Write-Log "POWER-ANOMALY  $($cfg.label) = $val (expected 0)"
        $anyAnomaly = $true
        powercfg /$($cfg.cmd) SCHEME_CURRENT $cfg.SG $cfg.SET 0 2>$null
        powercfg /setactive SCHEME_CURRENT 2>$null
        Write-Log "POWER-CORRECTED  $($cfg.label) set to 0"
    } else { Write-Log "POWER-OK  $($cfg.label) = 0" }
}

$dispAC = Get-PowerSetting -SubGroup $DISP_SG -Setting $DISP_SET -AcOrDc 'AC'
if ($dispAC -ne $null -and $dispAC -lt 600) {
    Write-Log "POWER-ANOMALY  Display timeout AC = $dispAC seconds (expected >= 600)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $DISP_SG $DISP_SET 600 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Display timeout AC set to 600"
} else { Write-Log "POWER-OK  Display timeout AC = $dispAC (>= 600)" }

if (-not $anyAnomaly) {
    Write-Log "POWER-CHECK-END  ALL_OK - no anomalies detected"
} else {
    Write-Log "POWER-CHECK-END  anomalies detected and corrected"
}
```

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

### `C:\Sync\Config\check_power_motion.ps1`
> Hourly audit + auto-heal of power settings required for continuous motion detection (Yawcam webcam).
> Run by Task `FolderSync-PowerCheck` as SYSTEM (every 1h + AtLogon + AtBoot). Requires Administrator.
> Checks: active plan not SCHEME_MAX, USB Selective Suspend=0 AC+DC, Sleep/Hibernate=0 AC+DC, Display AC>=600s.
> Logs to `C:\Sync\Logs\power_check\power_check_YYYY-MM-DD.log`. Created 2026-05-28 after power settings manipulation detected.

```powershell
#Requires -RunAsAdministrator
# check_power_motion.ps1 - hourly audit + auto-heal of power settings required for motion detection
# Idempotent: safe to run multiple times
# Scheduled Task: FolderSync-PowerCheck (every 1h, SYSTEM, RunLevel Highest)

$ErrorActionPreference = 'SilentlyContinue'

$LogDir  = "C:\Sync\Logs\power_check"
$LogFile = "$LogDir\power_check_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

# GUIDs
$USB_SG   = '2a737441-1930-4402-8d77-b2bebba308a3'
$USB_SET  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$SLEEP_SG = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$SLEEP_SET = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$HIB_SET  = '9d7815a6-7ee4-497e-8888-515a05f02364'
$DISP_SG  = '7516b95f-f776-4464-8c53-06167f40cc99'
$DISP_SET = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
$SCHEME_MAX     = 'a1841308-3541-4fab-bc81-f71556f20b4a'

Write-Log "POWER-CHECK-START"

$anyAnomaly = $false

# --- Helper: read a powercfg setting index value ---
function Get-PowerSetting {
    param($SubGroup, $Setting, $AcOrDc)
    # AcOrDc: 'AC' or 'DC'
    $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null
    if (-not $output) { return $null }
    $label = if ($AcOrDc -eq 'AC') { 'Current AC Power Setting Index' } else { 'Current DC Power Setting Index' }
    $line = $output | Where-Object { $_ -match $label }
    if (-not $line) { return $null }
    if ($line -match '0x([0-9a-fA-F]+)') { return [Convert]::ToInt64($Matches[1], 16) }
    return $null
}

# --- 1. Active power plan ---
$activeLine = powercfg /getactivescheme 2>$null
$isSchemeMax = $activeLine -match $SCHEME_MAX
if ($isSchemeMax) {
    Write-Log "POWER-ANOMALY  Active plan is Power Saver (SCHEME_MAX) - switching to Balanced"
    $anyAnomaly = $true
    powercfg /setactive SCHEME_BALANCED 2>$null
    Write-Log "POWER-CORRECTED  Active plan set to SCHEME_BALANCED"
} else {
    Write-Log "POWER-OK  Active plan is not Power Saver"
}

# --- 2. USB Selective Suspend AC ---
$usbAC = Get-PowerSetting -SubGroup $USB_SG -Setting $USB_SET -AcOrDc 'AC'
if ($usbAC -ne $null -and $usbAC -ne 0) {
    Write-Log "POWER-ANOMALY  USB Selective Suspend AC = $usbAC (expected 0)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $USB_SG $USB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  USB Selective Suspend AC set to 0"
} else {
    Write-Log "POWER-OK  USB Selective Suspend AC = 0"
}

# --- 3. USB Selective Suspend DC ---
$usbDC = Get-PowerSetting -SubGroup $USB_SG -Setting $USB_SET -AcOrDc 'DC'
if ($usbDC -ne $null -and $usbDC -ne 0) {
    Write-Log "POWER-ANOMALY  USB Selective Suspend DC = $usbDC (expected 0)"
    $anyAnomaly = $true
    powercfg /setdcvalueindex SCHEME_CURRENT $USB_SG $USB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  USB Selective Suspend DC set to 0"
} else {
    Write-Log "POWER-OK  USB Selective Suspend DC = 0"
}

# --- 4. Sleep after AC ---
$sleepAC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $SLEEP_SET -AcOrDc 'AC'
if ($sleepAC -ne $null -and $sleepAC -ne 0) {
    Write-Log "POWER-ANOMALY  Sleep AC = $sleepAC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $SLEEP_SG $SLEEP_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Sleep AC set to 0"
} else {
    Write-Log "POWER-OK  Sleep AC = 0"
}

# --- 5. Sleep after DC ---
$sleepDC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $SLEEP_SET -AcOrDc 'DC'
if ($sleepDC -ne $null -and $sleepDC -ne 0) {
    Write-Log "POWER-ANOMALY  Sleep DC = $sleepDC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setdcvalueindex SCHEME_CURRENT $SLEEP_SG $SLEEP_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Sleep DC set to 0"
} else {
    Write-Log "POWER-OK  Sleep DC = 0"
}

# --- 6. Hibernate after AC ---
$hibAC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $HIB_SET -AcOrDc 'AC'
if ($hibAC -ne $null -and $hibAC -ne 0) {
    Write-Log "POWER-ANOMALY  Hibernate AC = $hibAC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $SLEEP_SG $HIB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Hibernate AC set to 0"
} else {
    Write-Log "POWER-OK  Hibernate AC = 0"
}

# --- 7. Hibernate after DC ---
$hibDC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $HIB_SET -AcOrDc 'DC'
if ($hibDC -ne $null -and $hibDC -ne 0) {
    Write-Log "POWER-ANOMALY  Hibernate DC = $hibDC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setdcvalueindex SCHEME_CURRENT $SLEEP_SG $HIB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Hibernate DC set to 0"
} else {
    Write-Log "POWER-OK  Hibernate DC = 0"
}

# --- 8. Display timeout AC (must be >= 600s = 0x258) ---
$dispAC = Get-PowerSetting -SubGroup $DISP_SG -Setting $DISP_SET -AcOrDc 'AC'
if ($dispAC -ne $null -and $dispAC -lt 600) {
    Write-Log "POWER-ANOMALY  Display timeout AC = $dispAC seconds (expected >= 600)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $DISP_SG $DISP_SET 600 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Display timeout AC set to 600"
} else {
    Write-Log "POWER-OK  Display timeout AC = $dispAC (>= 600)"
}

if (-not $anyAnomaly) {
    Write-Log "POWER-CHECK-END  ALL_OK - no anomalies detected"
} else {
    Write-Log "POWER-CHECK-END  anomalies detected and corrected"
}
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
> ⚠ Credentials removed (T048, 2026-06-03) — stored in `b2_creds.dpapi` (DPAPI, LocalMachine). Run `store_b2_creds.ps1` once after reinstall.

```ini
[cloudsync]
type = b2
hard_delete = false
```

---

### `C:\Sync\Config\store_b2_creds.ps1`
> T048 (2026-06-03): One-time migration — reads B2 account+key (from rclone.conf or prompt), encrypts with DPAPI LocalMachine scope, writes `b2_creds.dpapi`. Run once as any user after reinstall.

```powershell
# store_b2_creds.ps1
# One-time migration: reads B2 credentials from rclone.conf and stores them
# as a DPAPI-encrypted blob (LocalMachine scope) in b2_creds.dpapi.
# Run once as any user. After running, remove account/key from rclone.conf.
# Last updated: 2026-06-03 - T048: migrate B2 credentials to DPAPI

Add-Type -AssemblyName System.Security

$RcloneConf = 'C:\Sync\Config\rclone.conf'
$OutputFile  = 'C:\Sync\Config\b2_creds.dpapi'

# --- Read current credentials from rclone.conf ---
if (-not (Test-Path $RcloneConf)) {
    Write-Host "  FAIL  rclone.conf not found at $RcloneConf" -ForegroundColor Red
    exit 1
}

$confContent = Get-Content -LiteralPath $RcloneConf -Raw
$accountMatch = [regex]::Match($confContent, '(?m)^\s*account\s*=\s*(.+)$')
$keyMatch     = [regex]::Match($confContent, '(?m)^\s*key\s*=\s*(.+)$')

if (-not $accountMatch.Success -or -not $keyMatch.Success) {
    Write-Host "  FAIL  Could not find account or key in rclone.conf." -ForegroundColor Red
    Write-Host "        Has it already been stripped? If so, enter credentials manually." -ForegroundColor Yellow
    $account = Read-Host "  Enter B2 account (application key ID)"
    $key     = Read-Host "  Enter B2 key (application key)"
} else {
    $account = $accountMatch.Groups[1].Value.Trim()
    $key     = $keyMatch.Groups[1].Value.Trim()
    Write-Host "  OK    Read credentials from rclone.conf (account: $($account.Substring(0,8))...)" -ForegroundColor Green
}

# --- Encrypt with DPAPI LocalMachine scope ---
$json      = [System.Text.Encoding]::UTF8.GetBytes("{`"account`":`"$account`",`"key`":`"$key`"}")
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $json,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
$base64 = [Convert]::ToBase64String($encrypted)

# --- Write to output file ---
$base64 | Set-Content -LiteralPath $OutputFile -NoNewline -Encoding ASCII
Write-Host "  OK    Encrypted credentials written to $OutputFile" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Cyan
Write-Host "    1. Verify cloud sync still works (next scheduled run or manual test)" -ForegroundColor Cyan
Write-Host "    2. account/key have been removed from rclone.conf (T048 migration complete)." -ForegroundColor Cyan
Write-Host "       cloud_sync.ps1 now reads credentials exclusively from b2_creds.dpapi." -ForegroundColor Cyan
Write-Host "    3. Verify the next scheduled sync completes with SYNC-OK in cloud_sync log." -ForegroundColor Cyan
```

---

### `C:\Sync\Config\migrate_cam2_creds.ps1`
> T049 (2026-06-03): One-time migration — reads cam2.conf, encrypts user+pass+ip+port+stream with DPAPI CurrentUser scope, writes `cam2_creds.dpapi`. Must run as Helder user (not SYSTEM).

```powershell
# migrate_cam2_creds.ps1
# One-time migration: encrypts CAM-2 credentials from cam2.conf into DPAPI blob.
# Run once as Helder (user session) - uses CurrentUser scope so only this account can decrypt.
# Output: C:\Sync\Config\cam2_creds.dpapi (Base64-encoded DPAPI-encrypted JSON)

Add-Type -AssemblyName System.Security

$ConfFile  = "C:\Sync\Config\cam2.conf"
$DpapiFile = "C:\Sync\Config\cam2_creds.dpapi"

if (-not (Test-Path $ConfFile)) {
    Write-Host "FAIL  cam2.conf not found at $ConfFile" -ForegroundColor Red
    exit 1
}

# Parse cam2.conf
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
    Write-Host "FAIL  cam2.conf missing required fields (CAM2_USER, CAM2_PASS, CAM2_IP)" -ForegroundColor Red
    exit 1
}

# Build JSON payload (all fields, IP/port/stream kept for completeness)
$payload = [ordered]@{
    user   = $user
    pass   = $pass
    ip     = $ip
    port   = if ($port) { $port } else { "554" }
    stream = if ($stream) { $stream } else { "stream1" }
}
$json = $payload | ConvertTo-Json -Compress

# DPAPI encrypt (CurrentUser scope - only Helder's account can decrypt)
$plainBytes     = [System.Text.Encoding]::UTF8.GetBytes($json)
$entropyBytes   = $null
$encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $entropyBytes,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)

# Base64-encode and write to file
$base64 = [Convert]::ToBase64String($encryptedBytes)
[System.IO.File]::WriteAllText($DpapiFile, $base64, [System.Text.Encoding]::ASCII)

Write-Host ""
Write-Host "  OK   cam2_creds.dpapi created at: $DpapiFile" -ForegroundColor Green
Write-Host "  OK   Encrypted fields: user, pass, ip, port, stream" -ForegroundColor Green
Write-Host ""
Write-Host "  cam2.conf can now be deleted. When ready, run:" -ForegroundColor Cyan
Write-Host "       Remove-Item '$ConfFile'" -ForegroundColor Cyan
Write-Host ""
Write-Host "  NOTE: cam2_creds.dpapi is gitignored and stays on this machine only." -ForegroundColor Yellow
Write-Host "        If you reinstall Windows or migrate to a new user account, re-run" -ForegroundColor Yellow
Write-Host "        this script (or setup_update.ps1 Step XX) to regenerate it." -ForegroundColor Yellow
```

---

### `C:\Sync\Config\cloud_sync.ps1`
> Rclone sync to Backblaze B2. Includes self-healing firewall detection+removal+retry, failure sentinel (.sync_failed), B2 lag alert (.last_sync_ok), 3-phase ACL protection (7 days), source folder retention (7 days, date-name based), log rotation (30 days), mirror cleanup. ACL failures logged with ACL-WARN prefix. All comments in English. Import-Module Microsoft.PowerShell.Security added for SYSTEM/PS5 compatibility (T050, 2026-06-05). (T026/T030/T031/T032, 2026-06-02; T048, 2026-06-03)

```powershell
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-06-05 - T050: add Import-Module Security for SYSTEM PS5 ACL fix

Add-Type -AssemblyName System.Security
Import-Module Microsoft.PowerShell.Security -ErrorAction SilentlyContinue

$Rclone             = 'C:\Tools\Rclone\rclone.exe'
$Config             = 'C:\Sync\Config\rclone.conf'
$Source             = 'C:\Users\helde\Repos\Bois'
$Remote             = 'cloudsync:helder-sync-mirror'
$Mirror             = 'C:\Sync\Mirror'
$LogDir             = 'C:\Sync\Logs\cloud_sync'
$Log                = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror   = 7
$DaysToKeepLogs     = 30
$SyncFailedSentinel = 'C:\Sync\Config\.sync_failed'
$LastSyncOkFile     = 'C:\Sync\Config\.last_sync_ok'

# Known malicious firewall rules that block Backblaze B2 sync
$MaliciousFirewallRules = @(
    'Block 104.153.233.180',
    'Block 149.137.142.15'
)

$B2CredsFile = 'C:\Sync\Config\b2_creds.dpapi'

function Load-B2Credentials {
    if (-not (Test-Path $B2CredsFile)) {
        Write-SyncLog "SYNC-FAIL  b2_creds.dpapi not found - run store_b2_creds.ps1 to migrate credentials"
        exit 1
    }
    try {
        $base64    = Get-Content -LiteralPath $B2CredsFile -Raw -Encoding ASCII
        $encrypted = [Convert]::FromBase64String($base64.Trim())
        $jsonBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        $json    = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
        $creds   = $json | ConvertFrom-Json
        $env:RCLONE_CONFIG_CLOUDSYNC_ACCOUNT = $creds.account
        $env:RCLONE_CONFIG_CLOUDSYNC_KEY     = $creds.key
    } catch {
        Write-SyncLog "SYNC-FAIL  Failed to decrypt b2_creds.dpapi: $($_.Exception.Message)"
        exit 1
    }
}

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
# INIT - Load B2 credentials from DPAPI-encrypted blob
# Sets RCLONE_CONFIG_CLOUDSYNC_ACCOUNT / _KEY env vars
# ============================================================
Load-B2Credentials

# ============================================================
# T030 - B2 lag alert: warn if last successful sync is stale
# ============================================================
if (Test-Path $LastSyncOkFile) {
    $lastOk = [datetime](Get-Content -LiteralPath $LastSyncOkFile -Raw).Trim()
    $lagMinutes = [math]::Round(((Get-Date) - $lastOk).TotalMinutes, 1)
    if ($lagMinutes -gt 15) {
        Write-SyncLog "B2-LAG-ALERT  Last successful sync was $lagMinutes minutes ago (threshold: 15)"
    }
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
            # T026: clear failure sentinel on successful retry
            if (Test-Path $SyncFailedSentinel) { Remove-Item -LiteralPath $SyncFailedSentinel -Force -ErrorAction SilentlyContinue }
            # T030: record successful sync timestamp
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Set-Content -LiteralPath $LastSyncOkFile -NoNewline
        } else {
            Write-SyncLog "FIREWALL-HEAL  Retry FAILED (exit $LASTEXITCODE) - sync still failing after firewall repair"
            Write-SyncLog "FIREWALL-HEAL  Manual investigation required"
            # T026: write failure sentinel
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  FIREWALL-HEAL Retry FAILED (exit $LASTEXITCODE)" |
                Set-Content -LiteralPath $SyncFailedSentinel -NoNewline
        }
    } else {
        Write-SyncLog "FIREWALL-DETECT  No known malicious rules found - unknown blocking cause"
        Write-SyncLog "FIREWALL-DETECT  Run check_status.ps1 and review firewall rules manually"
    }
} elseif ($rcloneExitCode -eq 0) {
    Write-SyncLog "SYNC-OK  Sync completed successfully (exit 0)"
    # T026: clear failure sentinel on success
    if (Test-Path $SyncFailedSentinel) { Remove-Item -LiteralPath $SyncFailedSentinel -Force -ErrorAction SilentlyContinue }
    # T030: record successful sync timestamp
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Set-Content -LiteralPath $LastSyncOkFile -NoNewline
} else {
    Write-SyncLog "SYNC-FAIL  Sync failed (exit $rcloneExitCode) - not a firewall error"
    # T026: write failure sentinel
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  SYNC-FAIL (exit $rcloneExitCode)" |
        Set-Content -LiteralPath $SyncFailedSentinel -NoNewline
}

# ============================================================
# PHASE 0 - Apply Deny Delete ACL to files younger than 7 days
# Protects each file that has not yet reached 7 days of age
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop

                # Check if file already has Deny Delete ACL (avoid duplicate)
                $hasDeny = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }

                if (-not $hasDeny) {
                    # Apply Deny Delete ACL
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
                # T032: surface ACL set failures
                Write-SyncLog "ACL-WARN  Failed to set ACL on $($_.FullName): $($_.Exception.Message)"
            }
        }
}

# ============================================================
# PHASE 1 - Remove Deny Delete ACL from files >= 7 days old
# Strips protection from files that have reached 7 days
# CRITICAL: Must run BEFORE attempting deletion (Phase 2)
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop

                # Find Deny Delete rules belonging to Everyone
                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }

                if ($denyRules) {
                    # Remove each Deny Delete rule found
                    foreach ($rule in $denyRules) {
                        $acl.RemoveAccessRule($rule) | Out-Null
                    }
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch {
                # T032: surface ACL removal failures
                Write-SyncLog "ACL-WARN  Failed to remove ACL on $($_.FullName): $($_.Exception.Message)"
            }
        }
}

# ============================================================
# PHASE 2 - Delete files >= 7 days old
# ACL was already stripped in PHASE 1, so delete runs without ERROR 5
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Clean up empty folders (after deleting files)
    Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ============================================================
# PHASE 3 - Source folder retention
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
> Watchdog loop (180s interval). Monitors RealTimeSync process and FolderSync-CloudBackup task. Logs WATCHDOG-HEARTBEAT every cycle. Restarts RealTimeSync if not running; re-enables task if Disabled. Logs to C:\Sync\Logs\services\watchdog.log. (T027, 2026-06-02)
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
    Write-Log "WATCHDOG-HEARTBEAT"

    # --- Check RealTimeSync ---
    $rts = Get-Process -Name "RealTimeSync" -ErrorAction SilentlyContinue
    if (-not $rts) {
        Write-Log "RealTimeSync not running â€” starting."
        Start-Process -FilePath $RealTimeSync -ArgumentList "`"$RealTimeSyncConfig`"" -WindowStyle Hidden
    }

    # --- Check scheduled task is enabled ---
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.State -eq 'Disabled') {
        Write-Log "Task $TaskName was disabled â€” re-enabling."
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

### `C:\Sync\Config\auditor.ps1`
> Security monitor: startup gap forensics, FileSystemWatcher on source folder, remote logon/service/system event polling. Background job cleanup every ~60s (T028); motion AVI vs suspicious delete distinction (T029); 30-day log rotation for audit logs (T033, 2026-06-02). Writes to security_audit_YYYY-MM-DD.log and file_audit_YYYY-MM-DD.log.
```powershell
# auditor.ps1
# FolderSync Security Auditor
# Monitors file system events, remote access, service tampering, and system events.
# Runs as NSSM service "FolderSyncAuditor".

$WatchedFolder  = 'C:\Users\helde\Repos\Bois'
$LogDir         = 'C:\Sync\Logs'
$AuditDir       = "$LogDir\audit"
$SecurityDir    = "$LogDir\security"
$StartupGapSecs = 120   # gap threshold to trigger forensic dump

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-FileAuditLog  { Join-Path $AuditDir    "file_audit_$(Get-Date -Format 'yyyy-MM-dd').log" }
function Get-SecurityLog   { Join-Path $SecurityDir "security_audit_$(Get-Date -Format 'yyyy-MM-dd').log" }

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
    $allLogs = Get-ChildItem $SecurityDir -Filter "security_audit_*.log" -ErrorAction SilentlyContinue |
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
    $path = Join-Path $AuditDir "interruption_report_$ts.txt"

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
# Log rotation (T033): delete audit logs older than 30 days
# ---------------------------------------------------------------------------
$script:LastLogRotation = [datetime]::MinValue

function Invoke-AuditLogRotation {
    if (([datetime]::Now - $script:LastLogRotation).TotalHours -lt 24) { return }
    $script:LastLogRotation = [datetime]::Now
    $cutoff = (Get-Date).AddDays(-30)

    foreach ($pattern in @("$SecurityDir\security_audit_*.log", "$AuditDir\file_audit_*.log")) {
        Get-ChildItem -LiteralPath (Split-Path $pattern) -Filter (Split-Path $pattern -Leaf) `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                Write-SecurityAudit "[LOG-ROTATE] Deleted old log: $($_.Name)"
            }
    }
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
        # ForÃ§amos a conversÃ£o para String AQUI, antes de entrar no Job
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

            $logFile = "C:\Sync\Logs\audit\file_audit_$($time.ToString('yyyy-MM-dd')).log"
            $ts = $time.ToString("yyyy-MM-dd HH:mm:ss")

            # T029: distinguish routine AVI aging from suspicious deletions
            # $name includes subdirectory when IncludeSubdirectories=true (e.g. "2026-06-05\motion_*.avi")
            # so extract just the filename before pattern-matching
            if ($type -eq 'DELETED') {
                if (([System.IO.Path]::GetFileName($name)) -like 'motion_*.avi') {
                    $detail = 'DELETED-ROUTINE'
                    $line = "$ts | $($detail.PadRight(25)) | user=$user | path=$path"
                    $line | Add-Content -LiteralPath $logFile -Encoding UTF8
                } else {
                    $detail = 'DELETED-SUSPICIOUS'
                    $line = "$ts | ALERT  $($detail.PadRight(18)) | user=$user | path=$path"
                    $line | Add-Content -LiteralPath $logFile -Encoding UTF8
                    $secLog = "C:\Sync\Logs\security\security_audit_$($time.ToString('yyyy-MM-dd')).log"
                    $line | Add-Content -LiteralPath $secLog -Encoding UTF8
                    & 'C:\Sync\Config\cloud_sync.ps1'
                }
            } else {
                # FormataÃ§Ã£o garantida como texto
                $detail = if ($old) { "RENAMED: $old -> $name" } else { $type }
                $line = "$ts | $($detail.PadRight(25)) | user=$user | path=$path"
                $line | Add-Content -LiteralPath $logFile -Encoding UTF8
            }
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

# T033: rotate old audit logs at startup
Invoke-AuditLogRotation

# Start file system watcher
$fsw = Start-FileWatcher
Write-FileAudit "[AUDITOR] FileSystemWatcher active on $WatchedFolder"

# Main polling loop
$script:LoopIteration = 0
try {
    while ($true) {
        Check-RemoteAccess
        Check-Services
        Check-SystemEvents

        # T028: clean up completed/failed background jobs every 60 iterations (~60s)
        $script:LoopIteration++
        if ($script:LoopIteration % 60 -eq 0) {
            Get-Job | Where-Object { $_.State -in 'Completed', 'Failed' } | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        # T033: daily log rotation check
        Invoke-AuditLogRotation

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

### `C:\Sync\Config\config_guard.ps1`
> FileSystemWatcher on `Config\` — auto-restores `cloud_sync.ps1` and `run_mirror.bat` from git HEAD the instant any process modifies them. Runs as a persistent hidden background process (keep-alive 30s sleep loop). Registered as `FolderSync-ConfigGuard` scheduled task (at logon, current user, no time limit) via `setup_update.ps1` Step 20. Logs to `C:\Sync\Logs\security\config_guard_YYYY-MM-DD.log`.
```powershell
# config_guard.ps1
# FileSystemWatcher on Config\ — auto-restores cloud_sync.ps1 and run_mirror.bat
# via git restore the moment they are modified by any process.
# Runs hidden at login via registry Run key or Task Scheduler.

$RepoRoot  = 'C:\Sync'
$ConfigDir = 'C:\Sync\Config'
$LogFile   = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
$GuardedFiles = @('cloud_sync.ps1', 'run_mirror.bat')

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

Write-Log "CONFIG-GUARD  START  watching $ConfigDir for changes to: $($GuardedFiles -join ', ')"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path   = $ConfigDir
$watcher.Filter = '*.*'
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $true

$action = {
    $name = $Event.SourceEventArgs.Name
    $full = $Event.SourceEventArgs.FullPath
    $type = $Event.SourceEventArgs.ChangeType

    $guarded = @('cloud_sync.ps1', 'run_mirror.bat')
    if ($guarded -notcontains $name) { return }

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "$ts  CONFIG-GUARD  ALERT  $type detected on $name - restoring from git"
    $logLine | Add-Content -LiteralPath "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"

    # Remove index.lock if present
    $lock = 'C:\Sync\.git\index.lock'
    if (Test-Path $lock) {
        Remove-Item -Force $lock -ErrorAction SilentlyContinue
        "$ts  CONFIG-GUARD  INFO  removed stale index.lock before restore" | Add-Content -LiteralPath "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
    }

    # Restore the file — use full path relative to repo root (Config/<name>)
    $repoRelPath = "Config/$name"
    $out = & git -C 'C:\Sync' restore $repoRelPath 2>&1
    $result = if ($LASTEXITCODE -eq 0) { "RESTORED" } else { "RESTORE-FAILED: $out" }
    "$ts  CONFIG-GUARD  $result  $name" | Add-Content -LiteralPath "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null

Write-Log "CONFIG-GUARD  READY  watcher active"

# Keep alive
while ($true) {
    Start-Sleep -Seconds 30

    # Daily log rotation
    $newLog = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
    if ($newLog -ne $LogFile) { $LogFile = $newLog }
}
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
# STEP 20 - FolderSync-ConfigGuard task (at logon, current user, hidden)
# Watches Config\cloud_sync.ps1 and run_mirror.bat via FileSystemWatcher.
# Restores them from git HEAD the instant any process modifies them.
# Runs as a persistent background process (keep-alive loop inside the script).
# =============================================================================
Write-Step "Step 20 - FolderSync-ConfigGuard task (at logon, current user, hidden)"

$userSid20 = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskXml20 = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$currentUser</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userSid20</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>pwsh.exe</Command>
      <Arguments>-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Sync\Config\config_guard.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Unregister-ScheduledTask -TaskName "FolderSync-ConfigGuard" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-ConfigGuard" -Xml $taskXml20 -Force | Out-Null
Write-OK "Task FolderSync-ConfigGuard registered ($currentUser / InteractiveToken, at logon, no time limit)"

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
> Camera and motion detection health check. Run interactively to verify Yawcam process, webcam PnP device, recordings, startup entries, CAM-2 VLC relay (process + port 8161 + restart sentinel), and recent recordings across all cameras. No admin required for most checks. (T025, 2026-06-02)

```powershell
# check_camera.ps1
# Camera / Motion Detection Health Check
# Modeled after check_status.ps1 â€” run interactively to diagnose camera state
# No admin required for most checks; PnP device queries may return partial data without elevation

$TodayDir  = "C:\Users\helde\Repos\Bois\$(Get-Date -Format 'yyyy-MM-dd')"
$TempPath  = "C:\TEMP\motion_videos"
$YawcamExe = "C:\Program Files (x86)\Yawcam\Yawcam.exe"
$MonitorV4 = "C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1"

# =============================================================================
Write-Host "=== YAWCAM PROCESS ===" -ForegroundColor Cyan
$yawcamProc = Get-Process -Name "yawcam" -ErrorAction SilentlyContinue
$javawProc  = Get-Process -Name "javaw"  -ErrorAction SilentlyContinue |
              Where-Object { $_.MainWindowTitle -like "*Yawcam*" }

if ($yawcamProc) {
    $yawcamProc | Select-Object Name, Id, CPU, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
} elseif ($javawProc) {
    Write-Host "  (running as javaw)" -ForegroundColor Yellow
    $javawProc | Select-Object Name, Id, CPU, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
} else {
    Write-Host "  NOT RUNNING" -ForegroundColor Red
}

# =============================================================================
Write-Host "`n=== YAWCAM MONITOR PROCESS ===" -ForegroundColor Cyan
$monitorProc = Get-Process -Name "powershell" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like "*yawcam_monitor*" }
if ($monitorProc) {
    $monitorProc | Select-Object Name, Id, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
} else {
    # Try WMI for command line
    $wmiProc = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like "*yawcam_monitor*" }
    if ($wmiProc) {
        $wmiProc | Select-Object Name, ProcessId, @{N="CommandLine(truncated)";E={$_.CommandLine.Substring(0,[math]::Min(80,$_.CommandLine.Length))}}
    } else {
        Write-Host "  NOT RUNNING" -ForegroundColor Red
    }
}

# =============================================================================
Write-Host "`n=== WEBCAM DEVICE (PnP) ===" -ForegroundColor Cyan
Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like "*HD User*" -or $_.FriendlyName -like "*webcam*" -or $_.FriendlyName -like "*camera*" -or $_.Class -eq "Camera" -or $_.Class -eq "Image" } |
    Select-Object FriendlyName, Status, Class, InstanceId

# =============================================================================
Write-Host "`n=== REGISTRY STARTUP ENTRIES ===" -ForegroundColor Cyan
$runKey = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
Write-Host "  Yawcam:        $($runKey.Yawcam)"
Write-Host "  YawcamMonitor:    $($runKey.YawcamMonitor)"
Write-Host "  YawcamCam2Relay:  $($runKey.YawcamCam2Relay)"
Write-Host "  (other Sync entries for reference)"
Write-Host "  FolderSyncRealTime: $($runKey.FolderSyncRealTime)"

# =============================================================================
Write-Host "`n=== YAWCAM INSTALLATION ===" -ForegroundColor Cyan
Write-Host "  Yawcam.exe     : $(if (Test-Path $YawcamExe) { 'FOUND - ' + (Get-Item $YawcamExe).LastWriteTime } else { 'NOT FOUND' })"
Write-Host "  monitor_v4.ps1 : $(if (Test-Path $MonitorV4) { 'FOUND - ' + (Get-Item $MonitorV4).LastWriteTime } else { 'NOT FOUND' })"

# =============================================================================
Write-Host "`n=== TODAY'S RECORDINGS ($TodayDir) ===" -ForegroundColor Cyan
if (Test-Path $TodayDir) {
    $files = Get-ChildItem $TodayDir -Filter "*.avi" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
    if ($files) {
        $totalMB  = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        $latest   = $files | Select-Object -Last 1
        $oldest   = $files | Select-Object -First 1
        $ageMin   = [math]::Round(((Get-Date) - $latest.LastWriteTime).TotalMinutes, 1)
        Write-Host "  Count      : $($files.Count) files"
        Write-Host "  Total size : $totalMB MB"
        Write-Host "  First      : $($oldest.Name)  ($($oldest.LastWriteTime))"
        Write-Host "  Latest     : $($latest.Name)  ($($latest.LastWriteTime))"
        if ($ageMin -le 5) {
            Write-Host "  Age        : $ageMin min ago  [ACTIVE - recording recently]" -ForegroundColor Green
        } elseif ($ageMin -le 15) {
            Write-Host "  Age        : $ageMin min ago  [OK - within normal gap]" -ForegroundColor Cyan
        } else {
            Write-Host "  Age        : $ageMin min ago  [GAP - no motion or camera frozen?]" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No .avi files yet today" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Directory not yet created for today" -ForegroundColor Yellow
}

# =============================================================================
Write-Host "`n=== MONITOR RECORDING PATH ($TempPath) ===" -ForegroundColor Cyan
if (Test-Path $TempPath) {
    $tmpFiles = Get-ChildItem $TempPath -Recurse -Filter "*.avi" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($tmpFiles) {
        $tmpAge = [math]::Round(((Get-Date) - $tmpFiles.LastWriteTime).TotalMinutes, 1)
        Write-Host "  Latest : $($tmpFiles.Name)  ($tmpAge min ago)"
    } else {
        Write-Host "  Path exists but no .avi files" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Path does not exist (monitor may fail to find recordings)" -ForegroundColor Red
    Write-Host "  NOTE: Actual recordings go to Bois dir (see above). Monitor path is legacy." -ForegroundColor Gray
}

# =============================================================================
Write-Host "`n=== RECENT RECORDINGS (last 5 across all cameras) ===" -ForegroundColor Cyan
$allDirs = Get-ChildItem "C:\Users\helde\Repos\Bois" -Directory -ErrorAction SilentlyContinue |
           Sort-Object Name -Descending | Select-Object -First 3
foreach ($dir in $allDirs) {
    $dirFiles = Get-ChildItem $dir.FullName -Filter "*.avi" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2
    foreach ($f in $dirFiles) {
        $age = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalMinutes, 0)
        Write-Host ("  [{0}]  {1}  ({2} min ago,  {3:N0} KB)" -f $dir.Name, $f.Name, $age, ($f.Length/1KB))
    }
}

# =============================================================================
Write-Host "`n=== CAM-2 RELAY (VLC: RTSP -> MJPEG http://127.0.0.1:8161/) ===" -ForegroundColor Cyan

# VLC process check
$relayProc = Get-CimInstance Win32_Process -Filter "Name = 'vlc.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -like "*cam2_relay*" -or $_.CommandLine -like "*8161*" }
if ($relayProc) {
    Write-Host "  VLC process : PASS  (PID $($relayProc.ProcessId))" -ForegroundColor Green
} else {
    $vlcAny = Get-Process -Name "vlc" -ErrorAction SilentlyContinue
    if ($vlcAny) {
        Write-Host "  VLC process : PASS  VLC running (PID $($vlcAny.Id)) - verify it is the cam2 relay" -ForegroundColor Yellow
    } else {
        Write-Host "  VLC process : FAIL  NOT RUNNING - run cam2_relay.ps1 or reboot to auto-start" -ForegroundColor Red
    }
}

# Port 8161 check
$port8161 = Test-NetConnection -ComputerName "127.0.0.1" -Port 8161 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($port8161.TcpTestSucceeded) {
    Write-Host "  Port 8161   : PASS  listening" -ForegroundColor Green
} else {
    Write-Host "  Port 8161   : FAIL  nothing listening on 127.0.0.1:8161" -ForegroundColor Red
}

# Sentinel: restart failure flag
$sentinelFail = "C:\Sync\Config\.camera_restart_failed"
if (Test-Path $sentinelFail) {
    $sentinelTs = Get-Content -LiteralPath $sentinelFail -ErrorAction SilentlyContinue
    Write-Host "  Restart sentinel : FAIL  .camera_restart_failed exists (timestamp: $sentinelTs)" -ForegroundColor Red
    Write-Host "                     Yawcam failed to recover after last restart attempt." -ForegroundColor Red
    Write-Host "                     Remove C:\Sync\Config\.camera_restart_failed after manual fix." -ForegroundColor Gray
} else {
    Write-Host "  Restart sentinel : PASS  no failure flag" -ForegroundColor Green
}

$cam2Reachable = Test-Connection -ComputerName "192.168.0.109" -Count 1 -Quiet -ErrorAction SilentlyContinue
Write-Host "  C100 ping   : $(if ($cam2Reachable) { 'REACHABLE (192.168.0.109)' } else { 'UNREACHABLE - camera offline or IP changed?' })" -ForegroundColor $(if ($cam2Reachable) { 'Green' } else { 'Red' })
$relayLog = "C:\Sync\Logs\services\cam2_relay.log"
if (Test-Path $relayLog) {
    $lastLine = Get-Content $relayLog -Tail 1
    Write-Host "  Last log    : $lastLine"
} else {
    Write-Host "  Relay log   : no log yet at $relayLog" -ForegroundColor Yellow
}

# =============================================================================
Write-Host "`n=== CAMERA INPUT SUMMARY ===" -ForegroundColor Cyan
Write-Host "  [CAM-1]  Built-in laptop webcam (HD User Facing)  ->  Yawcam 0.6.2 (direct)"
Write-Host "  [CAM-2]  TP-LINK Tapo C100 (192.168.0.109)        ->  VLC relay -> Yawcam (http://127.0.0.1:8161/)"
Write-Host ""

```

---

### `C:\Sync\Config\cam2_relay.ps1`
> CAM-2 VLC RTSP->MJPEG relay. Reads credentials from cam2.conf, starts VLC on http://127.0.0.1:8161/. Circuit breaker: max 5 restarts/hour. Port-listening verification after each restart. 7-day log rotation. Logs to C:\Sync\Logs\services\cam2_relay.log. (T024, 2026-06-02)

```powershell
# cam2_relay.ps1
# CAM-2 RTSP -> MJPEG HTTP relay for Yawcam
# Reads credentials from cam2.conf, starts VLC relay on http://127.0.0.1:8161/
# Registered as startup entry: HKCU:\...\Run\YawcamCam2Relay
# Logs to C:\Sync\Logs\services\cam2_relay.log (single rolling file, 7-day retention)

$ConfFile       = "C:\Sync\Config\cam2.conf"
$VlcExe         = "C:\Program Files\VideoLAN\VLC\vlc.exe"
$RelayPort      = 8161
$RelayHost      = "127.0.0.1"
$LogFile        = "C:\Sync\Logs\services\cam2_relay.log"
$CheckSecs      = 30   # health check interval
$MaxRestarts    = 5    # max restarts per hour before giving up
$RestartWindow  = 3600 # seconds (1 hour)

$restartTimes = [System.Collections.Generic.List[datetime]]::new()

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

function Invoke-LogRotation {
    if (-not (Test-Path $LogFile)) { return }
    $cutoff = (Get-Date).AddDays(-7)
    $lines = Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue
    if (-not $lines) { return }
    $kept = $lines | Where-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2})') {
            try { [datetime]$matches[1] -ge $cutoff } catch { $true }
        } else { $true }
    }
    $kept | Set-Content -LiteralPath $LogFile -Force
}

function Test-PortListening {
    $result = Test-NetConnection -ComputerName $RelayHost -Port $RelayPort -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    return $result.TcpTestSucceeded
}

# ---------------------------------------------------------------------------
# Read credentials from cam2.conf
# ---------------------------------------------------------------------------
if (-not (Test-Path $ConfFile)) {
    Write-Log "FAIL  cam2.conf not found at $ConfFile  - relay cannot start"
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

$RtspUrl = "rtsp://${user}:${pass}@${ip}:${port}/${stream}"
$SoutDst = "${RelayHost}:${RelayPort}/"
$SoutArg = "#transcode{vcodec=MJPG,fps=10,acodec=none}:std{access=http,mux=mpjpeg,dst=${SoutDst}}"

Invoke-LogRotation
Write-Log "START  CAM-2 relay starting  ->  http://${RelayHost}:${RelayPort}/"
Write-Log "INFO   Source: rtsp://${user}:***@${ip}:${port}/${stream}"

# ---------------------------------------------------------------------------
# Relay loop  - start VLC, monitor, restart on death
# ---------------------------------------------------------------------------
$vlcProc = $null

function Start-VlcRelay {
    Write-Log "INFO   Launching VLC relay"
    $vlcArgs = @(
        "-I", "dummy",
        "--no-one-instance",
        "--loop",
        "--sout-keep",
        $RtspUrl,
        "--sout=$SoutArg"
    )
    return Start-Process -FilePath $VlcExe -ArgumentList $vlcArgs -PassThru -WindowStyle Hidden
}

$vlcProc = Start-VlcRelay

$lastRotation = Get-Date

while ($true) {
    Start-Sleep -Seconds $CheckSecs

    # Daily log rotation (prune entries older than 7 days)
    if (((Get-Date) - $lastRotation).TotalHours -ge 24) {
        Invoke-LogRotation
        $lastRotation = Get-Date
    }

    if ($vlcProc -eq $null -or $vlcProc.HasExited) {
        Write-Log "WARN   VLC relay process died  - checking restart rate"

        # Prune restart timestamps outside the window
        $cutoff = (Get-Date).AddSeconds(-$RestartWindow)
        $restartTimes.RemoveAll([System.Predicate[datetime]]{ param($t) $t -lt $cutoff }) | Out-Null

        if ($restartTimes.Count -ge $MaxRestarts) {
            Write-Log "RELAY-GIVINGUP  $MaxRestarts restarts in last hour  - relay exiting"
            exit 1
        }

        $restartTimes.Add((Get-Date))
        Write-Log "WARN   Restarting VLC (attempt $($restartTimes.Count) of $MaxRestarts in current window)"
        $vlcProc = Start-VlcRelay

        # Wait for VLC to bind the port
        Start-Sleep -Seconds 5
        if (Test-PortListening) {
            Write-Log "INFO   Port $RelayPort listening - relay confirmed up"
        } else {
            Write-Log "WARN   Port $RelayPort not yet listening after restart"
        }
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
> Active Yawcam monitor (in C:\Sync\Config\). Scans C:\Users\helde\Repos\Bois recursively for latest .avi every 60s. Logs to C:\Sync\Logs\services\yawcam_monitor.log (T023). Restart failure writes sentinel .camera_restart_failed (T034). 600s cooldown. Starts Yawcam via start_yawcam.bat. (T022/T023/T034, 2026-06-02)
> Active Yawcam monitor (in C:\Sync\Config\). Scans C:\Users\helde\Repos\Bois recursively for latest .avi every 60s. Logs to C:\Sync\Logs\services\yawcam_monitor.log (T023). Restart failure writes sentinel .camera_restart_failed (T034). 600s cooldown. Starts Yawcam via start_yawcam.bat. (T022/T023/T034, 2026-06-02)

```powershell
# ========================================
# MONITOR YAWCAM - BASEADO EM GRAVACAO
# ========================================
# Relocated to C:\Sync\Config\ (was: C:\Program Files (x86)\Yawcam\)
# Scans C:\Users\helde\Repos\Bois recursively for latest *.avi across all date subdirs.

$YawcamPath      = "C:\Sync\Config\start_yawcam.bat"
$VideoPath       = "C:\Users\helde\Repos\Bois"
$LogFile         = "C:\Sync\Logs\services\yawcam_monitor.log"
$SentinelFail    = "C:\Sync\Config\.camera_restart_failed"
$CheckInterval   = 60
$MaxMinutesWithoutVideo = 15
$LastRestartTime = $null
$RestartCooldown = 600

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MONITOR YAWCAM - BASEADO EM GRAVACAO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verificacao: a cada $CheckInterval segundos" -ForegroundColor White
Write-Host "Alerta se: ficar $MaxMinutesWithoutVideo min sem gravar" -ForegroundColor White
Write-Host "Cooldown: $($RestartCooldown/60) minutos entre reinicos" -ForegroundColor White
Write-Host ""
Write-Host "Pressione Ctrl+C para parar" -ForegroundColor Yellow
Write-Host ""
Write-Log "START  monitor starting  VideoPath=$VideoPath  interval=${CheckInterval}s"

function Test-YawcamRunning {
    $yawcam = Get-Process -Name "yawcam" -ErrorAction SilentlyContinue
    if ($yawcam) { return $true }

    $javaw = Get-Process -Name "javaw" -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowTitle -like "*Yawcam*" }
    if ($javaw) { return $true }

    return $false
}

function Restart-YawcamSafely {
    Write-Host ""
    Write-Host ">>> REINICIANDO YAWCAM..." -ForegroundColor Cyan
    Write-Log "RESTART  beginning Yawcam restart sequence"

    Write-Host "   [1/5] Fechando Yawcam..." -ForegroundColor Gray
    Get-Process -Name "yawcam" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "javaw" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like "*Yawcam*" } |
        Stop-Process -Force
    Start-Sleep -Seconds 5

    Write-Host "   [2/5] Liberando camera..." -ForegroundColor Gray
    Get-PnpDevice | Where-Object { $_.FriendlyName -like "*HD User*" } |
        ForEach-Object {
            Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        }
    Start-Sleep -Seconds 3

    Write-Host "   [3/5] Aguardando estabilizacao..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    Write-Host "   [4/5] Iniciando Yawcam..." -ForegroundColor Gray
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$YawcamPath`""
    Start-Sleep -Seconds 10

    Write-Host "   [5/5] Verificando..." -ForegroundColor Gray
    if (Test-YawcamRunning) {
        Write-Host "   [OK] Yawcam reiniciado!" -ForegroundColor Green
        Write-Log "RESTART-OK  Yawcam process confirmed after restart"
        if (Test-Path $SentinelFail) { Remove-Item -LiteralPath $SentinelFail -Force -ErrorAction SilentlyContinue }
    } else {
        Write-Host "   [FAIL] Yawcam processo nao detectado apos reinicio" -ForegroundColor Red
        Write-Log "CAMERA-RESTART-FAILED  Yawcam process not detected after restart sequence"
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $ts | Set-Content -LiteralPath $SentinelFail -Force
    }
    Write-Host ""

    $script:LastRestartTime = Get-Date
}

while ($true) {
    $Timestamp = Get-Date -Format "HH:mm:ss"

    # PRIORIDADE 1: Verificar se esta gravando (mais importante!)
    $LatestVideo = Get-ChildItem -Path $VideoPath -Recurse -Filter "*.avi" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending |
                   Select-Object -First 1

    if ($LatestVideo) {
        $MinutesAgo = [math]::Round(((Get-Date) - $LatestVideo.LastWriteTime).TotalMinutes, 1)

        if ($MinutesAgo -le 5) {
            Write-Host "[$Timestamp] [OK] Gravando - ultimo video: $MinutesAgo min atras" -ForegroundColor Green
            Write-Log "OK  recording active  latest=$($LatestVideo.Name)  age=${MinutesAgo}min"
        }
        elseif ($MinutesAgo -le $MaxMinutesWithoutVideo) {
            Write-Host "[$Timestamp] [INFO] Ultimo video: $MinutesAgo min atras" -ForegroundColor Cyan
            Write-Log "INFO  no recent recording  latest=$($LatestVideo.Name)  age=${MinutesAgo}min"
        }
        else {
            Write-Host "[$Timestamp] [AVISO] SEM novos videos ha $MinutesAgo minutos!" -ForegroundColor Yellow
            Write-Log "WARN  no video for ${MinutesAgo}min  latest=$($LatestVideo.Name)"

            if ($LastRestartTime -eq $null -or ((Get-Date) - $LastRestartTime).TotalSeconds -gt $RestartCooldown) {
                Write-Host "[$Timestamp] [ACAO] Yawcam provavelmente congelado - reiniciando..." -ForegroundColor Magenta
                Write-Log "ACTION  triggering restart  reason=no-video-${MinutesAgo}min"
                Restart-YawcamSafely
            } else {
                $WaitTime = [math]::Round(($RestartCooldown - ((Get-Date) - $LastRestartTime).TotalSeconds) / 60, 1)
                Write-Host "[$Timestamp] [WAIT] Cooldown ativo - $WaitTime min restantes" -ForegroundColor Yellow
                Write-Log "WAIT  cooldown active  remaining=${WaitTime}min"
            }
        }
    } else {
        Write-Host "[$Timestamp] [AVISO] Nenhum video em $VideoPath" -ForegroundColor Yellow
        Write-Log "WARN  no *.avi files found under $VideoPath"

        if (-not (Test-YawcamRunning)) {
            Write-Host "[$Timestamp] [ERRO] Yawcam nao esta rodando!" -ForegroundColor Red
            Write-Log "ERROR  Yawcam not running"

            if ($LastRestartTime -eq $null -or ((Get-Date) - $LastRestartTime).TotalSeconds -gt $RestartCooldown) {
                Write-Log "ACTION  triggering restart  reason=process-not-running"
                Restart-YawcamSafely
            }
        }
    }

    Start-Sleep -Seconds $CheckInterval
}

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


---

### `C:\Sync\Config\run_tests.ps1`
> Tier 1-4 automated test orchestrator for T010-T034 changes. Tier 1: parse checks for 6 key scripts. Tier 2: safe live runs (DailySecurityCheck, check_camera). Tier 3: sentinel file verification (.last_sync_ok, .sync_failed, .camera_restart_failed). Tier 4: behavioral log checks (watchdog heartbeat, auditor job cleanup). Logs to C:\Sync\Logs\security\test_results_YYYY-MM-DD.log. (T035, 2026-06-02)
```powershell
#Requires -Version 5.1
# run_tests.ps1 - Tier 1-4 automated validation for T010-T034 changes
# Usage: powershell -ExecutionPolicy Bypass -File run_tests.ps1
# Results written to C:\Sync\Logs\security\test_results_YYYY-MM-DD.log

$LogFile = "C:\Sync\Logs\security\test_results_$(Get-Date -Format 'yyyy-MM-dd').log"
$pass = 0; $fail = 0; $warn = 0

function Write-Result($tier, $name, $status, $detail = '') {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts  [$tier]  $status  $name$(if ($detail) { "  - $detail" })"
    Add-Content -LiteralPath $LogFile -Value $line
    $color = switch ($status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'White' } }
    Write-Host $line -ForegroundColor $color
    switch ($status) { 'PASS' { $script:pass++ } 'FAIL' { $script:fail++ } 'WARN' { $script:warn++ } }
}

Add-Content -LiteralPath $LogFile -Value "`n=== TEST RUN $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# --- TIER 1: Parse Checks ---
Write-Host "`n>>> TIER 1 - Parse Checks" -ForegroundColor Cyan
$t1scripts = @('DailySecurityCheck.ps1','yawcam_monitor_v4.ps1','cam2_relay.ps1','wdog.ps1','auditor.ps1','cloud_sync.ps1')
foreach ($s in $t1scripts) {
    $path = "C:\Sync\Config\$s"
    $t = $null; $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e) | Out-Null
    if ($e.Count -eq 0) {
        Write-Result 'T1' $s 'PASS'
    } else {
        $errs = ($e | ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        Write-Result 'T1' $s 'FAIL' $errs
    }
}

# --- TIER 2: Safe Live Runs ---
Write-Host "`n>>> TIER 2 - Safe Live Runs" -ForegroundColor Cyan

# DailySecurityCheck - run non-interactively, check log written
$today = Get-Date -Format 'yyyy-MM-dd'
$dscLog = "C:\Sync\Logs\security\security_check_$today.log"
try {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -NonInteractive -File "C:\Sync\Config\DailySecurityCheck.ps1" 2>&1
    if (Test-Path $dscLog) {
        Write-Result 'T2' 'DailySecurityCheck - log written' 'PASS'
        # Verify new check sections present in log
        $logContent = Get-Content -LiteralPath $dscLog -Raw
        # Verify script ran to completion
        if ($logContent -match 'SCAN-END') {
            Write-Result 'T2' 'DailySecurityCheck - ran to completion' 'PASS'
        } else {
            Write-Result 'T2' 'DailySecurityCheck - ran to completion' 'FAIL' 'SCAN-END not found in log'
        }
        # Checks that always log (B2, RunKey, TaskIntegrity)
        foreach ($keyword in @('B2Connectivity','RunKey','TaskTamper|TaskMissing|TaskOK')) {
            if ($logContent -match $keyword) {
                Write-Result 'T2' "DailySecurityCheck - $keyword logged" 'PASS'
            } else {
                Write-Result 'T2' "DailySecurityCheck - $keyword logged" 'FAIL' 'keyword missing from log'
            }
        }
        # Alert-only checks (FirewallBlock, HostsPoison, EventLog) only log when triggered
        $alerts = @($logContent | Select-String 'ALERT')
        if ($alerts.Count -eq 0) {
            Write-Result 'T2' 'DailySecurityCheck - 0 alerts on clean system' 'PASS'
        } else {
            Write-Result 'T2' "DailySecurityCheck - $($alerts.Count) alerts fired" 'WARN' 'review log - may be real issues'
        }
    } else {
        Write-Result 'T2' 'DailySecurityCheck - log written' 'FAIL' 'log file not found after run'
    }
} catch {
    Write-Result 'T2' 'DailySecurityCheck - execution' 'FAIL' $_.Exception.Message
}

# check_camera.ps1 - verify new sections present
try {
    $camOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Sync\Config\check_camera.ps1" 2>&1 | Out-String
    if ($camOut -match 'CAM-2|cam2|relay|8161') {
        Write-Result 'T2' 'check_camera - CAM-2 relay section present' 'PASS'
    } else {
        Write-Result 'T2' 'check_camera - CAM-2 relay section present' 'FAIL' 'no CAM-2/relay output found'
    }
    if ($camOut -match 'camera_restart_failed|restart.failed') {
        Write-Result 'T2' 'check_camera - restart_failed sentinel check present' 'PASS'
    } else {
        Write-Result 'T2' 'check_camera - restart_failed sentinel check present' 'WARN' 'sentinel check not detected in output'
    }
} catch {
    Write-Result 'T2' 'check_camera - execution' 'FAIL' $_.Exception.Message
}

# --- TIER 3: Sentinel File Checks ---
Write-Host "`n>>> TIER 3 - Sentinel File Verification" -ForegroundColor Cyan

# .last_sync_ok
$lastSyncOk = 'C:\Sync\Config\.last_sync_ok'
if (Test-Path $lastSyncOk) {
    $ts = (Get-Content -LiteralPath $lastSyncOk -Raw).Trim()
    try {
        $age = (Get-Date) - [datetime]$ts
        if ($age.TotalMinutes -lt 15) {
            Write-Result 'T3' '.last_sync_ok - recent timestamp' 'PASS' "age: $([int]$age.TotalMinutes) min"
        } else {
            Write-Result 'T3' '.last_sync_ok - recent timestamp' 'WARN' "age: $([int]$age.TotalMinutes) min - cloud sync may not have run yet"
        }
    } catch {
        Write-Result 'T3' '.last_sync_ok - readable timestamp' 'FAIL' "content: $ts"
    }
} else {
    Write-Result 'T3' '.last_sync_ok - exists' 'WARN' 'not yet created - wait for next cloud_sync run (every 5 min)'
}

# .sync_failed should NOT exist on healthy system
if (Test-Path 'C:\Sync\Config\.sync_failed') {
    $reason = (Get-Content -LiteralPath 'C:\Sync\Config\.sync_failed' -Raw).Trim()
    Write-Result 'T3' '.sync_failed - not present on healthy system' 'FAIL' $reason
} else {
    Write-Result 'T3' '.sync_failed - not present on healthy system' 'PASS'
}

# .camera_restart_failed should NOT exist on healthy system
if (Test-Path 'C:\Sync\Config\.camera_restart_failed') {
    $ts = (Get-Content -LiteralPath 'C:\Sync\Config\.camera_restart_failed' -Raw).Trim()
    Write-Result 'T3' '.camera_restart_failed - not present on healthy system' 'WARN' "exists since: $ts - check if expected"
} else {
    Write-Result 'T3' '.camera_restart_failed - not present on healthy system' 'PASS'
}

# Monitor log - check path correctness
$monLog = 'C:\Sync\Logs\services\yawcam_monitor.log'
if (Test-Path $monLog) {
    $recentLines = Get-Content -LiteralPath $monLog -Tail 20 | Out-String
    if ($recentLines -match 'C:\\TEMP\\motion_videos') {
        Write-Result 'T3' 'yawcam_monitor.log - correct path (no TEMP reference)' 'FAIL' 'old path still appearing in recent log entries'
    } else {
        Write-Result 'T3' 'yawcam_monitor.log - correct path (no TEMP reference)' 'PASS'
    }
    if ($recentLines -match 'Bois') {
        Write-Result 'T3' 'yawcam_monitor.log - Bois path in log' 'PASS'
    } else {
        Write-Result 'T3' 'yawcam_monitor.log - Bois path in log' 'WARN' 'not yet seen - monitor may not have cycled'
    }
} else {
    Write-Result 'T3' 'yawcam_monitor.log - exists' 'WARN' 'not yet created - monitor must run one cycle first'
}

# --- TIER 4: Behavioral Log Checks ---
Write-Host "`n>>> TIER 4 - Behavioral Log Checks" -ForegroundColor Cyan

# Watchdog heartbeat
$wdogLog = 'C:\Sync\Logs\services\watchdog.log'
if (Test-Path $wdogLog) {
    $todayHB = Select-String -LiteralPath $wdogLog -Pattern "WATCHDOG-HEARTBEAT" | Where-Object { $_.Line -match $today }
    if ($todayHB) {
        Write-Result 'T4' 'watchdog.log - HEARTBEAT today' 'PASS' "$($todayHB.Count) entries"
    } else {
        Write-Result 'T4' 'watchdog.log - HEARTBEAT today' 'WARN' 'no heartbeat yet today - wait 3 min after service restart'
    }
} else {
    Write-Result 'T4' 'watchdog.log - exists' 'FAIL' 'log file missing'
}

# Auditor job cleanup
$auditLog = "C:\Sync\Logs\security\security_audit_$today.log"
if (Test-Path $auditLog) {
    $jobClean = Select-String -LiteralPath $auditLog -Pattern 'JOB-CLEANUP' -ErrorAction SilentlyContinue
    if ($jobClean) {
        Write-Result 'T4' 'auditor - JOB-CLEANUP entries present' 'PASS' "$($jobClean.Count) entries"
    } else {
        Write-Result 'T4' 'auditor - JOB-CLEANUP entries present' 'WARN' 'not yet seen - auditor needs ~60 loop iterations'
    }
} else {
    Write-Result 'T4' "security_audit_$today.log - exists" 'WARN' 'no audit log today yet'
}

# Summary
Write-Host "`n=== RESULTS: $pass PASS  $warn WARN  $fail FAIL ===" -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
Add-Content -LiteralPath $LogFile -Value "=== RESULTS: $pass PASS  $warn WARN  $fail FAIL ==="
exit $(if ($fail -gt 0) { 1 } else { 0 })

```

---

### `C:\Sync\Config\run_parse_check.ps1`
> Quick parse-only check for 6 key scripts: DailySecurityCheck, yawcam_monitor_v4, cam2_relay, wdog, auditor, cloud_sync. Exits 0 if all parse cleanly. (T035, 2026-06-02)
```powershell
$scripts = @('DailySecurityCheck.ps1','yawcam_monitor_v4.ps1','cam2_relay.ps1','wdog.ps1','auditor.ps1','cloud_sync.ps1')
$allPass = $true
foreach ($s in $scripts) {
    $path = "C:\Sync\Config\$s"
    $t = $null; $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e) | Out-Null
    $status = if ($e.Count -eq 0) { 'PASS' } else { 'FAIL'; $allPass = $false }
    Write-Host "$status  $s  ($($e.Count) errors)"
    if ($e.Count -gt 0) { $e | ForEach-Object { Write-Host "  L$($_.Extent.StartLineNumber): $($_.Message)" } }
}
exit $(if ($allPass) { 0 } else { 1 })

```
*Generated by Claude (claude-sonnet-4-6)*
*Safe to upload to GitHub Gist - contains no secrets.*
*Do NOT include `rclone.conf` in any gist.*

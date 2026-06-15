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
# Log rotation (T033): delete audit logs older than 365 days
# Forensic logs retained 1 year (raised from 30 days 2026-06-15) to preserve
# evidence of [SHUTDOWN]/DELETED-SUSPICIOUS events across long investigations.
# ---------------------------------------------------------------------------
$script:LastLogRotation = [datetime]::MinValue

function Invoke-AuditLogRotation {
    if (([datetime]::Now - $script:LastLogRotation).TotalHours -lt 24) { return }
    $script:LastLogRotation = [datetime]::Now
    $cutoff = (Get-Date).AddDays(-365)

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
                    & 'C:\Sync\Config\cloud_sync_helderTest.ps1'
                }
            } else {
                # Formatação garantida como texto
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
# Watermark for sleep (Event 42). A 60s look-back window misses sleeps because the
# event fires AS the system suspends and is far older than 60s once it resumes.
# Initialised to startup time so historical sleeps do not re-alert on every restart.
$script:LastSleepEventTime = [datetime]::Now

function Check-SystemEvents {
    if (([datetime]::Now - $script:LastSystemCheck).TotalSeconds -lt 60) { return }
    $script:LastSystemCheck = [datetime]::Now

    # --- Event 42 (sleep) via persistent watermark so it fires after resume ---
    # Power/sleep buttons are configured to "Do nothing" (setup_update.ps1), so a
    # "Button or Lid" sleep is anomalous and a known power-sabotage vector
    # (see THREAT_MODEL.md) - escalate to [ALERT] and best-effort send_alert.
    try {
        $latest42 = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 42
        } -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($latest42 -and $latest42.TimeCreated -gt $script:LastSleepEventTime) {
            $script:LastSleepEventTime = $latest42.TimeCreated
            $reason = 'unknown'
            # Match English "Reason:" and Portuguese "Motivo da Suspensao:"
            if ($latest42.Message -match '(?:Reason|Motivo)[^:]*:\s+(.+)') { $reason = $Matches[1].Trim() }
            if ($reason -match 'Button|Lid|Bot') {
                Write-SecurityAudit "[ALERT] [BUTTON-SLEEP] Power button/lid sleep at $($latest42.TimeCreated) reason=$reason - buttons set to Do nothing, possible physical tampering"
                try {
                    & 'C:\Sync\Config\send_alert.ps1' `
                        -Subject 'Button/Lid sleep detected' `
                        -Body "Power button or lid initiated a sleep at $($latest42.TimeCreated). The power and sleep buttons are configured to Do nothing, so this indicates a physical power-button press - possible physical access to the machine. Reason text: $reason" `
                        -B2Key "button_sleep_$($latest42.TimeCreated.ToString('yyyyMMdd_HHmmss')).txt"
                } catch {}
            } else {
                Write-SecurityAudit "[SLEEP] System entered sleep/hibernate at $($latest42.TimeCreated) reason=$reason"
            }
        }
    } catch {}

    # --- Event 1074 (shutdown/restart) within last 60s window ---
    $since = (Get-Date).AddSeconds(-60)
    try {
        $evts = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 1074
            StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($evt in $evts) {
            $who = if ($evt.Message -match 'User:\s+(\S+)') { $Matches[1] } else { 'unknown' }
            $type = if ($evt.Message -match 'shutdown type:\s+(\S+)') { $Matches[1] } else { '?' }
            Write-SecurityAudit "[SHUTDOWN] Initiated by $who - type=$type"
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
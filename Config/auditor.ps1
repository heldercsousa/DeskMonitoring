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
# Process-correlation helpers (T075)
# Registry writes to power keys (USB Selective Suspend, sleep timeouts) surface
# as svchost.exe; the true caller is only visible by correlating process-creation
# telemetry in the same time window. Prefer Sysmon Event 1 (T076), fall back to
# Security 4688 (enabled T014/setup Step 16a2).
# ---------------------------------------------------------------------------
function Get-EvtData($evt, [string]$name) {
    # Locale-independent read of an EventData <Data Name='X'> node via ToXml().
    try {
        $x = [xml]$evt.ToXml()
        $node = $x.Event.EventData.Data | Where-Object { $_.Name -eq $name }
        if ($node) { return [string]($node.'#text') }
    } catch {}
    return ''
}

function Get-CorrelatedProcesses([datetime]$eventTime) {
    # Returns process-creation candidates within eventTime +/- 5s.
    # Prefers Sysmon Operational Event 1; falls back to Security 4688.
    $start   = $eventTime.AddSeconds(-5)
    $end     = $eventTime.AddSeconds(5)
    $results = @()

    try {
        $sm = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Sysmon/Operational'; Id = 1; StartTime = $start; EndTime = $end
        } -ErrorAction SilentlyContinue
        foreach ($e in $sm) {
            $results += [pscustomobject]@{
                Source            = 'Sysmon-1'
                Image             = (Get-EvtData $e 'Image')
                CommandLine       = (Get-EvtData $e 'CommandLine')
                ParentImage       = (Get-EvtData $e 'ParentImage')
                ParentCommandLine = (Get-EvtData $e 'ParentCommandLine')
                User              = (Get-EvtData $e 'User')
                ProcessId         = (Get-EvtData $e 'ProcessId')
                TimeCreated       = $e.TimeCreated
            }
        }
    } catch {}

    if (-not $results -or @($results).Count -eq 0) {
        try {
            $sec = Get-WinEvent -FilterHashtable @{
                LogName = 'Security'; Id = 4688; StartTime = $start; EndTime = $end
            } -ErrorAction SilentlyContinue
            foreach ($e in $sec) {
                $results += [pscustomobject]@{
                    Source            = 'Sec-4688'
                    Image             = (Get-EvtData $e 'NewProcessName')
                    CommandLine       = (Get-EvtData $e 'CommandLine')
                    ParentImage       = (Get-EvtData $e 'ParentProcessName')
                    ParentCommandLine = ''
                    User              = (Get-EvtData $e 'SubjectUserName')
                    ProcessId         = (Get-EvtData $e 'NewProcessId')
                    TimeCreated       = $e.TimeCreated
                }
            }
        } catch {}
    }
    return $results
}

function Test-WhitelistedProc($p) {
    # Known-good: our own ecosystem scripts (powershell/pwsh/powercfg launched by a
    # C:\Sync\Config script). The hourly FolderSync-PowerCheck heal legitimately
    # rewrites these power keys; whitelist via the C:\Sync\Config marker on either the
    # process or its parent command line so the heal does not self-trigger [REG-TAMPER].
    $marker = 'C:\Sync\Config'
    if (($p.CommandLine       -and $p.CommandLine       -like "*$marker*") -or
        ($p.ParentCommandLine -and $p.ParentCommandLine -like "*$marker*")) { return $true }
    return $false
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
# Edge-triggered state for the unattended sleep timeout watcher: alert once when it
# leaves the compliant value (0=Never), log [RECOVERED] once when it returns, so a
# persistent non-compliant value does not re-alert every 60s before the hourly heal.
$script:UnattendNonCompliant = $false

# Watermark for the scheduled-task tamper watcher: only alert on task change events
# (4699 delete / 4701 disable / 4702 update) that occur after the auditor starts, so
# historical events do not re-fire on every boot.
$script:LastTaskEventTime = [datetime]::Now

# Watermark for the firewall-tamper watcher (T078): only alert on firewall change
# events (4946 add / 4947 modify / 4948 delete / 4950 setting / 5025 service stop)
# that occur after the auditor starts, so historical events do not re-fire on boot.
$script:LastFwEventTime = [datetime]::Now

# Watermark for the registry-tamper watcher (T075): only alert on registry write
# events (4657 value-modified / 4663 access) on guarded keys that occur after the
# auditor starts, so historical events do not re-fire on boot.
$script:LastRegEventTime = [datetime]::Now

# Guarded registry keys for T075. A write here is correlated against process-creation
# telemetry (Sysmon 1 / 4688) to unmask the true caller behind the svchost.exe proxy.
# Power subgroups: USB Selective Suspend + Sleep (unattended sleep timeout) - the known
# re-enable-between-corrections vector (T070); plus autostart Run keys.
$script:GuardedRegPatterns = @(
    '2a737441-1930-4402-8d77-b2bebba308a3',   # USB Selective Suspend power subgroup
    '238c9fa8-0aad-41ed-83f4-97be242c8f20',   # Sleep subgroup (unattended sleep timeout parent)
    '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0',   # System unattended sleep timeout setting
    '\Power\User\PowerSchemes',                # any active power-scheme value (catch-all; no trailing \ in ObjectName)
    '\CurrentVersion\Run'                       # HKCU/HKLM autostart Run keys
)

# T091 tuning: reporters that legitimately write HKCU Run key entries (e.g. Chrome updating
# its own autostart entry). Matched by suffix against the ProcessName field of Security 4663.
# Only suppresses Run key writes - power subgroup writes are never suppressed regardless of reporter.
$script:RunKeyReporterWhitelist = @(
    '\chrome.exe',
    '\GoogleUpdater.exe'
)

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

    # --- System unattended sleep timeout tampering (real-time, 60s) ---
    # This hidden setting (default 120s) sleeps a LOCKED session even with Sleep=Never,
    # stopping recording (confirmed 2026-06-17). It must stay 0=Never. Read it live from
    # the active scheme; alert the moment it leaves 0 (or its key is removed => default
    # 120s applies). The hourly FolderSync-PowerCheck heal reverts it; this gives instant
    # visibility instead of waiting up to an hour. Edge-triggered to avoid 60s spam.
    try {
        $act = (powercfg /getactivescheme) -join ' '
        if ($act -match '([0-9a-fA-F-]{36})') {
            $guid = $Matches[1]
            $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$guid\238c9fa8-0aad-41ed-83f4-97be242c8f20\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0"
            $ac = $null; $dc = $null
            if (Test-Path $p) {
                $v = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
                $ac = $v.ACSettingIndex; $dc = $v.DCSettingIndex
            }
            $bad = ($ac -ne 0) -or ($dc -ne 0)   # $null (key absent) => default 120s => non-compliant
            if ($bad -and -not $script:UnattendNonCompliant) {
                $script:UnattendNonCompliant = $true
                $shownAc = if ($ac -eq $null) { 'absent(default 120s)' } else { $ac }
                $shownDc = if ($dc -eq $null) { 'absent(default 120s)' } else { $dc }
                Write-SecurityAudit "[ALERT] [UNATTEND-SLEEP] System unattended sleep timeout changed to AC=$shownAc DC=$shownDc (expected 0=Never) - locked-session sleep risk, hourly auto-heal will revert"
                try {
                    & 'C:\Sync\Config\send_alert.ps1' `
                        -Subject 'Unattended sleep timeout changed' `
                        -Body "The System unattended sleep timeout changed to AC=$shownAc DC=$shownDc (expected 0=Never). This setting sleeps a locked session even with Sleep=Never, which stops motion recording. The hourly FolderSync-PowerCheck task will revert it; investigate what changed it." `
                        -B2Key "unattend_sleep_$([datetime]::Now.ToString('yyyyMMdd_HHmmss')).txt"
                } catch {}
            } elseif (-not $bad -and $script:UnattendNonCompliant) {
                $script:UnattendNonCompliant = $false
                Write-SecurityAudit "[RECOVERED] System unattended sleep timeout back to Never (AC=0 DC=0)"
            }
        }
    } catch {}

    # --- Scheduled-task tamper (real-time, events 4699/4701/4702 on FolderSync-* tasks) ---
    # A resident process disabled FolderSync-DailyCheck + FolderSync-CloudBackup in-process
    # on 2026-06-18 with no spawned schtasks/powershell (confirmed tampering, see
    # THREAT_MODEL.md). Task-change auditing is now on, so a disable/delete/update of a
    # defensive task emits 4701/4699/4702 with the Subject account. Alert the instant it
    # happens and capture that account; config_guard.ps1 handles the auto-heal. Watermarked
    # so each event alerts once.
    try {
        $taskEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'; Id = 4699, 4701, 4702; StartTime = $script:LastTaskEventTime
        } -ErrorAction SilentlyContinue
        foreach ($te in ($taskEvents | Sort-Object TimeCreated)) {
            if ($te.TimeCreated -le $script:LastTaskEventTime) { continue }
            $msg = $te.Message
            # Task path: match \FolderSync-XXX in either language
            if ($msg -notmatch '\\?(FolderSync-\S+)') { continue }
            $taskName = ($Matches[1]).TrimEnd('.', '"', "'")
            # Subject account that made the change (PT "Nome da Conta:" / EN "Account Name:")
            $acct = 'unknown'
            if ($msg -match '(?:Account Name|Nome da Conta)[^:]*:\s+(\S+)') { $acct = $Matches[1] }
            $verb = switch ($te.Id) { 4699 {'DELETED'} 4701 {'DISABLED'} 4702 {'UPDATED'} default {"id$($te.Id)"} }
            Write-SecurityAudit "[ALERT] [TASK-TAMPER] Defensive task $taskName was $verb at $($te.TimeCreated) by account=$acct (event $($te.Id)) - config_guard auto-heal will re-enable if disabled"
            try {
                & 'C:\Sync\Config\send_alert.ps1' `
                    -Subject "Defensive task ${verb}: $taskName" `
                    -Body "Scheduled task $taskName was $verb at $($te.TimeCreated) by account=$acct (Security event $($te.Id)). This is one of the FolderSync defensive tasks. The 2026-06-18 incident disabled two of these in-process with no spawned process - this alert captures the Subject account responsible. config_guard.ps1 re-enables disabled tasks automatically; investigate the account/process." `
                    -B2Key "task_tamper_$($te.TimeCreated.ToString('yyyyMMdd_HHmmss'))_$taskName.txt"
            } catch {}
        }
        if ($taskEvents) {
            $newest = ($taskEvents | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
            if ($newest -gt $script:LastTaskEventTime) { $script:LastTaskEventTime = $newest }
        }
    } catch {}

    # --- Firewall tamper (T078, real-time, events 4946/4947/4948/4950/5025) ---
    # Event-based complement to T010 (which only scans for known B2 BLOCK rules after
    # the fact). Catches a live add/modify/delete of any firewall rule, a firewall
    # setting change, and a firewall service stop, naming the Subject account. Requires
    # the "MPSSVC Rule-Level Policy Change" audit subcategory (setup_update.ps1 Step
    # 16a4). Whitelisted: when our own firewall scripts (setup_update.ps1 /
    # fix_firewall_b2.ps1) run they touch C:\Sync\Config\.fw_expected; a firewall event
    # within 300s of that touch is logged as [FW-CHANGE] INFO instead of an alert, to
    # avoid self-inflicted [FIREWALL-TAMPER] noise during remediation. Watermarked so
    # each event alerts once.
    try {
        $fwEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'; Id = 4946, 4947, 4948, 4950, 5025; StartTime = $script:LastFwEventTime
        } -ErrorAction SilentlyContinue
        # Is one of our own firewall scripts active right now? (sentinel fresh < 300s)
        $expected = $false
        $sentinel = 'C:\Sync\Config\.fw_expected'
        if (Test-Path $sentinel) {
            try { if (((Get-Date) - (Get-Item $sentinel).LastWriteTime).TotalSeconds -lt 300) { $expected = $true } } catch {}
        }
        foreach ($fe in ($fwEvents | Sort-Object TimeCreated)) {
            if ($fe.TimeCreated -le $script:LastFwEventTime) { continue }
            $msg = $fe.Message
            # Subject account that made the change (EN "Account Name:" / PT "Nome da Conta:")
            # 4946/4947/4948 use "Modifying User"/"Modifying Application"; the Subject block
            # carries the Account Name regardless, so match that.
            $acct = 'unknown'
            if ($msg -match '(?:Account Name|Nome da Conta)[^:]*:\s+(\S+)') { $acct = $Matches[1] }
            # Rule name / setting, where present
            $ruleName = 'n/a'
            if ($msg -match '(?:Rule Name|Nome da Regra)[^:]*:\s+(.+)') { $ruleName = ($Matches[1].Trim()) }
            elseif ($msg -match '(?:Rule ID|ID da Regra)[^:]*:\s+(.+)') { $ruleName = ($Matches[1].Trim()) }
            $verb = switch ($fe.Id) {
                4946 {'RULE-ADDED'} 4947 {'RULE-MODIFIED'} 4948 {'RULE-DELETED'}
                4950 {'SETTING-CHANGED'} 5025 {'SERVICE-STOPPED'} default {"id$($fe.Id)"}
            }
            if ($expected) {
                Write-SecurityAudit "[FW-CHANGE] $verb rule='$ruleName' at $($fe.TimeCreated) by account=$acct (event $($fe.Id)) - expected (own firewall script active), no alert"
                continue
            }
            Write-SecurityAudit "[ALERT] [FIREWALL-TAMPER] $verb rule='$ruleName' at $($fe.TimeCreated) by account=$acct (event $($fe.Id)) - no own firewall script active, possible tampering"
            try {
                & 'C:\Sync\Config\send_alert.ps1' `
                    -Subject "Firewall tamper ${verb}: $ruleName" `
                    -Body "A Windows Firewall change ($verb) occurred at $($fe.TimeCreated) by account=$acct (Security event $($fe.Id)), rule='$ruleName'. No FolderSync firewall script was active (sentinel .fw_expected not fresh), so this is unexpected. The attacker has previously added outbound BLOCK rules for Backblaze B2 IPs (104.153.233.180 / 149.137.142.15) to silently kill cloud sync - cross-reference with SYNC-FAIL / connectex errors in the cloud_sync log. Event 5025 (firewall service stopped) is especially high severity." `
                    -B2Key "firewall_tamper_$($fe.TimeCreated.ToString('yyyyMMdd_HHmmss'))_$($fe.Id).txt"
            } catch {}
        }
        if ($fwEvents) {
            $newest = ($fwEvents | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
            if ($newest -gt $script:LastFwEventTime) { $script:LastFwEventTime = $newest }
        }
    } catch {}

    # --- Registry tamper on guarded keys (T075, events 4657 value-modified / 4663 access) ---
    # Power-service registry writes (USB Selective Suspend, sleep timeouts) surface as
    # svchost.exe; the true caller is only visible by correlating process-creation
    # telemetry in the same +/-5s window. Requires the Registry audit subcategory plus a
    # SACL on the guarded keys (setup_update.ps1 Step 16a5 / enable_registry_auditing.ps1)
    # AND, ideally, Sysmon Event 1 (T076) for full command line + parent; falls back to
    # Security 4688. Whitelisted: our own ecosystem scripts (e.g. the hourly power heal).
    # Watermarked so each event alerts once.
    try {
        $regEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'; Id = 4657, 4663; StartTime = $script:LastRegEventTime
        } -ErrorAction SilentlyContinue
        foreach ($re in ($regEvents | Sort-Object TimeCreated)) {
            if ($re.TimeCreated -le $script:LastRegEventTime) { continue }
            $objName = Get-EvtData $re 'ObjectName'
            if (-not $objName) { continue }
            # Only registry objects (4663 also fires for files); guarded keys only
            $isGuarded = $false
            foreach ($pat in $script:GuardedRegPatterns) {
                if ($objName -like "*$pat*") { $isGuarded = $true; break }
            }
            if (-not $isGuarded) { continue }

            $regProc    = Get-EvtData $re 'ProcessName'
            if (-not $regProc) { $regProc = 'unknown' }
            # T091: suppress Run-key writes from known-benign reporters to reduce noise
            if ($objName -like '*\CurrentVersion\Run*') {
                $benignReporter = $false
                foreach ($w in $script:RunKeyReporterWhitelist) {
                    if ($regProc -like "*$w") { $benignReporter = $true; break }
                }
                if ($benignReporter) {
                    Write-SecurityAudit "[REG-INFO] Run key written by whitelisted reporter '$regProc' at $($re.TimeCreated) - no alert"
                    continue
                }
            }
            $candidates = Get-CorrelatedProcesses $re.TimeCreated
            $suspect    = @($candidates | Where-Object { -not (Test-WhitelistedProc $_) })

            if ($suspect.Count -eq 0) {
                # Either no correlation telemetry yet (Sysmon/T076 not live) or only our
                # own scripts ran in-window (benign power heal). Log INFO, do not alert.
                $note = if (@($candidates).Count -eq 0) { 'no process-creation telemetry in window (Sysmon/4688)' } else { 'correlated only with own ecosystem scripts' }
                Write-SecurityAudit "[REG-WRITE] Guarded key '$objName' written by $regProc at $($re.TimeCreated) (event $($re.Id)) - $note, no alert"
                continue
            }

            $names = ($suspect | ForEach-Object {
                "$($_.Image) (pid $($_.ProcessId), parent $($_.ParentImage), via $($_.Source))"
            }) -join '; '
            Write-SecurityAudit "[ALERT] [REG-TAMPER] Guarded key '$objName' written by $regProc at $($re.TimeCreated) (event $($re.Id)); correlated process(es): $names"

            # Evidence file (forensic record of the unmasked caller)
            try {
                $evStamp = $re.TimeCreated.ToString('yyyyMMdd_HHmmss')
                $evPath  = "C:\Sync\Evidence\$($re.TimeCreated.ToString('yyyy-MM-dd'))_reg-tamper_$evStamp.md"
                $ev = @()
                $ev += "# REG-TAMPER - guarded registry key written"
                $ev += ""
                $ev += "- Detected      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $ev += "- Event time    : $($re.TimeCreated)"
                $ev += "- Security event: $($re.Id)"
                $ev += "- Guarded key   : $objName"
                $ev += "- Reporting proc: $regProc (svchost proxy expected for power writes)"
                $ev += ""
                $ev += "## Correlated process-creation candidates (+/-5s, non-whitelisted)"
                foreach ($s in $suspect) {
                    $ev += "- [$($s.Source)] Image=$($s.Image) PID=$($s.ProcessId) User=$($s.User)"
                    $ev += "    CommandLine      : $($s.CommandLine)"
                    $ev += "    ParentImage      : $($s.ParentImage)"
                    $ev += "    ParentCommandLine: $($s.ParentCommandLine)"
                }
                $ev | Set-Content -LiteralPath $evPath -Encoding UTF8
                Write-SecurityAudit "[FORENSIC] REG-TAMPER evidence written: $evPath"
            } catch {}

            try {
                & 'C:\Sync\Config\send_alert.ps1' `
                    -Subject "Registry tamper on guarded key" `
                    -Body "A write to a guarded registry key was detected at $($re.TimeCreated) (Security event $($re.Id)). Key: $objName. The write was reported by $regProc (svchost.exe is the expected proxy for Power-service writes such as USB Selective Suspend / sleep timeouts). Correlating process-creation telemetry in the same +/-5s window unmasked the following non-whitelisted process(es): $names. This is the T070 vector (a resident process re-enabling USB Selective Suspend / sleep between corrections). Investigate the named process and its parent." `
                    -B2Key "reg_tamper_$($re.TimeCreated.ToString('yyyyMMdd_HHmmss'))_$($re.Id).txt"
            } catch {}
        }
        if ($regEvents) {
            $newest = ($regEvents | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
            if ($newest -gt $script:LastRegEventTime) { $script:LastRegEventTime = $newest }
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
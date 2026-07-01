#Requires -RunAsAdministrator
# start_ecosystem.ps1
# Starts all FolderSync + Camera ecosystem components.
# Writes .ecosystem_state = "running" on completion.
# Run as Administrator.

$ErrorActionPreference = 'SilentlyContinue'
$LogFile   = "C:\Sync\Logs\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$StateFile = "C:\Sync\Config\.ecosystem_state"

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Start" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Log "ECOSYSTEM-START  Starting all ecosystem components"

# --- FolderSyncWatchdog NSSM service ---
Write-Step "FolderSyncWatchdog service"
Start-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
$s = Get-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
if ($s -and $s.Status -eq 'Running') {
    Write-OK "FolderSyncWatchdog running"
    Write-Log "ECOSYSTEM-START  FolderSyncWatchdog running"
} else {
    Write-Warn "FolderSyncWatchdog: $($s.Status)"
    Write-Log "ECOSYSTEM-START  WARN FolderSyncWatchdog $($s.Status)"
}

# --- FolderSyncAuditor NSSM service ---
Write-Step "FolderSyncAuditor service"
Start-Service FolderSyncAuditor -ErrorAction SilentlyContinue
$s = Get-Service FolderSyncAuditor -ErrorAction SilentlyContinue
if ($s -and $s.Status -eq 'Running') {
    Write-OK "FolderSyncAuditor running"
    Write-Log "ECOSYSTEM-START  FolderSyncAuditor running"
} else {
    Write-Warn "FolderSyncAuditor: $($s.Status)"
    Write-Log "ECOSYSTEM-START  WARN FolderSyncAuditor $($s.Status)"
}

# --- Enable scheduled tasks ---
Write-Step "Scheduled tasks"
foreach ($task in @('FolderSync-CloudBackup', 'FolderSync-Watchdog', 'FolderSync-DailyCheck')) {
    $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    if ($t) {
        if ($t.State -eq 'Disabled') {
            Enable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
            Write-OK "$task enabled"
        } else {
            Write-OK "$task already enabled ($($t.State))"
        }
        Write-Log "ECOSYSTEM-START  Task $task state: $($t.State)"
    } else {
        Write-Warn "$task not found - re-run setup_update.ps1"
        Write-Log "ECOSYSTEM-START  WARN Task $task not found"
    }
}

# --- FolderSync-PowerCheck (must always be live + actually firing) ---
# Unlike the tasks above, this one is NOT re-registered by start; and a broken
# hourly trigger leaves State=Ready while NextRunTime is blank (the task never
# fires). So: re-register from canonical XML whenever it is absent OR its
# repeating TimeTrigger is not scheduling a next run. Keeps sleep auto-heal alive
# whenever the ecosystem is running, without waiting for a full setup_update run.
Write-Step "FolderSync-PowerCheck (sleep auto-heal)"
$pcXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <TimeTrigger>
      <Repetition><Interval>PT1H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\check_power_motion.ps1</Arguments>
    </Exec>
  </Actions>
</Task>
'@
$pcTask = Get-ScheduledTask -TaskName "FolderSync-PowerCheck" -ErrorAction SilentlyContinue
$pcNext = if ($pcTask) { (Get-ScheduledTaskInfo -TaskName "FolderSync-PowerCheck" -ErrorAction SilentlyContinue).NextRunTime } else { $null }
if (-not $pcTask -or $pcTask.State -eq 'Disabled' -or -not $pcNext) {
    $reason = if (-not $pcTask) { 'absent' } elseif ($pcTask.State -eq 'Disabled') { 'disabled' } else { 'no NextRunTime (dead trigger)' }
    Unregister-ScheduledTask -TaskName "FolderSync-PowerCheck" -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName "FolderSync-PowerCheck" -Xml $pcXml -Force | Out-Null
    Start-ScheduledTask -TaskName "FolderSync-PowerCheck" -ErrorAction SilentlyContinue
    Write-OK "FolderSync-PowerCheck re-registered ($reason) and kicked once"
    Write-Log "ECOSYSTEM-START  FolderSync-PowerCheck re-registered ($reason)"
} else {
    Write-OK "FolderSync-PowerCheck healthy (next run $pcNext)"
    Write-Log "ECOSYSTEM-START  FolderSync-PowerCheck healthy, next run $pcNext"
}

# --- RealTimeSync ---
Write-Step "RealTimeSync"
$rts = Get-Process RealTimeSync -ErrorAction SilentlyContinue
if (-not $rts) {
    Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
        -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $rts = Get-Process RealTimeSync -ErrorAction SilentlyContinue
    if ($rts) {
        Write-OK "RealTimeSync started"
        Write-Log "ECOSYSTEM-START  RealTimeSync started"
    } else {
        Write-Warn "RealTimeSync did not start - check FreeFileSync installation"
        Write-Log "ECOSYSTEM-START  WARN RealTimeSync not started"
    }
} else {
    Write-OK "RealTimeSync already running (PID $($rts.Id))"
    Write-Log "ECOSYSTEM-START  RealTimeSync already running"
}

# --- Yawcam ---
Write-Step "Yawcam (CAM-1)"
$yawcam = Get-Process yawcam -ErrorAction SilentlyContinue
if (-not $yawcam) {
    $yawcam = Get-CimInstance Win32_Process -Filter "Name = 'javaw.exe'" -ErrorAction SilentlyContinue |
              Where-Object { $_.CommandLine -like '*yawcam*' }
}
if (-not $yawcam) {
    Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe" `
        -WorkingDirectory "C:\Program Files (x86)\Yawcam" -ErrorAction SilentlyContinue
    # Yawcam runs as javaw - JVM startup needs up to 8s; check both process names
    Start-Sleep -Seconds 8
    $yawcam = Get-Process yawcam -ErrorAction SilentlyContinue
    if (-not $yawcam) {
        $yawcam = Get-CimInstance Win32_Process -Filter "Name = 'javaw.exe'" -ErrorAction SilentlyContinue |
                  Where-Object { $_.CommandLine -like '*yawcam*' }
    }
    if ($yawcam) {
        Write-OK "Yawcam started (PID $(if ($yawcam.Id) { $yawcam.Id } else { $yawcam.ProcessId }))"
        Write-Log "ECOSYSTEM-START  Yawcam started"
    } else {
        Write-Warn "Yawcam did not start - check C:\Program Files (x86)\Yawcam\Yawcam.exe"
        Write-Log "ECOSYSTEM-START  WARN Yawcam did not start"
    }
} else {
    Write-OK "Yawcam already running (PID $(if ($yawcam.Id) { $yawcam.Id } else { $yawcam.ProcessId }))"
    Write-Log "ECOSYSTEM-START  Yawcam already running"
}

# --- CAM-2 relay ---
Write-Step "CAM-2 relay (cam2_relay.ps1 via VLC)"
$vlc = Get-Process vlc -ErrorAction SilentlyContinue
if (-not $vlc) {
    Start-Process powershell.exe `
        -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\cam2_relay.ps1"' `
        -WindowStyle Hidden -ErrorAction SilentlyContinue
    # cam2_relay.ps1 spawns VLC which needs a few seconds to connect to RTSP stream
    Start-Sleep -Seconds 5
    $vlc = Get-Process vlc -ErrorAction SilentlyContinue
    if ($vlc) {
        Write-OK "CAM-2 relay started (VLC PID $($vlc.Id))"
        Write-Log "ECOSYSTEM-START  CAM-2 relay started"
    } else {
        Write-Warn "CAM-2 relay (VLC) did not start - check cam2_relay.ps1"
        Write-Log "ECOSYSTEM-START  WARN CAM-2 relay did not start"
    }
} else {
    Write-OK "CAM-2 relay (VLC) already running (PID $($vlc.Id))"
    Write-Log "ECOSYSTEM-START  CAM-2 relay already running"
}

# --- YawcamMonitor (keep-awake guard + restart-on-freeze watchdog) ---
Write-Step "YawcamMonitor"
$monitor = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*yawcam_monitor*' }
if (-not $monitor) {
    Start-Process powershell.exe `
        -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\yawcam_monitor_v4.ps1"' `
        -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $monitor = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like '*yawcam_monitor*' }
    if ($monitor) {
        Write-OK "YawcamMonitor started"
        Write-Log "ECOSYSTEM-START  YawcamMonitor started"
    } else {
        Write-Warn "YawcamMonitor did not start - check yawcam_monitor_v4.ps1"
        Write-Log "ECOSYSTEM-START  WARN YawcamMonitor did not start"
    }
} else {
    Write-OK "YawcamMonitor already running (PID $($monitor.ProcessId))"
    Write-Log "ECOSYSTEM-START  YawcamMonitor already running"
}

# --- Remove .camera_paused flag if present ---
$pausedFlag = "C:\Sync\Config\.camera_paused"
if (Test-Path $pausedFlag) {
    Remove-Item -LiteralPath $pausedFlag -Force -ErrorAction SilentlyContinue
    Write-OK ".camera_paused flag cleared"
    Write-Log "ECOSYSTEM-START  .camera_paused flag cleared"
}

# --- Write state flag ---
'running' | Set-Content -LiteralPath $StateFile -Encoding UTF8
Write-Log "ECOSYSTEM-START  State set to running"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Ecosystem started  --  state: running" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

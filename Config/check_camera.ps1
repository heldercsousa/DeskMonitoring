# check_camera.ps1
# Camera / Motion Detection Health Check
# Modeled after check_status.ps1 — run interactively to diagnose camera state
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

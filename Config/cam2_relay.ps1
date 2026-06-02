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

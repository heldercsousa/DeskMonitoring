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
$CheckSecs = 30   # health check interval

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

# ---------------------------------------------------------------------------
# Read credentials from cam2.conf
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Relay loop — start VLC, monitor, restart on death
# ---------------------------------------------------------------------------
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

    # Roll log file at midnight
    $LogFile = "C:\Sync\Logs\cam2_relay_$(Get-Date -Format 'yyyy-MM-dd').log"

    if ($vlcProc -eq $null -or $vlcProc.HasExited) {
        Write-Log "WARN   VLC relay process died — restarting"
        $vlcProc = Start-VlcRelay
    }
}

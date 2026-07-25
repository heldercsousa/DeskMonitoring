# cam2_relay.ps1
# CAM-2 RTSP -> MJPEG HTTP relay for Yawcam
# Reads credentials from cam2_creds.dpapi (DPAPI-encrypted); falls back to cam2.conf.
# Registered as startup entry: HKCU:\...\Run\YawcamCam2Relay
# Logs to C:\Sync\Logs\services\cam2_relay.log (single rolling file, 7-day retention)

Add-Type -AssemblyName System.Security

$ConfFile       = "C:\Sync\Config\cam2.conf"
$DpapiFile      = "C:\Sync\Config\cam2_creds.dpapi"
$VlcExe         = "C:\Program Files\VideoLAN\VLC\vlc.exe"
$RelayPort      = 8161
$RelayHost      = "127.0.0.1"
$LogFile        = "C:\Sync\Logs\services\cam2_relay.log"
$CheckSecs      = 30   # health check interval
$MaxRestarts    = 5    # max restarts per hour before giving up
$RestartWindow  = 3600 # seconds (1 hour)
$MaxStalls      = 3    # consecutive frameless checks before forcing a restart

$restartTimes = [System.Collections.Generic.List[datetime]]::new()
$stallCount   = 0

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
    $job = Start-Job {
        param($h,$p)
        $r = Test-NetConnection -ComputerName $h -Port $p -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $r.TcpTestSucceeded
    } -ArgumentList $RelayHost, $RelayPort
    $done = Wait-Job $job -Timeout 3
    if ($done) { $result = Receive-Job $job } else { $result = $false }
    Remove-Job $job -Force
    return [bool]$result
}

# ---------------------------------------------------------------------------
# Get-RelayBytes: how many bytes the MJPEG endpoint actually delivers.
# VLC is launched with --loop, so it stays alive retrying a dead RTSP source
# while port 8161 remains bound and answers HTTP 200 with zero frames.
# HasExited alone therefore cannot detect a dead camera (2026-07-24 incident:
# CAM-2 silently captured nothing while this relay reported healthy).
# ---------------------------------------------------------------------------
function Get-RelayBytes {
    param([int]$Seconds = 5)
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://${RelayHost}:${RelayPort}/")
        $req.Timeout          = 5000
        $req.ReadWriteTimeout = $Seconds * 1000
        $stream = $req.GetResponse().GetResponseStream()
        $buf    = New-Object byte[] 65536
        $total  = 0
        $sw     = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
            $n = $stream.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $total += $n
        }
        $stream.Close()
        return $total
    } catch {
        return 0
    }
}

# ---------------------------------------------------------------------------
# Load-Cam2Credentials: reads DPAPI blob; falls back to cam2.conf with WARN
# ---------------------------------------------------------------------------
function Load-Cam2Credentials {
    if (Test-Path $DpapiFile) {
        try {
            $base64        = [System.IO.File]::ReadAllText($DpapiFile, [System.Text.Encoding]::ASCII).Trim()
            $encBytes      = [Convert]::FromBase64String($base64)
            $plainBytes    = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $encBytes,
                $null,
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            $json          = [System.Text.Encoding]::UTF8.GetString($plainBytes)
            $creds         = $json | ConvertFrom-Json
            $script:user   = $creds.user
            $script:pass   = $creds.pass
            $script:ip     = $creds.ip
            $script:port   = $creds.port
            $script:stream = $creds.stream
            Write-Log "INFO   Credentials loaded from cam2_creds.dpapi (DPAPI)"
            return
        } catch {
            Write-Log "FAIL   cam2_creds.dpapi found but decryption failed - $_"
            exit 1
        }
    }

    # Fallback: cam2.conf (legacy plaintext - migrate with migrate_cam2_creds.ps1)
    if (Test-Path $ConfFile) {
        Write-Log "WARN   cam2_creds.dpapi not found - falling back to plaintext cam2.conf"
        Write-Log "WARN   Run migrate_cam2_creds.ps1 to encrypt credentials"
        $conf = @{}
        Get-Content $ConfFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
            $parts = $_ -split '=', 2
            $conf[$parts[0].Trim()] = $parts[1].Trim()
        }
        $script:user   = $conf['CAM2_USER']
        $script:pass   = $conf['CAM2_PASS']
        $script:ip     = $conf['CAM2_IP']
        $script:port   = $conf['CAM2_PORT']
        $script:stream = $conf['CAM2_STREAM']
        return
    }

    Write-Log "FAIL   cam2_creds.dpapi not found - run migrate_cam2_creds.ps1"
    exit 1
}

Load-Cam2Credentials

if (-not $user -or -not $pass -or -not $ip) {
    Write-Log "FAIL  credentials missing required fields (user, pass, ip)"
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
        $stallCount = 0
    }
    else {
        # VLC alive - but is it actually delivering frames?
        if ((Get-RelayBytes -Seconds 5) -gt 0) {
            if ($stallCount -gt 0) { Write-Log "INFO   Frames flowing again on port $RelayPort" }
            $stallCount = 0
        } else {
            $stallCount++
            Write-Log "WARN   No frames on port $RelayPort (stall $stallCount of $MaxStalls)"

            if ($stallCount -ge $MaxStalls) {
                Write-Log "RELAY-NOFRAMES  No frames for $MaxStalls checks - killing VLC to force restart"
                $stallCount = 0
                if ($vlcProc -and -not $vlcProc.HasExited) {
                    Stop-Process -Id $vlcProc.Id -Force -ErrorAction SilentlyContinue
                }
                $alertBody = "CAM-2 relay on $env:COMPUTERNAME is bound to port $RelayPort but delivered no frames for $MaxStalls consecutive checks.`n`nSource: rtsp://${user}:***@${ip}:${port}/${stream}`n`nLikely causes:`n- Camera offline or moved to a different DHCP address`n- RTSP Camera Account credentials no longer valid`n- Camera factory-reset`n`nVLC has been killed to force a relay restart."
                & pwsh.exe -NonInteractive -ExecutionPolicy Bypass -File 'C:\Sync\Config\send_alert.ps1' `
                    -Subject "CAM-2 RELAY DELIVERING NO FRAMES on $env:COMPUTERNAME" `
                    -Body $alertBody `
                    -B2Key "cam2_noframes_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
            }
        }
    }
}

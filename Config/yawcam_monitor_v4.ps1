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

# ----------------------------------------------------------------------------
# Keep-awake guard: tell Windows to refuse idle/away sleep while monitoring.
# Defense-in-depth against power-based sabotage (see THREAT_MODEL.md). NOTE: this
# blocks idle/unattended/away sleep only - it cannot block a physical power-button
# press (that is handled by setting buttons to Do nothing in setup_update.ps1).
# ES_CONTINUOUS=0x80000000  ES_SYSTEM_REQUIRED=0x00000001
# ----------------------------------------------------------------------------
$script:ES_CONTINUOUS      = [uint32]'0x80000000'
$script:ES_SYSTEM_REQUIRED = [uint32]'0x00000001'
Add-Type -Namespace PInvoke -Name Power -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@ -ErrorAction SilentlyContinue

function Assert-StayAwake {
    try { [void][PInvoke.Power]::SetThreadExecutionState($script:ES_CONTINUOUS -bor $script:ES_SYSTEM_REQUIRED) } catch {}
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
Assert-StayAwake
Write-Log "KEEP-AWAKE  ES_CONTINUOUS|ES_SYSTEM_REQUIRED asserted - system will refuse idle/away sleep"

# Yawcam runs as javaw.exe; MainWindowTitle is empty when tray-minimized, so
# detection MUST match on CommandLine via CIM (T093/T094 - same fix as c457e4d).
function Get-YawcamProcesses {
    $procs = @()
    $procs += @(Get-Process -Name "yawcam" -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Id })
    $procs += @(Get-CimInstance Win32_Process -Filter "Name = 'javaw.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -like "*yawcam*" } |
                ForEach-Object { $_.ProcessId })
    return @($procs | Where-Object { $_ } | Select-Object -Unique)
}

function Test-YawcamRunning {
    return ((Get-YawcamProcesses).Count -gt 0)
}

function Restart-YawcamSafely {
    Write-Host ""
    Write-Host ">>> REINICIANDO YAWCAM..." -ForegroundColor Cyan
    Write-Log "RESTART  beginning Yawcam restart sequence"

    Write-Host "   [1/5] Fechando Yawcam..." -ForegroundColor Gray
    # Kill ALL Yawcam instances (incl. zombies) by CIM CommandLine match (T094)
    $pids = Get-YawcamProcesses
    if ($pids.Count -gt 0) {
        Write-Log "RESTART-KILL  pids=$($pids -join ',')"
        $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
    } else {
        Write-Log "RESTART-KILL  no Yawcam process found to kill"
    }
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
    $newPids = Get-YawcamProcesses
    if ($newPids.Count -gt 0) {
        Write-Host "   [OK] Yawcam reiniciado!" -ForegroundColor Green
        Write-Log "RESTART-OK  Yawcam process confirmed after restart  pids=$($newPids -join ',')"
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

    # Re-assert keep-awake every loop (cheap; survives any state reset)
    Assert-StayAwake

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

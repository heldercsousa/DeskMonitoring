# ========================================
# MONITOR YAWCAM - BASEADO EM GRAVACAO
# ========================================
# Relocated to C:\Sync\Config\ (was: C:\Program Files (x86)\Yawcam\)
# Checks C:\TEMP\motion_videos for recent .avi files.
# NOTE: C:\TEMP\motion_videos should be a symlink to C:\Users\helde\Repos\Bois
#       so the monitor sees actual recordings. Create with:
#       cmd /c mklink /D C:\TEMP\motion_videos C:\Users\helde\Repos\Bois

$YawcamPath      = "C:\Sync\Config\start_yawcam.bat"
$VideoPath       = "C:\TEMP\motion_videos"
$CheckInterval   = 60
$MaxMinutesWithoutVideo = 15
$LastRestartTime = $null
$RestartCooldown = 600

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
    } else {
        Write-Host "   [AVISO] Processo nao detectado (pode ser normal)" -ForegroundColor Yellow
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
        }
        elseif ($MinutesAgo -le $MaxMinutesWithoutVideo) {
            Write-Host "[$Timestamp] [INFO] Ultimo video: $MinutesAgo min atras" -ForegroundColor Cyan
        }
        else {
            Write-Host "[$Timestamp] [AVISO] SEM novos videos ha $MinutesAgo minutos!" -ForegroundColor Yellow

            if ($LastRestartTime -eq $null -or ((Get-Date) - $LastRestartTime).TotalSeconds -gt $RestartCooldown) {
                Write-Host "[$Timestamp] [ACAO] Yawcam provavelmente congelado - reiniciando..." -ForegroundColor Magenta
                Restart-YawcamSafely
            } else {
                $WaitTime = [math]::Round(($RestartCooldown - ((Get-Date) - $LastRestartTime).TotalSeconds) / 60, 1)
                Write-Host "[$Timestamp] [WAIT] Cooldown ativo - $WaitTime min restantes" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[$Timestamp] [AVISO] Nenhum video em $VideoPath" -ForegroundColor Yellow

        if (-not (Test-YawcamRunning)) {
            Write-Host "[$Timestamp] [ERRO] Yawcam nao esta rodando!" -ForegroundColor Red

            if ($LastRestartTime -eq $null -or ((Get-Date) - $LastRestartTime).TotalSeconds -gt $RestartCooldown) {
                Restart-YawcamSafely
            }
        }
    }

    Start-Sleep -Seconds $CheckInterval
}

#Requires -RunAsAdministrator
# pause_camera.ps1
# Stops Yawcam without affecting sync, auditor, or watchdog.
# Creates .camera_paused flag so health checks skip camera checks.
# Use when: sitting at laptop and don't want motion recording.
# Resume with: resume_camera.ps1

$ErrorActionPreference = 'SilentlyContinue'
$LogFile    = "C:\Sync\Logs\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$PausedFlag = "C:\Sync\Config\.camera_paused"

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

if (Test-Path $PausedFlag) {
    Write-Host "  WARN Camera already paused (.camera_paused flag exists)" -ForegroundColor Yellow
    exit 0
}

Get-Process yawcam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process javaw -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like '*Yawcam*' } |
    Stop-Process -Force -ErrorAction SilentlyContinue

'paused' | Set-Content -LiteralPath $PausedFlag -Encoding UTF8
Write-Log "CAMERA-PAUSE  Yawcam stopped, .camera_paused flag set"

Write-Host "  OK   Camera paused (Yawcam stopped). Run resume_camera.ps1 to restart." -ForegroundColor Green

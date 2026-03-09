#Requires -RunAsAdministrator
# resume_camera.ps1
# Starts Yawcam and removes .camera_paused flag.
# Guard: exits cleanly if flag is absent (camera not paused).

$ErrorActionPreference = 'SilentlyContinue'
$LogFile    = "C:\Sync\Logs\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$PausedFlag = "C:\Sync\Config\.camera_paused"

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

if (-not (Test-Path $PausedFlag)) {
    Write-Host "  WARN .camera_paused flag not found -- camera may already be running" -ForegroundColor Yellow
    exit 0
}

Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Remove-Item -LiteralPath $PausedFlag -Force -ErrorAction SilentlyContinue
Write-Log "CAMERA-RESUME  Yawcam started, .camera_paused flag removed"

Write-Host "  OK   Camera resumed (Yawcam started)." -ForegroundColor Green

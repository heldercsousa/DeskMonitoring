$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty $runKey -Name "Yawcam" -Value '"C:\Program Files (x86)\Yawcam\Yawcam.exe"'
Set-ItemProperty $runKey -Name "YawcamMonitor" -Value 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\start_monitor.ps1"'
Set-ItemProperty $runKey -Name "YawcamCam2Relay" -Value 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\cam2_relay.ps1"'
Write-Host "Registry entries written."
Write-Host "Yawcam:          $((Get-ItemProperty $runKey).Yawcam)"
Write-Host "YawcamMonitor:   $((Get-ItemProperty $runKey).YawcamMonitor)"
Write-Host "YawcamCam2Relay: $((Get-ItemProperty $runKey).YawcamCam2Relay)"

# Start Yawcam if not running
$yawcam = Get-Process yawcam -ErrorAction SilentlyContinue
if (-not $yawcam) {
    $yawcam = Get-Process javaw -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*Yawcam*' }
}
if (-not $yawcam) {
    Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe"
    Start-Sleep -Seconds 3
    $yawcam = Get-Process yawcam -ErrorAction SilentlyContinue
    if ($yawcam) {
        Write-Host "Yawcam started (PID $($yawcam.Id))"
    } else {
        Write-Host "WARN: Yawcam did not appear in process list after 3s"
    }
} else {
    Write-Host "Yawcam already running (PID $($yawcam.Id))"
}

# Start monitor
Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\start_monitor.ps1"'
Write-Host "YawcamMonitor launched."

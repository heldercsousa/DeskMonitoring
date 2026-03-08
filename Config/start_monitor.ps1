# start_monitor.ps1
# Boot launcher for Yawcam monitor.
# Relocated to C:\Sync\Config\ (was: C:\Program Files (x86)\Yawcam\)
# Registry Run key: YawcamMonitor -> C:\Sync\Config\start_monitor.ps1

# Aguarda 30 segundos apos boot para estabilizar
Start-Sleep -Seconds 30

# Inicia o monitor em janela minimizada
Start-Process powershell.exe `
    -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\yawcam_monitor_v4.ps1"' `
    -WindowStyle Hidden

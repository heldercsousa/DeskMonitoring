# FolderSync Watchdog
# Ensures RealTimeSync, cloud sync scheduled task, and config_guard are alive.
# Runs as "FolderSync Watchdog Service" via NSSM.

$LogFile = "C:\Sync\Logs\services\watchdog.log"
$RealTimeSync = "C:\Program Files\FreeFileSync\RealTimeSync.exe"
$RealTimeSyncConfig = "C:\Sync\Config\realtime.ffs_real"
$TaskName = "FolderSync-CloudBackup"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LogFile -Append | Out-Null
}

Write-Log "Watchdog started."

while ($true) {
    Write-Log "WATCHDOG-HEARTBEAT"

    # --- Check RealTimeSync ---
    $rts = Get-Process -Name "RealTimeSync" -ErrorAction SilentlyContinue
    if (-not $rts) {
        Write-Log "RealTimeSync not running — starting."
        Start-Process -FilePath $RealTimeSync -ArgumentList "`"$RealTimeSyncConfig`"" -WindowStyle Hidden
    }

    # --- Check scheduled task is enabled ---
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.State -eq 'Disabled') {
        Write-Log "Task $TaskName was disabled — re-enabling."
        Enable-ScheduledTask -TaskName $TaskName | Out-Null
    }

    # --- Check config_guard is running ---
    # config_guard.ps1 watches cloud_sync.ps1 and run_mirror.bat for tampering.
    # The attacker kills it before modifying files. Wdog restarts it within 180s.
    $guard = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like '*config_guard.ps1*' }
    if (-not $guard) {
        Write-Log "WATCHDOG  config_guard.ps1 not running - restarting"
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Sync\Config\config_guard.ps1' `
            -WindowStyle Hidden
        Write-Log "WATCHDOG  config_guard.ps1 restarted"
    }

    Start-Sleep -Seconds 180
}

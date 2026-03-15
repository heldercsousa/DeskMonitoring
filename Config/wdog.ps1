# FolderSync Watchdog
# Ensures RealTimeSync and cloud sync scheduled task are alive.
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

    Start-Sleep -Seconds 180
}

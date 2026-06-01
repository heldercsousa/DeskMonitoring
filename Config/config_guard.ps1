# config_guard.ps1
# FileSystemWatcher on Config\ — auto-restores cloud_sync.ps1 and run_mirror.bat
# via git restore the moment they are modified by any process.
# Runs hidden at login via registry Run key or Task Scheduler.

$RepoRoot  = 'C:\Sync'
$ConfigDir = 'C:\Sync\Config'
$LogFile   = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
$GuardedFiles = @('cloud_sync.ps1', 'run_mirror.bat')

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

Write-Log "CONFIG-GUARD  START  watching $ConfigDir for changes to: $($GuardedFiles -join ', ')"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path   = $ConfigDir
$watcher.Filter = '*.*'
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $true

$action = {
    $name = $Event.SourceEventArgs.Name
    $full = $Event.SourceEventArgs.FullPath
    $type = $Event.SourceEventArgs.ChangeType

    $guarded = @('cloud_sync.ps1', 'run_mirror.bat')
    if ($guarded -notcontains $name) { return }

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "$ts  CONFIG-GUARD  ALERT  $type detected on $name - restoring from git"
    $logLine | Add-Content -LiteralPath "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"

    # Remove index.lock if present
    $lock = 'C:\Sync\.git\index.lock'
    if (Test-Path $lock) {
        Remove-Item -Force $lock -ErrorAction SilentlyContinue
        "$ts  CONFIG-GUARD  INFO  removed stale index.lock before restore" | Add-Content -LiteralPath "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
    }

    # Restore the file
    $out = & git -C 'C:\Sync' restore $name 2>&1
    $result = if ($LASTEXITCODE -eq 0) { "RESTORED" } else { "RESTORE-FAILED: $out" }
    "$ts  CONFIG-GUARD  $result  $name" | Add-Content -LiteralPath "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null

Write-Log "CONFIG-GUARD  READY  watcher active"

# Keep alive
while ($true) {
    Start-Sleep -Seconds 30

    # Daily log rotation
    $newLog = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
    if ($newLog -ne $LogFile) { $LogFile = $newLog }
}

# config_guard.ps1
# FileSystemWatcher on Config\ — auto-restores guarded files from git HEAD when
# a change is not attributable to a legitimate actor (Claude Code or an open editor).
# Runs hidden at login via registry Run key or Task Scheduler.

$RepoRoot     = 'C:\Sync'
$ConfigDir    = 'C:\Sync\Config'
$LogFile      = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
$GuardedFiles = @('cloud_sync.ps1', 'run_mirror.bat', 'auditor.ps1', 'setup_update.ps1')

# Process names that indicate a legitimate human edit - do NOT restore if any is foreground.
$EditorProcesses = @('claude', 'Code', 'code', 'notepad', 'notepad++', 'sublime_text',
                     'vim', 'nvim', 'nano', 'wordpad', 'WINWORD', 'devenv')

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

# P/Invoke: get the name of the process that owns the foreground window.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32FG {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@ -ErrorAction SilentlyContinue

Write-Log "CONFIG-GUARD  START  watching $ConfigDir for: $($GuardedFiles -join ', ')"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path             = $ConfigDir
$watcher.Filter           = '*.*'
$watcher.NotifyFilter     = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $true

$action = {
    $name = $Event.SourceEventArgs.Name
    $type = $Event.SourceEventArgs.ChangeType

    $guarded = @('cloud_sync.ps1', 'run_mirror.bat', 'auditor.ps1', 'setup_update.ps1')
    if ($guarded -notcontains $name) { return }

    $editors = @('claude', 'Code', 'code', 'notepad', 'notepad++', 'sublime_text',
                 'vim', 'nvim', 'nano', 'wordpad', 'WINWORD', 'devenv')

    $logPath = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Identify foreground process at the moment the event fires.
    $fgName = 'unknown'
    try {
        $hwnd = [Win32FG]::GetForegroundWindow()
        [uint32]$fgPid = 0
        [Win32FG]::GetWindowThreadProcessId($hwnd, [ref]$fgPid) | Out-Null
        if ($fgPid -gt 0) {
            $fgName = (Get-Process -Id $fgPid -ErrorAction SilentlyContinue).Name
            if (-not $fgName) { $fgName = 'unknown' }
        }
    } catch {}

    "$ts  CONFIG-GUARD  CHANGE  $type on $name  foreground=$fgName" | Add-Content -LiteralPath $logPath

    # Skip restore if a known editor or Claude Code is in the foreground.
    if ($editors -contains $fgName) {
        "$ts  CONFIG-GUARD  SKIP  foreground=$fgName is a trusted editor - no restore" | Add-Content -LiteralPath $logPath
        return
    }

    # No legitimate actor in foreground - treat as tamper, restore immediately.
    "$ts  CONFIG-GUARD  TAMPER  foreground=$fgName not a trusted editor - restoring $name from git HEAD" | Add-Content -LiteralPath $logPath

    # Remove stale index.lock if present.
    $lock = 'C:\Sync\.git\index.lock'
    if (Test-Path $lock) {
        Remove-Item -Force $lock -ErrorAction SilentlyContinue
        "$ts  CONFIG-GUARD  INFO  removed stale index.lock before restore" | Add-Content -LiteralPath $logPath
    }

    $repoRelPath = "Config/$name"
    $out = & git -C 'C:\Sync' checkout HEAD -- $repoRelPath 2>&1
    $result = if ($LASTEXITCODE -eq 0) { "AUTO-RESTORED" } else { "RESTORE-FAILED: $out" }
    "$ts  CONFIG-GUARD  $result  $name  foreground-was=$fgName" | Add-Content -LiteralPath $logPath
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null

Write-Log "CONFIG-GUARD  READY  watcher active - restore triggered when foreground is not a trusted editor"

# Keep alive - also monitor critical task state
$lastTaskCheck = $null
while ($true) {
    Start-Sleep -Seconds 30

    # Roll log path at midnight.
    $newLog = "C:\Sync\Logs\security\config_guard_$(Get-Date -Format 'yyyy-MM-dd').log"
    if ($newLog -ne $LogFile) { $LogFile = $newLog }

    # Check every 60s if FolderSync-CloudBackup is disabled (attacker tampering with task state)
    if ($null -eq $lastTaskCheck -or ((Get-Date) - $lastTaskCheck).TotalSeconds -ge 60) {
        try {
            $task = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue
            if ($task -and $task.State -eq "Disabled") {
                Write-Log "TASK-TAMPER  FolderSync-CloudBackup disabled - attacker attempt detected, re-enabling"
                Enable-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue
                Write-Log "TASK-AUTO-RESTORED  FolderSync-CloudBackup re-enabled"
            }
        } catch {
            # Silently continue if task check fails
        }
        $lastTaskCheck = Get-Date
    }
}

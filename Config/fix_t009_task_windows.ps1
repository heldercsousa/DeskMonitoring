#Requires -RunAsAdministrator
# fix_t009_task_windows.ps1
# Silences two flashing PowerShell windows identified in T009.
# This fix is also baked into setup_update.ps1 (Steps 11 + 19) so it survives reinstall.
#
# White window (pwsh.exe): FolderSync-AuditFilter runs as InteractiveToken/helde (needed
#   for DPAPI credential decryption in send_alert.ps1). Can't change principal. Fix: use a
#   VBScript launcher  - wscript.exe is a GUI app (no console), WshShell.Run style=0 hides
#   the child pwsh before the window is ever created.
#
# Blue window (powershell.exe): FolderSync-Watchdog task is redundant  - NSSM service
#   FolderSyncWatchdog already runs wdog.ps1. The duplicate task spawned new Interactive
#   powershell.exe instances every 3 min. Fix: remove the task entirely.

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }

# ── Fix 1: AuditFilter  - replace task action with VBScript launcher ──────────
Write-Step "Fix 1: FolderSync-AuditFilter  - use VBScript launcher (no console flash)"

# Write the launcher
$vbsPath = 'C:\Sync\Config\audit_filter_launcher.vbs'
Set-Content -Path $vbsPath -Encoding ASCII -Value @'
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pwsh.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Sync\Config\audit_filter.ps1""", 0, False
'@
Write-OK "VBScript launcher written: $vbsPath"

# Re-register the task with wscript.exe as the executor (keeps InteractiveToken for DPAPI)
$taskName  = 'FolderSync-AuditFilter'
$existing  = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Fail "Task '$taskName' not found"
} else {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    $newAction = New-ScheduledTaskAction `
        -Execute  'wscript.exe' `
        -Argument "`"$vbsPath`" //B //NoLogo"

    # Restore principal to current user InteractiveToken (broken by previous fix attempt)
    $newPrincipal = New-ScheduledTaskPrincipal `
        -UserId    $currentUser `
        -LogonType Interactive `
        -RunLevel  Highest

    Set-ScheduledTask -TaskName $taskName -Action $newAction -Principal $newPrincipal | Out-Null

    $updated = Get-ScheduledTask -TaskName $taskName
    $okAction    = $updated.Actions[0].Execute -match 'wscript'
    $okPrincipal = $updated.Principal.LogonType -eq 'Interactive'
    if ($okAction -and $okPrincipal) {
        Write-OK "Action: wscript.exe -> audit_filter_launcher.vbs"
        Write-OK "Principal restored: $($updated.Principal.UserId) / Interactive (DPAPI intact)"
    } else {
        Write-Fail "Update incomplete  - Action=$($updated.Actions[0].Execute) Principal=$($updated.Principal.LogonType)"
    }
}

# ── Fix 2: Watchdog task  - remove (NSSM service is canonical) ────────────────
Write-Step "Fix 2: FolderSync-Watchdog scheduled task  - remove"

$wdTask = 'FolderSync-Watchdog'
$wt = Get-ScheduledTask -TaskName $wdTask -ErrorAction SilentlyContinue
if (-not $wt) {
    Write-OK "Task '$wdTask' already absent"
} else {
    Unregister-ScheduledTask -TaskName $wdTask -Confirm:$false
    $gone = -not (Get-ScheduledTask -TaskName $wdTask -ErrorAction SilentlyContinue)
    if ($gone) {
        Write-OK "Task removed  - NSSM FolderSyncWatchdog service is the sole watchdog"
    } else {
        Write-Fail "Task still present after removal attempt"
    }
}

# ── Kill any remaining duplicate wdog.ps1 processes ──────────────────────────
Write-Step "Stopping duplicate wdog.ps1 processes (keeping NSSM service instance)"

$svcPid = $null
try {
    $svc = Get-CimInstance Win32_Service -Filter "Name='FolderSyncWatchdog'" -ErrorAction Stop
    $svcPid = $svc.ProcessId
} catch { Write-Warn "Could not query FolderSyncWatchdog service PID" }

$wdogProcs = Get-Process -Name powershell -ErrorAction SilentlyContinue
foreach ($p in $wdogProcs) {
    $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cl -match 'wdog\.ps1') {
        if ($p.Id -eq $svcPid) {
            Write-OK "PID $($p.Id) is the NSSM service  - keeping"
        } else {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-OK "Stopped duplicate wdog.ps1 PID $($p.Id)"
        }
    }
}

Write-Host "`n>>> Done." -ForegroundColor Green
Write-Host "    White window: AuditFilter now uses VBScript launcher (no console created)" -ForegroundColor Gray
Write-Host "    Blue window : Watchdog task removed (NSSM service unchanged)" -ForegroundColor Gray

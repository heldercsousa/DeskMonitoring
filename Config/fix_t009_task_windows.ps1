#Requires -RunAsAdministrator
# fix_t009_task_windows.ps1
# Silences two flashing PowerShell windows identified in T009:
#   1. FolderSync-AuditFilter (pwsh.exe, every 5 min) — move from Interactive/helde to SYSTEM
#   2. FolderSync-Watchdog (powershell.exe, every 3 min) — disable; NSSM service handles this

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

# ── Fix 1: AuditFilter — change principal to SYSTEM ──────────────────────────
Write-Step "Fix 1: FolderSync-AuditFilter — change principal to SYSTEM"

$taskName = 'FolderSync-AuditFilter'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Fail "Task '$taskName' not found — skipping"
} else {
    # Re-register with SYSTEM principal (preserves actions and triggers)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Set-ScheduledTask -TaskName $taskName -Principal $principal | Out-Null
    $updated = Get-ScheduledTask -TaskName $taskName
    $uid = $updated.Principal.UserId
    $lt  = $updated.Principal.LogonType
    if ($uid -eq 'SYSTEM' -and $lt -eq 'ServiceAccount') {
        Write-OK "Principal updated: UserId=$uid  LogonType=$lt"
    } else {
        Write-Fail "Update failed — UserId=$uid  LogonType=$lt"
    }
}

# ── Fix 2: Watchdog task — disable (NSSM service is canonical) ───────────────
Write-Step "Fix 2: FolderSync-Watchdog scheduled task — disable"

$wdTask = 'FolderSync-Watchdog'
$wt = Get-ScheduledTask -TaskName $wdTask -ErrorAction SilentlyContinue
if (-not $wt) {
    Write-Fail "Task '$wdTask' not found — skipping"
} else {
    Disable-ScheduledTask -TaskName $wdTask | Out-Null
    $state = (Get-ScheduledTask -TaskName $wdTask).State
    if ($state -eq 'Disabled') {
        Write-OK "Task disabled — NSSM FolderSyncWatchdog service remains canonical"
    } else {
        Write-Fail "Disable failed — State=$state"
    }
}

# ── Kill the duplicate wdog.ps1 task instance ────────────────────────────────
Write-Step "Stopping duplicate wdog.ps1 task instances (keeping NSSM service instance)"

$svcPid = (Get-WmiObject Win32_Service -Filter "Name='FolderSyncWatchdog'").ProcessId
$wdogProcs = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
    (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'wdog\.ps1'
}
foreach ($p in $wdogProcs) {
    if ($p.Id -eq $svcPid) {
        Write-OK "PID $($p.Id) is the NSSM service — keeping"
    } else {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Write-OK "Stopped duplicate wdog.ps1 PID $($p.Id)"
    }
}

Write-Host "`n>>> Done. Both window sources silenced." -ForegroundColor Green
Write-Host "    Verify: run 'Get-ScheduledTask FolderSync-AuditFilter | select -exp Principal | fl'" -ForegroundColor Gray
Write-Host "    Verify: run 'Get-ScheduledTask FolderSync-Watchdog | select State'" -ForegroundColor Gray

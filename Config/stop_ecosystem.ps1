#Requires -RunAsAdministrator
# stop_ecosystem.ps1
# Stops all FolderSync + Camera ecosystem components in reverse order.
# Writes .ecosystem_state = "stopped" on completion.
# Run as Administrator.

$ErrorActionPreference = 'SilentlyContinue'
$LogFile   = "C:\Sync\Logs\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$StateFile = "C:\Sync\Config\.ecosystem_state"

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Stop" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Log "ECOSYSTEM-STOP  Stopping all ecosystem components"

# --- CAM-2 relay (VLC) ---
Write-Step "CAM-2 relay (VLC)"
Get-Process vlc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-OK "CAM-2 relay stopped"
Write-Log "ECOSYSTEM-STOP  CAM-2 relay stopped"

# --- Yawcam ---
Write-Step "Yawcam"
Get-Process yawcam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process javaw -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like '*Yawcam*' } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Write-OK "Yawcam stopped"
Write-Log "ECOSYSTEM-STOP  Yawcam stopped"

# --- RealTimeSync ---
Write-Step "RealTimeSync"
Get-Process RealTimeSync -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-OK "RealTimeSync stopped"
Write-Log "ECOSYSTEM-STOP  RealTimeSync stopped"

# --- Disable scheduled tasks ---
Write-Step "Scheduled tasks"
foreach ($task in @('FolderSync-CloudBackup', 'FolderSync-Watchdog', 'FolderSync-DailyCheck')) {
    $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
        Write-OK "$task disabled"
        Write-Log "ECOSYSTEM-STOP  Task $task disabled"
    } else {
        Write-OK "$task already disabled or not found"
    }
}

# --- FolderSyncAuditor NSSM service ---
Write-Step "FolderSyncAuditor service"
Stop-Service FolderSyncAuditor -Force -ErrorAction SilentlyContinue
Write-OK "FolderSyncAuditor stopped"
Write-Log "ECOSYSTEM-STOP  FolderSyncAuditor stopped"

# --- FolderSyncWatchdog NSSM service ---
Write-Step "FolderSyncWatchdog service"
Stop-Service FolderSyncWatchdog -Force -ErrorAction SilentlyContinue
Write-OK "FolderSyncWatchdog stopped"
Write-Log "ECOSYSTEM-STOP  FolderSyncWatchdog stopped"

# --- Write state flag ---
'stopped' | Set-Content -LiteralPath $StateFile -Encoding UTF8
Write-Log "ECOSYSTEM-STOP  State set to stopped"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Ecosystem stopped  --  state: stopped" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""

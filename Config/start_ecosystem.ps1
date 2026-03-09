#Requires -RunAsAdministrator
# start_ecosystem.ps1
# Starts all FolderSync + Camera ecosystem components.
# Writes .ecosystem_state = "running" on completion.
# Run as Administrator.

$ErrorActionPreference = 'SilentlyContinue'
$LogFile   = "C:\Sync\Logs\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$StateFile = "C:\Sync\Config\.ecosystem_state"

# --- Credential guard ---
Write-Host "`n  Credential check required." -ForegroundColor Yellow
$credUser = Read-Host "  Username"
$credPass = Read-Host "  Password" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credPass)
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Machine')
$valid = $ctx.ValidateCredentials($credUser, $plainPass)
$plainPass = $null

if (-not $valid) {
    Write-Host "  FAIL  Invalid credentials. Aborting." -ForegroundColor Red
    exit 1
}

$adminGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ctx, 'Administrators')
$isAdmin = $adminGroup.Members | Where-Object { $_.SamAccountName -eq $credUser }
if (-not $isAdmin) {
    Write-Host "  FAIL  User is not in local Administrators group. Aborting." -ForegroundColor Red
    exit 1
}
Write-Host "  OK    Credentials verified." -ForegroundColor Green
# --- End credential guard ---

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Start" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Log "ECOSYSTEM-START  Starting all ecosystem components"

# --- FolderSyncWatchdog NSSM service ---
Write-Step "FolderSyncWatchdog service"
Start-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
$s = Get-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
if ($s -and $s.Status -eq 'Running') {
    Write-OK "FolderSyncWatchdog running"
    Write-Log "ECOSYSTEM-START  FolderSyncWatchdog running"
} else {
    Write-Warn "FolderSyncWatchdog: $($s.Status)"
    Write-Log "ECOSYSTEM-START  WARN FolderSyncWatchdog $($s.Status)"
}

# --- FolderSyncAuditor NSSM service ---
Write-Step "FolderSyncAuditor service"
Start-Service FolderSyncAuditor -ErrorAction SilentlyContinue
$s = Get-Service FolderSyncAuditor -ErrorAction SilentlyContinue
if ($s -and $s.Status -eq 'Running') {
    Write-OK "FolderSyncAuditor running"
    Write-Log "ECOSYSTEM-START  FolderSyncAuditor running"
} else {
    Write-Warn "FolderSyncAuditor: $($s.Status)"
    Write-Log "ECOSYSTEM-START  WARN FolderSyncAuditor $($s.Status)"
}

# --- Enable scheduled tasks ---
Write-Step "Scheduled tasks"
foreach ($task in @('FolderSync-CloudBackup', 'FolderSync-Watchdog', 'FolderSync-DailyCheck')) {
    $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    if ($t) {
        if ($t.State -eq 'Disabled') {
            Enable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
            Write-OK "$task enabled"
        } else {
            Write-OK "$task already enabled ($($t.State))"
        }
        Write-Log "ECOSYSTEM-START  Task $task state: $($t.State)"
    } else {
        Write-Warn "$task not found - re-run setup_update.ps1"
        Write-Log "ECOSYSTEM-START  WARN Task $task not found"
    }
}

# --- RealTimeSync ---
Write-Step "RealTimeSync"
$rts = Get-Process RealTimeSync -ErrorAction SilentlyContinue
if (-not $rts) {
    Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
        -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $rts = Get-Process RealTimeSync -ErrorAction SilentlyContinue
    if ($rts) {
        Write-OK "RealTimeSync started"
        Write-Log "ECOSYSTEM-START  RealTimeSync started"
    } else {
        Write-Warn "RealTimeSync did not start - check FreeFileSync installation"
        Write-Log "ECOSYSTEM-START  WARN RealTimeSync not started"
    }
} else {
    Write-OK "RealTimeSync already running (PID $($rts.Id))"
    Write-Log "ECOSYSTEM-START  RealTimeSync already running"
}

# --- Yawcam ---
Write-Step "Yawcam (CAM-1)"
$yawcam = Get-Process yawcam -ErrorAction SilentlyContinue
if (-not $yawcam) {
    $yawcam = Get-Process javaw -ErrorAction SilentlyContinue |
              Where-Object { $_.MainWindowTitle -like '*Yawcam*' }
}
if (-not $yawcam) {
    Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-OK "Yawcam started"
    Write-Log "ECOSYSTEM-START  Yawcam started"
} else {
    Write-OK "Yawcam already running"
    Write-Log "ECOSYSTEM-START  Yawcam already running"
}

# --- CAM-2 relay ---
Write-Step "CAM-2 relay (cam2_relay.ps1 via VLC)"
$vlc = Get-Process vlc -ErrorAction SilentlyContinue
if (-not $vlc) {
    Start-Process powershell.exe `
        -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\cam2_relay.ps1"' `
        -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-OK "CAM-2 relay started"
    Write-Log "ECOSYSTEM-START  CAM-2 relay started"
} else {
    Write-OK "CAM-2 relay (VLC) already running"
    Write-Log "ECOSYSTEM-START  CAM-2 relay already running"
}

# --- Remove .camera_paused flag if present ---
$pausedFlag = "C:\Sync\Config\.camera_paused"
if (Test-Path $pausedFlag) {
    Remove-Item -LiteralPath $pausedFlag -Force -ErrorAction SilentlyContinue
    Write-OK ".camera_paused flag cleared"
    Write-Log "ECOSYSTEM-START  .camera_paused flag cleared"
}

# --- Write state flag ---
'running' | Set-Content -LiteralPath $StateFile -Encoding UTF8
Write-Log "ECOSYSTEM-START  State set to running"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Ecosystem started  --  state: running" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

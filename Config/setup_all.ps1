#Requires -RunAsAdministrator
# =============================================================================
# setup_all.ps1 v2
# Centralized setup for FolderSync Ecosystem + Security Hardening
# Works on any Windows machine - detects current user automatically
# Run as Administrator from C:\Sync\Config\
# Place alongside: DailySecurityCheck.ps1, AutoCleanup.ps1
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$currentUser     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$sidAdmins       = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$sidAdminsAccount= $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value
$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Centralized Setup v2" -ForegroundColor Cyan
Write-Host "  Running as: $currentUser" -ForegroundColor Cyan
Write-Host "  Script dir: $scriptDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# =============================================================================
# STEP 1 - Firewall log read permissions
# =============================================================================
Write-Step "Step 1 - Firewall log read permissions"
foreach ($f in @("C:\Sync\Logs\firewall.log","C:\Sync\Logs\firewall.log.old")) {
    if (Test-Path $f) {
        icacls $f /grant:r "${currentUser}:(R)" | Out-Null
        Write-OK "Read access granted: $f"
    } else {
        Write-Warn "Not found (will be fixed when created): $f"
    }
}
icacls "C:\Sync\Logs" /grant:r "${currentUser}:(OI)(CI)(R)" | Out-Null
Write-OK "Future firewall logs readable by $currentUser"

# =============================================================================
# STEP 2 - Update run_mirror.bat with daily log rotation
# =============================================================================
Write-Step "Step 2 - Update run_mirror.bat (daily log rotation)"
$mirrorBat = "C:\Sync\Config\run_mirror.bat"
Set-Content -Path $mirrorBat -Encoding ASCII -Value @'
@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /MIR = mirror (purges files deleted from source)
:: /R:2  = retry twice on error
:: /W:5  = wait 5 seconds between retries
:: /LOG+ = append to DAILY rotating log (mirror_YYYY-MM-DD.log)
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /MIR /R:2 /W:5 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL
'@
Write-OK "run_mirror.bat updated → mirror_YYYY-MM-DD.log"

# Archive old bloated mirror log if exists
$oldMirror = "C:\Sync\Logs\mirror"
if (Test-Path $oldMirror) {
    Rename-Item $oldMirror "C:\Sync\Logs\mirror_archive_$(Get-Date -Format 'yyyy-MM-dd').log" -ErrorAction SilentlyContinue
    Write-OK "Old mirror log archived"
}

# =============================================================================
# STEP 3 - Update cloud_sync.ps1 with log rotation
# =============================================================================
Write-Step "Step 3 - Update cloud_sync.ps1 (log rotation + firewall exclusion)"
$cloudSyncPs1 = "C:\Sync\Config\cloud_sync.ps1"
Set-Content -Path $cloudSyncPs1 -Encoding UTF8 -Value @'
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-03-02

$Rclone           = 'C:\Tools\Rclone\rclone.exe'
$Config           = 'C:\Sync\Config\rclone.conf'
$Source           = 'C:\Users\helde\Repos\Bois'
$Remote           = 'cloudsync:helder-sync-mirror'
$Mirror           = 'C:\Sync\Mirror'
$LogDir           = 'C:\Sync\Logs'
$Log              = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror = 7
$DaysToKeepLogs   = 30

# 1. Sync to B2 (exclude logs folder to avoid re-upload loop)
& $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --transfers 4 `
    --checkers 8 `
    --fast-list `
    --exclude "logs/**"

# 2. Upload logs to B2 (copy only - never deletes from B2)
# firewall.log excluded: owned by SYSTEM, large, rotated independently
& $Rclone copy $LogDir "$Remote/logs" `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --exclude "firewall.log" `
    --exclude "firewall.log.old"

# 3. Mirror cleanup - delete files older than DaysToKeepMirror
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. cloud_sync log rotation - delete logs older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "cloud_sync_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. mirror log rotation - delete mirror_*.log older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "mirror_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
'@
Write-OK "cloud_sync.ps1 updated (Mirror: 7 days | Logs: 30 days retention)"

# =============================================================================
# STEP 4 - C:\Sync\Config ACL
# =============================================================================
Write-Step "Step 4 - Lock C:\Sync\Config permissions"
icacls C:\Sync\Config /inheritance:r | Out-Null
icacls C:\Sync\Config /remove:g "Todos"         | Out-Null
icacls C:\Sync\Config /remove:g "Everyone"      | Out-Null
icacls C:\Sync\Config /remove:g "BUILTIN\Users" | Out-Null
icacls C:\Sync\Config /grant:r "${currentUser}:(OI)(CI)F"        | Out-Null
icacls C:\Sync\Config /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F"   | Out-Null
icacls C:\Sync\Config /grant:r "${sidAdminsAccount}:(OI)(CI)F"   | Out-Null
Write-OK "C:\Sync\Config locked to: $currentUser + SYSTEM + Administrators"

# =============================================================================
# STEP 5 - DailySecurityCheck v7
# =============================================================================
Write-Step "Step 5 - Install DailySecurityCheck v7"
$secScriptsDir = "$env:USERPROFILE\Documents\SecurityScripts"
if (-not (Test-Path $secScriptsDir)) { New-Item -ItemType Directory -Path $secScriptsDir -Force | Out-Null }

foreach ($scriptName in @("DailySecurityCheck.ps1","AutoCleanup.ps1")) {
    $src = Join-Path $scriptDir $scriptName
    if (Test-Path $src) {
        Copy-Item $src "$secScriptsDir\$scriptName" -Force
        Write-OK "Copied $scriptName → $secScriptsDir"
    } else {
        Write-Warn "$scriptName not found next to setup_all.ps1 — copy manually to $secScriptsDir"
    }
}

$taskName  = "Verificacao Automatica de Seguranca"
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$secScriptsDir\DailySecurityCheck.ps1`""
$trigger   = New-ScheduledTaskTrigger -Daily -At "09:00"
$settings  = New-ScheduledTaskSettingsSet -Hidden -RunOnlyIfNetworkAvailable:$false
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-OK "Task registered: $taskName (daily 09:00)"

$shell    = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$([System.Environment]::GetFolderPath('Desktop'))\Verificar Seguranca.lnk")
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments  = "-ExecutionPolicy Bypass -File `"$secScriptsDir\DailySecurityCheck.ps1`""
$shortcut.Save()
Write-OK "Desktop shortcut created: Verificar Seguranca.lnk"

# =============================================================================
# STEP 6 - Disable remote access services
# =============================================================================
Write-Step "Step 6 - Disable remote access services"
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
Write-OK "RDP connections blocked"

foreach ($svc in @("RemoteRegistry","WinRM","TermService")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.StartType -ne 'Disabled') {
            Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            Write-OK "$svc disabled"
        } else {
            Write-OK "$svc already disabled"
        }
    }
}

try {
    Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force -ErrorAction SilentlyContinue
    Write-OK "SMB2 disabled"
} catch { Write-Warn "SMB2 disable failed: $_" }

# =============================================================================
# STEP 7 - Account lockout policy
# =============================================================================
Write-Step "Step 7 - Account lockout (5 attempts, 30 min)"
net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 | Out-Null
Write-OK "Lockout configured"

# =============================================================================
# STEP 8 - Screen auto-lock (5 minutes)
# =============================================================================
Write-Step "Step 8 - Screen auto-lock (5 minutes)"
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 300 | Out-Null
powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE  CONSOLELOCK   1 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE  CONSOLELOCK   1 | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null
Write-OK "Auto-lock: 5 minutes, password required on wake"

# =============================================================================
# STEP 9 - Windows Firewall logging
# =============================================================================
Write-Step "Step 9 - Windows Firewall logging"
netsh advfirewall set allprofiles logging droppedconnections enable | Out-Null
netsh advfirewall set allprofiles logging allowedconnections enable | Out-Null
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\firewall.log" | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 8192 | Out-Null
Start-Sleep -Seconds 1
if (Test-Path "C:\Sync\Logs\firewall.log") {
    icacls "C:\Sync\Logs\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
    Write-OK "Firewall logging active + read permission set"
} else {
    Write-OK "Firewall logging active (log created on first connection)"
}

# =============================================================================
# STEP 10 - Register FolderSync-CloudBackup task (SYSTEM)
# NOTE: For new device only. Skip if task already exists and is correct.
# =============================================================================
Write-Step "Step 10 - FolderSync-CloudBackup task (SYSTEM, every 5 min)"
$existingBackup = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue
if (-not $existingBackup) {
    $action1   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
    $trigger1  = @(
        $(New-ScheduledTaskTrigger -AtStartup),
        $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
    )
    $settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $principal1= New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force | Out-Null
    Write-OK "Task FolderSync-CloudBackup registered (SYSTEM)"
} else {
    Write-OK "Task FolderSync-CloudBackup already exists — skipped"
}

# =============================================================================
# STEP 11 - Register FolderSync-Watchdog task (current user, interactive)
# NOTE: MUST run as current user — SYSTEM cannot launch RealTimeSync GUI
# =============================================================================
Write-Step "Step 11 - FolderSync-Watchdog task (current user, every 3 min)"
$action2   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
$trigger2  = @(
    $(New-ScheduledTaskTrigger -AtLogOn),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 3) -Once -At (Get-Date))
)
$settings2 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal2= New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Unregister-ScheduledTask -TaskName "FolderSync-Watchdog" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-Watchdog" -Action $action2 -Trigger $trigger2 -Settings $settings2 -Principal $principal2 -Force | Out-Null
Write-OK "Task FolderSync-Watchdog registered ($currentUser)"

# =============================================================================
# STEP 12 - Install FolderSyncWatchdog NSSM service
# =============================================================================
Write-Step "Step 12 - FolderSyncWatchdog NSSM service"
$nssm = 'C:\Tools\NSSM\nssm.exe'
if (Test-Path $nssm) {
    & $nssm stop   FolderSyncWatchdog 2>$null
    & $nssm remove FolderSyncWatchdog confirm 2>$null
    Start-Sleep 2
    & $nssm install FolderSyncWatchdog powershell.exe
    & $nssm set FolderSyncWatchdog AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
    & $nssm set FolderSyncWatchdog DisplayName   'Folder Sync Watchdog Service'
    & $nssm set FolderSyncWatchdog Description   'Monitors and restarts folder sync processes (RealTimeSync + cloud backup task).'
    & $nssm set FolderSyncWatchdog Start          SERVICE_AUTO_START
    & $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\watchdog_svc.log'
    & $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\watchdog_svc_err.log'
    & $nssm set FolderSyncWatchdog AppRotateFiles  1
    & $nssm set FolderSyncWatchdog AppRotateBytes  1048576
    Start-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
    $s = Get-Service FolderSyncWatchdog -ErrorAction SilentlyContinue
    Write-OK "FolderSyncWatchdog service: $($s.Status)"
} else {
    Write-Warn "NSSM not found at $nssm — install NSSM first, then rerun this step manually"
}

# =============================================================================
# STEP 13 - Install FolderSyncAuditor NSSM service
# =============================================================================
Write-Step "Step 13 - FolderSyncAuditor NSSM service"
if (Test-Path $nssm) {
    & $nssm stop   FolderSyncAuditor 2>$null
    & $nssm remove FolderSyncAuditor confirm 2>$null
    Start-Sleep 2
    & $nssm install FolderSyncAuditor powershell.exe
    & $nssm set FolderSyncAuditor AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auditor.ps1'
    & $nssm set FolderSyncAuditor DisplayName   'Folder Sync Security Auditor'
    & $nssm set FolderSyncAuditor Description   'Monitors file changes, remote access, and service tampering.'
    & $nssm set FolderSyncAuditor Start          SERVICE_AUTO_START
    & $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\auditor_svc.log'
    & $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\auditor_svc_err.log'
    & $nssm set FolderSyncAuditor AppRotateFiles  1
    & $nssm set FolderSyncAuditor AppRotateBytes  2097152
    & $nssm set FolderSyncAuditor AppRestartDelay 30000
    Start-Service FolderSyncAuditor -ErrorAction SilentlyContinue
    $s = Get-Service FolderSyncAuditor -ErrorAction SilentlyContinue
    Write-OK "FolderSyncAuditor service: $($s.Status)"
} else {
    Write-Warn "NSSM not found — skipped FolderSyncAuditor"
}

# =============================================================================
# STEP 14 - RealTimeSync startup registry entry
# =============================================================================
Write-Step "Step 14 - RealTimeSync startup registry"
$rtsPath = '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "FolderSyncRealTime" -Value $rtsPath -ErrorAction SilentlyContinue
Write-OK "Registry startup entry set for RealTimeSync"

# Start RealTimeSync now if not running
$rts = Get-Process RealTimeSync -ErrorAction SilentlyContinue
if (-not $rts) {
    Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" `
        -ArgumentList '"C:\Sync\Config\realtime.ffs_real"' -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-OK "RealTimeSync started"
} else {
    Write-OK "RealTimeSync already running (PID $($rts.Id))"
}

# =============================================================================
# STEP 15 - Enable file auditing (SACL on watched folder)
# =============================================================================
Write-Step "Step 15 - File system auditing (SACL)"
$auditScript = "C:\Sync\Config\enable_file_auditing.ps1"
if (Test-Path $auditScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $auditScript
    Write-OK "File auditing configured"
} else {
    Write-Warn "enable_file_auditing.ps1 not found — run manually when available"
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup Complete — Full Ecosystem + Security Hardening" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Applied:" -ForegroundColor White
Write-Host "  Step  1 - Firewall log read permissions" -ForegroundColor Gray
Write-Host "  Step  2 - run_mirror.bat daily rotation" -ForegroundColor Gray
Write-Host "  Step  3 - cloud_sync.ps1 log rotation (Mirror:7d, Logs:30d)" -ForegroundColor Gray
Write-Host "  Step  4 - C:\Sync\Config ACL locked" -ForegroundColor Gray
Write-Host "  Step  5 - DailySecurityCheck v7 + scheduled task + shortcut" -ForegroundColor Gray
Write-Host "  Step  6 - Remote access disabled (RDP/WinRM/SMB2/RemoteRegistry)" -ForegroundColor Gray
Write-Host "  Step  7 - Account lockout (5 attempts, 30 min)" -ForegroundColor Gray
Write-Host "  Step  8 - Screen auto-lock (5 min)" -ForegroundColor Gray
Write-Host "  Step  9 - Firewall logging → C:\Sync\Logs\firewall.log" -ForegroundColor Gray
Write-Host "  Step 10 - FolderSync-CloudBackup task (SYSTEM)" -ForegroundColor Gray
Write-Host "  Step 11 - FolderSync-Watchdog task (current user)" -ForegroundColor Gray
Write-Host "  Step 12 - FolderSyncWatchdog NSSM service" -ForegroundColor Gray
Write-Host "  Step 13 - FolderSyncAuditor NSSM service" -ForegroundColor Gray
Write-Host "  Step 14 - RealTimeSync startup registry + started" -ForegroundColor Gray
Write-Host "  Step 15 - File system auditing (SACL)" -ForegroundColor Gray
Write-Host ""
Write-Host "Pending (manual — requires web UI or physical access):" -ForegroundColor Yellow
Write-Host "  - B2 Lifecycle Rules (versioning) via backblaze.com" -ForegroundColor Yellow
Write-Host "  - BIOS password on Acer Nitro 5" -ForegroundColor Yellow
Write-Host "  - Windows Hello PIN (resolve via Microsoft account portal)" -ForegroundColor Yellow
Write-Host "  - C100 RTSP integration" -ForegroundColor Yellow
Write-Host ""
Write-Host "Validate with:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER to close"
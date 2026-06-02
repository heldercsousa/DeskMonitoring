#Requires -RunAsAdministrator
# =============================================================================
# setup_update.ps1 v3
# Centralized setup for FolderSync Ecosystem + Security Hardening
# Replaces setup_all.ps1. Adds .ecosystem_state awareness:
#   - Stops ecosystem before reconfiguring if currently running
#   - Restarts after config if it was running before
# Run as Administrator from C:\Sync\Config\
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$currentUser     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$sidAdmins       = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$sidAdminsAccount= $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value
$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateFile       = "C:\Sync\Config\.ecosystem_state"

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FolderSync Ecosystem - Centralized Setup v3" -ForegroundColor Cyan
Write-Host "  Running as: $currentUser" -ForegroundColor Cyan
Write-Host "  Script dir: $scriptDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# =============================================================================
# STATE MANAGEMENT - read .ecosystem_state, stop if running
# =============================================================================
$wasRunning = $false
if (Test-Path $StateFile) {
    $state = (Get-Content -LiteralPath $StateFile -Raw).Trim()
    if ($state -eq 'running') {
        $wasRunning = $true
        Write-Warn "Ecosystem is running - stopping before reconfigure"
        & powershell.exe -ExecutionPolicy Bypass -File "$scriptDir\stop_ecosystem.ps1"
        Start-Sleep -Seconds 3
    } else {
        Write-OK "Ecosystem state: stopped - proceeding with config"
    }
} else {
    Write-OK "No .ecosystem_state file - assuming first run (will start after setup)"
    $wasRunning = $true  # default: start after fresh install
}

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
:: /E    = Copy subdirectories (including empty ones), do NOT delete from dest
:: /Z    = Restartable mode (essential for video files if copy is interrupted)
:: /R:1  = Retry only once to avoid massive logs
:: /W:2  = Short wait between retries
:: /NFL  = No File List - suppresses per-file output, keeps summary only (prevents log bloat)
:: /LOG+ = Append to DAILY rotating log (mirror_YYYY-MM-DD.log)
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL /NC /NS /NFL
'@
Write-OK "run_mirror.bat updated -> mirror_YYYY-MM-DD.log"

# Archive old bloated mirror log if exists
$oldMirror = "C:\Sync\Logs\mirror"
if (Test-Path $oldMirror) {
    Rename-Item $oldMirror "C:\Sync\Logs\mirror_archive_$(Get-Date -Format 'yyyy-MM-dd').log" -ErrorAction SilentlyContinue
    Write-OK "Old mirror log archived"
}

# =============================================================================
# STEP 3 - Update cloud_sync.ps1 with self-healing firewall + 3-phase ACL
# =============================================================================
Write-Step "Step 3 - Update cloud_sync.ps1 (firewall self-healing + 3-phase ACL protection)"
$cloudSyncPs1 = "C:\Sync\Config\cloud_sync.ps1"
Set-Content -Path $cloudSyncPs1 -Encoding UTF8 -Value @'
# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-03-07 - Added self-healing firewall detection+removal+retry

$Rclone           = 'C:\Tools\Rclone\rclone.exe'
$Config           = 'C:\Sync\Config\rclone.conf'
$Source           = 'C:\Users\helde\Repos\Bois'
$Remote           = 'cloudsync:helder-sync-mirror'
$Mirror           = 'C:\Sync\Mirror'
$LogDir           = 'C:\Sync\Logs'
$Log              = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror = 7
$DaysToKeepLogs   = 30

# Known malicious firewall rules that block Backblaze B2 sync
$MaliciousFirewallRules = @(
    'Block 104.153.233.180',
    'Block 149.137.142.15'
)

function Write-SyncLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $Log
}

function Remove-MaliciousFirewallRules {
    $removed = @()
    foreach ($ruleName in $MaliciousFirewallRules) {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            $removed += $ruleName
            Write-SyncLog "FIREWALL-HEAL  Removed malicious block rule: $ruleName"
        }
    }
    # Also scan for any unknown outbound BLOCK rules targeting B2 IP ranges
    $allBlockRules = Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' } |
        Where-Object { $_.DisplayName -notlike 'Block 0.0.0.0*' }
    foreach ($r in $allBlockRules) {
        $addr = ($r | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress
        if ($addr -match '104\.153\.|149\.137\.|backblaze') {
            Remove-NetFirewallRule -DisplayName $r.DisplayName -ErrorAction SilentlyContinue
            $removed += $r.DisplayName
            Write-SyncLog "FIREWALL-HEAL  Removed unknown B2 block rule: $($r.DisplayName) -> $addr"
        }
    }
    return $removed
}

# ============================================================
# STEP 1 - Pre-flight: check for known malicious firewall rules
# Remove before sync attempt to avoid wasted run
# ============================================================
Write-SyncLog "SYNC-START  Beginning cloud sync run"

$preRemoved = @()
foreach ($ruleName in $MaliciousFirewallRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule) {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        $preRemoved += $ruleName
        Write-SyncLog "FIREWALL-PREFLIGHT  Removed malicious block rule before sync: $ruleName"
    }
}
if ($preRemoved.Count -gt 0) {
    Write-SyncLog "FIREWALL-PREFLIGHT  WARNING: $($preRemoved.Count) malicious rule(s) were active at sync start - possible active attack"
}

# ============================================================
# STEP 2 - Run rclone sync, capture output for error detection
# ============================================================
$rcloneOutput = & $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --transfers 4 `
    --checkers 8 `
    --fast-list 2>&1

$rcloneExitCode = $LASTEXITCODE

# ============================================================
# STEP 3 - Detect firewall blocking pattern in rclone output
# If detected: remove rules, retry sync once
# ============================================================
$firewallBlocked = $false
if ($rcloneOutput -match 'connectex|socket access forbidden|access is forbidden|connect: permission denied') {
    $firewallBlocked = $true
    Write-SyncLog "FIREWALL-DETECT  Rclone reported connection blocked - checking firewall rules"

    $healed = Remove-MaliciousFirewallRules
    if ($healed.Count -gt 0) {
        Write-SyncLog "FIREWALL-HEAL  Removed $($healed.Count) malicious rule(s): $($healed -join ', ')"
        Write-SyncLog "FIREWALL-HEAL  Retrying sync after firewall repair"

        # Retry sync
        $rcloneOutput2 = & $Rclone sync $Source $Remote `
            --config $Config `
            --log-file $Log `
            --log-level INFO `
            --transfers 4 `
            --checkers 8 `
            --fast-list 2>&1

        $rcloneExitCode = $LASTEXITCODE

        if ($LASTEXITCODE -eq 0) {
            Write-SyncLog "FIREWALL-HEAL  Retry SUCCESS - sync completed after firewall repair"
        } else {
            Write-SyncLog "FIREWALL-HEAL  Retry FAILED (exit $LASTEXITCODE) - sync still failing after firewall repair"
            Write-SyncLog "FIREWALL-HEAL  Manual investigation required"
        }
    } else {
        Write-SyncLog "FIREWALL-DETECT  No known malicious rules found - unknown blocking cause"
        Write-SyncLog "FIREWALL-DETECT  Run check_status.ps1 and review firewall rules manually"
    }
} elseif ($rcloneExitCode -eq 0) {
    Write-SyncLog "SYNC-OK  Sync completed successfully (exit 0)"
} else {
    Write-SyncLog "SYNC-FAIL  Sync failed (exit $rcloneExitCode) - not a firewall error"
}

# ============================================================
# FASE 0 - Aplicar ACL Deny Delete em arquivos < 7 dias
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop

                $hasDeny = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }

                if (-not $hasDeny) {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
                        'Delete',
                        'None',
                        'None',
                        'Deny'
                    )
                    $acl.AddAccessRule($rule)
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch {
                # Silencioso
            }
        }
}

# ============================================================
# FASE 1 - Remover ACL Deny Delete de arquivos >= 7 dias
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop

                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }

                if ($denyRules) {
                    foreach ($rule in $denyRules) {
                        $acl.RemoveAccessRule($rule) | Out-Null
                    }
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch {
                # Silencioso
            }
        }
}

# ============================================================
# FASE 2 - Deletar arquivos >= 7 dias
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. cloud_sync log rotation
Get-ChildItem -Path $LogDir -Filter "cloud_sync_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. mirror log rotation
Get-ChildItem -Path $LogDir -Filter "mirror_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-SyncLog "SYNC-END  Cloud sync run complete"
'@
Write-OK "cloud_sync.ps1 updated (self-healing firewall + 3-phase ACL protection)"

# =============================================================================
# STEP 4 - SINGLE AUTHORITY: all Deny Delete ACL rules for C:\Sync
# =============================================================================
Write-Step "Step 4 - Apply all Deny Delete ACL rules (single authority)"

$sidEveryone = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')

function Set-DenyDeleteFull($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone, 'Delete,DeleteSubdirectoriesAndFiles',
        'ContainerInherit,ObjectInherit', 'None', 'Deny')
    $acl.RemoveAccessRule($rule) | Out-Null
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

function Set-DenyDeleteFolderOnly($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone, 'Delete', 'None', 'None', 'Deny')
    $acl.RemoveAccessRule($rule) | Out-Null
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

Set-DenyDeleteFolderOnly 'C:\Sync'
Write-OK "C:\Sync root locked (folder-only, no inherit)"

Set-DenyDeleteFull 'C:\Sync\Config'
Write-OK "C:\Sync\Config locked (recursive)"

Set-DenyDeleteFull 'C:\Sync\Logs'
Write-OK "C:\Sync\Logs locked (recursive)"

if (-not (Test-Path 'C:\Sync\Evidence')) { New-Item -ItemType Directory -Path 'C:\Sync\Evidence' -Force | Out-Null }
Set-DenyDeleteFull 'C:\Sync\Evidence'
Write-OK "C:\Sync\Evidence locked (recursive)"

if (Test-Path 'C:\Sync\.git') {
    icacls "C:\Sync\.git" /remove:d "*S-1-1-0" /T /Q | Out-Null
    icacls "C:\Sync\.git" /remove:d "*S-1-5-32-545" /T /Q | Out-Null
    icacls "C:\Sync\.git" /remove:d "*S-1-5-32-544" /T /Q | Out-Null
    Write-OK "C:\Sync\.git liberated (no Deny Delete)"
    $gitDeny = (icacls "C:\Sync\.git" 2>&1) | Where-Object { $_ -match ':D\b' }
    if ($gitDeny) {
        Write-Fail "C:\Sync\.git still has Deny rules - investigate: $gitDeny"
    } else {
        Write-OK "C:\Sync\.git verified clean (zero Deny rules)"
    }
}
Write-OK "C:\Sync\Mirror - no folder ACL (cloud_sync.ps1 manages per-file ACLs)"

# =============================================================================
# STEP 5 - DailySecurityCheck v8
# =============================================================================
Write-Step "Step 5 - Install DailySecurityCheck v8"

foreach ($oldName in @("Verificacao Automatica de Seguranca", "Verificacao Automatica de Seguranca")) {
    if (Get-ScheduledTask -TaskName $oldName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $oldName -Confirm:$false -ErrorAction SilentlyContinue
        Write-OK "Removed legacy task: $oldName"
    }
}

$taskName  = "FolderSync-DailyCheck"
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\Sync\Config\DailySecurityCheck.ps1`""
$trigger   = New-ScheduledTaskTrigger -Daily -At "09:00"
$settings  = New-ScheduledTaskSettingsSet -Hidden -RunOnlyIfNetworkAvailable:$false
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-OK "Task registered: $taskName -> C:\Sync\Config\DailySecurityCheck.ps1 (daily 09:00)"

$shell    = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$([System.Environment]::GetFolderPath('Desktop'))\Verificar Seguranca.lnk")
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments  = "-ExecutionPolicy Bypass -File `"C:\Sync\Config\DailySecurityCheck.ps1`""
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
netsh advfirewall set allprofiles logging filename "C:\Sync\Logs\security\firewall.log" | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 8192 | Out-Null
Start-Sleep -Seconds 1
if (Test-Path "C:\Sync\Logs\security\firewall.log") {
    icacls "C:\Sync\Logs\security\firewall.log" /grant:r "${currentUser}:(R)" | Out-Null
    Write-OK "Firewall logging active + read permission set"
} else {
    Write-OK "Firewall logging active (log created on first connection)"
}

# =============================================================================
# STEP 10 - Register FolderSync-CloudBackup task (SYSTEM)
# =============================================================================
Write-Step "Step 10 - FolderSync-CloudBackup task (SYSTEM, every 5 min)"
$existingBackup = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue

$needsRecreate = $false
if ($existingBackup) {
    $currentArgs = $existingBackup.Actions[0].Arguments
    $currentExec = $existingBackup.Actions[0].Execute

    if ($currentExec -like "*.bat" -or $currentArgs -notlike "*-NoWindow*") {
        Write-Warn "Task exists but uses .bat or missing -NoWindow - will recreate"
        $needsRecreate = $true
    }
}

if (-not $existingBackup -or $needsRecreate) {
    if ($existingBackup) {
        Unregister-ScheduledTask -TaskName "FolderSync-CloudBackup" -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    $action1   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoWindow -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
    $trigger1  = @(
        $(New-ScheduledTaskTrigger -AtStartup),
        $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
    )
    $settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $principal1= New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force | Out-Null
    Write-OK "Task FolderSync-CloudBackup registered (PowerShell with -NoWindow)"
} else {
    Write-OK "Task FolderSync-CloudBackup already exists with correct arguments"
}

# =============================================================================
# STEP 11 - Remove FolderSync-Watchdog scheduled task (NSSM service is canonical)
# The NSSM FolderSyncWatchdog service (Step 12) is the proper watchdog mechanism.
# Having both caused duplicate wdog.ps1 processes + flashing blue PS windows.
# =============================================================================
Write-Step "Step 11 - Remove FolderSync-Watchdog task (NSSM service handles this)"
Unregister-ScheduledTask -TaskName "FolderSync-Watchdog" -Confirm:$false -ErrorAction SilentlyContinue
Write-OK "FolderSync-Watchdog task removed - NSSM FolderSyncWatchdog service is the watchdog"

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
    & $nssm set FolderSyncWatchdog AppStdout      'C:\Sync\Logs\services\watchdog_svc.log'
    & $nssm set FolderSyncWatchdog AppStderr      'C:\Sync\Logs\services\watchdog_svc_err.log'
    & $nssm set FolderSyncWatchdog AppRotateFiles  1
    & $nssm set FolderSyncWatchdog AppRotateBytes  1048576
    Write-OK "FolderSyncWatchdog service installed (start via start_ecosystem.ps1)"
} else {
    Write-Warn "NSSM not found at $nssm - install NSSM first, then rerun this step manually"
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
    & $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\services\auditor_svc.log'
    & $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\services\auditor_svc_err.log'
    & $nssm set FolderSyncAuditor AppRotateFiles  1
    & $nssm set FolderSyncAuditor AppRotateBytes  2097152
    & $nssm set FolderSyncAuditor AppRestartDelay 30000
    Write-OK "FolderSyncAuditor service installed (start via start_ecosystem.ps1)"
} else {
    Write-Warn "NSSM not found - skipped FolderSyncAuditor"
}

# =============================================================================
# STEP 14 - Startup registry entries (RealTimeSync + Yawcam + Monitor + CAM-2)
# =============================================================================
Write-Step "Step 14 - Startup registry entries"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# RealTimeSync
$rtsPath = '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'
Set-ItemProperty $runKey -Name "FolderSyncRealTime" -Value $rtsPath -ErrorAction SilentlyContinue
Write-OK "Registry: FolderSyncRealTime -> RealTimeSync.exe"

# Yawcam - use bat wrapper so working dir is set correctly (prevents launcher.cfg error)
Set-ItemProperty $runKey -Name "Yawcam" `
    -Value '"C:\Sync\Config\start_yawcam.bat"' -ErrorAction SilentlyContinue
Write-OK "Registry: Yawcam -> C:\Sync\Config\start_yawcam.bat"

# YawcamMonitor (uses relocated start_monitor.ps1 in C:\Sync\Config\)
$monitorCmd = 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\start_monitor.ps1"'
Set-ItemProperty $runKey -Name "YawcamMonitor" -Value $monitorCmd -ErrorAction SilentlyContinue
Write-OK "Registry: YawcamMonitor -> C:\Sync\Config\start_monitor.ps1"

# YawcamCam2Relay
$cam2Cmd = 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Sync\Config\cam2_relay.ps1"'
Set-ItemProperty $runKey -Name "YawcamCam2Relay" -Value $cam2Cmd -ErrorAction SilentlyContinue
Write-OK "Registry: YawcamCam2Relay -> C:\Sync\Config\cam2_relay.ps1"

# =============================================================================
# STEP 15 - Remove any known malicious firewall rules
# =============================================================================
Write-Step "Step 15 - Remove malicious firewall rules (B2 block rules)"
$maliciousRules = @(
    "Block 104.153.233.180",
    "Block 149.137.142.15"
)
$removedCount = 0
foreach ($ruleName in $maliciousRules) {
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        Write-Warn "Removed malicious rule: $ruleName"
        $removedCount++
    }
}
if ($removedCount -eq 0) {
    Write-OK "No malicious B2 block rules found"
} else {
    Write-OK "$removedCount malicious rule(s) removed"
}

# =============================================================================
# STEP 16 - File system auditing SACL on watched folder (Bois)
# =============================================================================
Write-Step "Step 16 - File system auditing (SACL on Bois folder)"
$auditScript = "C:\Sync\Config\enable_file_auditing.ps1"
if (Test-Path $auditScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $auditScript
    Write-OK "File auditing (SACL) configured"
} else {
    Write-Warn "enable_file_auditing.ps1 not found - run manually when available"
}

# =============================================================================
# STEP 16b - SACL write auditing on C:\Sync\Config\ (catches tampering process via event 4663)
# =============================================================================
Write-Step "Step 16b - SACL write auditing on Config\, Evidence\, .git\ + 512 MB Security log"
$configAuditScript = "C:\Sync\Config\enable_config_auditing.ps1"
if (Test-Path $configAuditScript) {
    & pwsh.exe -ExecutionPolicy Bypass -File $configAuditScript
    Write-OK "SACL configured on Config\+Evidence\+.git\ - tampering appears as event 4663"
} else {
    Write-Warn "enable_config_auditing.ps1 not found - run manually when available"
}

# =============================================================================
# STEP 17 - FolderSync-GitCommitLogs task (current user, daily 23:30)
# =============================================================================
Write-Step "Step 17 - FolderSync-GitCommitLogs task (daily 23:30)"
$action17   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auto_commit_logs.ps1'
$trigger17  = New-ScheduledTaskTrigger -Daily -At "23:30"
$settings17 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal17= New-ScheduledTaskPrincipal -UserId $currentUser -LogonType S4U -RunLevel Highest
Unregister-ScheduledTask -TaskName "FolderSync-GitCommitLogs" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-GitCommitLogs" -Action $action17 -Trigger $trigger17 -Settings $settings17 -Principal $principal17 -Force | Out-Null
Write-OK "Task FolderSync-GitCommitLogs registered ($currentUser, daily 23:30)"

# =============================================================================
# STEP 18 - FolderSync-PowerCheck task (SYSTEM, every 1h + AtLogon + AtBoot)
# Registers check_power_motion.ps1 to audit and auto-heal power settings
# =============================================================================
Write-Step "Step 18 - FolderSync-PowerCheck task (SYSTEM, hourly + AtLogon + AtBoot)"

$taskXml18 = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <TimeTrigger>
      <Repetition><Interval>PT1H</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\check_power_motion.ps1</Arguments>
    </Exec>
  </Actions>
</Task>
'@

Unregister-ScheduledTask -TaskName "FolderSync-PowerCheck" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-PowerCheck" -Xml $taskXml18 -Force | Out-Null
Write-OK "Task FolderSync-PowerCheck registered (SYSTEM, hourly + AtLogon + AtBoot)"

# Apply power settings immediately on reinstall
Write-Step "Step 18b - Apply motion-detection power settings (fix_power_motion.ps1)"
try {
    & powershell.exe -ExecutionPolicy Bypass -File "$scriptDir\fix_power_motion.ps1"
    Write-OK "Power settings applied (Balanced plan, USB Suspend disabled, sleep/hibernate Never)"
} catch {
    Write-Warn "fix_power_motion.ps1 failed: $_ - run manually after setup"
}

# =============================================================================
# STEP 19 - FolderSync-AuditFilter task (every 5 min — suspicious-only 4663 filter)
# Must run as current user (InteractiveToken) — send_alert.ps1 uses DPAPI CurrentUser scope.
# Uses a VBScript launcher so wscript.exe (GUI, no console) spawns pwsh with SW_HIDE (0),
# suppressing the white console window flash that InteractiveToken tasks show on creation.
# =============================================================================
Write-Step "Step 19 - FolderSync-AuditFilter task (every 5 min, current user, VBS launcher)"

# Write the VBScript launcher (runs pwsh hidden at Win32 level, before window is created)
$vbsPath = 'C:\Sync\Config\audit_filter_launcher.vbs'
Set-Content -Path $vbsPath -Encoding ASCII -Value @'
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pwsh.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Sync\Config\audit_filter.ps1""", 0, False
'@
Write-OK "audit_filter_launcher.vbs written -> $vbsPath"

$userSid  = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskXml19 = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <TimeTrigger>
      <Repetition><Interval>PT5M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$currentUser</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT3M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"C:\Sync\Config\audit_filter_launcher.vbs" //B //NoLogo</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Unregister-ScheduledTask -TaskName "FolderSync-AuditFilter" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-AuditFilter" -Xml $taskXml19 -Force | Out-Null
Write-OK "Task FolderSync-AuditFilter registered ($currentUser / InteractiveToken, every 5 min)"

# =============================================================================
# STATE MANAGEMENT - start ecosystem if it was running before config
# =============================================================================
if ($wasRunning) {
    Write-Step "Restarting ecosystem (was running before config)"
    & powershell.exe -ExecutionPolicy Bypass -File "$scriptDir\start_ecosystem.ps1"
} else {
    # Write stopped state explicitly
    'stopped' | Set-Content -LiteralPath $StateFile -Encoding UTF8
    Write-OK "Ecosystem left in stopped state (was stopped before config)"
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup Complete - Full Ecosystem + Security Hardening" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Applied:" -ForegroundColor White
Write-Host "  Step  1 - Firewall log read permissions" -ForegroundColor Gray
Write-Host "  Step  2 - run_mirror.bat with /E flag (no delete mirroring)" -ForegroundColor Gray
Write-Host "  Step  3 - cloud_sync.ps1 with firewall self-healing + 3-phase ACL (7d retention)" -ForegroundColor Gray
Write-Host "  Step  4 - ACL: root(folder-only), Config+Logs+Evidence(recursive), .git liberated, Mirror unmanaged" -ForegroundColor Gray
Write-Host "  Step  5 - DailySecurityCheck v8 + FolderSync-DailyCheck task + shortcut" -ForegroundColor Gray
Write-Host "  Step  6 - Remote access disabled (RDP/WinRM/SMB2/RemoteRegistry)" -ForegroundColor Gray
Write-Host "  Step  7 - Account lockout (5 attempts, 30 min)" -ForegroundColor Gray
Write-Host "  Step  8 - Screen auto-lock (5 min)" -ForegroundColor Gray
Write-Host "  Step  9 - Firewall logging -> C:\Sync\Logs\firewall.log" -ForegroundColor Gray
Write-Host "  Step 10 - FolderSync-CloudBackup task (SYSTEM)" -ForegroundColor Gray
Write-Host "  Step 11 - FolderSync-Watchdog task REMOVED (NSSM service is canonical, no duplicate)" -ForegroundColor Gray
Write-Host "  Step 12 - FolderSyncWatchdog NSSM service (installed, not started)" -ForegroundColor Gray
Write-Host "  Step 13 - FolderSyncAuditor NSSM service (installed, not started)" -ForegroundColor Gray
Write-Host "  Step 14 - Startup registry: RealTimeSync + Yawcam + YawcamMonitor + YawcamCam2Relay" -ForegroundColor Gray
Write-Host "  Step 15 - Malicious firewall rules removed (B2 block rules)" -ForegroundColor Gray
Write-Host "  Step 16 - File system auditing (SACL on Bois folder)" -ForegroundColor Gray
Write-Host "  Step 16b- SACL on Config\+Evidence\+.git\ + 512 MB Security log" -ForegroundColor Gray
Write-Host "  Step 17 - FolderSync-GitCommitLogs task (daily 23:30)" -ForegroundColor Gray
Write-Host "  Step 18 - FolderSync-PowerCheck task (SYSTEM, hourly + AtLogon + AtBoot)" -ForegroundColor Gray
Write-Host "  Step 18b- Power settings applied (Balanced plan, USB Suspend disabled)" -ForegroundColor Gray
Write-Host "  Step 19 - FolderSync-AuditFilter task (current user, VBS launcher - no window flash)" -ForegroundColor Gray
Write-Host ""
Write-Host "Pending (manual - requires web UI or physical access):" -ForegroundColor Yellow
Write-Host "  - B2 Lifecycle Rules (versioning) via backblaze.com" -ForegroundColor Yellow
Write-Host "  - BIOS password on Acer Nitro 5" -ForegroundColor Yellow
Write-Host "  - Windows Hello PIN (resolve via Microsoft account portal)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Ecosystem control:" -ForegroundColor Cyan
Write-Host "  Start : powershell -ExecutionPolicy Bypass -File C:\Sync\Config\start_ecosystem.ps1" -ForegroundColor Cyan
Write-Host "  Stop  : powershell -ExecutionPolicy Bypass -File C:\Sync\Config\stop_ecosystem.ps1" -ForegroundColor Cyan
Write-Host "  Health: /project:health" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER to close"

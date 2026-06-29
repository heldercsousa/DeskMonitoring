#Requires -RunAsAdministrator
param(
    [switch]$NoWait = $false
)
# =============================================================================
# setup_update.ps1 v3
# Centralized setup for FolderSync Ecosystem + Security Hardening
# Replaces setup_all.ps1. Adds .ecosystem_state awareness:
#   - Stops ecosystem before reconfiguring if currently running
#   - Restarts after config if it was running before
# Run as Administrator from C:\Sync\Config\
#
# Parameters:
#   -NoWait    Skip the final "Press ENTER to close" prompt (for automated pipelines)
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
# STEP 3 - Update cloud_sync_helderTest.ps1 with self-healing firewall + 3-phase ACL
# =============================================================================
Write-Step "Step 3 - Update cloud_sync_helderTest.ps1 (firewall self-healing + 3-phase ACL protection)"
$cloudSyncPs1 = "C:\Sync\Config\cloud_sync_helderTest.ps1"
Set-Content -Path $cloudSyncPs1 -Encoding UTF8 -Value @'
# cloud_sync_helderTest.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-06-05 - T050: add Import-Module Security for SYSTEM PS5 ACL fix

Add-Type -AssemblyName System.Security
Import-Module Microsoft.PowerShell.Security -ErrorAction SilentlyContinue

$Rclone             = 'C:\Tools\Rclone\rclone.exe'
$Config             = 'C:\Sync\Config\rclone.conf'
$Source             = 'C:\Users\helde\Repos\Bois'
$Remote             = 'cloudsync:helder-sync-mirror'
$Mirror             = 'C:\Sync\Mirror'
$LogDir             = 'C:\Sync\Logs\cloud_sync'
$Log                = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror   = 7
$DaysToKeepLogs     = 30
$SyncFailedSentinel = 'C:\Sync\Config\.sync_failed'
$LastSyncOkFile     = 'C:\Sync\Config\.last_sync_ok'

# Known malicious firewall rules that block Backblaze B2 sync
$MaliciousFirewallRules = @(
    'Block 104.153.233.180',
    'Block 149.137.142.15'
)

$B2CredsFile = 'C:\Sync\Config\b2_creds.dpapi'

function Load-B2Credentials {
    if (-not (Test-Path $B2CredsFile)) {
        Write-SyncLog "SYNC-FAIL  b2_creds.dpapi not found - run store_b2_creds.ps1 to migrate credentials"
        exit 1
    }
    try {
        $base64    = Get-Content -LiteralPath $B2CredsFile -Raw -Encoding ASCII
        $encrypted = [Convert]::FromBase64String($base64.Trim())
        $jsonBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        $json    = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
        $creds   = $json | ConvertFrom-Json
        $env:RCLONE_CONFIG_CLOUDSYNC_ACCOUNT = $creds.account
        $env:RCLONE_CONFIG_CLOUDSYNC_KEY     = $creds.key
    } catch {
        Write-SyncLog "SYNC-FAIL  Failed to decrypt b2_creds.dpapi: $($_.Exception.Message)"
        exit 1
    }
}

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
# INIT - Load B2 credentials from DPAPI-encrypted blob
# Sets RCLONE_CONFIG_CLOUDSYNC_ACCOUNT / _KEY env vars
# ============================================================
Load-B2Credentials

# ============================================================
# T030 - B2 lag alert: warn if last successful sync is stale
# ============================================================
if (Test-Path $LastSyncOkFile) {
    $lastOk = [datetime](Get-Content -LiteralPath $LastSyncOkFile -Raw).Trim()
    $lagMinutes = [math]::Round(((Get-Date) - $lastOk).TotalMinutes, 1)
    if ($lagMinutes -gt 15) {
        Write-SyncLog "B2-LAG-ALERT  Last successful sync was $lagMinutes minutes ago (threshold: 15)"
    }
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
Write-OK "cloud_sync_helderTest.ps1 updated (self-healing firewall + 3-phase ACL protection)"

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
Write-OK "C:\Sync\Mirror - no folder ACL (cloud_sync_helderTest.ps1 manages per-file ACLs)"

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
        -Argument '-NoWindow -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync_helderTest.ps1'
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
# STEP 16a2 - Process creation auditing (event 4688 - identifies parent of any process)
# =============================================================================
Write-Step "Step 16a2 - Enable process creation auditing (event 4688)"
auditpol /set /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" /success:enable | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-OK "Process creation auditing enabled - spawned processes logged as event 4688"
} else {
    Write-Warn "auditpol failed - run manually: auditpol /set /subcategory:`"{0CCE922B-69AE-11D9-BED3-505054503030}`" /success:enable"
}

# =============================================================================
# STEP 16a3 - Scheduled-task change auditing (events 4698-4702 - task create/delete/enable/disable)
# =============================================================================
Write-Step "Step 16a3 - Enable scheduled-task change auditing (events 4698-4702)"
auditpol /set /subcategory:"{0CCE9227-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-OK "Task-change auditing enabled - task disable/delete logged as event 4701/4699/4702"
} else {
    Write-Warn "auditpol failed - run manually: auditpol /set /subcategory:`"{0CCE9227-69AE-11D9-BED3-505054503030}`" /success:enable /failure:enable"
}

# =============================================================================
# STEP 16a4 - Firewall rule-change auditing (events 4946-4950/5025 - rule add/modify/delete, setting/service)
# =============================================================================
Write-Step "Step 16a4 - Enable firewall rule-change auditing (events 4946-4950/5025)"
# Touch the firewall-expected sentinel so auditor.ps1 treats any firewall change this
# setup run triggers as [FW-CHANGE] INFO (own script) rather than [FIREWALL-TAMPER].
try { Set-Content -LiteralPath 'C:\Sync\Config\.fw_expected' -Value (Get-Date -Format 'o') -ErrorAction SilentlyContinue } catch {}
auditpol /set /subcategory:"{0CCE9232-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-OK "Firewall-change auditing enabled - rule add/modify/delete logged as event 4946/4947/4948, setting/service as 4950/5025"
} else {
    Write-Warn "auditpol failed - run manually: auditpol /set /subcategory:`"{0CCE9232-69AE-11D9-BED3-505054503030}`" /success:enable /failure:enable"
}

# =============================================================================
# STEP 16a5 - Registry auditing on guarded power/Run keys (T075 - events 4657/4663)
# Enables the Registry audit subcategory and SACLs the USB Selective Suspend / sleep
# power keys + autostart Run keys, so a write fires 4657/4663. auditor.ps1 then
# correlates against Sysmon Event 1 (T076, fallback 4688) to unmask the true caller.
# =============================================================================
Write-Step "Step 16a5 - Enable registry auditing on guarded power/Run keys (events 4657/4663)"
$regAuditScript = "C:\Sync\Config\enable_registry_auditing.ps1"
if (Test-Path $regAuditScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $regAuditScript
    Write-OK "Registry auditing (subcategory + SACL) configured on power/Run keys"
} else {
    Write-Warn "enable_registry_auditing.ps1 not found - run manually when available"
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
# STEP 17 - FolderSync-GitCommitLogs task (current user, hourly off-box push)
# T077 interim mitigation: tighten Logs/+Evidence/ off-box (git push) cadence
# from daily to hourly so tamper evidence reaches GitHub within ~1h, until a
# real WEF collector host exists.
# =============================================================================
Write-Step "Step 17 - FolderSync-GitCommitLogs task (hourly off-box push)"
$action17   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auto_commit_logs.ps1'
$trigger17  = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([System.TimeSpan]::MaxValue)
$settings17 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal17= New-ScheduledTaskPrincipal -UserId $currentUser -LogonType S4U -RunLevel Highest
Unregister-ScheduledTask -TaskName "FolderSync-GitCommitLogs" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-GitCommitLogs" -Action $action17 -Trigger $trigger17 -Settings $settings17 -Principal $principal17 -Force | Out-Null
Write-OK "Task FolderSync-GitCommitLogs registered ($currentUser, hourly off-box push)"

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
      <Repetition><Interval>PT1H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
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
& powershell.exe -ExecutionPolicy Bypass -File "$scriptDir\fix_power_motion.ps1"
$powerExit = $LASTEXITCODE
if ($powerExit -eq 0) {
    Write-OK "Power settings applied (Balanced, USB Suspend off, sleep/hibernate/disk Never, unattended sleep timeout Never, power+sleep buttons & lid Do nothing)"
} else {
    Write-Fail "fix_power_motion.ps1 reported NON-COMPLIANT power settings (exit $powerExit)"
}

# Step 18c - Verify the sleep-critical settings actually landed. A locked-session
# sleep (unattended timeout) silently stopped recording before this was enforced
# (2026-06-17), so reinstall MUST confirm compliance rather than assume it.
Write-Step "Step 18c - Verify sleep-critical power compliance"
$active = (powercfg /getactivescheme) -join ' '
$schemeGuid = if ($active -match '([0-9a-fA-F-]{36})') { $Matches[1] } else { $null }
$powerCompliant = $true
$sleepChecks = @(
    @{ Sub='238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set='29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; Label='Sleep after' },
    @{ Sub='238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set='7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'; Label='Unattended sleep timeout' }
)
if ($schemeGuid) {
    foreach ($c in $sleepChecks) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$schemeGuid\$($c.Sub)\$($c.Set)"
        $v = if (Test-Path $p) { Get-ItemProperty -Path $p -ErrorAction SilentlyContinue } else { $null }
        if ($null -eq $v -or $v.ACSettingIndex -ne 0 -or $v.DCSettingIndex -ne 0) {
            $acv = if ($v) { $v.ACSettingIndex } else { 'absent(default)' }
            $dcv = if ($v) { $v.DCSettingIndex } else { 'absent(default)' }
            Write-Fail "$($c.Label) NON-COMPLIANT: AC=$acv DC=$dcv (expected 0) - sleep can still interrupt recording"
            $powerCompliant = $false
        } else {
            Write-OK "$($c.Label) = Never (AC + DC)"
        }
    }
} else {
    Write-Fail "Could not resolve active power scheme GUID - cannot verify sleep compliance"
    $powerCompliant = $false
}
if (-not $powerCompliant) {
    Write-Fail "POWER COMPLIANCE CHECK FAILED - rerun fix_power_motion.ps1 as Administrator and re-verify before relying on motion capture"
}

# Create motion_videos symlink for yawcam_monitor_v4.ps1
Write-Step "Step 18c - Motion videos symlink (C:\TEMP\motion_videos -> Bois)"
$symlinkPath = "C:\TEMP\motion_videos"
if (-not (Test-Path $symlinkPath)) {
    New-Item -ItemType SymbolicLink -Path $symlinkPath -Target "C:\Users\helde\Repos\Bois" -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $symlinkPath) { Write-OK "Symlink created: $symlinkPath" }
    else { Write-Warn "Symlink creation failed - create manually: mklink /D C:\TEMP\motion_videos C:\Users\helde\Repos\Bois" }
} else {
    Write-OK "Symlink already exists: $symlinkPath"
}

# =============================================================================
# STEP 18d - B2 credential DPAPI migration (T048)
# Encrypts B2 account+key with LocalMachine DPAPI for SYSTEM-accessible storage.
# Skip if b2_creds.dpapi already exists.
# =============================================================================
Write-Step "Step 18d - B2 credentials: migrate to DPAPI (b2_creds.dpapi)"
$B2CredsFile = 'C:\Sync\Config\b2_creds.dpapi'
if (-not (Test-Path $B2CredsFile)) {
    Write-Warn "b2_creds.dpapi not found - run store_b2_creds.ps1 manually before first sync"
    Write-Host "          Command: powershell -ExecutionPolicy Bypass -File 'C:\Sync\Config\store_b2_creds.ps1'" -ForegroundColor Yellow
} else {
    Write-OK "b2_creds.dpapi exists - B2 credentials stored securely"
}

# =============================================================================
# STEP 18e - CAM-2 credential DPAPI migration (T049)
# Encrypts Tapo C100 user+pass+ip with CurrentUser DPAPI.
# Skip if cam2_creds.dpapi already exists.
# Note: must be run as Helder user (CurrentUser scope) — SYSTEM cannot create this.
# =============================================================================
Write-Step "Step 18e - CAM-2 credentials: migrate to DPAPI (cam2_creds.dpapi)"
$Cam2CredsFile = 'C:\Sync\Config\cam2_creds.dpapi'
if (-not (Test-Path $Cam2CredsFile)) {
    Write-Warn "cam2_creds.dpapi not found - run migrate_cam2_creds.ps1 as Helder before starting cam2 relay"
    Write-Host "          Command: powershell -ExecutionPolicy Bypass -File 'C:\Sync\Config\migrate_cam2_creds.ps1'" -ForegroundColor Yellow
} else {
    Write-OK "cam2_creds.dpapi exists - CAM-2 credentials stored securely"
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
# STEP 20 - FolderSync-ConfigGuard task (at logon, current user, hidden)
# Watches Config\cloud_sync_helderTest.ps1 and run_mirror.bat via FileSystemWatcher.
# Restores them from git HEAD the instant any process modifies them.
# Runs as a persistent background process (keep-alive loop inside the script).
# =============================================================================
Write-Step "Step 20 - FolderSync-ConfigGuard task (at logon, current user, hidden)"

$userSid20 = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskXml20 = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$currentUser</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userSid20</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>pwsh.exe</Command>
      <Arguments>-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Sync\Config\config_guard.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Unregister-ScheduledTask -TaskName "FolderSync-ConfigGuard" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "FolderSync-ConfigGuard" -Xml $taskXml20 -Force | Out-Null
Write-OK "Task FolderSync-ConfigGuard registered ($currentUser / InteractiveToken, at logon, no time limit)"

# =============================================================================
# STEP 20b - Export defensive task definitions to version-controlled backups
# =============================================================================
# config_guard.ps1 re-registers a defensive task from these XML backups if it is
# found deleted (the 2026-06-18 incident disabled tasks; a delete is the worse case
# and file-level Deny-Delete ACLs do NOT stop it - the parent Tasks folder grants
# Administrators "delete child"). Backups live under Config\ (Deny-Delete protected,
# git-tracked) so they survive and are restorable. Re-export here so the backups
# always match the just-registered definitions.
Write-Step "Step 20b - Export defensive task definitions to Config\task_backups\"
$taskBackupDir = "C:\Sync\Config\task_backups"
New-Item -ItemType Directory -Force -Path $taskBackupDir | Out-Null
$defensiveTasks = @('FolderSync-CloudBackup','FolderSync-DailyCheck','FolderSync-ConfigGuard',
                    'FolderSync-AuditFilter','FolderSync-GitCommitLogs','FolderSync-PowerCheck')
foreach ($dt in $defensiveTasks) {
    if (Get-ScheduledTask -TaskName $dt -ErrorAction SilentlyContinue) {
        $xml = Export-ScheduledTask -TaskName $dt
        [System.IO.File]::WriteAllText((Join-Path $taskBackupDir "$dt.xml"), $xml, [System.Text.Encoding]::Unicode)
    }
}
Write-OK "Task definition backups exported ($($defensiveTasks.Count) tasks) - config_guard restores from these if a task is deleted"

# =============================================================================
# STEP 21 - Install / update Sysmon (SwiftOnSecurity config) (T076)
# =============================================================================
# Sysmon gives authoritative on-host process (Event ID 1), network (3) and DNS (22)
# telemetry that feeds the T075 correlation rules and (once built) T077 off-box
# forwarding. The config lives in git (C:\Sync\Config\sysmonconfig.xml, ACL-locked)
# so it survives reinstall; the binary is staged under C:\Tools\Sysmon (downloaded
# from Sysinternals on first run if absent). Idempotent: if Sysmon is already
# installed we just push the current config (-c); otherwise we install it (-i).
# CAVEAT (T076 plan): Sysmon is NOT hardened against an admin attacker - its value
# is only realized once events are forwarded off-box (T077). On its own it can be
# blinded by the same resident process that disables tasks.
Write-Step "Step 21 - Install / update Sysmon (SwiftOnSecurity config)"
$sysmonDir = "C:\Tools\Sysmon"
$sysmonExe = "$sysmonDir\Sysmon64.exe"
$sysmonCfg = "C:\Sync\Config\sysmonconfig.xml"
$sysmonLog = "Microsoft-Windows-Sysmon/Operational"
if (-not (Test-Path -LiteralPath $sysmonCfg)) {
    Write-Fail "Sysmon config not found at $sysmonCfg - cannot install (restore from git)"
} else {
    try {
        New-Item -ItemType Directory -Force -Path $sysmonDir | Out-Null
        if (-not (Test-Path -LiteralPath $sysmonExe)) {
            Write-Host "  ..   Sysmon64.exe absent - downloading from Sysinternals" -ForegroundColor Gray
            $zip = Join-Path $env:TEMP "Sysmon.zip"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
            Expand-Archive -LiteralPath $zip -DestinationPath $sysmonDir -Force
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path -LiteralPath $sysmonExe)) {
            Write-Fail "Sysmon64.exe still missing after download attempt - install manually"
        } else {
            $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
            if ($svc) {
                & $sysmonExe -c $sysmonCfg | Out-Null
                Write-OK "Sysmon already installed - config reapplied from sysmonconfig.xml"
            } else {
                & $sysmonExe -accepteula -i $sysmonCfg | Out-Null
                Write-OK "Sysmon installed (-accepteula -i) with SwiftOnSecurity config"
            }
            $ch = Get-WinEvent -ListLog $sysmonLog -ErrorAction SilentlyContinue
            if ($ch -and $ch.IsEnabled) {
                Write-OK "Event channel '$sysmonLog' present and enabled (Event ID 1/3/22 will flow here)"
            } else {
                Write-Warn "Event channel '$sysmonLog' not found/enabled yet - re-check after a process spawns"
            }
        }
    } catch {
        Write-Fail "Sysmon install/update failed: $($_.Exception.Message)"
    }
}

# =============================================================================
# STEP 22 - Autoruns persistence baseline + daily diff task (T079)
# =============================================================================
# autorunsc captures the full autostart surface (Run keys, services, drivers,
# scheduled tasks, WMI, Winlogon, codecs). check_autoruns.ps1 diffs it against a
# stored baseline (Config\autoruns\baseline.csv) and logs new/changed persistence
# as [AUTORUN-DELTA] + Evidence + alert. Feeds T070/T072. EVIDENCE-ONLY (live OS) -
# corroborate suspicious deltas against an offline mount (T082). Runs as SYSTEM
# daily for full HKLM/service/signature coverage.
Write-Step "Step 22 - FolderSync-AutoRunsCheck task + baseline capture (T079)"
$autorunsScript = "C:\Sync\Config\check_autoruns.ps1"
if (Test-Path $autorunsScript) {
    $action22   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\check_autoruns.ps1'
    $trigger22  = New-ScheduledTaskTrigger -Daily -At "08:45"
    $settings22 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -RunOnlyIfNetworkAvailable:$false
    $principal22= New-ScheduledTaskPrincipal -UserId "S-1-5-18" -RunLevel Highest
    Unregister-ScheduledTask -TaskName "FolderSync-AutoRunsCheck" -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName "FolderSync-AutoRunsCheck" -Action $action22 -Trigger $trigger22 -Settings $settings22 -Principal $principal22 -Force | Out-Null
    Write-OK "Task FolderSync-AutoRunsCheck registered (SYSTEM, daily 08:45)"

    # Capture the baseline now if it does not exist yet (downloads autorunsc on first run)
    if (-not (Test-Path "C:\Sync\Config\autoruns\baseline.csv")) {
        Write-Host "  ..   Capturing initial autoruns baseline (downloads autorunsc if absent)" -ForegroundColor Gray
        & powershell.exe -ExecutionPolicy Bypass -File $autorunsScript | Out-Null
        if (Test-Path "C:\Sync\Config\autoruns\baseline.csv") {
            Write-OK "Autoruns baseline captured -> Config\autoruns\baseline.csv (commit it to git)"
        } else {
            Write-Warn "Baseline not captured - check C:\Sync\Logs\security\autoruns_*.log (autorunsc download may have failed)"
        }
    } else {
        Write-OK "Autoruns baseline already present - left unchanged (re-baseline via check_autoruns.ps1 -UpdateBaseline)"
    }
} else {
    Write-Warn "check_autoruns.ps1 not found - run manually when available"
}

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
Write-Host "  Step  3 - cloud_sync_helderTest.ps1 with firewall self-healing + 3-phase ACL (7d retention)" -ForegroundColor Gray
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
Write-Host "  Step 16a5- Registry auditing on power/Run keys (events 4657/4663, T075)" -ForegroundColor Gray
Write-Host "  Step 16b- SACL on Config\+Evidence\+.git\ + 512 MB Security log" -ForegroundColor Gray
Write-Host "  Step 17 - FolderSync-GitCommitLogs task (hourly off-box push)" -ForegroundColor Gray
Write-Host "  Step 18 - FolderSync-PowerCheck task (SYSTEM, hourly + AtLogon + AtBoot)" -ForegroundColor Gray
Write-Host "  Step 18b- Power settings applied (Balanced plan, USB Suspend disabled)" -ForegroundColor Gray
Write-Host "  Step 18d- B2 credentials: checked/warned if b2_creds.dpapi missing" -ForegroundColor Gray
Write-Host "  Step 18e- CAM-2 credentials: checked/warned if cam2_creds.dpapi missing" -ForegroundColor Gray
Write-Host "  Step 19 - FolderSync-AuditFilter task (current user, VBS launcher - no window flash)" -ForegroundColor Gray
Write-Host "  Step 20 - FolderSync-ConfigGuard task (current user, at logon, watches Config\ for tampering)" -ForegroundColor Gray
Write-Host "  Step 21 - Sysmon installed/updated (SwiftOnSecurity config) - process/network/DNS telemetry" -ForegroundColor Gray
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
if (-not $NoWait) {
    Read-Host "Press ENTER to close"
}

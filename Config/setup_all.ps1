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
# Protege cada arquivo que ainda nao atingiu 7 dias de idade
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop

                # Verificar se ja tem ACL Deny Delete (evitar duplicado)
                $hasDeny = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }

                if (-not $hasDeny) {
                    # Aplicar ACL Deny Delete
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
                # Silencioso - arquivo pode ter sido deletado/movido
            }
        }
}

# ============================================================
# FASE 1 - Remover ACL Deny Delete de arquivos >= 7 dias
# Remove protecao de arquivos que atingiram 7 dias
# CRITICO: Fazer ANTES de tentar deletar (Fase 2)
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)

    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName -ErrorAction Stop

                # Encontrar regras Deny Delete de "Everyone"
                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq 'Deny' -and
                    $_.IdentityReference -like '*Everyone*' -and
                    $_.FileSystemRights -like '*Delete*'
                }

                if ($denyRules) {
                    # Remover cada regra Deny Delete encontrada
                    foreach ($rule in $denyRules) {
                        $acl.RemoveAccessRule($rule) | Out-Null
                    }
                    Set-Acl $_.FullName $acl -ErrorAction Stop
                }
            } catch {
                # Silencioso - arquivo pode ter sido deletado
            }
        }
}

# ============================================================
# FASE 2 - Deletar arquivos >= 7 dias
# Agora ACL foi removido em FASE 1, delete pode executar sem ERROR 5
# ============================================================
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Cleanup de pastas vazias (apos deletar arquivos)
    Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
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

Write-SyncLog "SYNC-END  Cloud sync run complete"
'@
Write-OK "cloud_sync.ps1 updated (self-healing firewall + 3-phase ACL protection)"

# =============================================================================
# STEP 4 - SINGLE AUTHORITY: all Deny Delete ACL rules for C:\Sync
# =============================================================================
# This is the only place that sets ACL rules. No other script defines ACLs.
# Canonical table:
#   C:\Sync (root)    Deny Delete folder-only (no inherit)  -- prevent root deletion
#   C:\Sync\Config    Deny Delete + Children (full inherit)  -- scripts tamper-proof
#   C:\Sync\Logs      Deny Delete + Children (full inherit)  -- logs tamper-proof
#   C:\Sync\Evidence  Deny Delete + Children (full inherit)  -- forensic tamper-proof
#   C:\Sync\.git      NONE (liberated via icacls /T)         -- git needs full write
#   C:\Sync\Mirror    NONE at folder level                   -- cloud_sync.ps1 manages per-file ACLs
# =============================================================================
Write-Step "Step 4 - Apply all Deny Delete ACL rules (single authority)"

$sidEveryone = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')

function Set-DenyDeleteFull($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone, 'Delete,DeleteSubdirectoriesAndFiles',
        'ContainerInherit,ObjectInherit', 'None', 'Deny')
    $acl.RemoveAccessRule($rule) | Out-Null   # no-op if absent; prevents duplicate stacking on reruns
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

function Set-DenyDeleteFolderOnly($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone, 'Delete', 'None', 'None', 'Deny')
    $acl.RemoveAccessRule($rule) | Out-Null   # no-op if absent; prevents duplicate stacking on reruns
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
        Write-Fail "C:\Sync\.git still has Deny rules — investigate: $gitDeny"
    } else {
        Write-OK "C:\Sync\.git verified clean (zero Deny rules)"
    }
}
Write-OK "C:\Sync\Mirror - no folder ACL (cloud_sync.ps1 manages per-file ACLs)"

# =============================================================================
# STEP 5 - DailySecurityCheck v8
# Scripts live in C:\Sync\Config\ (no copy to Documents needed)
# Task runs without -NonInteractive so the MessageBox dialog can appear
# =============================================================================
Write-Step "Step 5 - Install DailySecurityCheck v8"

# Remove legacy tasks that used the old Documents path
foreach ($oldName in @("Verificacao Automatica de Seguranca", "Verificação Automática de Segurança")) {
    if (Get-ScheduledTask -TaskName $oldName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $oldName -Confirm:$false -ErrorAction SilentlyContinue
        Write-OK "Removed legacy task: $oldName"
    }
}

# Register canonical task pointing to C:\Sync\Config\ (no -NonInteractive so dialog works)
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
# NOTE: Always re-register to ensure PowerShell (not .bat) and correct -NoWindow flag
# =============================================================================
Write-Step "Step 10 - FolderSync-CloudBackup task (SYSTEM, every 5 min)"
$existingBackup = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue

# Check if task exists and has CORRECT arguments (PowerShell with -NoWindow)
$needsRecreate = $false
if ($existingBackup) {
    $currentArgs = $existingBackup.Actions[0].Arguments
    $currentExec = $existingBackup.Actions[0].Execute
    
    # If running .bat or missing -NoWindow, force recreate
    if ($currentExec -like "*.bat" -or $currentArgs -notlike "*-NoWindow*") {
        Write-Warn "Task exists but uses .bat or missing -NoWindow - will recreate"
        $needsRecreate = $true
    }
}

if (-not $existingBackup -or $needsRecreate) {
    # Remove old task if it exists
    if ($existingBackup) {
        Unregister-ScheduledTask -TaskName "FolderSync-CloudBackup" -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    
    # Create with POWERSHELL (not .bat) and -NoWindow flag
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
# STEP 11 - Register FolderSync-Watchdog task (current user, interactive)
# NOTE: MUST run as current user - SYSTEM cannot launch RealTimeSync GUI
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
    & $nssm set FolderSyncAuditor AppStdout      'C:\Sync\Logs\auditor_svc.log'
    & $nssm set FolderSyncAuditor AppStderr      'C:\Sync\Logs\auditor_svc_err.log'
    & $nssm set FolderSyncAuditor AppRotateFiles  1
    & $nssm set FolderSyncAuditor AppRotateBytes  2097152
    & $nssm set FolderSyncAuditor AppRestartDelay 30000
    Start-Service FolderSyncAuditor -ErrorAction SilentlyContinue
    $s = Get-Service FolderSyncAuditor -ErrorAction SilentlyContinue
    Write-OK "FolderSyncAuditor service: $($s.Status)"
} else {
    Write-Warn "NSSM not found - skipped FolderSyncAuditor"
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
# STEP 15 - Remove any known malicious firewall rules (attacker sabotage)
# Add new B2 IPs here whenever the attacker changes their approach
# =============================================================================
Write-Step "Step 15 - Remove malicious firewall rules (B2 block rules)"
$maliciousRules = @(
    "Block 104.153.233.180",   # Backblaze B2 API IP - blocked by attacker 2026-03-06
    "Block 149.137.142.15"     # Backblaze B2 API IP - blocked by attacker 2026-03-06
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
# NOTE: ACL (Deny Delete) rules are handled exclusively in Step 4.
# This step only configures SACL (Windows audit policy + audit rules).
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
Write-Host "  Step  5 - DailySecurityCheck v8 + FolderSync-DailyCheck task + shortcut (C:\Sync\Config\)" -ForegroundColor Gray
Write-Host "  Step  6 - Remote access disabled (RDP/WinRM/SMB2/RemoteRegistry)" -ForegroundColor Gray
Write-Host "  Step  7 - Account lockout (5 attempts, 30 min)" -ForegroundColor Gray
Write-Host "  Step  8 - Screen auto-lock (5 min)" -ForegroundColor Gray
Write-Host "  Step  9 - Firewall logging -> C:\Sync\Logs\firewall.log" -ForegroundColor Gray
Write-Host "  Step 10 - FolderSync-CloudBackup task (SYSTEM)" -ForegroundColor Gray
Write-Host "  Step 11 - FolderSync-Watchdog task (current user)" -ForegroundColor Gray
Write-Host "  Step 12 - FolderSyncWatchdog NSSM service" -ForegroundColor Gray
Write-Host "  Step 13 - FolderSyncAuditor NSSM service" -ForegroundColor Gray
Write-Host "  Step 14 - RealTimeSync startup registry + started" -ForegroundColor Gray
Write-Host "  Step 15 - Malicious firewall rules removed (B2 block rules)" -ForegroundColor Gray
Write-Host "  Step 16 - File system auditing (SACL on Bois folder)" -ForegroundColor Gray
Write-Host ""
Write-Host "Pending (manual - requires web UI or physical access):" -ForegroundColor Yellow
Write-Host "  - B2 Lifecycle Rules (versioning) via backblaze.com" -ForegroundColor Yellow
Write-Host "  - BIOS password on Acer Nitro 5" -ForegroundColor Yellow
Write-Host "  - Windows Hello PIN (resolve via Microsoft account portal)" -ForegroundColor Yellow
Write-Host "  - C100 RTSP integration" -ForegroundColor Yellow
Write-Host ""
Write-Host "Validate with:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File C:\Sync\Config\check_status.ps1" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER to close"
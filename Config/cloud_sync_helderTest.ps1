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

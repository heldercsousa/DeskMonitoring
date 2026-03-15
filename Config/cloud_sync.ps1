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
$Log              = "$LogDir\cloud_sync\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
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
# STEP 3 - Detect blocking patterns in rclone output
# Handles: IP firewall blocks AND DNS-level sabotage
# If detected: attempt repair, retry sync once
# ============================================================
$firewallBlocked = $false
$dnsBlocked = $false

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
} elseif ($rcloneOutput -match 'no such host|i/o timeout|dial tcp.*lookup') {
    # DNS-level attack: rogue DHCP server serving 127.0.0.1 as DNS (confirmed 2026-03-15)
    $dnsBlocked = $true
    Write-SyncLog "DNS-ATTACK-DETECT  Rclone reported DNS failure - possible rogue DNS/DHCP attack"

    # Check if Ethernet adapter has DHCP-assigned DNS (127.0.0.1 = rogue)
    $ethDns = (Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    Write-SyncLog "DNS-ATTACK-DETECT  Ethernet DNS: $($ethDns -join ', ')"

    # Test live resolution
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses('api.backblazeb2.com')
        Write-SyncLog "DNS-ATTACK-DETECT  api.backblazeb2.com resolves NOW: $($resolved -join ', ') - transient DNS issue"
    } catch {
        Write-SyncLog "DNS-ATTACK-DETECT  api.backblazeb2.com still FAILS to resolve - DNS attack may be active"
        Write-SyncLog "DNS-ATTACK-DETECT  Check: hosts file, Ethernet DNS settings, router DHCP config"
    }

    # Retry sync (DNS may have recovered if interface switched)
    Write-SyncLog "DNS-ATTACK-DETECT  Retrying sync after DNS diagnosis"
    $rcloneOutput2 = & $Rclone sync $Source $Remote `
        --config $Config `
        --log-file $Log `
        --log-level INFO `
        --transfers 4 `
        --checkers 8 `
        --fast-list 2>&1

    $rcloneExitCode = $LASTEXITCODE

    if ($LASTEXITCODE -eq 0) {
        Write-SyncLog "DNS-ATTACK-HEAL  Retry SUCCESS - sync completed after DNS recovery"
    } else {
        Write-SyncLog "DNS-ATTACK-FAIL  Retry FAILED (exit $LASTEXITCODE) - DNS still broken"
        Write-SyncLog "DNS-ATTACK-FAIL  Run: Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 1.1.1.1,8.8.8.8"
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

# 4. cloud_sync log rotation
Get-ChildItem -Path "$LogDir\cloud_sync" -Filter "cloud_sync_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. mirror log rotation
Get-ChildItem -Path "$LogDir\mirror" -Filter "mirror_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 6. security log rotation
foreach ($filter in @('security_audit_*.log','security_check_*.log','firewall_*.log')) {
    Get-ChildItem -Path "$LogDir\security" -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 7. file audit log rotation
Get-ChildItem -Path "$LogDir\audit" -Filter "file_audit_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 8. ecosystem log rotation
foreach ($filter in @('ecosystem_*.log','health_check_*.log')) {
    Get-ChildItem -Path "$LogDir\ecosystem" -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 9. camera log rotation
Get-ChildItem -Path "$LogDir\camera" -Filter "cam2_relay_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 10. firewall.log daily rotation - copy today's slice to dated file, truncate live log
$FwLog   = "$LogDir\security\firewall.log"
$FwDated = "$LogDir\security\firewall_$(Get-Date -Format 'yyyy-MM-dd').log"
if ((Test-Path $FwLog) -and -not (Test-Path $FwDated)) {
    Copy-Item $FwLog $FwDated -ErrorAction SilentlyContinue
    Clear-Content $FwLog -ErrorAction SilentlyContinue
    Write-SyncLog "FIREWALL-ROTATE  Archived to $FwDated"
}

Write-SyncLog "SYNC-END  Cloud sync run complete"

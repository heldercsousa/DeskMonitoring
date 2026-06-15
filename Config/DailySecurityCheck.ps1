# DailySecurityCheck.ps1 - v9
# Security detection: suspicious processes, firewall tampering, DNS/hosts poisoning,
# scheduled task integrity, B2 connectivity, Event Log audit, Run key persistence.
# Scheduled task: "FolderSync-DailyCheck" (daily at 09:00, runs as helde)

$logPath = "C:\Sync\Logs\security\security_check_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $logPath
}

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

$knownDevices = @{
    '192.168.0.1'   = 'Router Humax'
    '192.168.0.106' = 'Samsung TV'
    '192.168.0.109' = 'TP-Link C100 Cam'
    '192.168.0.152' = 'This machine (LAP)'
    '192.168.0.206' = 'Samsung S23 Ultra'
}

$b2IPs = @('104.153.233.180', '149.137.142.15')
$b2Host = 'api.backblazeb2.com'

$knownRunKeys = @(
    'Yawcam',
    'YawcamMonitor',
    'YawcamCam2Relay',
    'FolderSyncRealTime',
    'electron.app.Fing',
    'OneDrive',
    'Docker Desktop'
    # MicrosoftCopilotAutoLaunch_* matched below via wildcard
)

try {
    $locationPath       = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
    $suspiciousPatterns = @("AppMonitor", "CefView")

    $excludePatterns = @(
        "Mbam", "OneDrive", "Malware", "Windows", "Microsoft",
        "msedge", "PackageManager", "svchost", "RuntimeBroker",
        "SearchHost", "StartMenuExperienceHost", "ShellExperienceHost",
        "SystemSettings", "Explorer", "Defender", "SecurityHealth",
        "Update", "Store", "Xbox", "Gaming", "Cortana", "ActionsServer",
        "devenv", "VSCode", "Code", "copilot", "git", "node",
        "dotnet", "msbuild", "ServiceHub", "PerfWatson",
        "WindowsPackageManager"
    )

    $issues = 0

    Write-Log "SCAN-START  DailySecurityCheck v9"

    # -----------------------------------------------------------------------
    # [1] Suspicious processes
    # -----------------------------------------------------------------------
    Write-Step "[1] Suspicious processes"
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $name         = $_.ProcessName
        $isSuspicious = $false
        $isExcluded   = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $isSuspicious = $true; break } }
        if ($isSuspicious) {
            foreach ($e in $excludePatterns) { if ($name -like "*$e*") { $isExcluded = $true; break } }
        }
        $isSuspicious -and -not $isExcluded
    }

    if ($procs) {
        foreach ($proc in $procs) {
            $issues++
            $path    = if ($proc.Path) { $proc.Path } else { "Unknown" }
            $company = if ($proc.Company) { $proc.Company } else { "Unknown" }
            $signed  = "No"
            $signer  = "N/A"
            $risk    = "HIGH"
            $action  = "Investigate and consider terminating"
            if ($proc.Path -and (Test-Path $proc.Path)) {
                $sig = Get-AuthenticodeSignature -FilePath $proc.Path -ErrorAction SilentlyContinue
                if ($sig -and $sig.Status -eq "Valid") {
                    $signed = "Yes"
                    $signer = $sig.SignerCertificate.Subject -replace "CN=", "" -replace ",.*", ""
                }
            }
            $inProgramFiles = $path -like "*Program Files*"
            if ($signed -eq "Yes" -and $inProgramFiles) {
                $risk   = "LOW"
                $action = "Add to exclusions if legitimate"
            } elseif ($signed -eq "Yes" -and -not $inProgramFiles) {
                $risk   = "MEDIUM"
                $action = "Verify path and company before cleanup"
            }
            Write-Log "ALERT  [SuspiciousProcess] Name=$($proc.ProcessName) PID=$($proc.Id) Path=$path Company=$company Signed=$signed Risk=$risk Action=$action"
            Write-Fail "Suspicious process: $($proc.ProcessName) | Risk=$risk | Path=$path"
        }
    } else {
        Write-OK "No suspicious processes"
    }

    # -----------------------------------------------------------------------
    # [2] Registry location entries
    # -----------------------------------------------------------------------
    Write-Step "[2] Registry location access entries"
    $subApps = Get-ChildItem -Path $locationPath -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.PSChildName
        $hit  = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $hit = $true; break } }
        $hit
    }
    if ($subApps) {
        $issues++
        foreach ($r in $subApps) {
            Write-Log "ALERT  [RegistryLocation] Entry=$($r.PSChildName)"
            Write-Fail "Suspicious registry location entry: $($r.PSChildName)"
        }
    } else {
        Write-OK "No suspicious registry location entries"
    }

    # -----------------------------------------------------------------------
    # [3] Remote access tools running
    # -----------------------------------------------------------------------
    Write-Step "[3] Remote access tools"
    $remoteTools = @('AnyDesk', 'VNCViewer', 'vncserver', 'ScreenConnect', 'Ammyy', 'RemoteUtilities', 'Rustdesk')
    foreach ($tool in $remoteTools) {
        $p = Get-Process $tool -ErrorAction SilentlyContinue
        if ($p) {
            $issues++
            Write-Log "ALERT  [RemoteTool] Name=$tool PID=$($p.Id -join ',')"
            Write-Fail "Remote access tool running: $tool (PID $($p.Id -join ','))"
        }
    }

    # -----------------------------------------------------------------------
    # [4] Suspicious listening ports
    # -----------------------------------------------------------------------
    Write-Step "[4] Suspicious listening ports"
    $suspiciousPorts = @(4444, 5900, 5901, 1080, 8443, 31337, 12345, 54321, 9999, 6666)
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $listening) {
        if ($conn.LocalPort -in $suspiciousPorts) {
            $issues++
            $proc     = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
            $procPath = if ($proc -and $proc.Path) { $proc.Path } else { "Unknown" }
            Write-Log "ALERT  [SuspiciousPort] Port=$($conn.LocalPort) PID=$($conn.OwningProcess) Process=$procName Path=$procPath"
            Write-Fail "Suspicious port $($conn.LocalPort) listening - $procName ($procPath)"
        }
    }
    if ($issues -eq 0) { Write-OK "No suspicious ports open" }

    # -----------------------------------------------------------------------
    # [5] Unknown devices on network (ARP table)
    # -----------------------------------------------------------------------
    Write-Step "[5] Unknown network devices (ARP)"
    try {
        $arpOutput = arp -a 2>$null
        $arpLines  = $arpOutput | Where-Object { $_ -match '^\s+\d+\.\d+\.\d+\.\d+' }
        foreach ($line in $arpLines) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([\w-]+)\s+(\w+)') {
                $ip   = $Matches[1]
                $type = $Matches[3]
                if ($type -eq 'dynamic') {
                    if (-not $knownDevices.ContainsKey($ip)) {
                        $issues++
                        Write-Log "ALERT  [UnknownDevice] IP=$ip"
                        Write-Warn "Unknown device on network: $ip"
                    }
                }
            }
        }
    } catch {}

    # -----------------------------------------------------------------------
    # [6] FolderSync services status
    # -----------------------------------------------------------------------
    Write-Step "[6] FolderSync services"
    $watchedSvcs = @('FolderSyncAuditor', 'FolderSyncWatchdog')
    foreach ($svc in $watchedSvcs) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne 'Running') {
            $issues++
            Write-Log "ALERT  [ServiceStopped] Service=$svc Status=$($s.Status) StartType=$($s.StartType)"
            Write-Fail "Service not running: $svc (Status=$($s.Status) StartType=$($s.StartType))"
        } elseif ($s) {
            Write-OK "$svc is running"
        } else {
            $issues++
            Write-Log "ALERT  [ServiceMissing] Service=$svc"
            Write-Fail "Service not found: $svc"
        }
    }

    # -----------------------------------------------------------------------
    # [10] Firewall tamper detection (B2 outbound BLOCK rules)
    # -----------------------------------------------------------------------
    Write-Step "[10] Firewall tamper detection"
    $fwRules = Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' }
    $badRules = @()
    foreach ($rule in $fwRules) {
        $filter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
        if ($filter) {
            $addrs = @($filter.RemoteAddress)
            foreach ($b2ip in $b2IPs) {
                if ($addrs -contains $b2ip -or $addrs -contains "$b2ip/32") {
                    $badRules += $rule.DisplayName
                }
            }
            if ($addrs -contains $b2Host) { $badRules += $rule.DisplayName }
        }
    }
    if ($badRules.Count -gt 0) {
        $issues++
        foreach ($r in ($badRules | Select-Object -Unique)) {
            Write-Log "ALERT  [FirewallTamper] Rule=`"$r`" blocks B2 outbound"
            Write-Fail "Firewall tamper: outbound BLOCK rule targeting B2 - `"$r`""
        }
    } else {
        Write-OK "No outbound BLOCK rules targeting B2 IPs"
    }

    # -----------------------------------------------------------------------
    # [11] Hosts file poisoning check
    # -----------------------------------------------------------------------
    Write-Step "[11] Hosts file check"
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    $hostsLines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
    if ($hostsLines) {
        foreach ($line in $hostsLines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^#' -or $trimmed -eq '') { continue }
            $isPoison = $false
            if ($trimmed -match $b2Host) { $isPoison = $true }
            foreach ($b2ip in $b2IPs) { if ($trimmed -match [regex]::Escape($b2ip)) { $isPoison = $true } }
            if ($isPoison) {
                $issues++
                Write-Log "ALERT  [HostsPoison] Line=`"$trimmed`""
                Write-Fail "Hosts file poisoning detected: `"$trimmed`""
            }
        }
    }
    if ($issues -eq 0) { Write-OK "Hosts file clean" }

    # -----------------------------------------------------------------------
    # [12] Scheduled task integrity check
    # -----------------------------------------------------------------------
    Write-Step "[12] Scheduled task integrity"
    $taskChecks = @(
        @{ Name = 'FolderSync-CloudBackup'; ExpectedPath = 'C:\Sync\Config\cloud_sync_helderTest.ps1' }
    )
    foreach ($tc in $taskChecks) {
        $task = Get-ScheduledTask -TaskName $tc.Name -ErrorAction SilentlyContinue
        if (-not $task) {
            $issues++
            Write-Log "ALERT  [TaskMissing] Task=$($tc.Name)"
            Write-Fail "Scheduled task missing: $($tc.Name)"
            continue
        }
        $deviations = @()
        if ($task.State -ne 'Ready') { $deviations += "State=$($task.State) (expected Ready)" }
        $principal = $task.Principal
        if ($principal.UserId -notmatch 'S-1-5-18|SYSTEM|SISTEMA') { $deviations += "Principal=$($principal.UserId) (expected SYSTEM)" }
        if ($principal.RunLevel -ne 'Highest') { $deviations += "RunLevel=$($principal.RunLevel) (expected Highest)" }
        $action = $task.Actions | Select-Object -First 1
        if ($action -and $action.Arguments -notmatch [regex]::Escape($tc.ExpectedPath)) {
            $deviations += "Arguments=`"$($action.Arguments)`" (expected to contain $($tc.ExpectedPath))"
        }
        if ($deviations.Count -gt 0) {
            $issues++
            foreach ($d in $deviations) {
                Write-Log "ALERT  [TaskTamper] Task=$($tc.Name) Deviation=$d"
                Write-Fail "Task integrity violation: $($tc.Name) - $d"
            }
        } else {
            Write-OK "$($tc.Name) integrity OK"
        }
    }

    # -----------------------------------------------------------------------
    # [13] Active B2 connectivity probe
    # -----------------------------------------------------------------------
    Write-Step "[13] B2 connectivity probe"
    $conn443 = Test-NetConnection -ComputerName $b2Host -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($conn443 -and $conn443.TcpTestSucceeded) {
        Write-OK "B2 connectivity OK ($b2Host:443)"
        Write-Log "INFO  [B2Connectivity] Host=$b2Host Port=443 Result=OK"
    } else {
        $issues++
        Write-Log "ALERT  [B2Connectivity] Host=$b2Host Port=443 Result=FAIL - B2 outbound blocked or unreachable"
        Write-Fail "B2 connectivity FAILED: $b2Host:443 unreachable"
    }

    # -----------------------------------------------------------------------
    # [14] Windows Event Log audit (last 24h)
    # -----------------------------------------------------------------------
    Write-Step "[14] Windows Event Log audit (last 24h)"
    $since = (Get-Date).AddHours(-24)
    $auditEventIds = @(
        @{ Id = 4698; Desc = 'New scheduled task created' }
        @{ Id = 4720; Desc = 'New user account created' }
        @{ Id = 4732; Desc = 'Member added to security-enabled local group' }
    )
    foreach ($ae in $auditEventIds) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName   = 'Security'
                Id        = $ae.Id
                StartTime = $since
            } -ErrorAction SilentlyContinue
            if ($events) {
                $issues++
                foreach ($ev in $events) {
                    Write-Log "ALERT  [EventLog] EventId=$($ae.Id) Desc=$($ae.Desc) Time=$($ev.TimeCreated) Message=$($ev.Message -replace '\r?\n',' ' -replace '\s+',' ')"
                    Write-Fail "Security event $($ae.Id) ($($ae.Desc)) at $($ev.TimeCreated)"
                }
            } else {
                Write-OK "EventId $($ae.Id) ($($ae.Desc)): none in last 24h"
            }
        } catch {}
    }

    # -----------------------------------------------------------------------
    # [17] HKCU Run key persistence check
    # -----------------------------------------------------------------------
    Write-Step "[17] HKCU Run key persistence check"
    $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $runEntries = Get-ItemProperty -Path $runKeyPath -ErrorAction SilentlyContinue
    if ($runEntries) {
        $runEntries.PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS' } |
            ForEach-Object {
                $entryName = $_.Name
                if ($entryName -notin $knownRunKeys -and $entryName -notmatch '^MicrosoftCopilotAutoLaunch_') {
                    $issues++
                    Write-Log "ALERT  [RunKeyUnknown] Name=`"$entryName`" Value=`"$($_.Value)`""
                    Write-Fail "Unknown HKCU Run key: `"$entryName`" = `"$($_.Value)`""
                } else {
                    Write-OK "Run key `"$entryName`" is whitelisted"
                }
            }
    }

    # -----------------------------------------------------------------------
    # Summary log line
    # -----------------------------------------------------------------------
    Write-Log "SCAN-END  Issues=$issues"

    # -----------------------------------------------------------------------
    # Interactive dialog (skip when running as scheduled task)
    # -----------------------------------------------------------------------
    if (-not [Environment]::UserInteractive) { return }

    Add-Type -AssemblyName System.Windows.Forms

    if ($issues -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "System secure. No threats detected.`n`nChecked at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Security Check",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } else {
        $msg  = "WARNING: $issues issue(s) detected!`n"
        $msg += "Checked at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        $msg += "-------------------------------------------`n"
        $msg += "See log for details: $logPath`n`n"
        $msg += "-------------------------------------------`n"
        $msg += "Run AUTO-CLEANUP?"

        $result = [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Security Alert",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $cleanupScript = "C:\Sync\Config\AutoCleanup.ps1"
            if (Test-Path $cleanupScript) {
                Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$cleanupScript`"" -Verb RunAs
            }
        }
    }

} catch {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  ERROR: $_" | Add-Content -LiteralPath $logPath
}

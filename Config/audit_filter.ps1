# audit_filter.ps1
# Runs every 5 minutes. Reads Windows Security event 4663 (file write audit)
# for the last 6 minutes, strips known-good processes, and appends any
# suspicious writes to C:\Sync\Evidence\suspicious_writes_YYYY-MM-DD.md.
#
# Known-good allowlist: processes that legitimately write to C:\Sync\.
# Anything NOT on this list triggers an alert entry in Evidence\.

$EvidenceDir  = 'C:\Sync\Evidence'
$OutFile      = "$EvidenceDir\suspicious_writes_$(Get-Date -Format 'yyyy-MM-dd').md"
$LookbackMins = 6

# ============================================================
# Known-good process allowlist (basename, no path, no .exe)
# ============================================================
$KnownGood = @(
    'git',
    'pwsh',
    'powershell',
    'robocopy',
    'rclone',
    'Code',                 # VS Code
    'node',                 # Claude Code / npm
    'cmd',                  # run_mirror.bat, setup scripts
    'conhost',
    'MsMpEng',              # Windows Defender
    'SearchIndexer',
    'SearchProtocolHost',
    'TiWorker',             # Windows Update
    'TrustedInstaller',
    'svchost',
    'WmiPrvSE',
    'services',
    'lsass',
    'System',
    'explorer',
    'RuntimeBroker',
    'taskhostw',
    'backgroundTaskHost',
    'dllhost',
    'sihost',
    'ctfmon',
    'RealTimeSync',         # FreeFileSync
    'FreeFileSync'
)

# ============================================================
# Monitored paths — only alert on writes under these
# ============================================================
$MonitoredPaths = @(
    'C:\Sync\Config',
    'C:\Sync\Evidence',
    'C:\Sync\.git'
)

# ============================================================
# Query Security log for event 4663 in last LookbackMins
# ============================================================
$since = (Get-Date).AddMinutes(-$LookbackMins)

$events = Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4663
    StartTime = $since
} -ErrorAction SilentlyContinue

if (-not $events) { exit 0 }

$suspicious = [System.Collections.Generic.List[string]]::new()

foreach ($ev in $events) {
    $msg = $ev.Message

    # Extract object name (file path)
    $objectName = ''
    if ($msg -match 'Nome do Objeto\s*:\s*(.+)') {
        $objectName = $Matches[1].Trim()
    } elseif ($msg -match 'Object Name\s*:\s*(.+)') {
        $objectName = $Matches[1].Trim()
    }

    # Only care about monitored paths
    $isMonitored = $false
    foreach ($p in $MonitoredPaths) {
        if ($objectName -like "$p*") { $isMonitored = $true; break }
    }
    if (-not $isMonitored) { continue }

    # Extract process name
    $processName = ''
    if ($msg -match 'Nome do Processo\s*:\s*(.+)') {
        $processName = $Matches[1].Trim()
    } elseif ($msg -match 'Process Name\s*:\s*(.+)') {
        $processName = $Matches[1].Trim()
    }
    $processBasename = [System.IO.Path]::GetFileNameWithoutExtension($processName)

    # Check against allowlist
    $isKnownGood = $false
    foreach ($k in $KnownGood) {
        if ($processBasename -ieq $k) { $isKnownGood = $true; break }
    }
    if ($isKnownGood) { continue }

    # icacls liberating C:\Sync\.git is routine (setup_all.ps1 Step 4.3); suppress to prevent bloat
    if ($processBasename -ieq 'icacls' -and $objectName -like 'C:\Sync\.git*') { continue }

    # Extract account name
    $account = ''
    if ($msg -match 'Nome da Conta\s*:\s*(\S+)') {
        $account = $Matches[1].Trim()
    } elseif ($msg -match 'Account Name\s*:\s*(\S+)') {
        $account = $Matches[1].Trim()
    }

    # Extract access type
    $access = ''
    if ($msg -match 'Acessos\s*:\s*(.+?)(\r|\n)') {
        $access = $Matches[1].Trim()
    } elseif ($msg -match 'Accesses\s*:\s*(.+?)(\r|\n)') {
        $access = $Matches[1].Trim()
    }

    $ts = $ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
    $suspicious.Add("| $ts | ``$processName`` | $account | $access | ``$objectName`` |")
}

if ($suspicious.Count -eq 0) { exit 0 }

# ============================================================
# Append to Evidence file (tamper-protected by ACL)
# ============================================================
$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$header = @"

## $timestamp - $($suspicious.Count) suspicious write(s) detected

| Time | Process | Account | Access | Object |
|------|---------|---------|--------|--------|
"@

$block = $header + "`n" + ($suspicious -join "`n")
$block | Add-Content -LiteralPath $OutFile -Encoding UTF8

# Cross-reference in security audit log
$secLog = "C:\Sync\Logs\security\security_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
"$timestamp  AUDIT-FILTER  SUSPICIOUS-WRITES  $($suspicious.Count) event(s) - see $OutFile" |
    Add-Content -LiteralPath $secLog -Encoding UTF8

# ============================================================
# Email + B2 upload — off-machine, admin-proof
# ============================================================
$emailBody = @"
SUSPICIOUS FILE WRITES DETECTED ON C:\Sync
Time: $timestamp
Count: $($suspicious.Count) event(s)

$($suspicious -join "`n")

Evidence file: $OutFile
Machine: $env:COMPUTERNAME
"@

$b2Key = "suspicious_writes_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').md"

& pwsh.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File 'C:\Sync\Config\send_alert.ps1' `
    -Subject "SUSPICIOUS WRITES on $env:COMPUTERNAME - $($suspicious.Count) event(s)" `
    -Body $emailBody `
    -AttachFile $OutFile `
    -B2Key $b2Key

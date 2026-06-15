#Requires -Version 5.1
# run_tests.ps1 - Tier 1-4 automated validation for T010-T034 changes
# Usage: powershell -ExecutionPolicy Bypass -File run_tests.ps1
# Results written to C:\Sync\Logs\security\test_results_YYYY-MM-DD.log

$LogFile = "C:\Sync\Logs\security\test_results_$(Get-Date -Format 'yyyy-MM-dd').log"
$pass = 0; $fail = 0; $warn = 0

function Write-Result($tier, $name, $status, $detail = '') {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts  [$tier]  $status  $name$(if ($detail) { "  - $detail" })"
    Add-Content -LiteralPath $LogFile -Value $line
    $color = switch ($status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'White' } }
    Write-Host $line -ForegroundColor $color
    switch ($status) { 'PASS' { $script:pass++ } 'FAIL' { $script:fail++ } 'WARN' { $script:warn++ } }
}

Add-Content -LiteralPath $LogFile -Value "`n=== TEST RUN $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# --- TIER 1: Parse Checks ---
Write-Host "`n>>> TIER 1 - Parse Checks" -ForegroundColor Cyan
$t1scripts = @('DailySecurityCheck.ps1','yawcam_monitor_v4.ps1','cam2_relay.ps1','wdog.ps1','auditor.ps1','cloud_sync_helderTest.ps1')
foreach ($s in $t1scripts) {
    $path = "C:\Sync\Config\$s"
    $t = $null; $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e) | Out-Null
    if ($e.Count -eq 0) {
        Write-Result 'T1' $s 'PASS'
    } else {
        $errs = ($e | ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        Write-Result 'T1' $s 'FAIL' $errs
    }
}

# --- TIER 2: Safe Live Runs ---
Write-Host "`n>>> TIER 2 - Safe Live Runs" -ForegroundColor Cyan

# DailySecurityCheck - run non-interactively, check log written
$today = Get-Date -Format 'yyyy-MM-dd'
$dscLog = "C:\Sync\Logs\security\security_check_$today.log"
try {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -NonInteractive -File "C:\Sync\Config\DailySecurityCheck.ps1" 2>&1
    if (Test-Path $dscLog) {
        Write-Result 'T2' 'DailySecurityCheck - log written' 'PASS'
        # Verify new check sections present in log
        $logContent = Get-Content -LiteralPath $dscLog -Raw
        # Verify script ran to completion
        if ($logContent -match 'SCAN-END') {
            Write-Result 'T2' 'DailySecurityCheck - ran to completion' 'PASS'
        } else {
            Write-Result 'T2' 'DailySecurityCheck - ran to completion' 'FAIL' 'SCAN-END not found in log'
        }
        # Checks that always log (B2, RunKey, TaskIntegrity)
        foreach ($keyword in @('B2Connectivity','RunKey','TaskTamper|TaskMissing|TaskOK')) {
            if ($logContent -match $keyword) {
                Write-Result 'T2' "DailySecurityCheck - $keyword logged" 'PASS'
            } else {
                Write-Result 'T2' "DailySecurityCheck - $keyword logged" 'FAIL' 'keyword missing from log'
            }
        }
        # Alert-only checks (FirewallBlock, HostsPoison, EventLog) only log when triggered
        $alerts = @($logContent | Select-String 'ALERT')
        if ($alerts.Count -eq 0) {
            Write-Result 'T2' 'DailySecurityCheck - 0 alerts on clean system' 'PASS'
        } else {
            Write-Result 'T2' "DailySecurityCheck - $($alerts.Count) alerts fired" 'WARN' 'review log - may be real issues'
        }
    } else {
        Write-Result 'T2' 'DailySecurityCheck - log written' 'FAIL' 'log file not found after run'
    }
} catch {
    Write-Result 'T2' 'DailySecurityCheck - execution' 'FAIL' $_.Exception.Message
}

# check_camera.ps1 - verify new sections present
try {
    $camOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Sync\Config\check_camera.ps1" 2>&1 | Out-String
    if ($camOut -match 'CAM-2|cam2|relay|8161') {
        Write-Result 'T2' 'check_camera - CAM-2 relay section present' 'PASS'
    } else {
        Write-Result 'T2' 'check_camera - CAM-2 relay section present' 'FAIL' 'no CAM-2/relay output found'
    }
    if ($camOut -match 'camera_restart_failed|restart.failed') {
        Write-Result 'T2' 'check_camera - restart_failed sentinel check present' 'PASS'
    } else {
        Write-Result 'T2' 'check_camera - restart_failed sentinel check present' 'WARN' 'sentinel check not detected in output'
    }
} catch {
    Write-Result 'T2' 'check_camera - execution' 'FAIL' $_.Exception.Message
}

# --- TIER 3: Sentinel File Checks ---
Write-Host "`n>>> TIER 3 - Sentinel File Verification" -ForegroundColor Cyan

# .last_sync_ok
$lastSyncOk = 'C:\Sync\Config\.last_sync_ok'
if (Test-Path $lastSyncOk) {
    $ts = (Get-Content -LiteralPath $lastSyncOk -Raw).Trim()
    try {
        $age = (Get-Date) - [datetime]$ts
        if ($age.TotalMinutes -lt 15) {
            Write-Result 'T3' '.last_sync_ok - recent timestamp' 'PASS' "age: $([int]$age.TotalMinutes) min"
        } else {
            Write-Result 'T3' '.last_sync_ok - recent timestamp' 'WARN' "age: $([int]$age.TotalMinutes) min - cloud sync may not have run yet"
        }
    } catch {
        Write-Result 'T3' '.last_sync_ok - readable timestamp' 'FAIL' "content: $ts"
    }
} else {
    Write-Result 'T3' '.last_sync_ok - exists' 'WARN' 'not yet created - wait for next cloud_sync run (every 5 min)'
}

# .sync_failed should NOT exist on healthy system
if (Test-Path 'C:\Sync\Config\.sync_failed') {
    $reason = (Get-Content -LiteralPath 'C:\Sync\Config\.sync_failed' -Raw).Trim()
    Write-Result 'T3' '.sync_failed - not present on healthy system' 'FAIL' $reason
} else {
    Write-Result 'T3' '.sync_failed - not present on healthy system' 'PASS'
}

# .camera_restart_failed should NOT exist on healthy system
if (Test-Path 'C:\Sync\Config\.camera_restart_failed') {
    $ts = (Get-Content -LiteralPath 'C:\Sync\Config\.camera_restart_failed' -Raw).Trim()
    Write-Result 'T3' '.camera_restart_failed - not present on healthy system' 'WARN' "exists since: $ts - check if expected"
} else {
    Write-Result 'T3' '.camera_restart_failed - not present on healthy system' 'PASS'
}

# Monitor log - check path correctness
$monLog = 'C:\Sync\Logs\services\yawcam_monitor.log'
if (Test-Path $monLog) {
    $recentLines = Get-Content -LiteralPath $monLog -Tail 20 | Out-String
    if ($recentLines -match 'C:\\TEMP\\motion_videos') {
        Write-Result 'T3' 'yawcam_monitor.log - correct path (no TEMP reference)' 'FAIL' 'old path still appearing in recent log entries'
    } else {
        Write-Result 'T3' 'yawcam_monitor.log - correct path (no TEMP reference)' 'PASS'
    }
    if ($recentLines -match 'Bois') {
        Write-Result 'T3' 'yawcam_monitor.log - Bois path in log' 'PASS'
    } else {
        Write-Result 'T3' 'yawcam_monitor.log - Bois path in log' 'WARN' 'not yet seen - monitor may not have cycled'
    }
} else {
    Write-Result 'T3' 'yawcam_monitor.log - exists' 'WARN' 'not yet created - monitor must run one cycle first'
}

# --- TIER 4: Behavioral Log Checks ---
Write-Host "`n>>> TIER 4 - Behavioral Log Checks" -ForegroundColor Cyan

# Watchdog heartbeat
$wdogLog = 'C:\Sync\Logs\services\watchdog.log'
if (Test-Path $wdogLog) {
    $todayHB = Select-String -LiteralPath $wdogLog -Pattern "WATCHDOG-HEARTBEAT" | Where-Object { $_.Line -match $today }
    if ($todayHB) {
        Write-Result 'T4' 'watchdog.log - HEARTBEAT today' 'PASS' "$($todayHB.Count) entries"
    } else {
        Write-Result 'T4' 'watchdog.log - HEARTBEAT today' 'WARN' 'no heartbeat yet today - wait 3 min after service restart'
    }
} else {
    Write-Result 'T4' 'watchdog.log - exists' 'FAIL' 'log file missing'
}

# Auditor job cleanup
$auditLog = "C:\Sync\Logs\security\security_audit_$today.log"
if (Test-Path $auditLog) {
    $jobClean = Select-String -LiteralPath $auditLog -Pattern 'JOB-CLEANUP' -ErrorAction SilentlyContinue
    if ($jobClean) {
        Write-Result 'T4' 'auditor - JOB-CLEANUP entries present' 'PASS' "$($jobClean.Count) entries"
    } else {
        Write-Result 'T4' 'auditor - JOB-CLEANUP entries present' 'WARN' 'not yet seen - auditor needs ~60 loop iterations'
    }
} else {
    Write-Result 'T4' "security_audit_$today.log - exists" 'WARN' 'no audit log today yet'
}

# Summary
Write-Host "`n=== RESULTS: $pass PASS  $warn WARN  $fail FAIL ===" -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
Add-Content -LiteralPath $LogFile -Value "=== RESULTS: $pass PASS  $warn WARN  $fail FAIL ==="
exit $(if ($fail -gt 0) { 1 } else { 0 })

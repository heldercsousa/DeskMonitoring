#Requires -RunAsAdministrator
# fix_power_motion.ps1 - restores power settings required for continuous motion detection
# Idempotent: safe to run multiple times
# Context: USB Selective Suspend was found re-enabled (0x1) on 2026-05-28, causing webcam dropout

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host "=== Motion Detection Power Settings Repair ===" -ForegroundColor Cyan
Write-Host "    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# 1. Switch to Balanced plan (away from Power Saver / SCHEME_MAX)
Write-Step "Activating Balanced power plan (away from Power Saver)"
try {
    powercfg /setactive SCHEME_BALANCED
    Write-OK "Balanced plan active"
} catch {
    Write-Fail "Could not activate Balanced plan: $_"
    exit 1
}

# 2. USB Selective Suspend - DISABLE on both AC and DC
Write-Step "Disabling USB Selective Suspend (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    Write-OK "USB Selective Suspend = Disabled (AC + DC)"
} catch {
    Write-Fail "USB Selective Suspend update failed: $_"
    exit 1
}

# 3. Sleep - Never (0 seconds)
Write-Step "Setting Sleep to Never (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
    powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
    Write-OK "Sleep = Never (AC + DC)"
} catch {
    Write-Fail "Sleep setting failed: $_"
    exit 1
}

# 4. Hibernate - Never (0 seconds)
Write-Step "Setting Hibernate to Never (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
    powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
    Write-OK "Hibernate = Never (AC + DC)"
} catch {
    Write-Fail "Hibernate setting failed: $_"
    exit 1
}

# 5. Display turn off - 10 min (600s) AC, 2 min (120s) DC
Write-Step "Setting display timeout (600s AC / 120s DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 600
    powercfg /setdcvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 120
    Write-OK "Display off = 600s AC / 120s DC"
} catch {
    Write-Fail "Display setting failed: $_"
    exit 1
}

# 6. Apply all changes
Write-Step "Applying changes (powercfg /setactive SCHEME_CURRENT)"
powercfg /setactive SCHEME_CURRENT

Write-Host ""
Write-Host "=== Repair complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Verify USB Selective Suspend (both indexes must show 0x00000000):" -ForegroundColor Cyan
Write-Host "  powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -ForegroundColor Gray
Write-Host ""
Write-Host "Also verify webcam device power management in Device Manager:" -ForegroundColor Cyan
Write-Host "  Cameras -> right-click webcam -> Properties -> Power Management tab" -ForegroundColor Gray
Write-Host "  Uncheck: 'Allow the computer to turn off this device to save power'" -ForegroundColor Gray

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

# 5b. Disk turn-off - Never (0 seconds) so active recording is never interrupted
Write-Step "Setting Disk turn-off to Never (AC + DC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0
    powercfg /setdcvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0
    Write-OK "Disk turn-off = Never (AC + DC)"
} catch {
    Write-Fail "Disk turn-off setting failed: $_"
}

# 6. Disable webcam device power management (Device Manager setting)
Write-Step "Disabling webcam device power management"
$webcamFound = $false
try {
    Get-WmiObject Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.Description -match 'camera|webcam|RGB|integrated' } | ForEach-Object {
        $device = $_
        $instanceName = $device.Name
        Write-Host "  Found webcam: $instanceName" -ForegroundColor Gray
        $webcamFound = $true
        # Disable via registry key PowerDownLevel = 0
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.PNPDeviceID)\Device Parameters"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "PowerDownLevel" -Value 0 -ErrorAction SilentlyContinue
            Write-Host "  OK   Device power management disabled: $instanceName" -ForegroundColor Green
        } else {
            Write-Host "  WARN Registry path not found for $instanceName (device may not support power control)" -ForegroundColor Yellow
        }
    }
} catch {
    # Continue — device may not be enumerable or no webcam attached
}
if (-not $webcamFound) {
    Write-Host "  WARN No webcam device found via WMI (this is ok if device is disabled in BIOS)" -ForegroundColor Yellow
}

# 6b. Power button + sleep button + lid = Do nothing (AC + DC)
# Context: Event 42 "Button or Lid" sleeps confirmed 2026-06-15 were stopping
# recording. Power-button press is a physical power-sabotage vector (THREAT_MODEL).
# Setting buttons to Do nothing (0) neutralises it. Shutdown is via Start menu only.
Write-Step "Disabling power/sleep button and lid sleep actions (Do nothing, AC + DC)"
try {
    # PBUTTONACTION
    powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 0
    powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 0
    # SBUTTONACTION
    powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 96996bc0-ad50-47ec-923b-6f41874dd9eb 0
    powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 96996bc0-ad50-47ec-923b-6f41874dd9eb 0
    # LIDACTION
    powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
    powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
    Write-OK "Power button / sleep button / lid = Do nothing (AC + DC)"
} catch {
    Write-Fail "Button/lid action update failed: $_"
}

# 7. Apply all changes
Write-Step "Applying changes (powercfg /setactive SCHEME_CURRENT)"
powercfg /setactive SCHEME_CURRENT

Write-Host ""
Write-Host "=== Repair complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Verify settings were applied:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  USB Selective Suspend (both values must be 0x00000000):" -ForegroundColor Gray
Write-Host "    powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -ForegroundColor Gray
Write-Host ""
Write-Host "  Sleep setting (must be 0x00000000 for both AC and DC):" -ForegroundColor Gray
Write-Host "    powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da" -ForegroundColor Gray
Write-Host ""
Write-Host "  Device Manager alternative check:" -ForegroundColor Gray
Write-Host "    Win+X → Device Manager → Cameras → right-click webcam → Properties" -ForegroundColor Gray
Write-Host "    Power Management tab should be unchecked (script above attempted to set this)" -ForegroundColor Gray

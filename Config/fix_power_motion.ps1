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
# T092: Description-based Win32_PnPEntity match failed on Portuguese Windows
# (camera Description = "Dispositivo de video USB"). Use Get-PnpDevice with the
# locale-independent Class filter proven in check_camera.ps1 instead.
Write-Step "Disabling webcam device power management"
$webcamFound = $false
try {
    Get-PnpDevice -ErrorAction Stop |
        Where-Object { $_.FriendlyName -like "*HD User*" -or $_.FriendlyName -like "*webcam*" -or $_.FriendlyName -like "*camera*" -or $_.Class -eq "Camera" -or $_.Class -eq "Image" } |
        ForEach-Object {
            $device = $_
            $instanceName = $device.FriendlyName
            Write-Host "  Found webcam: $instanceName [$($device.Class)] Status=$($device.Status)" -ForegroundColor Gray
            $webcamFound = $true
            # Disable via registry key PowerDownLevel = 0
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)\Device Parameters"
            if (Test-Path $regPath) {
                Set-ItemProperty -Path $regPath -Name "PowerDownLevel" -Value 0 -ErrorAction Stop
                $applied = (Get-ItemProperty -Path $regPath -Name "PowerDownLevel" -ErrorAction SilentlyContinue).PowerDownLevel
                if ($applied -eq 0) {
                    Write-Host "  OK   Device power management disabled (PowerDownLevel=0): $instanceName" -ForegroundColor Green
                } else {
                    Write-Host "  FAIL PowerDownLevel write did not persist for $instanceName (value=$applied)" -ForegroundColor Red
                }
            } else {
                Write-Host "  WARN Registry path not found for $instanceName (device may not support power control)" -ForegroundColor Yellow
            }
        }
} catch {
    Write-Host "  FAIL Webcam power management step errored: $_" -ForegroundColor Red
}
if (-not $webcamFound) {
    Write-Host "  FAIL No webcam device found via Get-PnpDevice - webcam power hardening NOT applied. Investigate (device disabled/removed?)" -ForegroundColor Red
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

# 6c. System unattended sleep timeout = Never (0) AC + DC
# Context: confirmed 2026-06-17 - locking the session (Ctrl+L) and walking away
# slept the machine ~2 min later, stopping recording, even with Sleep = Never.
# Windows treats a locked session as "unattended" and applies this hidden timeout
# (default 120s), which overrides the normal Sleep-after value. Unhide + set 0.
Write-Step "Setting System unattended sleep timeout to Never (AC + DC)"
try {
    powercfg /attributes 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 -ATTRIB_HIDE | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0
    powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0
    Write-OK "Unattended sleep timeout = Never (AC + DC)"
} catch {
    Write-Fail "Unattended sleep timeout update failed: $_"
    exit 1
}

# 7. Apply all changes
Write-Step "Applying changes (powercfg /setactive SCHEME_CURRENT)"
powercfg /setactive SCHEME_CURRENT

# 8. Verify compliance - read settings back and FAIL LOUDLY if any non-compliant.
# This non-zero exit is what lets setup_update.ps1 Step 18b detect a failed apply
# instead of silently warning. Read from registry under the active scheme GUID
# (locale-independent, and works for hidden settings powercfg /query omits).
Write-Step "Verifying power compliance"
$active = (powercfg /getactivescheme) -join ' '
$schemeGuid = if ($active -match '([0-9a-fA-F-]{36})') { $Matches[1] } else { $null }
$compliant = $true
function Test-RegSetting($sub, $set, $expect, $label) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$schemeGuid\$sub\$set"
    if (-not (Test-Path $p)) {
        Write-Fail "$label : key absent (Windows default applies) - expected $expect"
        $script:compliant = $false
        return
    }
    $v = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    if ($v.ACSettingIndex -ne $expect -or $v.DCSettingIndex -ne $expect) {
        Write-Fail "$label : AC=$($v.ACSettingIndex) DC=$($v.DCSettingIndex) - expected $expect"
        $script:compliant = $false
    } else {
        Write-OK "$label : AC=$expect DC=$expect"
    }
}
if ($schemeGuid) {
    Test-RegSetting '238c9fa8-0aad-41ed-83f4-97be242c8f20' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' 0 'Sleep after'
    Test-RegSetting '238c9fa8-0aad-41ed-83f4-97be242c8f20' '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0' 0 'Unattended sleep timeout'
    Test-RegSetting '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 'USB Selective Suspend'
} else {
    Write-Fail "Could not resolve active scheme GUID - cannot verify compliance"
    $compliant = $false
}
# T092: verify webcam device power management actually persisted (PowerDownLevel=0)
$webcams = @(Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like "*HD User*" -or $_.FriendlyName -like "*webcam*" -or $_.FriendlyName -like "*camera*" -or $_.Class -eq "Camera" -or $_.Class -eq "Image" })
if ($webcams.Count -eq 0) {
    Write-Fail "Webcam power mgmt : no webcam device found via Get-PnpDevice"
    $compliant = $false
} else {
    foreach ($cam in $webcams) {
        $rp = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($cam.InstanceId)\Device Parameters"
        $pdl = (Get-ItemProperty -Path $rp -Name "PowerDownLevel" -ErrorAction SilentlyContinue).PowerDownLevel
        if ($pdl -eq 0) {
            Write-OK "Webcam power mgmt : PowerDownLevel=0 ($($cam.FriendlyName))"
        } else {
            Write-Fail "Webcam power mgmt : PowerDownLevel=$pdl ($($cam.FriendlyName)) - expected 0"
            $compliant = $false
        }
    }
}
if (-not $compliant) {
    Write-Fail "POWER SETTINGS NOT COMPLIANT - motion capture is at risk of interruption"
    exit 1
}

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

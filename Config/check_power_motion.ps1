#Requires -RunAsAdministrator
# check_power_motion.ps1 - hourly audit + auto-heal of power settings required for motion detection
# Idempotent: safe to run multiple times
# Scheduled Task: FolderSync-PowerCheck (every 1h, SYSTEM, RunLevel Highest)

$ErrorActionPreference = 'SilentlyContinue'

$LogDir  = "C:\Sync\Logs\power_check"
$LogFile = "$LogDir\power_check_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

# GUIDs
$USB_SG   = '2a737441-1930-4402-8d77-b2bebba308a3'
$USB_SET  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$SLEEP_SG = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$SLEEP_SET = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$HIB_SET  = '9d7815a6-7ee4-497e-8888-515a05f02364'
$DISP_SG  = '7516b95f-f776-4464-8c53-06167f40cc99'
$DISP_SET = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
$DISK_SG  = '0012ee47-9041-4b5d-9b77-535fba8b1442'
$DISK_SET = '6738e2c4-e8a5-4a42-b16a-e040e769756e'
$BTN_SG   = '4f971e89-eebd-4455-a8de-9e59040e7347'
$PBTN_SET = '7648efa3-dd9c-4e3e-b566-50f929386280'   # power button action
$SBTN_SET = '96996bc0-ad50-47ec-923b-6f41874dd9eb'   # sleep button action
$UNATTEND = '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'   # system unattended sleep timeout
$CONLOCK  = '8ec4b3a5-6868-48c2-be75-4f3044be88a7'   # console lock display off timeout (T098)
$SCHEME_MAX     = 'a1841308-3541-4fab-bc81-f71556f20b4a'

Write-Log "POWER-CHECK-START"

$anyAnomaly = $false

# --- Helper: read a powercfg setting index value ---
function Get-PowerSetting {
    param($SubGroup, $Setting, $AcOrDc)
    # AcOrDc: 'AC' or 'DC'
    $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null
    if (-not $output) { return $null }
    # Locale-robust: match English ("Current AC Power Setting Index") AND
    # Portuguese ("...Correntes Alternadas Atuais" / "...Correntes Cont nuas Atuais").
    # Without this, powercfg output on non-English Windows never matched and every
    # check silently passed - the auto-heal was a no-op (fixed 2026-06-15).
    $label = if ($AcOrDc -eq 'AC') { 'AC Power Setting Index|Alternadas Atuais' } else { 'DC Power Setting Index|Cont.+Atuais' }
    $line = $output | Where-Object { $_ -match $label }
    if (-not $line) { return $null }
    if ($line -match '0x([0-9a-fA-F]+)') { return [Convert]::ToInt64($Matches[1], 16) }
    return $null
}

# --- Helper: read a button action from the registry ---
# powercfg /query does not emit hidden button settings, so read them directly.
# Returns $null when no override key exists - which means the hardware DEFAULT
# (Sleep on this laptop) applies, i.e. the vulnerable state - so callers must
# treat $null as an anomaly and (re)apply 0 = Do nothing.
function Get-ButtonActionReg {
    param($Setting, $AcOrDc)
    $act = (powercfg /getactivescheme) -join ' '
    if ($act -notmatch '([0-9a-fA-F-]{36})') { return $null }
    $guid = $Matches[1]
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$guid\$BTN_SG\$Setting"
    if (-not (Test-Path $p)) { return $null }
    $v = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    if ($AcOrDc -eq 'AC') { return $v.ACSettingIndex } else { return $v.DCSettingIndex }
}

# --- Helper: read any scheme setting index straight from the registry ---
# Used for hidden settings (e.g. unattended sleep timeout) that powercfg /query
# omits. Returns $null when the override key is absent - meaning the Windows
# DEFAULT applies (120s for unattended sleep = the vulnerable state) - so callers
# must treat $null as an anomaly and (re)apply 0.
function Get-SchemeRegIndex {
    param($SubGroup, $Setting, $AcOrDc)
    $act = (powercfg /getactivescheme) -join ' '
    if ($act -notmatch '([0-9a-fA-F-]{36})') { return $null }
    $guid = $Matches[1]
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$guid\$SubGroup\$Setting"
    if (-not (Test-Path $p)) { return $null }
    $v = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    if ($AcOrDc -eq 'AC') { return $v.ACSettingIndex } else { return $v.DCSettingIndex }
}

# --- 1. Active power plan ---
$activeLine = powercfg /getactivescheme 2>$null
$isSchemeMax = $activeLine -match $SCHEME_MAX
if ($isSchemeMax) {
    Write-Log "POWER-ANOMALY  Active plan is Power Saver (SCHEME_MAX) - switching to Balanced"
    $anyAnomaly = $true
    powercfg /setactive SCHEME_BALANCED 2>$null
    Write-Log "POWER-CORRECTED  Active plan set to SCHEME_BALANCED"
} else {
    Write-Log "POWER-OK  Active plan is not Power Saver"
}

# --- 2. USB Selective Suspend AC ---
$usbAC = Get-PowerSetting -SubGroup $USB_SG -Setting $USB_SET -AcOrDc 'AC'
if ($usbAC -ne $null -and $usbAC -ne 0) {
    Write-Log "POWER-ANOMALY  USB Selective Suspend AC = $usbAC (expected 0)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $USB_SG $USB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  USB Selective Suspend AC set to 0"
} else {
    Write-Log "POWER-OK  USB Selective Suspend AC = 0"
}

# --- 3. USB Selective Suspend DC ---
$usbDC = Get-PowerSetting -SubGroup $USB_SG -Setting $USB_SET -AcOrDc 'DC'
if ($usbDC -ne $null -and $usbDC -ne 0) {
    Write-Log "POWER-ANOMALY  USB Selective Suspend DC = $usbDC (expected 0)"
    $anyAnomaly = $true
    powercfg /setdcvalueindex SCHEME_CURRENT $USB_SG $USB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  USB Selective Suspend DC set to 0"
} else {
    Write-Log "POWER-OK  USB Selective Suspend DC = 0"
}

# --- 4. Sleep after AC ---
$sleepAC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $SLEEP_SET -AcOrDc 'AC'
if ($sleepAC -ne $null -and $sleepAC -ne 0) {
    Write-Log "POWER-ANOMALY  Sleep AC = $sleepAC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $SLEEP_SG $SLEEP_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Sleep AC set to 0"
} else {
    Write-Log "POWER-OK  Sleep AC = 0"
}

# --- 5. Sleep after DC ---
$sleepDC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $SLEEP_SET -AcOrDc 'DC'
if ($sleepDC -ne $null -and $sleepDC -ne 0) {
    Write-Log "POWER-ANOMALY  Sleep DC = $sleepDC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setdcvalueindex SCHEME_CURRENT $SLEEP_SG $SLEEP_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Sleep DC set to 0"
} else {
    Write-Log "POWER-OK  Sleep DC = 0"
}

# --- 6. Hibernate after AC ---
$hibAC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $HIB_SET -AcOrDc 'AC'
if ($hibAC -ne $null -and $hibAC -ne 0) {
    Write-Log "POWER-ANOMALY  Hibernate AC = $hibAC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $SLEEP_SG $HIB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Hibernate AC set to 0"
} else {
    Write-Log "POWER-OK  Hibernate AC = 0"
}

# --- 7. Hibernate after DC ---
$hibDC = Get-PowerSetting -SubGroup $SLEEP_SG -Setting $HIB_SET -AcOrDc 'DC'
if ($hibDC -ne $null -and $hibDC -ne 0) {
    Write-Log "POWER-ANOMALY  Hibernate DC = $hibDC seconds (expected 0)"
    $anyAnomaly = $true
    powercfg /setdcvalueindex SCHEME_CURRENT $SLEEP_SG $HIB_SET 0 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Hibernate DC set to 0"
} else {
    Write-Log "POWER-OK  Hibernate DC = 0"
}

# --- 8. Display timeout AC (must be >= 600s = 0x258) ---
$dispAC = Get-PowerSetting -SubGroup $DISP_SG -Setting $DISP_SET -AcOrDc 'AC'
if ($dispAC -ne $null -and $dispAC -lt 600) {
    Write-Log "POWER-ANOMALY  Display timeout AC = $dispAC seconds (expected >= 600)"
    $anyAnomaly = $true
    powercfg /setacvalueindex SCHEME_CURRENT $DISP_SG $DISP_SET 600 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Log "POWER-CORRECTED  Display timeout AC set to 600"
} else {
    Write-Log "POWER-OK  Display timeout AC = $dispAC (>= 600)"
}

# --- 9. Power button action (must be 0 = Do nothing) AC + DC ---
# A power button mapped to Sleep was confirmed stopping recording on 2026-06-15
# (Event 42 "Button or Lid"). Auto-heal back to Do nothing to defeat re-tampering.
foreach ($dc in @('AC','DC')) {
    $v = Get-ButtonActionReg -Setting $PBTN_SET -AcOrDc $dc
    if ($v -ne 0) {   # $null (no override = default Sleep) or non-zero both need correcting
        $shown = if ($v -eq $null) { 'default(Sleep)' } else { $v }
        Write-Log "POWER-ANOMALY  Power button $dc = $shown (expected 0=Do nothing)"
        $anyAnomaly = $true
        $cmd = if ($dc -eq 'AC') { 'setacvalueindex' } else { 'setdcvalueindex' }
        powercfg /$cmd SCHEME_CURRENT $BTN_SG $PBTN_SET 0 2>$null
        powercfg /setactive SCHEME_CURRENT 2>$null
        Write-Log "POWER-CORRECTED  Power button $dc set to 0 (Do nothing)"
    } else {
        Write-Log "POWER-OK  Power button $dc = 0 (Do nothing)"
    }
}

# --- 10. Sleep button action (must be 0 = Do nothing) AC + DC ---
foreach ($dc in @('AC','DC')) {
    $v = Get-ButtonActionReg -Setting $SBTN_SET -AcOrDc $dc
    if ($v -ne 0) {
        $shown = if ($v -eq $null) { 'default(Sleep)' } else { $v }
        Write-Log "POWER-ANOMALY  Sleep button $dc = $shown (expected 0=Do nothing)"
        $anyAnomaly = $true
        $cmd = if ($dc -eq 'AC') { 'setacvalueindex' } else { 'setdcvalueindex' }
        powercfg /$cmd SCHEME_CURRENT $BTN_SG $SBTN_SET 0 2>$null
        powercfg /setactive SCHEME_CURRENT 2>$null
        Write-Log "POWER-CORRECTED  Sleep button $dc set to 0 (Do nothing)"
    } else {
        Write-Log "POWER-OK  Sleep button $dc = 0 (Do nothing)"
    }
}

# --- 11. Disk turn-off (must be 0 = Never) AC + DC ---
foreach ($dc in @('AC','DC')) {
    $v = Get-PowerSetting -SubGroup $DISK_SG -Setting $DISK_SET -AcOrDc $dc
    if ($v -ne $null -and $v -ne 0) {
        Write-Log "POWER-ANOMALY  Disk turn-off $dc = $v seconds (expected 0=Never)"
        $anyAnomaly = $true
        $cmd = if ($dc -eq 'AC') { 'setacvalueindex' } else { 'setdcvalueindex' }
        powercfg /$cmd SCHEME_CURRENT $DISK_SG $DISK_SET 0 2>$null
        powercfg /setactive SCHEME_CURRENT 2>$null
        Write-Log "POWER-CORRECTED  Disk turn-off $dc set to 0 (Never)"
    } else {
        Write-Log "POWER-OK  Disk turn-off $dc = 0 (Never)"
    }
}

# --- 12. System unattended sleep timeout (must be 0 = Never) AC + DC ---
# Locking the session (Ctrl+L) puts Windows in "unattended" mode; this hidden
# timeout (default 120s) then sleeps the machine, stopping recording, even with
# Sleep after = Never. Confirmed 2026-06-17. Absent key = default = anomaly.
foreach ($dc in @('AC','DC')) {
    $v = Get-SchemeRegIndex -SubGroup $SLEEP_SG -Setting $UNATTEND -AcOrDc $dc
    if ($v -ne 0) {   # $null (default 120s) or non-zero both need correcting
        $shown = if ($v -eq $null) { 'default(120s)' } else { $v }
        Write-Log "POWER-ANOMALY  Unattended sleep timeout $dc = $shown (expected 0=Never)"
        $anyAnomaly = $true
        powercfg /attributes $SLEEP_SG $UNATTEND -ATTRIB_HIDE 2>$null
        $cmd = if ($dc -eq 'AC') { 'setacvalueindex' } else { 'setdcvalueindex' }
        powercfg /$cmd SCHEME_CURRENT $SLEEP_SG $UNATTEND 0 2>$null
        powercfg /setactive SCHEME_CURRENT 2>$null
        Write-Log "POWER-CORRECTED  Unattended sleep timeout $dc set to 0 (Never)"
    } else {
        Write-Log "POWER-OK  Unattended sleep timeout $dc = 0 (Never)"
    }
}

# --- 13. Console lock display off timeout (must be 0 = Never) AC + DC (T098) ---
# After Win+L the display turns off on this hidden timeout (found at 300s on
# 2026-07-07) and webcam frame delivery to Yawcam stops with it - confirmed by
# controlled test: no clips while the locked screen was black despite motion,
# instant resume at unlock. With 0 the lock screen stays lit ("blue") and
# capture continues, matching the historical known-good behavior.
foreach ($dc in @('AC','DC')) {
    $v = Get-SchemeRegIndex -SubGroup $DISP_SG -Setting $CONLOCK -AcOrDc $dc
    if ($v -ne 0) {   # $null (Windows default 60s) or non-zero both need correcting
        $shown = if ($v -eq $null) { 'default(60s)' } else { $v }
        Write-Log "POWER-ANOMALY  Console lock display off timeout $dc = $shown (expected 0=Never)"
        $anyAnomaly = $true
        powercfg /attributes $DISP_SG $CONLOCK -ATTRIB_HIDE 2>$null
        $cmd = if ($dc -eq 'AC') { 'setacvalueindex' } else { 'setdcvalueindex' }
        powercfg /$cmd SCHEME_CURRENT $DISP_SG $CONLOCK 0 2>$null
        powercfg /setactive SCHEME_CURRENT 2>$null
        Write-Log "POWER-CORRECTED  Console lock display off timeout $dc set to 0 (Never)"
    } else {
        Write-Log "POWER-OK  Console lock display off timeout $dc = 0 (Never)"
    }
}

if (-not $anyAnomaly) {
    Write-Log "POWER-CHECK-END  ALL_OK - no anomalies detected"
} else {
    Write-Log "POWER-CHECK-END  anomalies detected and corrected"
}

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
$SCHEME_MAX     = 'a1841308-3541-4fab-bc81-f71556f20b4a'

Write-Log "POWER-CHECK-START"

$anyAnomaly = $false

# --- Helper: read a powercfg setting index value ---
function Get-PowerSetting {
    param($SubGroup, $Setting, $AcOrDc)
    # AcOrDc: 'AC' or 'DC'
    $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null
    if (-not $output) { return $null }
    $label = if ($AcOrDc -eq 'AC') { 'Current AC Power Setting Index' } else { 'Current DC Power Setting Index' }
    $line = $output | Where-Object { $_ -match $label }
    if (-not $line) { return $null }
    if ($line -match '0x([0-9a-fA-F]+)') { return [Convert]::ToInt64($Matches[1], 16) }
    return $null
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

if (-not $anyAnomaly) {
    Write-Log "POWER-CHECK-END  ALL_OK - no anomalies detected"
} else {
    Write-Log "POWER-CHECK-END  anomalies detected and corrected"
}

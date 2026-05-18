#Requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

# -- Paths -----------------------------------------------------------------
$LogFile     = "C:\Sync\Logs\ecosystem\health_check_$(Get-Date -Format yyyy-MM-dd).log"
$CheckStatus = "C:\Sync\Config\check_status.ps1"
$CheckCamera = "C:\Sync\Config\check_camera.ps1"

# -- Logging helpers -------------------------------------------------------
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }

# -- Capture subscript output ----------------------------------------------
function Invoke-ScriptCapture($ScriptPath) {
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return "[ERROR] Script not found: $ScriptPath"
    }
    $out = & powershell.exe -ExecutionPolicy Bypass -NonInteractive -File $ScriptPath 2>&1 | Out-String
    return $out
}

# --------------------------------------------------------------------------
Write-Step "Running FolderSync health sub-check..."
Write-Log "--- BEGIN health_check_all.ps1 ---"
$statusOut = Invoke-ScriptCapture $CheckStatus
Write-Log "check_status.ps1 output captured ($($statusOut.Length) chars)"

Write-Step "Running Camera health sub-check..."
$cameraOut = Invoke-ScriptCapture $CheckCamera
Write-Log "check_camera.ps1 output captured ($($cameraOut.Length) chars)"

# ==========================================================================
# FOLDERSYNC BASELINE EVALUATION
# ==========================================================================
$fsIssues = @()

# FolderSync-CloudBackup task: State = Ready
$task = Get-ScheduledTask -TaskName FolderSync-CloudBackup -ErrorAction SilentlyContinue
if (-not $task) {
    $fsIssues += "FolderSync-CloudBackup task: NOT FOUND"
} elseif ($task.State -notin @("Ready","Running")) {
    $fsIssues += "FolderSync-CloudBackup task: State = $($task.State) (expected Ready)"
}

# FolderSync-Watchdog task: State = Ready or Running
$wdTask = Get-ScheduledTask -TaskName FolderSync-Watchdog -ErrorAction SilentlyContinue
if (-not $wdTask) {
    $fsIssues += "FolderSync-Watchdog task: NOT FOUND"
} elseif ($wdTask.State -notin @("Ready","Running")) {
    $fsIssues += "FolderSync-Watchdog task: State = $($wdTask.State) (expected Ready or Running)"
}

# FolderSyncWatchdog service: Status = Running, StartType = Automatic
$wdSvc = Get-Service -Name FolderSyncWatchdog -ErrorAction SilentlyContinue
if (-not $wdSvc) {
    $fsIssues += "FolderSyncWatchdog service: NOT FOUND"
} else {
    if ($wdSvc.Status -ne "Running")      { $fsIssues += "FolderSyncWatchdog service: Status = $($wdSvc.Status) (expected Running)" }
    if ($wdSvc.StartType -ne "Automatic") { $fsIssues += "FolderSyncWatchdog service: StartType = $($wdSvc.StartType) (expected Automatic)" }
}

# FolderSyncAuditor service: Status = Running, StartType = Automatic
$audSvc = Get-Service -Name FolderSyncAuditor -ErrorAction SilentlyContinue
if (-not $audSvc) {
    $fsIssues += "FolderSyncAuditor service: NOT FOUND"
} else {
    if ($audSvc.Status -ne "Running")      { $fsIssues += "FolderSyncAuditor service: Status = $($audSvc.Status) (expected Running)" }
    if ($audSvc.StartType -ne "Automatic") { $fsIssues += "FolderSyncAuditor service: StartType = $($audSvc.StartType) (expected Automatic)" }
}

# Registry FolderSyncRealTime: non-empty
$rtReg = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name FolderSyncRealTime -ErrorAction SilentlyContinue
if (-not $rtReg -or [string]::IsNullOrWhiteSpace($rtReg.FolderSyncRealTime)) {
    $fsIssues += "Registry FolderSyncRealTime: NOT FOUND or empty"
}

# RealTimeSync process: listed
$rtProc = Get-Process -Name RealTimeSync -ErrorAction SilentlyContinue
if (-not $rtProc) {
    $fsIssues += "RealTimeSync process: NOT RUNNING"
}

# Rclone: returns version string
$rclonePath = "C:\Tools\Rclone\rclone.exe"
if (-not (Test-Path -LiteralPath $rclonePath)) {
    $fsIssues += "Rclone binary: NOT FOUND at $rclonePath"
} else {
    $rcloneVer = & $rclonePath version 2>&1 | Select-Object -First 1
    if ($rcloneVer -notmatch "rclone") {
        $fsIssues += "Rclone: did not return version string (got: $rcloneVer)"
    }
}

# Cloud sync log today: exists
$todayLog = "C:\Sync\Logs\cloud_sync\cloud_sync_$(Get-Date -Format yyyy-MM-dd).log"
if (-not (Test-Path -LiteralPath $todayLog)) {
    $fsIssues += "Cloud sync log today: NOT FOUND ($todayLog)"
}

# ==========================================================================
# CAMERA BASELINE EVALUATION
# ==========================================================================
$camIssues = @()

# Yawcam process (yawcam or javaw): running
$yawProc   = Get-Process -Name yawcam -ErrorAction SilentlyContinue
$javawProc = Get-Process -Name javaw  -ErrorAction SilentlyContinue
if (-not $yawProc -and -not $javawProc) {
    $camIssues += "Yawcam process (yawcam or javaw): NOT RUNNING"
}

# Monitor process (powershell with yawcam_monitor): running
$monProc = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "yawcam_monitor" }
if (-not $monProc) {
    $camIssues += "Yawcam monitor process (powershell yawcam_monitor): NOT RUNNING"
}

# Webcam PnP device: Status = OK
$webcam = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match "camera|webcam|HD User Facing" -and $_.Class -eq "Camera" } |
    Select-Object -First 1
if (-not $webcam) {
    $camIssues += "Webcam PnP device: NOT FOUND"
} elseif ($webcam.Status -ne "OK") {
    $camIssues += "Webcam PnP device: Status = $($webcam.Status) (expected OK)"
}

# Registry Yawcam: non-empty
$yawReg = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name Yawcam -ErrorAction SilentlyContinue
if (-not $yawReg -or [string]::IsNullOrWhiteSpace($yawReg.Yawcam)) {
    $camIssues += "Registry Yawcam: NOT FOUND or empty"
}

# Registry YawcamMonitor: non-empty
$monReg = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name YawcamMonitor -ErrorAction SilentlyContinue
if (-not $monReg -or [string]::IsNullOrWhiteSpace($monReg.YawcamMonitor)) {
    $camIssues += "Registry YawcamMonitor: NOT FOUND or empty"
}

# ==========================================================================
# SUMMARY
# ==========================================================================
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$fsPass      = $fsIssues.Count -eq 0
$camPass     = $camIssues.Count -eq 0
$overallPass = $fsPass -and $camPass

$fsLabel    = if ($fsPass)      { "PASS" } else { "FAIL -- $($fsIssues.Count) issue(s)" }
$camLabel   = if ($camPass)     { "PASS" } else { "FAIL -- $($camIssues.Count) issue(s)" }
$overallLbl = if ($overallPass) { "ALL SYSTEMS OPERATIONAL" } else { "$($fsIssues.Count + $camIssues.Count) ISSUE(S) FOUND" }

$summaryLines = @(
    "============================================================",
    "  ECOSYSTEM HEALTH SUMMARY -- $timestamp",
    "============================================================",
    "  FOLDERSYNC  : $fsLabel",
    "  CAMERA      : $camLabel",
    "------------------------------------------------------------",
    "  OVERALL     : $overallLbl",
    "============================================================"
)

Write-Host ""
foreach ($line in $summaryLines) { Write-Host $line }

if (-not $fsPass) {
    Write-Host "`n  FolderSync issues:" -ForegroundColor Red
    foreach ($issue in $fsIssues) { Write-Fail "    $issue" }
}
if (-not $camPass) {
    Write-Host "`n  Camera issues:" -ForegroundColor Red
    foreach ($issue in $camIssues) { Write-Fail "    $issue" }
}
Write-Host ""

foreach ($line in $summaryLines) { Write-Log $line }
if (-not $fsPass)  { foreach ($i in $fsIssues)  { Write-Log "  FOLDERSYNC ISSUE: $i" } }
if (-not $camPass) { foreach ($i in $camIssues) { Write-Log "  CAMERA ISSUE: $i" } }
Write-Log "--- END health_check_all.ps1 ---"

if ($overallPass) { exit 0 } else { exit 1 }

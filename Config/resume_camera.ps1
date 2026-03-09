#Requires -RunAsAdministrator
# resume_camera.ps1
# Starts Yawcam and removes .camera_paused flag.
# Guard: exits cleanly if flag is absent (camera not paused).

$ErrorActionPreference = 'SilentlyContinue'
$LogFile    = "C:\Sync\Logs\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"
$PausedFlag = "C:\Sync\Config\.camera_paused"

# --- Credential guard ---
Write-Host "`n  Credential check required." -ForegroundColor Yellow
$credUser = Read-Host "  Username"
$credPass = Read-Host "  Password" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credPass)
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Machine')
$valid = $ctx.ValidateCredentials($credUser, $plainPass)
$plainPass = $null

if (-not $valid) {
    Write-Host "  FAIL  Invalid credentials. Aborting." -ForegroundColor Red
    exit 1
}

$adminGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ctx, 'Administrators')
$isAdmin = $adminGroup.Members | Where-Object { $_.SamAccountName -eq $credUser }
if (-not $isAdmin) {
    Write-Host "  FAIL  User is not in local Administrators group. Aborting." -ForegroundColor Red
    exit 1
}
Write-Host "  OK    Credentials verified." -ForegroundColor Green
# --- End credential guard ---

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

if (-not (Test-Path $PausedFlag)) {
    Write-Host "  WARN .camera_paused flag not found -- camera may already be running" -ForegroundColor Yellow
    exit 0
}

Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Remove-Item -LiteralPath $PausedFlag -Force -ErrorAction SilentlyContinue
Write-Log "CAMERA-RESUME  Yawcam started, .camera_paused flag removed"

Write-Host "  OK   Camera resumed (Yawcam started)." -ForegroundColor Green

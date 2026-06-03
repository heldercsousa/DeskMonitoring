# migrate_cam2_creds.ps1
# One-time migration: encrypts CAM-2 credentials from cam2.conf into DPAPI blob.
# Run once as Helder (user session) — uses CurrentUser scope so only this account can decrypt.
# Output: C:\Sync\Config\cam2_creds.dpapi (Base64-encoded DPAPI-encrypted JSON)

Add-Type -AssemblyName System.Security

$ConfFile  = "C:\Sync\Config\cam2.conf"
$DpapiFile = "C:\Sync\Config\cam2_creds.dpapi"

if (-not (Test-Path $ConfFile)) {
    Write-Host "FAIL  cam2.conf not found at $ConfFile" -ForegroundColor Red
    exit 1
}

# Parse cam2.conf
$conf = @{}
Get-Content $ConfFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $conf[$parts[0].Trim()] = $parts[1].Trim()
}

$user   = $conf['CAM2_USER']
$pass   = $conf['CAM2_PASS']
$ip     = $conf['CAM2_IP']
$port   = $conf['CAM2_PORT']
$stream = $conf['CAM2_STREAM']

if (-not $user -or -not $pass -or -not $ip) {
    Write-Host "FAIL  cam2.conf missing required fields (CAM2_USER, CAM2_PASS, CAM2_IP)" -ForegroundColor Red
    exit 1
}

# Build JSON payload (all fields, IP/port/stream kept for completeness)
$payload = [ordered]@{
    user   = $user
    pass   = $pass
    ip     = $ip
    port   = if ($port) { $port } else { "554" }
    stream = if ($stream) { $stream } else { "stream1" }
}
$json = $payload | ConvertTo-Json -Compress

# DPAPI encrypt (CurrentUser scope — only Helder's account can decrypt)
$plainBytes     = [System.Text.Encoding]::UTF8.GetBytes($json)
$entropyBytes   = $null
$encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $entropyBytes,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)

# Base64-encode and write to file
$base64 = [Convert]::ToBase64String($encryptedBytes)
[System.IO.File]::WriteAllText($DpapiFile, $base64, [System.Text.Encoding]::ASCII)

Write-Host ""
Write-Host "  OK   cam2_creds.dpapi created at: $DpapiFile" -ForegroundColor Green
Write-Host "  OK   Encrypted fields: user, pass, ip, port, stream" -ForegroundColor Green
Write-Host ""
Write-Host "  cam2.conf can now be deleted. When ready, run:" -ForegroundColor Cyan
Write-Host "       Remove-Item '$ConfFile'" -ForegroundColor Cyan
Write-Host ""
Write-Host "  NOTE: cam2_creds.dpapi is gitignored and stays on this machine only." -ForegroundColor Yellow
Write-Host "        If you reinstall Windows or migrate to a new user account, re-run" -ForegroundColor Yellow
Write-Host "        this script (or setup_update.ps1 Step XX) to regenerate it." -ForegroundColor Yellow

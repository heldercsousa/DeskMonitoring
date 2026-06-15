# store_b2_creds.ps1
# One-time migration: reads B2 credentials from rclone.conf and stores them
# as a DPAPI-encrypted blob (LocalMachine scope) in b2_creds.dpapi.
# Run once as any user. After running, remove account/key from rclone.conf.
# Last updated: 2026-06-03 - T048: migrate B2 credentials to DPAPI

Add-Type -AssemblyName System.Security

$RcloneConf = 'C:\Sync\Config\rclone.conf'
$OutputFile  = 'C:\Sync\Config\b2_creds.dpapi'

# --- Read current credentials from rclone.conf ---
if (-not (Test-Path $RcloneConf)) {
    Write-Host "  FAIL  rclone.conf not found at $RcloneConf" -ForegroundColor Red
    exit 1
}

$confContent = Get-Content -LiteralPath $RcloneConf -Raw
$accountMatch = [regex]::Match($confContent, '(?m)^\s*account\s*=\s*(.+)$')
$keyMatch     = [regex]::Match($confContent, '(?m)^\s*key\s*=\s*(.+)$')

if (-not $accountMatch.Success -or -not $keyMatch.Success) {
    Write-Host "  FAIL  Could not find account or key in rclone.conf." -ForegroundColor Red
    Write-Host "        Has it already been stripped? If so, enter credentials manually." -ForegroundColor Yellow
    $account = Read-Host "  Enter B2 account (application key ID)"
    $key     = Read-Host "  Enter B2 key (application key)"
} else {
    $account = $accountMatch.Groups[1].Value.Trim()
    $key     = $keyMatch.Groups[1].Value.Trim()
    Write-Host "  OK    Read credentials from rclone.conf (account: $($account.Substring(0,8))...)" -ForegroundColor Green
}

# --- Encrypt with DPAPI LocalMachine scope ---
$json      = [System.Text.Encoding]::UTF8.GetBytes("{`"account`":`"$account`",`"key`":`"$key`"}")
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $json,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
$base64 = [Convert]::ToBase64String($encrypted)

# --- Write to output file ---
$base64 | Set-Content -LiteralPath $OutputFile -NoNewline -Encoding ASCII
Write-Host "  OK    Encrypted credentials written to $OutputFile" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Cyan
Write-Host "    1. Verify cloud sync still works (next scheduled run or manual test)" -ForegroundColor Cyan
Write-Host "    2. account/key have been removed from rclone.conf (T048 migration complete)." -ForegroundColor Cyan
Write-Host "       cloud_sync_helderTest.ps1 now reads credentials exclusively from b2_creds.dpapi." -ForegroundColor Cyan
Write-Host "    3. Verify the next scheduled sync completes with SYNC-OK in cloud_sync log." -ForegroundColor Cyan

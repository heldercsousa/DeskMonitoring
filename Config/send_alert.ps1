# send_alert.ps1
# Reusable alert sender. Sends email via Gmail SMTP + uploads payload to B2.
# Credentials loaded from alert_credentials.enc (DPAPI, current-user only).
# Never stores plaintext credentials anywhere.
#
# Usage:
#   & "C:\Sync\Config\send_alert.ps1" -Subject "..." -Body "..."
#   & "C:\Sync\Config\send_alert.ps1" -Subject "..." -Body "..." -AttachFile "C:\path\to\file.md"

param(
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$Body,
    [string]$AttachFile = '',
    [string]$B2Key = ''      # optional rclone dest path under cloudsync:helder-sync-mirror/alerts/
)

Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Mail

$CredFile = 'C:\Sync\Config\alert_credentials.enc'
$Rclone   = 'C:\Tools\Rclone\rclone.exe'
$RcloneCfg= 'C:\Sync\Config\rclone.conf'
$LogFile  = "C:\Sync\Logs\security\send_alert_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile -Encoding UTF8
}

# ============================================================
# 1. Decrypt credentials
# ============================================================
if (-not (Test-Path $CredFile)) {
    Write-Log "SEND-ALERT  FAIL  alert_credentials.enc not found"
    exit 1
}

try {
    $enc  = [System.IO.File]::ReadAllBytes($CredFile)
    $dec  = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'CurrentUser')
    $parts= [System.Text.Encoding]::UTF8.GetString($dec) -split '\|'
    $smtpHost = $parts[0]
    $smtpPort = [int]$parts[1]
    $smtpUser = $parts[2]
    $smtpPass = $parts[3]
    $smtpTo   = $parts[4]
} catch {
    Write-Log "SEND-ALERT  FAIL  credential decryption failed: $_"
    exit 1
}

# ============================================================
# 2. Send email
# ============================================================
try {
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From    = $smtpUser
    $msg.To.Add($smtpTo)
    $msg.Subject = "[SyncAlert] $Subject"
    $msg.Body    = $Body
    $msg.IsBodyHtml = $false

    if ($AttachFile -and (Test-Path $AttachFile)) {
        $att = New-Object System.Net.Mail.Attachment($AttachFile)
        $msg.Attachments.Add($att)
    }

    $client = New-Object System.Net.Mail.SmtpClient($smtpHost, $smtpPort)
    $client.EnableSsl   = $true
    $client.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPass)
    $client.Send($msg)
    $msg.Dispose()

    Write-Log "SEND-ALERT  OK  email sent: $Subject"
} catch {
    Write-Log "SEND-ALERT  FAIL  email send failed: $_"
    # Don't exit — still attempt B2 upload
}

# ============================================================
# 3. Upload to B2 (append-only alerts/ prefix)
# ============================================================
if ($B2Key -and (Test-Path $Rclone)) {
    $dest = "cloudsync:helder-sync-mirror/alerts/$B2Key"
    $src  = if ($AttachFile -and (Test-Path $AttachFile)) { $AttachFile } else {
        # Write body to temp file and upload that
        $tmp = [System.IO.Path]::GetTempFileName() + '.txt'
        $Body | Set-Content -LiteralPath $tmp -Encoding UTF8
        $tmp
    }
    $out = & $Rclone copyto $src $dest --config $RcloneCfg 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "SEND-ALERT  OK  B2 upload: $dest"
    } else {
        Write-Log "SEND-ALERT  FAIL  B2 upload failed: $out"
    }
    # Clean up temp file if we created one
    if ($src -like "$env:TEMP*") { Remove-Item $src -Force -ErrorAction SilentlyContinue }
}

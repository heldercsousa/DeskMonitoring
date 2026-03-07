#Requires -RunAsAdministrator
# fix_firewall_b2.ps1
# Removes malicious outbound BLOCK rules for Backblaze B2 IPs added by attacker.
# Run once as Administrator.

$LogFile = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}

Write-Host "`n>>> Removing malicious B2 firewall block rules" -ForegroundColor Cyan

$rulesToRemove = @(
    "Block 104.153.233.180",
    "Block 149.137.142.15"
)

foreach ($rule in $rulesToRemove) {
    $existing = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction Stop
        Write-Host "  OK   Removed: $rule" -ForegroundColor Green
        Write-Log "SECURITY  Removed malicious outbound BLOCK firewall rule: $rule"
    } else {
        Write-Host "  INFO Not found (already removed or never existed): $rule" -ForegroundColor Yellow
        Write-Log "SECURITY  Firewall rule not found (skip): $rule"
    }
}

# Verify removal
Write-Host "`n>>> Verifying B2 IPs are no longer blocked" -ForegroundColor Cyan
$remaining = @()
foreach ($rule in $rulesToRemove) {
    $check = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    if ($check) { $remaining += $rule }
}

if ($remaining.Count -eq 0) {
    Write-Host "  OK   All malicious rules removed. B2 connectivity restored." -ForegroundColor Green
    Write-Log "SECURITY  B2 firewall remediation complete — all block rules removed."
} else {
    Write-Host "  FAIL Rules still present: $($remaining -join ', ')" -ForegroundColor Red
    Write-Log "SECURITY  WARNING: Some block rules could not be removed: $($remaining -join ', ')"
}

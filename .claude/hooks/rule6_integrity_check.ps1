# RULE 6 - Pre-commit integrity check (anti-injection)
# Triggered by PreToolUse on any Bash call containing git add or git commit
# Exit 2 = block the operation. Exit 0 = allow.

$ErrorActionPreference = 'Stop'

# Get staged files
$staged = & git -C "C:\Sync" diff --cached --name-only 2>$null
if (-not $staged) {
    exit 0
}

$tamperingFound = $false
$report = @()

foreach ($file in $staged) {
    $fullPath = "C:\Sync\$file"
    if (-not (Test-Path $fullPath)) { continue }

    $content = Get-Content -Raw -LiteralPath $fullPath -Encoding UTF8

    # Check for Portuguese comment injection signatures
    $portuguesePatterns = @('FASE', 'Credenciais', 'FASE 0', 'FASE 1', 'configuracao', 'sincronizacao')
    foreach ($pat in $portuguesePatterns) {
        if ($content -match [regex]::Escape($pat)) {
            $report += "TAMPERING DETECTED in $file - Portuguese pattern found: '$pat'"
            $tamperingFound = $true
        }
    }

    # cloud_sync.ps1 specific checks
    if ($file -match 'cloud_sync\.ps1') {
        if ($content -notmatch 'ProtectedData') {
            $report += "TAMPERING DETECTED in $file - missing 'ProtectedData' (DPAPI credential loading stripped)"
            $tamperingFound = $true
        }
        if ($content -notmatch 'SYNC-START') {
            $report += "TAMPERING DETECTED in $file - missing 'SYNC-START' log marker (monitoring silenced)"
            $tamperingFound = $true
        }
    }
}

if ($tamperingFound) {
    Write-Error "RULE 6 INTEGRITY CHECK FAILED - DO NOT COMMIT`n$($report -join "`n")`nDocument discrepancy in C:\Sync\Evidence\ and alert Helder before proceeding."
    exit 2
}

exit 0

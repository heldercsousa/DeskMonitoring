# check_autoruns.ps1 (T079)
# Autoruns persistence baseline + daily diff.
#
# Captures the full Windows autostart surface (Run keys, services, drivers,
# scheduled tasks, WMI subscriptions, Winlogon, codecs, etc.) via Sysinternals
# autorunsc, compares it against a stored baseline, and logs any NEW or CHANGED
# persistence entry with the prefix [AUTORUN-DELTA]. Deltas also produce an
# Evidence file + an email/B2 alert (send_alert.ps1).
#
# Directly supports investigations T070 (resident process disabling tasks) and
# T072 (screen blink) by surfacing newly planted persistence as a daily delta.
#
# EVIDENCE-ONLY CAVEAT (T079 plan / Protecao_Win11.md): autorunsc runs in the live
# OS. An admin/kernel attacker can hide entries from it. Corroborate suspicious
# deltas against an offline mount (T082). A clean run is NOT an all-clear.
#
# Optional VirusTotal hash enrichment is wired as a hook (ties to T080) and stays
# disabled until a free VT API key is provided in the VIRUSTOTAL_API_KEY env var.
# It is HASH-ONLY - the script never uploads any file content.
#
# Schedule: FolderSync-AutoRunsCheck (SYSTEM, daily 08:45). Needs admin/SYSTEM for
# full coverage (HKLM hives, service ACLs, signature verification).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File check_autoruns.ps1
#   powershell -ExecutionPolicy Bypass -File check_autoruns.ps1 -UpdateBaseline
#       (accept the current autostart surface as the new known-good baseline -
#        run this once after a deliberate, reviewed change e.g. a Windows update)

param(
    [switch]$UpdateBaseline
)

$ErrorActionPreference = 'SilentlyContinue'

# ============================================================
# Paths
# ============================================================
$AutorunsDir = 'C:\Sync\Config\autoruns'
$Baseline    = Join-Path $AutorunsDir 'baseline.csv'
$ToolDir     = 'C:\Tools\Sysinternals'
$Tool        = Join-Path $ToolDir 'autorunsc64.exe'
$LogDir      = 'C:\Sync\Logs\security'
$LogFile     = Join-Path $LogDir "autoruns_$(Get-Date -Format 'yyyy-MM-dd').log"
$EvidenceDir = 'C:\Sync\Evidence'
$AlertScript = 'C:\Sync\Config\send_alert.ps1'

New-Item -ItemType Directory -Force -Path $AutorunsDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile -Encoding UTF8
}

Write-Log "AUTORUN-START  check_autoruns.ps1 (UpdateBaseline=$UpdateBaseline)"

# ============================================================
# 1. Locate autorunsc (download from Sysinternals if absent) - mirrors Step 21
#    Sysmon pattern. Needs network on first run only.
# ============================================================
if (-not (Test-Path -LiteralPath $Tool)) {
    Write-Log "AUTORUN-TOOL  autorunsc64.exe absent - downloading from Sysinternals"
    try {
        New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
        $zip = Join-Path $env:TEMP 'Autoruns.zip'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Autoruns.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -LiteralPath $zip -DestinationPath $ToolDir -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "AUTORUN-FAIL  download failed: $($_.Exception.Message)"
    }
}
if (-not (Test-Path -LiteralPath $Tool)) {
    Write-Log "AUTORUN-FAIL  autorunsc64.exe not available - cannot run. Install Sysinternals Autoruns to $ToolDir"
    exit 1
}

# ============================================================
# 2. Capture the current autostart surface
#    -a *  all categories | -c CSV | -h hashes | -s verify signatures
#    -nobanner suppresses the version banner | -accepteula for unattended runs
#    Output is captured from stdout (already decoded) to avoid UTF-16 file pitfalls.
# ============================================================
$raw = & $Tool -accepteula -nobanner -a '*' -c -h -s '*' 2>$null
if (-not $raw -or $raw.Count -lt 2) {
    Write-Log "AUTORUN-FAIL  autorunsc produced no output (count=$($raw.Count))"
    exit 1
}

# Drop any leading non-CSV noise; the header row starts with the Time column.
$headerIdx = ($raw | Select-String -Pattern '^"?Time"?,').LineNumber
if ($headerIdx) { $raw = $raw[($headerIdx[0]-1)..($raw.Count-1)] }

try {
    $current = $raw | ConvertFrom-Csv
} catch {
    Write-Log "AUTORUN-FAIL  CSV parse error: $($_.Exception.Message)"
    exit 1
}
if (-not $current) {
    Write-Log "AUTORUN-FAIL  CSV parsed to 0 rows"
    exit 1
}
Write-Log "AUTORUN-CAPTURE  $($current.Count) autostart entries captured"

# ============================================================
# 3. Identity + change keys
#    Identity (is this the same entry?) = location + entry + image path + launch string
#    Change signal = SHA-256 + Signer + Enabled (so a swapped binary or revoked
#    signature on an EXISTING entry is flagged too, not just brand-new entries).
# ============================================================
function Get-Field($row, $name) {
    $p = $row.PSObject.Properties[$name]
    if ($p) { [string]$p.Value } else { '' }
}
function Get-IdKey($row) {
    ('{0}|{1}|{2}|{3}' -f (Get-Field $row 'Entry Location'), (Get-Field $row 'Entry'),
        (Get-Field $row 'Image Path'), (Get-Field $row 'Launch String'))
}
function Get-ChangeSig($row) {
    ('sha256={0};signer={1};enabled={2}' -f (Get-Field $row 'SHA-256'),
        (Get-Field $row 'Signer'), (Get-Field $row 'Enabled'))
}

# ============================================================
# 4. First run OR -UpdateBaseline: write baseline and stop
# ============================================================
if ($UpdateBaseline -or -not (Test-Path -LiteralPath $Baseline)) {
    $current | Export-Csv -LiteralPath $Baseline -NoTypeInformation -Encoding UTF8
    $reason = if ($UpdateBaseline) { 'baseline updated on request' } else { 'baseline created (first run)' }
    Write-Log "AUTORUN-BASELINE  $reason - $($current.Count) entries -> $Baseline"
    Write-Log "AUTORUN-END  no diff performed (baseline write)"
    exit 0
}

# ============================================================
# 5. Load baseline + diff
# ============================================================
$baseRows = Import-Csv -LiteralPath $Baseline
$baseMap  = @{}
foreach ($r in $baseRows) { $baseMap[(Get-IdKey $r)] = $r }
$curMap   = @{}
foreach ($r in $current)  { $curMap[(Get-IdKey $r)] = $r }

$deltas = New-Object System.Collections.Generic.List[string]

foreach ($k in $curMap.Keys) {
    $cur = $curMap[$k]
    if (-not $baseMap.ContainsKey($k)) {
        $line = ("[AUTORUN-DELTA] NEW location='{0}' entry='{1}' image='{2}' launch='{3}' signer='{4}' sha256={5}" -f `
            (Get-Field $cur 'Entry Location'), (Get-Field $cur 'Entry'), (Get-Field $cur 'Image Path'),
            (Get-Field $cur 'Launch String'), (Get-Field $cur 'Signer'), (Get-Field $cur 'SHA-256'))
        $deltas.Add($line)
    } elseif ((Get-ChangeSig $cur) -ne (Get-ChangeSig $baseMap[$k])) {
        $line = ("[AUTORUN-DELTA] CHANGED location='{0}' entry='{1}' image='{2}' was({3}) now({4})" -f `
            (Get-Field $cur 'Entry Location'), (Get-Field $cur 'Entry'), (Get-Field $cur 'Image Path'),
            (Get-ChangeSig $baseMap[$k]), (Get-ChangeSig $cur))
        $deltas.Add($line)
    }
}
foreach ($k in $baseMap.Keys) {
    if (-not $curMap.ContainsKey($k)) {
        $b = $baseMap[$k]
        $line = ("[AUTORUN-DELTA] REMOVED location='{0}' entry='{1}' image='{2}'" -f `
            (Get-Field $b 'Entry Location'), (Get-Field $b 'Entry'), (Get-Field $b 'Image Path'))
        $deltas.Add($line)
    }
}

# ============================================================
# 6. Optional VirusTotal HASH-ONLY enrichment (T080 hook, disabled w/o key)
#    Never uploads files - submits the SHA-256 only. Best-effort, throttled.
# ============================================================
function Add-VtNote([string]$line) {
    $key = $env:VIRUSTOTAL_API_KEY
    if (-not $key) { return $line }
    if ($line -notmatch 'sha256=([0-9A-Fa-f]{64})') { return $line }
    $sha = $Matches[1]
    try {
        $hdr = @{ 'x-apikey' = $key }
        $resp = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/files/$sha" -Headers $hdr -Method Get -ErrorAction Stop
        $mal = $resp.data.attributes.last_analysis_stats.malicious
        Start-Sleep -Milliseconds 15500   # respect free tier 4 req/min
        return "$line vt_malicious=$mal"
    } catch {
        return "$line vt=lookup-failed"
    }
}

# ============================================================
# 7. Report
# ============================================================
if ($deltas.Count -eq 0) {
    Write-Log "AUTORUN-OK  no new/changed persistence vs baseline ($($current.Count) entries)"
    Write-Log "AUTORUN-END"
} else {
    Write-Log "AUTORUN-ALERT  $($deltas.Count) persistence delta(s) vs baseline"
    $enriched = New-Object System.Collections.Generic.List[string]
    foreach ($d in $deltas) {
        $e = Add-VtNote $d
        Write-Log $e
        $enriched.Add($e)
    }

    # Evidence file (append-only naming; unique per run)
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $evFile = Join-Path $EvidenceDir "$($stamp)_autorun-delta.md"
    $body = @()
    $body += "# Autoruns persistence delta - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $body += ""
    $body += "Detected by check_autoruns.ps1 (T079). EVIDENCE-ONLY: live-OS scan; an"
    $body += "admin/kernel attacker can hide entries. Corroborate against an offline"
    $body += "mount (T082). $($deltas.Count) delta(s) vs baseline:"
    $body += ""
    $body += '```'
    $body += $enriched
    $body += '```'
    $body += ""
    $body += "Baseline: $Baseline"
    $body += "If these changes are expected, re-baseline with: check_autoruns.ps1 -UpdateBaseline"
    $body -join "`r`n" | Set-Content -LiteralPath $evFile -Encoding UTF8
    Write-Log "AUTORUN-EVIDENCE  wrote $evFile"

    # Alert (email + B2)
    if (Test-Path -LiteralPath $AlertScript) {
        $alertBody = "Autoruns persistence delta detected ($($deltas.Count)):`n`n" + ($enriched -join "`n")
        & powershell.exe -ExecutionPolicy Bypass -File $AlertScript `
            -Subject "AUTORUN-DELTA: $($deltas.Count) new/changed persistence entries" `
            -Body $alertBody `
            -AttachFile $evFile `
            -B2Key "autoruns/$($stamp)_autorun-delta.md" 2>$null
        Write-Log "AUTORUN-ALERT-SENT  send_alert.ps1 invoked"
    }
    Write-Log "AUTORUN-END  deltas present - baseline NOT auto-updated (review then -UpdateBaseline)"
}

# ============================================================
# 8. 30-day log rotation (matches cloud_sync retention)
# ============================================================
Get-ChildItem -LiteralPath $LogDir -Filter 'autoruns_*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

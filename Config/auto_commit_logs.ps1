# auto_commit_logs.ps1
# Commits any dirty Logs/ files to git once per day.
# Runs as LAP\helde (interactive) via Task Scheduler at 23:30.
# Skips silently if nothing changed or if git is locked.

$RepoRoot = 'C:\Sync'
$LogDir   = 'C:\Sync\Logs'
$EcoLog   = "$LogDir\ecosystem\ecosystem_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-EcoLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $EcoLog
}

# Guard: abort if git index is locked (another git op in progress)
$lockFile = "$RepoRoot\.git\index.lock"
if (Test-Path $lockFile) {
    Write-EcoLog "GIT-COMMIT-LOGS  SKIP  git index.lock exists - skipping this run"
    exit 0
}

# Check for dirty Logs/ and Evidence/ files
$statusLines = & git -C $RepoRoot status --porcelain -- Logs/ Evidence/ 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git status failed: $statusLines"
    exit 1
}

$dirty = $statusLines | Where-Object { $_ -match '\S' }
if (-not $dirty) {
    Write-EcoLog "GIT-COMMIT-LOGS  SKIP  no Logs/ or Evidence/ changes"
    exit 0
}

# Stage and commit
$commitMsg = "logs: auto-commit $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

& git -C $RepoRoot add Logs/ Evidence/ 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git add failed"
    exit 1
}

$commitOut = & git -C $RepoRoot commit -m $commitMsg 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  OK  committed $($dirty.Count) Logs/ file(s): $commitMsg"
} else {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git commit failed: $commitOut"
    exit 1
}

# auto_commit_logs.ps1
# Commits dirty Logs/ and Evidence/ files to git, then PUSHES them off-box to
# the GitHub origin remote so a local-admin attacker cannot retroactively erase
# tamper evidence (T077 interim mitigation until a real WEF collector exists).
# Runs as LAP\helde (interactive) via Task Scheduler hourly.
# Skips silently if nothing changed or if git is locked. Push failure is non-fatal.

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

# Resolve current branch once (used for both commit context and push target)
$branch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch) { $branch = 'master' }

# Check for dirty Logs/ and Evidence/ files
$statusLines = & git -C $RepoRoot status --porcelain -- Logs/ Evidence/ 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git status failed: $statusLines"
    exit 1
}

$dirty = $statusLines | Where-Object { $_ -match '\S' }

if ($dirty) {
    # Stage and commit
    $commitMsg = "logs: auto-commit $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    & git -C $RepoRoot add Logs/ Evidence/ 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git add failed"
        exit 1
    }

    $commitOut = & git -C $RepoRoot commit -m $commitMsg 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-EcoLog "GIT-COMMIT-LOGS  OK  committed $($dirty.Count) Logs/+Evidence/ file(s): $commitMsg"
    } else {
        Write-EcoLog "GIT-COMMIT-LOGS  FAIL  git commit failed: $commitOut"
        exit 1
    }
} else {
    Write-EcoLog "GIT-COMMIT-LOGS  SKIP  no Logs/ or Evidence/ changes"
}

# Off-box forwarding (T077 interim mitigation): push to GitHub so the committed
# evidence survives local tampering / .git history rewrite. Push every run even
# when nothing new was committed, in case a prior run committed but failed to push.
$ahead = (& git -C $RepoRoot rev-list --count "origin/$branch..$branch" 2>$null)
if ($ahead -and ($ahead -as [int]) -gt 0) {
    $pushOut = & git -C $RepoRoot push origin $branch 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-EcoLog "LOG-FORWARD  OK  pushed $ahead commit(s) off-box to origin/$branch"
    } else {
        Write-EcoLog "LOG-FORWARD  WARN  push to origin/$branch failed (off-box copy stale): $pushOut"
    }
} else {
    Write-EcoLog "LOG-FORWARD  SKIP  local branch not ahead of origin/$branch - already off-box"
}

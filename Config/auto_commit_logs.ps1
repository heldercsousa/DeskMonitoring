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

# Guard: stale index.lock self-heal (T096). A stale lock silently blocked this
# task for ~26h on 2026-07-05/06, defeating the T077 off-box evidence push.
# Young lock or live git.exe = legit operation in progress -> skip (but alert
# after 3 consecutive skips). Lock older than 10 min with no git.exe = stale ->
# remove it and continue; alert if removal fails (Deny-ACL trap on .git).
$lockFile  = "$RepoRoot\.git\index.lock"
$SkipsFile = "$RepoRoot\Config\.gitlock_skips"
if (Test-Path $lockFile) {
    $lockAgeMin = [math]::Round(((Get-Date) - (Get-Item $lockFile).LastWriteTime).TotalMinutes, 1)
    $gitAlive = @(Get-Process -Name git -ErrorAction SilentlyContinue).Count -gt 0
    if ($lockAgeMin -gt 10 -and -not $gitAlive) {
        Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $lockFile) {
            Write-EcoLog "GIT-COMMIT-LOGS  FAIL  stale index.lock (age ${lockAgeMin}min) could not be removed - off-box evidence push blocked. Admin fix: icacls 'C:\Sync\.git' /remove:d (Everyone/Users/Admins) /T then delete the lock"
            & "$RepoRoot\Config\send_alert.ps1" -Subject "GIT-LOCK-STUCK" -Body "auto_commit_logs: stale .git\index.lock (age ${lockAgeMin}min, no git process) cannot be removed. Hourly off-box evidence push is blocked until fixed." 2>&1 | Out-Null
            exit 1
        }
        Write-EcoLog "GIT-COMMIT-LOGS  GIT-LOCK-HEALED  removed stale index.lock (age ${lockAgeMin}min, no git process) - continuing"
    } else {
        $skips = 0
        if (Test-Path $SkipsFile) { $skips = [int]((Get-Content -LiteralPath $SkipsFile -ErrorAction SilentlyContinue | Select-Object -First 1) -as [int]) }
        $skips++
        Set-Content -LiteralPath $SkipsFile -Value $skips
        Write-EcoLog "GIT-COMMIT-LOGS  SKIP  git index.lock exists (age ${lockAgeMin}min, gitAlive=$gitAlive) - skipping this run (consecutive=$skips)"
        if ($skips -eq 3) {
            & "$RepoRoot\Config\send_alert.ps1" -Subject "GIT-LOCK-SKIPS" -Body "auto_commit_logs: 3 consecutive hourly runs skipped on .git\index.lock (current age ${lockAgeMin}min, gitAlive=$gitAlive). Off-box evidence push is stalled - investigate." 2>&1 | Out-Null
        }
        exit 0
    }
}
# Healthy run (or healed): reset the consecutive-skip counter
if (Test-Path $SkipsFile) { Set-Content -LiteralPath $SkipsFile -Value 0 }

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

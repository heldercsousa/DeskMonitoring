# post_commit_push.ps1
# Called by .git/hooks/post-commit after every commit.
# Pushes to GitHub (origin master). On failure: emails alert + uploads to B2.

$RepoRoot = 'C:\Sync'
$LogFile  = "C:\Sync\Logs\security\git_push_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Add-Content -LiteralPath $LogFile -Encoding UTF8
}

# Get last commit info for the alert message
$commitHash = & git -C $RepoRoot rev-parse --short HEAD 2>&1
$commitMsg  = & git -C $RepoRoot log -1 --pretty=%s 2>&1

Write-Log "GIT-PUSH  Pushing $commitHash - $commitMsg"

$pushOut = & git -C $RepoRoot push origin master 2>&1
$pushExit = $LASTEXITCODE

if ($pushExit -eq 0) {
    Write-Log "GIT-PUSH  OK  $commitHash pushed to origin/master"
    exit 0
}

# Push failed — alert immediately
Write-Log "GIT-PUSH  FAIL  exit $pushExit : $pushOut"

$body = @"
GIT PUSH FAILED on $env:COMPUTERNAME
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Commit: $commitHash - $commitMsg
Exit code: $pushExit

Git output:
$pushOut

This may indicate:
- Network blocked by attacker (B2/GitHub firewall rule)
- Git credentials tampered
- Repository state corrupted
"@

& pwsh.exe -NonInteractive -ExecutionPolicy Bypass -File 'C:\Sync\Config\send_alert.ps1' `
    -Subject "GIT PUSH FAILED on $env:COMPUTERNAME" `
    -Body $body `
    -B2Key "git_push_fail_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"

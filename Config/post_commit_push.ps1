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

# Never let a credential helper block this non-interactive hook.
# 2026-07-24 incident: GCM (manager-core) tried an interactive browser OAuth flow
# and blocked forever, hanging 20 hourly runs and leaking 100 git processes.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE     = 'never'

$job = Start-Job -ScriptBlock {
    param($root)
    $out = & git -C $root push origin master 2>&1
    [pscustomobject]@{ Out = ($out | Out-String); Code = $LASTEXITCODE }
} -ArgumentList $RepoRoot

if (Wait-Job $job -Timeout 120) {
    $res      = Receive-Job $job
    $pushOut  = $res.Out
    $pushExit = $res.Code
} else {
    Stop-Job $job -ErrorAction SilentlyContinue
    # Kill any git process this hook left behind so they cannot accumulate.
    Get-CimInstance Win32_Process -Filter "Name='git.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$RepoRoot*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $pushOut  = "push exceeded 120s timeout - job stopped, stray git processes killed"
    $pushExit = 124
}
Remove-Job $job -Force -ErrorAction SilentlyContinue

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

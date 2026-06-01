Set-Location 'C:\Sync'

$status = & git status --short 2>$null

$relevant = $status | Where-Object {
    $_ -and
    $_ -notmatch 'Logs[/\\]' -and
    $_ -notmatch 'Mirror[/\\]' -and
    $_ -notmatch 'rclone\.conf' -and
    $_ -notmatch 'credentials\.enc' -and
    $_ -notmatch 'realtime\.ffs_real' -and
    $_ -notmatch '\.ecosystem_state' -and
    $_ -notmatch '\.camera_paused' -and
    $_ -notmatch 'bash\.exe\.stackdump' -and
    $_ -notmatch 'alert_credentials'
}

if ($relevant) {
    $files = ($relevant | ForEach-Object { $_.Trim() }) -join "`n  "
    Write-Output "UNCOMMITTED CHANGES in C:\Sync - please run /project:commit before finishing:`n  $files"
    exit 2
}

exit 0

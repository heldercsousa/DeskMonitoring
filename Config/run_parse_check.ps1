$scripts = @('DailySecurityCheck.ps1','yawcam_monitor_v4.ps1','cam2_relay.ps1','wdog.ps1','auditor.ps1','cloud_sync.ps1')
$allPass = $true
foreach ($s in $scripts) {
    $path = "C:\Sync\Config\$s"
    $t = $null; $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e) | Out-Null
    $status = if ($e.Count -eq 0) { 'PASS' } else { 'FAIL'; $allPass = $false }
    Write-Host "$status  $s  ($($e.Count) errors)"
    if ($e.Count -gt 0) { $e | ForEach-Object { Write-Host "  L$($_.Extent.StartLineNumber): $($_.Message)" } }
}
exit $(if ($allPass) { 0 } else { 1 })

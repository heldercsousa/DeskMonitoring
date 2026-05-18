$scripts = @('cloud_sync.ps1','cam2_relay.ps1','check_status.ps1','health_check_all.ps1','check_camera.ps1','install_service.ps1','install_auditor_service.ps1','setup_update.ps1','setup_all.ps1')
foreach ($f in $scripts) {
    $t=$null;$e=$null
    [System.Management.Automation.Language.Parser]::ParseFile("C:\Sync\Config\$f",[ref]$t,[ref]$e)
    Write-Host "$f`: $($e.Count) errors"
}

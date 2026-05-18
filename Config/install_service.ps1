$nssm = 'C:\Tools\NSSM\nssm.exe'
$svcName = 'FolderSyncWatchdog'

# Remove existing service if present
& $nssm stop $svcName 2>$null
& $nssm remove $svcName confirm 2>$null

# Install service
& $nssm install $svcName powershell.exe
& $nssm set $svcName AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
& $nssm set $svcName DisplayName 'Folder Sync Watchdog Service'
& $nssm set $svcName Description 'Monitors and restarts folder sync processes (RealTimeSync + cloud backup task).'
& $nssm set $svcName Start SERVICE_AUTO_START
& $nssm set $svcName AppStdout 'C:\Sync\Logs\services\watchdog_svc.log'
& $nssm set $svcName AppStderr 'C:\Sync\Logs\services\watchdog_svc_err.log'
& $nssm set $svcName AppRotateFiles 1
& $nssm set $svcName AppRotateBytes 1048576

Start-Service $svcName
Write-Host "Service '$svcName' installed and started"

# install_auditor_service.ps1
# Installs FolderSyncAuditor as an NSSM Windows service.
# Run as Administrator.

$nssm    = 'C:\Tools\NSSM\nssm.exe'
$svcName = 'FolderSyncAuditor'

if (-not (Test-Path $nssm)) {
    Write-Error "NSSM not found at $nssm"
    exit 1
}

# Stop and remove existing service if present
& $nssm stop   $svcName 2>$null
& $nssm remove $svcName confirm 2>$null
Start-Sleep -Seconds 2

# Install
& $nssm install $svcName powershell.exe
& $nssm set $svcName AppParameters '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\auditor.ps1'
& $nssm set $svcName DisplayName   'Folder Sync Security Auditor'
& $nssm set $svcName Description   'Monitors file changes, remote access, and service tampering for the FolderSync ecosystem.'
& $nssm set $svcName Start         SERVICE_AUTO_START
& $nssm set $svcName AppStdout     'C:\Sync\Logs\auditor_svc.log'
& $nssm set $svcName AppStderr     'C:\Sync\Logs\auditor_svc_err.log'
& $nssm set $svcName AppRotateFiles  1
& $nssm set $svcName AppRotateBytes  2097152   # 2 MB

# Restart delay: 30s (matches NSSM default, avoids false startup-gap triggers)
& $nssm set $svcName AppRestartDelay 30000

Start-Service $svcName
$svc = Get-Service $svcName -ErrorAction SilentlyContinue
Write-Host "Service '$svcName' installed - status: $($svc.Status)"
Write-Host ""
Write-Host "Next step: run enable_file_auditing.ps1 (as Administrator) to activate Security Event Log attribution."

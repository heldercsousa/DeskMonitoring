#Requires -RunAsAdministrator
# enable_config_auditing.ps1
# Adds SACL (write audit) to C:\Sync\Config\ so Windows Security log event 4663
# records the exact process name + PID whenever any file in Config\ is written.

$ConfigPath = 'C:\Sync\Config'

Write-Host "`n>>> Enabling SACL write auditing on $ConfigPath" -ForegroundColor Cyan

# Ensure audit policy records object access successes
auditpol /set /subcategory:"File System" /success:enable /failure:enable | Out-Null
Write-Host "  OK   auditpol: File System auditing enabled" -ForegroundColor Green

# Apply SACL: audit Write by Everyone, inherit to all children
$acl = Get-Acl -Path $ConfigPath -Audit

$auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
    [System.Security.Principal.SecurityIdentifier]'S-1-1-0',  # Everyone
    [System.Security.AccessControl.FileSystemRights]'WriteData,AppendData,WriteAttributes,WriteExtendedAttributes',
    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [System.Security.AccessControl.PropagationFlags]'None',
    [System.Security.AccessControl.AuditFlags]'Success'
)

$acl.AddAuditRule($auditRule)
Set-Acl -Path $ConfigPath -AclObject $acl

Write-Host "  OK   SACL applied to $ConfigPath (recursive, Write, Success)" -ForegroundColor Green
Write-Host "`n  >>> From now on: any write to Config\ will appear in Windows Security log as event 4663" -ForegroundColor Yellow
Write-Host "  >>> To read: Get-WinEvent -FilterHashtable @{LogName='Security';Id=4663} | Where-Object { `$_.Message -match 'Sync.Config' }" -ForegroundColor Yellow

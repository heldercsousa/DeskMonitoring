$WatchedFolder = 'C:\Users\helde\Repos\Bois'
$RootPath      = 'C:\Sync'
$LogPath       = "C:\Sync\Logs"
$MirrorPath    = "C:\Sync\Mirror"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Acesso negado. Execute como Administrador."
    exit 1
}

# Configuração do SO
auditpol /set /subcategory:"Sistema de Arquivos" /success:enable /failure:enable

# SACL na pasta Bois
$AclData = Get-Acl -Path $WatchedFolder -Audit
$Everyone = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'
$AuditRule = New-Object System.Security.AccessControl.FileSystemAuditRule($Everyone, "Delete,DeleteSubdirectoriesAndFiles,WriteData", "ContainerInherit,ObjectInherit", "None", "Success,Failure")
$AclData.SetAuditRule($AuditRule)
Set-Acl -Path $WatchedFolder -AclObject $AclData

if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }

# NOTE: ACL/Deny Delete rules are managed exclusively by setup_all.ps1 Step 4.
# This script only handles SACL (audit) configuration. Do not add ACL rules here.

Write-Host "Configuração de Auditoria aplicada com sucesso." -ForegroundColor Green
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

# Blindagem da Raiz C:\Sync (Logs e Configs)
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }
$RootAcl = Get-Acl $RootPath
$RootAcl.SetAccessRuleProtection($true, $true)
$DenyRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Everyone, "Delete,DeleteSubdirectoriesAndFiles", "ContainerInherit,ObjectInherit", "None", "Deny")
$RootAcl.AddAccessRule($DenyRule)
Set-Acl $RootPath $RootAcl

# Exceção para Mirror (Permite deleção via SYSTEM)
if (Test-Path $MirrorPath) {
    $MirrorAcl = Get-Acl $MirrorPath
    $SystemSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'
    $SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $UserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $UserRule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserSid, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    $MirrorAcl.SetAccessRuleProtection($true, $false) 
    $MirrorAcl.AddAccessRule($SystemRule)
    $MirrorAcl.AddAccessRule($UserRule)
    Set-Acl $MirrorPath $MirrorAcl
}

Write-Host "Configuração de Auditoria e Blindagem aplicada com sucesso." -ForegroundColor Green
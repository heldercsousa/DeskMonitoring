# protect_sync_folders.ps1
# Repair script: re-applies the canonical Deny Delete ACL rules for C:\Sync.
# SINGLE SOURCE OF TRUTH is setup_all.ps1 Step 4.
# This script mirrors those exact rules for manual repair without running full setup.
# Run as Administrator.
#
# Canonical ACL table (matches setup_all.ps1 Step 4):
#   C:\Sync (root)    Deny Delete folder-only (no inherit)  -- prevent root deletion
#   C:\Sync\Config    Deny Delete + Children (full inherit)  -- scripts tamper-proof
#   C:\Sync\Logs      Deny Delete + Children (full inherit)  -- logs tamper-proof
#   C:\Sync\Evidence  Deny Delete + Children (full inherit)  -- forensic tamper-proof
#   C:\Sync\.git      NONE (liberate)                        -- git needs full write
#   C:\Sync\Mirror    NONE at folder level                   -- cloud_sync.ps1 manages per-file ACLs

#Requires -RunAsAdministrator

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }

$sidEveryone = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')

function Set-DenyDeleteFull($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone,
        [System.Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles',
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Deny
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

function Set-DenyDeleteFolderOnly($path) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidEveryone,
        [System.Security.AccessControl.FileSystemRights]'Delete',
        [System.Security.AccessControl.InheritanceFlags]::None,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Deny
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

Write-Step "Applying canonical ACL rules"

Set-DenyDeleteFolderOnly 'C:\Sync'
Write-OK "C:\Sync root locked (folder-only, no inherit)"

Set-DenyDeleteFull 'C:\Sync\Config'
Write-OK "C:\Sync\Config locked (Deny Delete recursive)"

Set-DenyDeleteFull 'C:\Sync\Logs'
Write-OK "C:\Sync\Logs locked (Deny Delete recursive)"

if (-not (Test-Path 'C:\Sync\Evidence')) { New-Item -ItemType Directory -Path 'C:\Sync\Evidence' -Force | Out-Null }
Set-DenyDeleteFull 'C:\Sync\Evidence'
Write-OK "C:\Sync\Evidence locked (Deny Delete recursive)"

Write-Step "Liberating C:\Sync\.git"
if (Test-Path 'C:\Sync\.git') {
    icacls "C:\Sync\.git" /remove:d "*S-1-1-0" /T /Q | Out-Null
    icacls "C:\Sync\.git" /remove:d "*S-1-5-32-545" /T /Q | Out-Null
    icacls "C:\Sync\.git" /remove:d "*S-1-5-32-544" /T /Q | Out-Null
    Write-OK "C:\Sync\.git liberated (git unrestricted)"
} else {
    Write-Warn "C:\Sync\.git not found"
}

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "  C:\Sync root    : folder delete blocked (no inheritance)"
Write-Host "  Config/Logs/Evidence : all deletions blocked recursively"
Write-Host "  .git            : no Deny Delete (git unrestricted)"
Write-Host "  Mirror          : no folder ACL (cloud_sync.ps1 manages per-file ACLs)"

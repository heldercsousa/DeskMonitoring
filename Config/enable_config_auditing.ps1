#Requires -RunAsAdministrator
# enable_config_auditing.ps1
# Applies SACL (write audit) to critical C:\Sync paths so Windows Security log
# event 4663 records the exact process + PID for every write.
#
# Covered paths:
#   C:\Sync\Config\   — scripts (tamper target)
#   C:\Sync\Evidence\ — forensic files
#   C:\Sync\.git\     — git index (mass-deletion attack target)
#
# Also increases Security log max size to 512 MB to retain history longer.
# Events go to Windows Security log — NOT to a file in C:\Sync.

Import-Module Microsoft.PowerShell.Security -ErrorAction Stop

function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }

# ============================================================
# 1. Enable File System audit policy (locale-safe GUID)
#    {0CCE921D-69AE-11D9-BED3-505054503030} = File System
# ============================================================
Write-Step "Enabling File System audit policy"
auditpol /set /subcategory:"{0CCE921D-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-OK "auditpol: File System auditing enabled (success + failure)"
} else {
    Write-Warn "auditpol returned $LASTEXITCODE - continuing"
}

# ============================================================
# 2. Increase Security log max size to 512 MB (default is 20 MB)
#    Prevents rollover from hiding attacker activity
# ============================================================
Write-Step "Increasing Security log max size to 512 MB"
$maxSizeBytes = 512 * 1024 * 1024
wevtutil sl Security /ms:$maxSizeBytes | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-OK "Security log max size set to 512 MB"
} else {
    Write-Warn "wevtutil returned $LASTEXITCODE"
}

# ============================================================
# 3. Helper: apply SACL to a path
# ============================================================
function Set-WriteSACL($path) {
    if (-not (Test-Path $path)) {
        Write-Warn "$path does not exist - skipping"
        return
    }
    $acl = Get-Acl -Path $path -Audit

    $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
        [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
        [System.Security.AccessControl.FileSystemRights]'WriteData,AppendData,WriteAttributes,WriteExtendedAttributes,ChangePermissions,TakeOwnership',
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
        [System.Security.AccessControl.PropagationFlags]'None',
        [System.Security.AccessControl.AuditFlags]'Success,Failure'
    )

    # Remove existing identical rule first to avoid duplicates
    $acl.RemoveAuditRule($auditRule) | Out-Null
    $acl.AddAuditRule($auditRule)
    Set-Acl -Path $path -AclObject $acl
    Write-OK "SACL applied: $path"
}

# ============================================================
# 4. Apply SACL to each critical path
# ============================================================
Write-Step "Applying SACL to critical paths"
Set-WriteSACL 'C:\Sync\Config'
Set-WriteSACL 'C:\Sync\Evidence'
Set-WriteSACL 'C:\Sync\.git'

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SACL auditing active on Config\, Evidence\, .git\" -ForegroundColor Green
Write-Host "  Events -> Windows Security Log (event 4663)" -ForegroundColor Green
Write-Host "  Security log size: 512 MB" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Suspicious-only filter: FolderSync-AuditFilter task (every 5 min)" -ForegroundColor Cyan
Write-Host "  Output: C:\Sync\Evidence\suspicious_writes_YYYY-MM-DD.md" -ForegroundColor Cyan
Write-Host ""

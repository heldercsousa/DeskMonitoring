#Requires -RunAsAdministrator
# enable_registry_auditing.ps1 (T075)
# Enables the Registry audit subcategory and applies a SACL (write/value audit)
# to the guarded registry keys so a write produces Windows Security event 4657
# (value modified) / 4663 (object access). auditor.ps1 then correlates the event
# against process-creation telemetry (Sysmon Event 1, fallback 4688) to unmask
# the true caller behind the svchost.exe Power-service proxy.
#
# Guarded keys:
#   HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes  (USB Selective
#       Suspend, sleep / unattended-sleep timeouts - the T070 re-enable vector)
#   HKLM\...\CurrentVersion\Run    (machine autostart)
#   HKCU\...\CurrentVersion\Run    (user autostart)
#
# Events -> Windows Security log (4657/4663). No file written under C:\Sync.

function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }

# ============================================================
# 1. Enable Registry audit policy (locale-safe GUID)
#    {0CCE921E-69AE-11D9-BED3-505054503030} = Registry (Object Access)
# ============================================================
Write-Step "Enabling Registry audit policy"
auditpol /set /subcategory:"{0CCE921E-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-OK "auditpol: Registry auditing enabled (success + failure)"
} else {
    Write-Warn "auditpol returned $LASTEXITCODE - continuing"
}

# ============================================================
# 2. Helper: apply registry SACL (audit every value write / subkey change)
#    S-1-1-0 = Everyone; ContainerInherit so child scheme keys are covered.
# ============================================================
function Set-RegSACL($regPath) {
    if (-not (Test-Path $regPath)) {
        Write-Warn "$regPath does not exist - skipping"
        return
    }
    # -ErrorAction Stop is required: Set-Acl/Get-Acl raise NON-terminating errors,
    # so without it the catch never fires and a denied SACL still prints OK
    # (observed 2026-06-29 on the protected HKLM\SYSTEM PowerSchemes key, which an
    # elevated user cannot SACL without SeSecurityPrivilege/ownership).
    try {
        $acl  = Get-Acl -Path $regPath -Audit -ErrorAction Stop
        $rule = New-Object System.Security.AccessControl.RegistryAuditRule(
            [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
            [System.Security.AccessControl.RegistryRights]'SetValue,CreateSubKey,Delete,WriteKey,ChangePermissions,TakeOwnership',
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit',
            [System.Security.AccessControl.PropagationFlags]'None',
            [System.Security.AccessControl.AuditFlags]'Success,Failure'
        )
        $acl.RemoveAuditRule($rule) | Out-Null
        $acl.AddAuditRule($rule)
        Set-Acl -Path $regPath -AclObject $acl -ErrorAction Stop
        Write-OK "SACL applied: $regPath"
    } catch {
        Write-Warn "Failed to apply SACL to $regPath : $($_.Exception.Message)"
    }
}

# ============================================================
# 3. Apply SACL to each guarded key
# ============================================================
Write-Step "Applying SACL to guarded registry keys"
Set-RegSACL 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
Set-RegSACL 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
Set-RegSACL 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Registry SACL auditing active on Power\PowerSchemes + Run keys" -ForegroundColor Green
Write-Host "  Writes -> Windows Security log (event 4657 / 4663)" -ForegroundColor Green
Write-Host "  auditor.ps1 correlates against Sysmon Event 1 (fallback 4688)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

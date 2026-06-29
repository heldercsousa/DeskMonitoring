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
#
# SACL write uses advapi32 RegSetKeySecurity via P/Invoke (T089, 2026-06-29):
# the protected HKLM\SYSTEM PowerSchemes key cannot be SACL'd through Get-Acl/Set-Acl
# (the elevated user lacks WRITE_DAC, and that managed path also depends on the
# Microsoft.PowerShell.Security module which does not load in every context, e.g.
# SYSTEM). The native path enables SeSecurityPrivilege and opens the key with
# ACCESS_SYSTEM_SECURITY, which is the only access a SACL write actually requires.

function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }

# ============================================================
# 0. Native helpers: enable SeSecurityPrivilege + RegSetKeySecurity
#    (no Microsoft.PowerShell.Security dependency - works under SYSTEM too)
# ============================================================
$regSecSig = @"
using System;
using System.Runtime.InteropServices;
public static class RegSec {
    [DllImport("ntdll.dll")]
    public static extern int RtlAdjustPrivilege(int Privilege, bool bEnablePrivilege, bool IsThreadPrivilege, out bool PreviousValue);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern int RegOpenKeyEx(IntPtr hKey, string subKey, int options, int samDesired, out IntPtr phkResult);
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern int RegSetKeySecurity(IntPtr hKey, int SecurityInformation, byte[] pSecurityDescriptor);
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern int RegCloseKey(IntPtr hKey);
}
"@
Add-Type -TypeDefinition $regSecSig
$prevPriv = $false
[RegSec]::RtlAdjustPrivilege(8, $true, $false, [ref]$prevPriv) | Out-Null   # 8 = SeSecurityPrivilege

$ACCESS_SYSTEM_SECURITY = 0x01000000
$SACL_SECURITY_INFO     = 0x00000008

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
#    Builds the SACL in managed code, persists it natively via RegSetKeySecurity.
# ============================================================
function Set-RegSACL($psPath) {
    if ($psPath -match '^HKLM:\\(.+)$') {
        $baseKey = [Microsoft.Win32.Registry]::LocalMachine; $hive = [IntPtr](-2147483646); $sub = $Matches[1]
    } elseif ($psPath -match '^HKCU:\\(.+)$') {
        $baseKey = [Microsoft.Win32.Registry]::CurrentUser;  $hive = [IntPtr](-2147483647); $sub = $Matches[1]
    } else {
        Write-Warn "Unsupported registry root: $psPath"; return
    }

    $read = $baseKey.OpenSubKey($sub, $false)
    if (-not $read) { Write-Warn "$psPath does not exist - skipping"; return }
    try {
        $sec  = $read.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Audit)
        $rule = New-Object System.Security.AccessControl.RegistryAuditRule(
            [System.Security.Principal.SecurityIdentifier]'S-1-1-0',
            [System.Security.AccessControl.RegistryRights]'SetValue,CreateSubKey,Delete,WriteKey,ChangePermissions,TakeOwnership',
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit',
            [System.Security.AccessControl.PropagationFlags]'None',
            [System.Security.AccessControl.AuditFlags]'Success,Failure'
        )
        $sec.RemoveAuditRule($rule) | Out-Null
        $sec.AddAuditRule($rule)
        $bin = $sec.GetSecurityDescriptorBinaryForm()
    } catch {
        Write-Warn "Failed to build SACL for $psPath : $($_.Exception.Message)"; $read.Close(); return
    } finally {
        if ($read) { $read.Close() }
    }

    $h = [IntPtr]::Zero
    $rc = [RegSec]::RegOpenKeyEx($hive, $sub, 0, $ACCESS_SYSTEM_SECURITY, [ref]$h)
    if ($rc -ne 0) { Write-Warn "RegOpenKeyEx failed (rc=$rc) for $psPath"; return }
    $rc2 = [RegSec]::RegSetKeySecurity($h, $SACL_SECURITY_INFO, $bin)
    [RegSec]::RegCloseKey($h) | Out-Null
    if ($rc2 -ne 0) { Write-Warn "RegSetKeySecurity failed (rc=$rc2) for $psPath"; return }

    # Verify the audit rule actually landed
    $v  = $baseKey.OpenSubKey($sub, $false)
    $au = $v.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Audit).GetAuditRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    $v.Close()
    if ($au | Where-Object { $_.IdentityReference.Value -eq 'S-1-1-0' }) {
        Write-OK "SACL applied + verified: $psPath"
    } else {
        Write-Warn "SACL set but verify found no Everyone rule: $psPath"
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

# protect_sync_folders.ps1
# Protects C:\Sync folder structure from deletion.
# Uses SIDs instead of localized names (works on any Windows language).
# Run as Administrator.

# ---------------------------------------------------------------------------
# Identities via SID (language-independent)
# ---------------------------------------------------------------------------
$sidEveryone  = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')       # Everyone / Todos
$sidAdmins    = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')  # BUILTIN\Administrators
$sidSystem    = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')      # NT AUTHORITY\SYSTEM
$sidCurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User         # current user SID

function Write-Step($msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Step 0 — Clean up any previous incorrect rules
# ---------------------------------------------------------------------------
Write-Step "Step 0 - Removing previous incorrect Deny rules"

foreach ($path in @('C:\Sync', 'C:\Sync\Config', 'C:\Sync\Logs', 'C:\Sync\Mirror')) {
    $acl = Get-Acl $path
    $denyRules = $acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' }
    foreach ($rule in $denyRules) {
        $acl.RemoveAccessRule($rule) | Out-Null
        Write-Host "  Removed Deny rule [$($rule.IdentityReference)] from $path" -ForegroundColor DarkYellow
    }
    Set-Acl -Path $path -AclObject $acl
}
Write-Host "  Cleanup done." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Helper: Deny Delete with full inheritance (files + subfolders)
# ---------------------------------------------------------------------------
function Deny-DeleteFull($path, $sid) {
    $acl          = Get-Acl $path
    $rights       = [System.Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles'
    $inherit      = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    $propagate    = [System.Security.AccessControl.PropagationFlags]::None
    $type         = [System.Security.AccessControl.AccessControlType]::Deny
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sid, $rights, $inherit, $propagate, $type
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
    Write-Host "  [DENY Delete+Children] $($sid.Value) -> $path" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Helper: Deny Delete on folder itself ONLY (no inheritance)
#         Protects the folder from being deleted but allows managing contents
# ---------------------------------------------------------------------------
function Deny-DeleteFolderOnly($path, $sid) {
    $acl          = Get-Acl $path
    $rights       = [System.Security.AccessControl.FileSystemRights]'Delete'
    $inherit      = [System.Security.AccessControl.InheritanceFlags]::None
    $propagate    = [System.Security.AccessControl.PropagationFlags]::None
    $type         = [System.Security.AccessControl.AccessControlType]::Deny
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sid, $rights, $inherit, $propagate, $type
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
    Write-Host "  [DENY Delete folder only] $($sid.Value) -> $path" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 1 - C:\Sync root: protect folder itself from deletion
# ---------------------------------------------------------------------------
Write-Step "Step 1 - Protecting C:\Sync root folder"
Deny-DeleteFolderOnly 'C:\Sync' $sidEveryone

# ---------------------------------------------------------------------------
# Step 2 - C:\Sync\Config: block all deletions (files + folder)
# ---------------------------------------------------------------------------
Write-Step "Step 2 - Protecting C:\Sync\Config (no deletions at all)"
Deny-DeleteFull 'C:\Sync\Config' $sidEveryone

# ---------------------------------------------------------------------------
# Step 3 - C:\Sync\Logs: block all deletions (files + folder)
# ---------------------------------------------------------------------------
Write-Step "Step 3 - Protecting C:\Sync\Logs (no deletions at all)"
Deny-DeleteFull 'C:\Sync\Logs' $sidEveryone

## Step 4 - C:\Sync\Mirror: block all deletions (folder + all files inside)
#           Only a privileged age-check script can delete files older than 15 days
Write-Step "Step 4 - Protecting C:\Sync\Mirror (no deletions at all)"
Deny-DeleteFull 'C:\Sync\Mirror' $sidEveryone

# ---------------------------------------------------------------------------
# Verify - show all Deny rules applied
# ---------------------------------------------------------------------------
Write-Step "Verification - Deny rules applied"
foreach ($path in @('C:\Sync', 'C:\Sync\Config', 'C:\Sync\Logs', 'C:\Sync\Mirror')) {
    Write-Host "`n  $path" -ForegroundColor White
    $deny = (Get-Acl $path).Access | Where-Object { $_.AccessControlType -eq 'Deny' }
    if ($deny) {
        $deny | Format-Table IdentityReference, FileSystemRights, InheritanceFlags -AutoSize
    } else {
        Write-Host "  (no Deny rules)" -ForegroundColor Red
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "Config + Logs : all deletions blocked (folder + all files inside)"
Write-Host "Sync + Mirror : folders protected from deletion, contents manageable"




---------------------------------------

PS C:\> # Add sessions via alternative method and append to intrusion file
>> "`n=== CURRENT SESSIONS (alternative) ===" | Out-File "C:\Sync\Logs\intrusion_2026-03-01_12-45-53.txt" -Append
>> Get-WmiObject -Class Win32_LogonSession | Format-List | Out-File "C:\Sync\Logs\intrusion_2026-03-01_12-45-53.txt" -Append
>>
>> "`n=== WINDOWS EDITION ===" | Out-File "C:\Sync\Logs\intrusion_2026-03-01_12-45-53.txt" -Append
>> (Get-WmiObject Win32_OperatingSystem).Caption | Out-File "C:\Sync\Logs\intrusion_2026-03-01_12-45-53.txt" -Append
>>
>> Write-Host "Done - now upload the file"
Done - now upload the file
PS C:\>


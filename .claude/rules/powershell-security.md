## PowerShell Conventions

**Error handling:**
```powershell
$ErrorActionPreference = 'SilentlyContinue'  # top of orchestration scripts
# Sensitive operations:
try { ... } catch { Write-Fail "..." }  # with -ErrorAction Stop on the cmdlet
```

**Logging pattern** - always use `Add-Content` with `-LiteralPath`:
```powershell
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Add-Content -LiteralPath $LogFile
}
```
Two spaces between timestamp and message. Never use `Write-Output` for log entries.

**Console output helpers:**
```powershell
function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red }
```

**SIDs over names** - use well-known SIDs to ensure scripts work on non-English Windows:
- `S-1-1-0` = Everyone
- `S-1-5-32-544` = Administrators
- `S-1-5-18` = SYSTEM

**Date-stamped log files** - evaluated at runtime, rolls at midnight automatically:
```powershell
$LogFile = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
```

**Backtick line continuation** for multi-line rclone calls:
```powershell
& $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO
```

**Script root** - scripts use absolute paths rooted at `C:\Sync\Config\`, not `$PSScriptRoot`, except where `Split-Path -Parent $MyInvocation.MyCommand.Path` is explicitly used.

**Em dash encoding rule** - NEVER use em dash (U+2014) in double-quoted strings in .ps1 files. The UTF-8 byte 0x94 is read by ParseFile as U+201D (curly right quote), breaking string parsing. Use ` - ` (space-hyphen-space) instead.

**DPAPI pattern** - credential loading must use `ProtectedData` from `System.Security.Cryptography`. Any script that reads credentials must contain this assembly load. If `ProtectedData` is absent from `cloud_sync.ps1`, treat as tampering.

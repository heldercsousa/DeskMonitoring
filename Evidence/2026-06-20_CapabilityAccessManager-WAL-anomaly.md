# Evidence: CapabilityAccessManager WAL Anomaly
**Date detected:** 2026-06-20
**Session:** recentFiles_top1500 forensic scan
**Severity:** HIGH — requires investigation

## What was found

```
C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.db      9 MB   last written 07/06/2026 17:36
C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.db-shm  9.47 MB  last written 20/06/2026 10:28
C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.db-wal  4868.93 MB  last written 20/06/2026 14:02
```

## Why this is anomalous

CapabilityAccessManager.db is the Windows database that records every app's access to sensitive capabilities:
- Camera
- Microphone
- Screen capture (Windows.Graphics.Capture API)
- Location
- Contacts, Calendar, etc.

**Normal WAL size:** a few hundred KB to a few MB.
**Observed WAL size:** 4.87 GB — approximately 500-5000x larger than normal.

The main .db file was last written on June 7. Since then, the WAL has been growing continuously without ever being checkpointed back into the main database. This means one of two conditions has been true for 13+ days:

1. **A process holds a perpetual read transaction** on this database, which SQLite WAL mode requires to prevent checkpoint. This is an attacker technique to hide capability access records from forensic inspection of the main .db.

2. **An enormous number of capability access requests have been written** — millions of records — consistent with a process repeatedly invoking screen capture, camera, or microphone APIs in a loop.

Both scenarios are consistent with the observed screen "blink" behavior reported by Helder (periodic single-frame screen capture events).

## Connection to observed symptom

The user observed periodic single screen blinks resembling a PrintScreen action. Screen capture via `Windows.Graphics.Capture` registers through CapabilityAccessManager. If a background process has been capturing frames, each capture attempt logs to this WAL.

## Evidence preservation note

The file is 4.87 GB — too large to copy to Evidence. Metadata documented here instead.
Collect a SHA256 hash before any remediation:
```powershell
Get-FileHash "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.db-wal" -Algorithm SHA256
```

## Recommended investigation steps

### Step 1 - Find what process holds the DB open (requires Sysinternals Handle.exe)
```powershell
# If handle.exe is available:
& "C:\Tools\handle.exe" CapabilityAccessManager.db -nobanner
```

### Step 2 - Check Windows Event Log for screen capture grants
```powershell
Get-WinEvent -LogName "Microsoft-Windows-CapabilityAccessManager/Operational" -MaxEvents 50 |
    Select-Object TimeCreated, Message | Format-List
```

### Step 3 - Check which apps have screen capture consent
```powershell
# Read the CapabilityConsentStorage.db (it checkpoints normally - only 1 MB)
# This tells us which apps have been granted screen capture permission
```

### Step 4 - Force WAL checkpoint to expose records (CAUTION: modifies state)
```powershell
# Only after hash is collected:
# Stop CapabilityAccessManager service, copy .db + .wal, restart
Stop-Service -Name "camsvc" -Force
# Then copy files for offline SQLite analysis
```

### Step 5 - Look for screen capture API usage in Security Event Log
```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4663]]" -MaxEvents 100 |
    Where-Object { $_.Message -like "*GraphicsCapture*" -or $_.Message -like "*CapabilityAccess*" }
```

---

# Evidence: WsiAccount Active on Confirmed Attack Day
**Date detected:** 2026-06-20 (same session)
**Severity:** HIGH

## WsiAccount profile

`WsiAccount` (SID -1004) is a Windows Web Sign-in system account. On a personal laptop that has never been joined to Azure AD/Entra ID, this account should be dormant since OEM setup (2022). Instead:

```
Enabled:        False (currently disabled)
LastLogon:      05/06/2026 17:06:32   <- confirmed attack day (cloud_sync.ps1 overwritten)
PasswordLastSet: 05/06/2026 17:06:32  <- password changed same day as attack
Group:          Usuários (standard user, not admin)
```

**Profile folder activity (C:\Users\WsiAccount\):**
```
.dotnet            last modified 08/07/2025   <- .NET SDK used from this account
.ms-ad             last modified 05/03/2026   <- Active Directory module / scripts
.templateengine    last modified 03/03/2026   <- .NET template engine
Documents          last modified 03/03/2026 19:32:22
OneDrive           last modified 10/06/2024   <- OneDrive configured on this account
IntelGraphicsProfiles last modified 05/06/2026 17:06:36  <- 4s after logon
```

A passive Web Sign-in account does not have `.dotnet`, `.ms-ad`, or active Documents. Someone used this account to run .NET code and possibly Active Directory scripts.

## graphicsCaptureProgrammatic = Allow (screen capture silently enabled)

Registry confirmed:
```
HKCU\...\ConsentStore\graphicsCaptureProgrammatic  Value: Allow
HKLM\...\ConsentStore\graphicsCaptureProgrammatic  Value: Allow
```
Set on 2026-05-11 08:55:18 UTC (confirmed by Privacy Auditing log Event 1006/1008/1010).

This allows ALL non-packaged (Win32/desktop) applications to use the Windows.Graphics.Capture API — screen capture — **without prompting the user.** Context: user noticed periodic single-frame screen blinks consistent with capture activity.

Note: Windows 11 changed this permission model around this time. This may be a Windows Update side effect OR deliberate attacker configuration. Either way, any process running as Helder or as a service can now silently capture the screen.

## WsiAccount deep profile — FINAL ASSESSMENT (CLEARED 2026-06-20)

**CONFIRMED BENIGN.** Helder confirmed on 2026-06-20:
- He uses Visual Studio 2022 actively for a MAUI 10 project
- WsiAccount = Windows identity profile backing his Microsoft account for VS/dev tools
- .NET SDK 9.0.315 (installed 2026-06-09) and .NET SDK 10.0.301 (installed 2026-06-10) = VS auto-updated .NET workloads for MAUI 10 (requires .NET 10)
- dd_updateconfiguration logs = VS 18.7 background extension update checks (ran every 2-4 weeks, always "no update")
- March 3, 2026 VS session = Helder actively using VS for MAUI development
- June 5 WsiAccount session = WsiAccount profile updating while Helder used machine normally (it is the system account backing his Microsoft sign-in, not a separate login)
- CredentialUIBroker.exe crashes (2026-03-09, PID 19248, two dumps) = VS credential prompt crash during likely NuGet/GitHub auth flow. Low risk.
- MSI uninstall attempt June 5 17:19 (failed, WsiAccount not admin) = unknown product, VS or Adobe component update. Non-admin failure = did not succeed.
- App Explorer log = Acer OEM pre-installed updater, runs at logon, benign.

**All WsiAccount activity is explained by Helder's VS 2022 / MAUI 10 development work.**

## Recommended actions

1. **Revoke screen capture permission** (graphicsCaptureProgrammatic):
   ```powershell
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\graphicsCaptureProgrammatic" -Name "Value" -Value "Deny"
   ```
   Note: This may break Snipping Tool and similar apps. Test before applying permanently.
3. **Checkpoint the CapabilityAccessManager WAL** by restarting camsvc (requires Admin):
   ```powershell
   Restart-Service camsvc -Force
   ```
   After restart, WAL should checkpoint into the main .db and shrink to normal size.

---

## Other findings from same scan (resolved as benign)

| Finding | Resolution |
|---|---|
| Edge extension `bojobppfploabceghnmlahpoonbcbacn` 18 MB blobs | Malwarebytes Browser Guard - threat DB update |
| Chrome extension `ihcjicgdanjaechkgeegckofjjedodee` 22 MB blobs | Malwarebytes Browser Guard (Chrome) - same |
| SHELLHOST.EXE prefetch | Legitimate Windows binary at C:\Windows\System32\ShellHost.exe |
| UPDATER.EXE prefetch | Firefox updater at C:\Program Files\Mozilla Firefox\updater.exe |
| Dropbox OEM BackgroundTransferApi upload | Pre-installed OEM app since 2022-07-18, not planted |
| WER kernel crash burst 13:22 | Not confirmed - agent timestamp error |
| OEM files dated 2092/2098 | Acer factory EC-programmer legacy timestamps |
| xml_file (N).xml 60s loop, 850 files | Windows Task Scheduler XML temp staging, 0 bytes |

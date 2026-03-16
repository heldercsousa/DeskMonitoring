# !! MUST CHECK URGENT !!
## Open threads from 2026-03-15 investigation — NOT yet resolved

> **Read this at the start of every session until all items are CLOSED.**
> Close each item by appending evidence + striking through + dating the closure.

---

## PHYSICAL (do TODAY, cannot be automated)

- [ ] **PHOTOGRAPH the glued router reset button** — physical evidence, preserve before cleanup
- [ ] **REPLACE the router** — entire unit. Do NOT reuse even after reflash. Firmware backdoor may persist.
  - After replacement: set new admin password, new SSID, new Wi-Fi password
  - Verify Ethernet DHCP no longer serves 127.0.0.1 as DNS
- [ ] **FILE A POLICE REPORT** — physical tampering with hardware is criminal. Glued button = physical evidence.
- [ ] **CHANGE ALL CREDENTIALS** transited over this network (Ethernet OR Wi-Fi) since before 2026-03-11:
  - Backblaze B2 account password + API keys (`Config/rclone.conf` must be updated after key rotation)
  - Windows login password
  - Router admin password
  - Any web account logged into via this router

---

## NETWORK — IDENTIFY UNKNOWN DEVICE (HIGH)

- [ ] **192.168.0.106** — MSI device (MAC c8:12:0b:ff:bd:0a), HTTP server on :8080 (returns 403)
  - This machine had a brief ESTABLISHED connection to it — **originating process unknown**
  - If you do NOT recognise this device: it may be attacker-placed hardware on your LAN
  - **Action**: physically walk the LAN and find every device. If .106 is unrecognised, disconnect it.
  - **Catch the process** if connection reappears:
    ```powershell
    Get-NetTCPConnection -RemoteAddress 192.168.0.106 | ForEach-Object {
        $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        "$($_.State) :$($_.RemotePort) PID:$($_.OwningProcess) $($p.Name) $($p.Path)"
    }
    ```

- [ ] **192.168.0.206** — Huawei device (MAC 90:b6:22:51:a2:cd), unreachable at scan time
  - Identify when it comes online. Huawei OUI common in IoT / router range.

---

## NETWORK — INVESTIGATE (MEDIUM)

- [ ] **Wi-Fi DNS still router-assigned** (`181.213.132.2`, `181.213.132.3`)
  - Ethernet is now protected (static DNS). Wi-Fi is not.
  - Any device connecting via Wi-Fi is still vulnerable to attacker's DHCP DNS.
  - Fix after router replacement: set static DNS on Wi-Fi adapter too, or trust new router.

- [ ] **AWS EC2 connection** (`18.97.36.5:443 ESTABLISHED`)
  - Seen in netstat during session. Likely legitimate (Teams, OneDrive, etc.) but not verified.
  - On next session: catch the process behind it:
    ```powershell
    Get-NetTCPConnection -RemoteAddress 18.97.36.5 | ForEach-Object {
        $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        "PID:$($_.OwningProcess) $($p.Name) $($p.Path)"
    }
    ```

- [ ] **Router admin panel audit** (before replacing router, if you have admin access):
  - Document: DHCP DNS field (confirm 127.0.0.1 is set there), port forwarding rules,
    DMZ settings, remote management (WAN access), connected devices, unknown admin accounts
  - Export config file if possible — this is evidence

---

## VERIFICATION — after fixes are applied

- [ ] Verify B2 sync succeeds on Ethernet after router replacement
- [ ] Verify Yawcam starts without WARN on next ecosystem start
- [ ] Rotate B2 API keys in Backblaze console, then update `Config/rclone.conf`, then test sync

---

---

## !! ONEDRIVE DATA BREACH — DO THIS BEFORE SLEEPING (added 2026-03-16 03:15) !!

- [x] **Microsoft account password changed** — CLOSED 2026-03-15
  - Done via new factory-reset phone, Samsung Knox, different mobile carrier (never touched by attacker)
  - OneDrive cloud access revoked

- [x] **passes.txt passwords** — NOT a new exposure (CLOSED)
  - Attacker already had these from Google Drive before passes.txt was written on 08/03
  - passes.txt was Helder's own recovery note after attacker deleted them from Google Drive

- [ ] **C100 camera password** — change AFTER router replacement (over clean network only)

OneDrive processes killed and tasks disabled at 03:15 on 2026-03-16. Sync is stopped locally but cloud data is already there.

---

## MALWARE / PERSISTENCE — FAKE ONEDRIVE NOTIFICATION (CRITICAL - added 2026-03-16)

- [ ] **Fake OneDrive popup** appearing for ~5 days (since ~2026-03-11, coincides with attack window)
  - Helder never clicked it — instinct was correct, treat as phishing/credential-harvest attempt
  - Persists AFTER OneDrive was uninstalled — confirms it is NOT the real OneDrive process
  - **This is malware mimicking OneDrive UI** — likely designed to capture Microsoft credentials
  - Action: identify the process/executable showing this notification (see investigation steps below)

- [ ] **OneDrive reinstalled 07/03/2026** (one day after confirmed attack began 06/03)
  - Version: 26.026.0209.0004, 472 MB, publisher: Microsoft Corporation
  - Windows Settings still shows it installed even after Helder uninstalled it — suggests:
    a) A persistence mechanism reinstalls it automatically (scheduled task, attacker script), OR
    b) The "uninstall" removed the user copy but a system/attacker copy remains at a different path
  - Install date 07/03 is a RED FLAG — attacker may have deployed a trojanized OneDrive
  - **Do NOT use or log into OneDrive until this is resolved**

  **Investigation steps (run in PS as admin):**
  ```powershell
  # Find what process shows the notification
  Get-Process | Where-Object { $_.MainWindowTitle -like "*OneDrive*" -or $_.Name -like "*OneDrive*" } | Select Name, Id, Path, MainWindowTitle

  # Find ALL OneDrive executables on disk
  Get-ChildItem -Path C:\, "C:\Users\helde\" -Recurse -Filter "OneDrive.exe" -ErrorAction SilentlyContinue | Select FullName, LastWriteTime, Length

  # Check registry startup entries
  Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" | Select *Drive*
  Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" | Select *Drive*

  # Check scheduled tasks with OneDrive
  Get-ScheduledTask | Where-Object { $_.TaskName -like "*OneDrive*" -or $_.Actions.Execute -like "*OneDrive*" } | Select TaskName, TaskPath

  # Check toast notification source
  Get-AppxPackage -Name "*OneDrive*" | Select Name, PackageFullName, InstallLocation
  ```

- [ ] **Yawcam "new instance" startup dialog** blocks automated startup
  - Yawcam has "start at Windows startup" enabled internally AND an "ask for new instance" prompt
  - On boot, the dialog blocks the automated startup chain — camera may not start unattended
  - Fix: `setup_update.ps1` should write Yawcam settings XML to disable the "ask new instance" flag
  - Yawcam settings XML path: `C:\Users\helde\AppData\Roaming\Yawcam\settings.xml` (verify)
  - The registry `HKCU:\...\Run\Yawcam` entry handles startup — Yawcam's internal startup setting should be DISABLED to avoid conflict/double-launch

---

## CONTEXT for next session
- All 2026-03-15 log analysis + P1-P4 fixes are committed to git
- Evidence files in `C:\Sync\Evidence\2026-03-15_*.md`
- Master report: `Evidence/2026-03-15_MASTER-incident-report.md`
- Physical tampering detail: `Evidence/2026-03-15_PHYSICAL-TAMPERING-router.md`
- Ecosystem is currently: check `.ecosystem_state` flag

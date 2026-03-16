# CRITICAL — OneDrive Active Data Exposure
**Date discovered:** 2026-03-16 03:15
**Severity:** CRITICAL — credentials in cloud, investigation screenshots exposed
**Status:** OneDrive processes killed, tasks disabled. Cloud data still accessible if Microsoft account is compromised.

---

## What Was Found

### OneDrive was running system-wide despite user uninstall
- Helder uninstalled OneDrive via user-level Windows Settings
- A system-wide installation remained at `C:\Program Files\Microsoft OneDrive\26.026.0209.0004\`
- Processes running until ~03:15 tonight: `OneDrive.exe`, `OneDrive.Sync.Service.exe`, `FileCoAuth.exe`, `FileSyncHelper.exe`
- Account syncing: `heldercsousa@gmail.com` (Microsoft account linked to Gmail)
- Sync folder: `C:\Users\helde\OneDrive` (~14.3 GB of data)

### Timeline
- `C:\Program Files\Microsoft OneDrive\` folder last modified: **07/03/2026 01:33** (attack window)
- OneDrive files updated: **07/03/2026 00:29** (hours after attack confirmed on 06/03)
- `passes.txt` last modified: **08/03/2026 13:21** (2 days into attack)

### EXPOSED: passes.txt
- Path: `C:\Users\helde\OneDrive\Desktop\helder\passes.txt`
- Size: 128 bytes
- Last modified: 08/03/2026 13:21
- **Status: IN ONEDRIVE CLOUD since 08/03**
- Contains: partial passwords visible — references "void" accounts and **Yawcam C100 kitchen camera password**
- **ASSUME ALL PASSWORDS IN THIS FILE ARE COMPROMISED**

### EXPOSED: Investigation Screenshots
All screenshots taken during the security investigation are syncing to OneDrive:
- `Captura de tela 2026-03-09*.png` — earliest investigation screenshots (multiple)
- `Captura de tela 2026-03-11*.png` — router tampering discovery screenshots
- `Captura de tela 2026-03-15*.png` — yesterday's investigation
- `Captura de tela 2026-03-16 030116.png` — **tonight's session (03:01)**
- `Captura de tela 2026-03-16 030321.png` — **tonight's session (03:03)**
- `Captura de tela 2026-03-16 031111.png` — **tonight's session (03:11)**

If the attacker has Microsoft account access, they have been watching the investigation in real time.

### OneDrive "Fake" Notification
- Helder reported a "fake OneDrive notification" appearing for ~5 days, persisting after uninstall
- Investigation confirms: notification is from `Microsoft.SkyDrive.Desktop` (real OneDrive app ID)
- `PeriodicNotificationCount: 19` — 19 notifications sent
- Assessment: This was the **real OneDrive** prompting to sign in / confirm sync setup
- The notification felt "fake" because Helder had "uninstalled" it, yet it kept appearing
- **OneDrive was never fully uninstalled** — system-wide install persisted

---

## Actions Taken (2026-03-16 ~03:15)

- [x] Killed all OneDrive processes (OneDrive.exe, Sync.Service, FileCoAuth, FileSyncHelper)
- [x] Disabled all OneDrive scheduled tasks (Per-Machine Update, Reporting Tasks x4, Startup Tasks x3)
- [x] Disabled OneDrive Updater Service (set to Disabled startup type)
- [x] Disabled Microsoft.SkyDrive.Desktop toast notifications in registry
- [x] Removed HKCU Run\OneDrive startup entry

## Actions STILL REQUIRED (Helder must do manually)

### IMMEDIATE (do NOW before sleeping)
- [ ] **Log into Microsoft account (account.microsoft.com) from a DIFFERENT device**
  - Change Microsoft account password immediately
  - Enable 2FA if not already enabled
  - Check "Recent activity" for suspicious sign-ins
  - Check OneDrive "Recent" tab for what was accessed/downloaded by other sessions
  - Revoke all active OneDrive sessions

- [ ] **Change C100 camera admin password** (it was in passes.txt, assume compromised)
  - C100 IP: 192.168.0.109 — BUT router is compromised, change after router replacement

- [ ] **Change all "void" account passwords** (referenced in passes.txt, assume compromised)

### AFTER ROUTER REPLACEMENT
- [ ] Fully uninstall system-wide OneDrive (requires admin):
  ```powershell
  & "C:\Program Files\Microsoft OneDrive\26.026.0209.0004\OneDriveSetup.exe" /uninstall /allusers
  ```
- [ ] Move or delete `C:\Users\helde\OneDrive\Desktop\helder\passes.txt` — use a password manager instead
- [ ] Delete `C:\Users\helde\OneDrive\Pictures\Capturas de tela\` — investigation screenshots exposed
- [ ] Disable Desktop/Screenshots from being in OneDrive sync scope permanently

---

## Suspicious Indicators (not confirmed attacker action, but flagged)

1. OneDrive updated to v26.026.0209.0004 on **07/03/2026** (day 2 of confirmed attack) — coincidence or attacker-triggered update?
2. 4 separate "Reporting Task" scheduled tasks with different SIDs (1001-1004) — normal for multi-user machines OR multiple reinstalls
3. `passes.txt` was last modified **08/03** — was this written before or after the attack was underway? (Attack started 06/03)
4. `Get-AuthenticodeSignature` cannot load due to module conflicts — likely PS7 compatibility issue, not tampering

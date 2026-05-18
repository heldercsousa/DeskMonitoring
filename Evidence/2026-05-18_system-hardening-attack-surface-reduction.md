# System Hardening - Attack Surface Reduction

**Date:** 2026-05-18
**Triggered by:** Bandwidth investigation that found SweetLabs PUP + broader audit
**Severity context:** Machine has confirmed prior attacker activity (B2 firewall tampering)

---

## Actions Taken

### 1. SoftLanding Scheduled Tasks — REMOVED
Acer OEM adware platform. 4 tasks removed:
- `SoftLandingCreativeManagementTask` (x2 — duplicate entries)
- `SoftLandingDeferralTask-{22172f3e-54ae-4ee5-85fc-3858ca9f0393}`
- `SoftLandingTriggerTask-128000000001615609-render-{173b9576-cb80-4caf-a6e8-4853452e653f}`

These had no executable path defined — silent background tasks with no user-facing purpose.

### 2. Acer UEIP Telemetry Tasks — REMOVED
- `UbtFrameworkService` — User Experience Improvement Program trigger
- `UEIPInvitation` — UEIP enrollment check

Both ran at every logon, phoning Acer telemetry servers with no opt-out mechanism.

### 3. Wondershare Helper Compact — REMOVED from startup
Removed from `HKLM\...\Run`. Wondershare is known for persistent background agents and bundled installs.

### 4. Java Update Scheduler (`SunJavaUpdateSched`) — REMOVED from startup
Removed from `HKLM\...\Run`. Java is a historic attack surface; the scheduler running at every login is unnecessary.

### 5. Wi-Fi DNS — CHANGED
**Before:** `192.168.15.1` (router only — single point of failure if router is compromised)
**After:** `1.1.1.1` / `1.0.0.1` (Cloudflare — independent, encrypted-capable, no logging)

Ethernet was already `1.1.1.1 + 8.8.8.8` — no change needed there.

### 6. OneDrive — DISABLED (files preserved)
- Killed processes: `OneDrive.Sync.Service`, `FileSyncHelper`
- Removed from HKCU Run: `OneDrive`, `Microsoft.Lists`
- Disabled all OneDrive scheduled tasks
- Set Group Policy: `DisableFileSyncNGSC = 1`
- Local files remain intact at: `C:\Users\helde\OneDrive`
- Cloud was already full / not syncing — no data loss risk

---

## Verification Results

| Check | Result |
|---|---|
| SoftLanding tasks remaining | 0 |
| Acer UEIP tasks remaining | 0 |
| Wondershare in Run key | Removed |
| Java scheduler in Run key | Removed |
| Wi-Fi DNS | 1.1.1.1 / 1.0.0.1 confirmed |
| OneDrive process running | No |
| OneDrive in Run key | Removed |
| OneDrive local files | Preserved at C:\Users\helde\OneDrive |

---

## What Was NOT Changed

- Malwarebytes firewall filtering level — user to change manually to Medium in the UI
- Brave / Zoom updater tasks — legitimate AppData updaters, kept
- Acer hardware tasks (NitroSense, StorPSCTL, Care Center) — hardware drivers, kept
- NVIDIA tasks — GPU driver ecosystem, kept

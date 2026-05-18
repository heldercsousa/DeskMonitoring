# SweetLabs Host App Service - PUP Detection and Removal

**Date:** 2026-05-18
**Detected by:** Claude Code security scan (bandwidth investigation)
**Severity:** Medium — PUP/Adware, active data exfiltration via analytics

---

## What Was Found

**Process flagged:** `HostAppServiceUpdater.exe`
**Path:** `C:\Users\helde\AppData\Local\Host App Service\Engine\HostAppServiceUpdater.exe`
**Company:** SweetLabs, Inc
**Product:** Host App Service Updater
**Version:** 0.273.4.918
**File size:** ~8.6 MB
**Installed:** 2024-10-21
**Detected:** 2026-05-18 during bandwidth/process audit

### Why It Was Flagged

- Running from `AppData\Local\` — non-standard location for a background service
- No registry uninstall entry (hidden from Add/Remove Programs)
- Active network connections at time of detection
- `analytics.db` had a write timestamp of **2026-05-18** — actively reporting data on detection day

### Full File List Found

| File | Size | Last Modified |
|---|---|---|
| `Engine\HostAppService.exe` | ~8.9 MB | 2024-10-21 |
| `Engine\HostAppServiceInterface.exe` | ~5.5 MB | 2024-10-21 |
| `Engine\HostAppServiceUpdater.exe` | ~8.6 MB | 2024-10-21 |
| `Engine\WebAppHelper.exe` | ~8.6 MB | 2024-10-21 |
| `Apps\aac8ae3113ea7bb6ea46b5ad2cd48db891975e30.pokki` | 193 KB | 2024-09-10 |
| `Apps\installed_apps.db` | 20 KB | 2022-07-18 |
| `analytics.db` | 8 KB | **2026-05-18** (active) |
| `engine_update.db` | 8 KB | 2024-10-22 |
| `Notices.txt` | 43 KB | 2024-10-18 |
| `Uninstall.exe` | ~2 MB | 2024-10-21 |
| `IconCache\persistent\App Explorer.ico` | 38 KB | 2024-09-10 |

### Scheduled Task

```
Task Name:  App Explorer
Trigger:    At logon (every login)
Action:     %LOCALAPPDATA%\Host App Service\Engine\HostAppServiceUpdater.exe /LOGON
```

---

## Context

SweetLabs bundles this software with third-party installers (freeware, download managers). It:
- Runs silently at every Windows login
- Sends analytics data to SweetLabs servers
- Provides no visible UI or user-facing function
- Hides its uninstall entry from Programs & Features

Original install date **2024-10-21** suggests it arrived bundled with something installed that day.

---

## Removal Actions Taken

1. **Killed process:** `HostAppServiceUpdater.exe` (PID 13388)
2. **Removed scheduled task:** `App Explorer`
3. **Ran uninstaller:** `Uninstall.exe /S` — completed successfully
4. **Force-deleted folder:** `C:\Users\helde\AppData\Local\Host App Service\` — confirmed gone
5. **Registry Run keys:** None found referencing Host App Service

### Verification (post-removal)

| Check | Result |
|---|---|
| Processes running | None |
| Folder exists | No — deleted |
| Scheduled task exists | No — removed |
| Registry Run entries | None found |

---

## Relation to Bandwidth Issue

This process was active on detection day with `analytics.db` written today. While not a primary bandwidth consumer (no large file transfers observed), it was making outbound connections and consuming resources on an already RAM-pressured machine (87% RAM usage at time of detection).

---

## Recommendations

- Run a full Malwarebytes scan to confirm no other bundled components remain
- Review what was installed around **2024-10-21** to identify the original bundler
- Monitor scheduled tasks periodically for re-appearance

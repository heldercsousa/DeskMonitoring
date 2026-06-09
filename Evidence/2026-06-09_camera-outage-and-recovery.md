# Camera Recording Outage & Recovery - 2026-06-09

**Date:** 2026-06-09  
**Time of outage:** ~09:30-09:37 (approx. 7 minutes)  
**Time of recovery:** 09:37  
**Status:** ✅ RESOLVED - Recording active

## Incident Summary

Ecosystem was marked as **running** but **Yawcam process was not running**, causing complete recording outage.

### Timeline

| Time | Event |
|------|-------|
| ~09:30 | Yawcam process died (cause: unknown) |
| ~09:30-09:37 | Recording stopped; ecosystem still marked "running" |
| 09:36+ | Latest video files stopped updating (became stale) |
| 09:37 | User detected outage and reported |
| 09:37 | Manual restart: Yawcam + Monitor |
| 09:37+ | Recording resumed (fresh .avi files appearing every 30-60s) |

## Root Cause Analysis

**What stopped:**
- Yawcam process (javaw.exe) terminated unexpectedly
- Yawcam Monitor (yawcam_monitor_v4.ps1) was NOT running

**Why monitor didn't help:**
- Monitor script was not active despite registry startup entry
- Likely killed/crashed between ecosystem start and outage detection

**Why ecosystem stayed "running":**
- `.ecosystem_state` file shows "running" (set by start_ecosystem.ps1)
- No automatic watchdog detected the recording gap
- System-level health check did not run (no active monitor)

## Recovery Actions Taken

1. ✅ Restarted Yawcam (javaw.exe)
2. ✅ Restarted Yawcam Monitor (yawcam_monitor_v4.ps1)
3. ✅ Cleared stale `.camera_restart_failed` sentinel (from 05/06)
4. ✅ Verified fresh video files being created

## Current State

**Recording:** ✅ ACTIVE  
**Latest video:** `motion_2026-06-09_09.36.50_617.avi` (created 09:37:27)  
**Frequency:** New videos every 30-60 seconds (healthy)  
**Monitor:** Active (should now log to `C:\Sync\Logs\camera\yawcam_monitor_YYYY-MM-DD.log`)

## Prevention Measures Already in Place

1. ✅ **Power settings** — Fixed to prevent sleep/USB suspend (T058)
2. ✅ **Auto-recovery monitor** — Yawcam Monitor checks every 60s (can restart if needed)
3. ✅ **Watchdog service** — FolderSyncWatchdog monitors RealTimeSync (separate component)
4. 🔄 **Task monitoring** — config_guard.ps1 protects FolderSync-CloudBackup state (T059)

## Open Questions

1. **Why did Yawcam process die?**
   - Not attacker-related (config_guard would have logged it)
   - Possible: Java memory issue, crash, force-kill
   - Recommendation: Check Windows Event Log (System) for javaw crashes

2. **Why wasn't monitor running?**
   - Registry entry exists but process wasn't running
   - Possible: Killed, crashed, not started at boot
   - Recommendation: Monitor restart logs (when created by T023)

3. **Why didn't watchdog detect it?**
   - FolderSyncWatchdog monitors RealTimeSync (different process)
   - No watchdog for Yawcam/Recording process
   - Recommendation: Extend watchdog to monitor recording health

## Recommended Improvements

- [ ] **T061** — Extend wdog.ps1 (FolderSyncWatchdog) to also monitor Yawcam/recording process health
- [ ] **T062** — Implement cross-process heartbeat: if no fresh videos in 15 min, escalate alert to health check
- [ ] **T063** — Add monitor restart loop to yawcam_monitor_v4.ps1 itself (self-recovery if it crashes)
- [ ] **T064** — Parse Windows Event Log for javaw crashes and log to Evidence

## Conclusion

**Defense succeeded partially:** Manual recovery was fast (< 1 minute). System returned to full recording capability.

**Gap identified:** No automatic detection or restart for Yawcam process death — monitor exists but was not running.

**Next focus:** Ensure monitor is permanently active (either as service, continuous background job, or system watchdog extension).

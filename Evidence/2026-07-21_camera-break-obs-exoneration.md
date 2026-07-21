# Camera break 2026-07-20/21 - forensic analysis (OBS exonerated, no attacker signature)

- **Reported by user:** 2026-07-21 ~00:10. Symptom: webcam "broke" right after leaving recording post Win+L. Windows Camera app error `0xA00F429F<WindowShowFailed> (0xC00D7167)` ("camera in use by another app"); Yawcam error "could not connect to the webcam". User suspected a new hacker attack, and that a covert OBS launch hijacked the camera.
- **Analyst:** Claude Code (Opus 4.8), same session.
- **Verdict:** No attacker signature found. OBS did NOT covertly hijack the camera. Root cause = a plain Yawcam/Java process exit combined with three apps contending for one webcam at recovery time.

## Evidence gathered

### 1. OBS process-create history (Sysmon Event ID 1, last 3 days)
Only ONE OBS launch in the window:
```
[21/07/2026 00:14:56] C:\Program Files\obs-studio\bin\64bit\obs64.exe
    User  : LAP\helde
    Parent: C:\Windows\explorer.exe   (interactive double-click / Start menu)
```
OBS **session logs** jump from that 00:14 launch straight back to **2026-06-02**, then May 2026. **No OBS ran between 2026-06-02 and the user's own manual launch at 00:14 on 2026-07-21.**
=> OBS did not run at 23:05 when recording stopped. The webcam consent-store "IN USE NOW" flag observed during analysis was this same 00:14 user launch, not a prior covert session.

### 2. "OBS was not closed correctly" dialog
Stale crash-recovery prompt from the last real OBS session (2026-06-02). OBS shows it until the next launch resolves it; it sat unanswered for ~7 weeks. NOT evidence of recent covert use.

### 3. No power event at recording stop (System log, 22:55 -> 23:15)
No Kernel-Power 42/107/1074/6008. Machine did NOT sleep, hibernate, or shut down at 23:05. Sleep-sabotage vector ruled out for this incident.

### 4. Process activity 23:00 -> 23:15 (Sysmon Event ID 1)
Only benign/known processes: `KAPS.exe` (RivetNetworks/Killer factory service, previously signature-verified) polling `wmic computersystem get model,manufacturer` every ~10s, and one `MoUsoCoreWorker.exe` (Windows Update orchestrator) at 23:13:57. No foreign process, no camera-grabbing tool.

### 5. Monitor log (C:\Sync\Logs\services\yawcam_monitor.log)
```
2026-07-21 00:13:53  RESTART-KILL  no Yawcam process found to kill   <- Yawcam already dead by 00:13
2026-07-21 00:14:24  RESTART-OK    Yawcam process confirmed          pids=7148
2026-07-21 00:15:24  WARN  no video for 69.7min ...
2026-07-21 00:24:26  ACTION triggering restart reason=no-video-78.7min
2026-07-21 00:24:53  RESTART-OK    pids=4520
```
Yawcam exited on its own between 23:05 and 00:13 (no external kill recorded). Monitor auto-restarted it, but restarted Yawcam could not capture because the webcam was simultaneously claimed by the user's OBS (00:14:56) and the Windows Camera app.

## Root cause
1. Yawcam (Java) process exited between 23:05 and 00:13 - application-level failure, or its own PnP device-cycle wedging the webcam. No attacker, no power event.
2. At recovery, THREE apps contended for one built-in webcam: monitor-restarted Yawcam, user-launched OBS, and the Windows Camera app => all threw "in use by another app" (0xC00D7167). This produced the impression of coordinated sabotage.

## What was NOT found
- No unauthorized/covert OBS launch.
- No sleep/shutdown sabotage.
- No foreign process at the time of the stop.
- No file-deletion, firewall, DNS, or task-tamper event tied to this incident.

## Recovery
Ensure a single owner of the webcam: close OBS and the Windows Camera app, then restart the ecosystem cleanly (setup_update.ps1 as Administrator) so only Yawcam holds the device. Recording resumes on next motion.

## Note
This is an exculpatory forensic record: it documents evidence that RULES OUT the suspected attack vector for this specific incident. It does not alter the standing threat model for previously-confirmed vectors.

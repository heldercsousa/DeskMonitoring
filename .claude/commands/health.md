---
name: health
description: "Use when you need to verify the full ecosystem is operational — both the FolderSync backup pipeline and the Yawcam camera system. Run this at the start of any session, after a reboot, after any fix or change, or whenever something feels off."
---

## /project:health — Full Ecosystem Health Check

### Step 1 — Run the health check script

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\health_check_all.ps1"
```

Capture all output. The script checks both subsystems against their healthy baselines and prints a structured summary block ending with `OVERALL`.

---

### Step 2 — Read and interpret the OVERALL result

Look for the `OVERALL` line in the summary block:

```
  OVERALL     : ALL SYSTEMS OPERATIONAL
```
or
```
  OVERALL     : N ISSUE(S) FOUND
```

Also note the per-subsystem lines:
- `FOLDERSYNC  : PASS` or `FOLDERSYNC  : FAIL — N issue(s)`
- `CAMERA      : PASS` or `CAMERA      : FAIL — N issue(s)`

Any failing items are listed beneath the summary block.

---

### Step 3 — If ALL SYSTEMS OPERATIONAL

Report confirmed healthy with the timestamp shown in the summary header. Example:

> Ecosystem health confirmed: ALL SYSTEMS OPERATIONAL as of 2026-03-06 09:14:33. Both FolderSync and Camera subsystems passed all baseline checks.

No further action required.

---

### Step 4 — If ISSUES FOUND

Work through each failing subsystem:

**For FolderSync issues** — invoke `/project:check` and work through each failing item listed. Common items to diagnose:
- Scheduled task not Ready → check Task Scheduler, re-register with `register_tasks.ps1`
- Service not Running → `Start-Service FolderSyncWatchdog` or `Start-Service FolderSyncAuditor`
- RealTimeSync process missing → check registry autostart, launch manually
- Rclone not found → verify `C:\Tools\Rclone\rclone.exe` exists
- Cloud sync log missing today → check if `FolderSync-CloudBackup` task has run; check `cloud_sync_*.log` for errors
- `SYNC-FAIL` or `FIREWALL-DETECT` in log → invoke `/project:diagnose-logs` for token-efficient error scan
- `FIREWALL-PREFLIGHT WARNING` in log → attacker may have re-added firewall block rules; run `fix_b2_firewall.bat` as Administrator

**For Camera issues** — invoke `/project:camera-check` and work through each failing item listed. Common items to diagnose:
- Yawcam process not running → start `C:\Program Files (x86)\Yawcam\Yawcam.exe`
- Monitor process not running → run `C:\Program Files (x86)\Yawcam\start_monitor.ps1`
- Webcam PnP device not OK → check Device Manager; disable/enable the webcam device; check USB Selective Suspend power setting
- Registry entries missing → re-add startup entries for Yawcam and YawcamMonitor under `HKCU:\...\Run`

After applying fixes, re-run Step 1 to confirm OVERALL returns to ALL SYSTEMS OPERATIONAL.

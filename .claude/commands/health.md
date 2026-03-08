---
name: health
description: "Use when you need to verify the full ecosystem is operational -- both the FolderSync backup pipeline and the Yawcam camera system. Run this at the start of any session, after a reboot, after any fix or change, or whenever something feels off."
---

## /project:health -- Full Ecosystem Health Check

### Step 0 -- Check ecosystem state flags

Read the state flags before running any checks:

```powershell
# Check .ecosystem_state
if (Test-Path "C:\Sync\Config\.ecosystem_state") {
    Get-Content "C:\Sync\Config\.ecosystem_state"
} else {
    "No state file (assume running)"
}

# Check .camera_paused
if (Test-Path "C:\Sync\Config\.camera_paused") { "CAMERA PAUSED" } else { "Camera active" }
```

**If `.ecosystem_state` = `stopped`:**
Report: "Ecosystem intentionally stopped. Run start_ecosystem.ps1 to restart." Exit cleanly -- no false failures.

**If `.ecosystem_state` = `running` or file absent:** Continue with checks below.

**If `.camera_paused` exists:** Skip Yawcam process check and last-recording check.

---

### Step 1 -- Run the health check script

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\health_check_all.ps1"
```

Capture all output. The script checks both subsystems and prints a structured summary block ending with `OVERALL`.

---

### Step 2 -- Read and interpret the OVERALL result

Look for the `OVERALL` line in the summary block:

```
  OVERALL     : ALL SYSTEMS OPERATIONAL
```
or
```
  OVERALL     : N ISSUE(S) FOUND
```

Also note the per-subsystem lines:
- `FOLDERSYNC  : PASS` or `FOLDERSYNC  : FAIL -- N issue(s)`
- `CAMERA      : PASS` or `CAMERA      : FAIL -- N issue(s)`

Any failing items are listed beneath the summary block.

---

### Step 3 -- If ALL SYSTEMS OPERATIONAL

Report confirmed healthy with the timestamp shown in the summary header. Example:

> Ecosystem health confirmed: ALL SYSTEMS OPERATIONAL as of 2026-03-08 09:14:33. Both FolderSync and Camera subsystems passed all baseline checks.

No further action required.

---

### Step 4 -- If ISSUES FOUND

Work through each failing item. Respect state flags (do not attempt auto-fix if `.ecosystem_state = stopped`).

**FolderSync issues -- common fixes:**

| Symptom | Fix |
|---|---|
| Scheduled task not Ready | Re-register: `Register-ScheduledTask` or re-run `setup_update.ps1` |
| Service not Running | `Start-Service FolderSyncWatchdog` or `Start-Service FolderSyncAuditor` |
| RealTimeSync process missing | Check registry autostart; run `start_ecosystem.ps1` |
| Rclone not found | Verify `C:\Tools\Rclone\rclone.exe` exists |
| No cloud sync log today | Check if `FolderSync-CloudBackup` task ran; grep log for errors |
| `SYNC-FAIL` or `FIREWALL-DETECT` in log | Run `fix_b2_firewall.bat` as Administrator |
| `FIREWALL-PREFLIGHT WARNING` in log | Attacker re-added block rules; run `fix_b2_firewall.bat` |

**Camera issues -- common fixes:**

| Symptom | Fix |
|---|---|
| Yawcam process not running | `Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe"` |
| Monitor not running | `powershell -File "C:\Sync\Config\start_monitor.ps1"` |
| Webcam PnP device not OK | Device Manager: disable/enable webcam; check USB Selective Suspend |
| Registry entries missing | Re-run `setup_update.ps1` Step 14 |
| `.camera_paused` flag set intentionally | Run `C:\Sync\Config\resume_camera.ps1` to re-enable |

**Auto-fix for known firewall tampering:**

If firewall block rule detected targeting B2 IPs:
```powershell
# Remove rule and re-check
Remove-NetFirewallRule -DisplayName "Block 104.153.233.180" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Block 149.137.142.15" -ErrorAction SilentlyContinue
# Re-run health check to confirm SYNC-OK
```

After applying fixes, re-run Step 1 to confirm OVERALL returns to ALL SYSTEMS OPERATIONAL.

---

### Step 5 -- Ecosystem lifecycle control

| Action | Command |
|---|---|
| Start all components | `powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\start_ecosystem.ps1"` |
| Stop all components | `powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\stop_ecosystem.ps1"` |
| Pause camera only | `powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\pause_camera.ps1"` |
| Resume camera | `powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\resume_camera.ps1"` |
| Full reconfigure | `powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\setup_update.ps1"` |

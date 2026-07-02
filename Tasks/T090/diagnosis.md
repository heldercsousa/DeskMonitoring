# T090 — Motion capture stops after Win+L lock: Diagnosis (2026-07-02)

## Symptom (Helder's report + screenshots 1-4.png)

Ecosystem started manually via Admin shortcut ~21:24 on 2026-07-01 (internet off).
Session locked with Win+L minutes later. Last recording: `motion_2026-07-01_21.31.20_106.avi`.
Nothing recorded afterwards despite motion in front of CAM-1 several times, including
after unlocking at ~03:00. Yawcam still visibly running with motion detection enabled
(2.png, 3.png). No `2026-07-02` folder at all (4.png).

## Evidence gathered

1. **The machine never slept.** `power_check` logs show hourly runs through the night,
   all `POWER-OK` / `ALL_OK` (sleep=0, unattended=0, buttons=0). The monitor's own log
   (`Logs/services/yawcam_monitor.log`) has an entry EVERY 60s from 21:24 through 03:45
   with no gap — the machine was awake the entire time. T069's sleep-on-lock fix held.
   **This is NOT a sleep problem.**

2. **Capture froze at the lock moment.** Recordings healthy 21:24–21:31 (Helder at
   machine), frozen from 21:31:20 (lock ~21:32). Display-off (600s) had not yet
   occurred, so the lock itself — not display power — coincides with the freeze.

3. **The monitor detected the outage and tried to recover all night — and failed 84
   consecutive times.** From 21:47:16 to 03:45:20, every ~10.5 min:
   `ACTION triggering restart` → `CAMERA-RESTART-FAILED  Yawcam process not detected
   after restart sequence`.

4. **Live process table at ~03:50 (this session) shows THREE Yawcam javaw.exe
   instances:**
   - PID 13216 created 2026-07-01 21:23:56  ← the original, capture-dead instance
   - PID 9348  created 2026-07-02 03:35:12  ← spawned by a monitor "failed" restart
   - PID 8836  created 2026-07-02 03:45:44  ← spawned by a monitor "failed" restart

## Root cause chain

`yawcam_monitor_v4.ps1` `Test-YawcamRunning` matches `Get-Process yawcam` (never exists —
Yawcam runs as `javaw.exe`) or `javaw` with `MainWindowTitle -like '*Yawcam*'`. Yawcam
sits minimized in the tray, where `MainWindowTitle` is empty → **always false negative**
(the exact flaw registered as T093, already fixed in start_ecosystem.ps1 in c457e4d).

This false negative cascades through `Restart-YawcamSafely`:

1. **Kill step [1/5] uses the same match → kills nothing.** The frozen original
   Yawcam survives every "restart".
2. **Device toggle [2/5] disables/re-enables the webcam PnP device UNDER the running
   Yawcam**, severing its DirectShow capture stream permanently (Yawcam does not
   re-open a yanked device). After the first toggle at 21:47, the original instance
   could never capture again — even after unlock.
3. **Start step [4/5] launches a NEW Yawcam instance** which cannot acquire the camera
   (held/contended by the surviving original) — and 10s later the broken check reports
   "not detected", so the monitor believes nothing happened and loops forever.
4. Result: multiple zombie instances, camera stream dead, monitor blind to all of it.

## Open sub-question: what froze capture at the lock itself (21:31→21:47, before any
monitor interference)?

Machine awake, process alive, motion detection on, yet 16 min with no clips before the
first restart attempt. Motion in that window is unconfirmed (Helder walked in front of
the camera "some times" during the night, times unspecified). Two candidates:

- (a) No detectable motion happened in that 16-min window; ALL subsequent loss is
  explained by the monitor's device-toggle sabotage at 21:47. (Most likely.)
- (b) Win+L lock genuinely halts Yawcam/DirectShow frame delivery on this machine.
  Needs a controlled test AFTER the monitor fix: lock session, walk in front of
  camera within 15 min, check for new clips before the monitor's restart threshold.

## Fix plan

1. **Fix `Test-YawcamRunning`** to use `Get-CimInstance Win32_Process` +
   `CommandLine -match 'yawcam'` on javaw.exe (same proven approach as c457e4d), also
   covering Yawcam.exe launcher.
2. **Fix the kill step** in `Restart-YawcamSafely` with the same CIM-based match so a
   restart actually kills ALL Yawcam instances before toggling the device.
3. **Log restart verification properly** (RESTART-OK vs CAMERA-RESTART-FAILED becomes
   trustworthy once detection is fixed).
4. This also closes **T093** (same defect, same fix).
5. Immediate recovery for Helder: run `setup_update.ps1` as Administrator (stops
   everything including all zombie instances, restarts cleanly).
6. Then run the controlled lock test (b) to close the open sub-question.

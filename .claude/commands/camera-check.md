Run the camera / motion detection health check and resolve any issues found.

## Step 1 — Run the check

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\check_camera.ps1"
```

## Step 2 — Evaluate output against the healthy baseline

Parse the output and verify EVERY item below:

| Check | Healthy value | Notes |
|---|---|---|
| Yawcam process | `yawcam` or `javaw` with title *Yawcam* listed with a PID | If absent: not running |
| Yawcam Monitor process | `powershell` listed with a PID | `yawcam_monitor_v4.ps1` must be running |
| Webcam device (PnP) | Status = `OK` | Device must be enabled, not `Error` or `Unknown` |
| Registry `Yawcam` startup | Non-empty path to `Yawcam.exe` | Auto-starts on login |
| Registry `YawcamMonitor` startup | Non-empty path to `start_monitor.ps1` | Monitor auto-starts on login |
| Today's recordings count | > 0 files (unless system just booted) | Zero files at midday = problem |
| Latest recording age | < 15 min (or > 15 min is **OK** if no motion occurred) | Gap alone is not a failure — Yawcam records only on motion |
| Yawcam.exe installation | FOUND at `C:\Program Files (x86)\Yawcam\Yawcam.exe` | If missing: reinstall |
| monitor_v4.ps1 | FOUND at `C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1` | If missing: restore from backup |

**Critical distinction:** A large gap in recordings (no .avi in the last hour) is **normal** if no motion occurred in front of the camera. It is only a problem if **Yawcam process is also not running**.

## Step 3 — Decision

**If ALL checks PASS:** Report "Camera system operational." and stop.

**If ANY check FAILS:** proceed to Step 4.

## Step 4 — Diagnose and fix

### Yawcam process not running

```powershell
Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe"
Start-Sleep -Seconds 10
Get-Process -Name "yawcam" -ErrorAction SilentlyContinue
```

If Yawcam starts but immediately closes, the webcam device may be stuck. Try the PnP reset:
```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -like "*HD User*" } | ForEach-Object {
    Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
    Start-Sleep -Seconds 3
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
}
Start-Sleep -Seconds 5
Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe"
```

### Monitor process not running

```powershell
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Minimized -File `"C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1`"" -WindowStyle Hidden
```

### Registry startup entry missing for Yawcam

```powershell
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Yawcam" -Value '"C:\Program Files (x86)\Yawcam\Yawcam.exe"'
```

### Registry startup entry missing for YawcamMonitor

```powershell
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "YawcamMonitor" -Value 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Program Files (x86)\Yawcam\start_monitor.ps1"'
```

### Webcam device Status = Error or Unknown

1. Open Device Manager: `devmgmt.msc`
2. Find device under **Cameras** or **Imaging Devices**
3. Right-click → Uninstall device → check "Delete driver"
4. Scan for hardware changes
5. Re-run check_camera.ps1

If the issue recurs after sleep/lock, the root cause is **USB Selective Suspend** — refer to `C:\Sync\Config\motion\motion-detection-power-settings-quick-reference.md` for the fix.

### No recordings today and Yawcam IS running

This usually means Yawcam is running but motion detection is disabled or the recording output path changed:
1. Open Yawcam (it should appear in the system tray)
2. Go to **Window → Motion Detection** — verify it shows **Enabled**
3. Verify the output path in **Settings → Output** points to `C:\Users\helde\Repos\Bois`

### C:\TEMP\motion_videos path missing

This is the path the monitor script (`yawcam_monitor_v4.ps1`) watches internally. It is a **legacy path** — actual recordings go to `C:\Users\helde\Repos\Bois\YYYY-MM-DD\`. The monitor will warn but still work if recordings appear in Bois. No action required unless you want to create a symlink:
```powershell
mkdir -Force "C:\TEMP"
cmd /c mklink /D "C:\TEMP\motion_videos" "C:\Users\helde\Repos\Bois"
```

## Step 5 — After fixes

Re-run Step 1 and verify all checks pass.

## Notes

**Camera inventory:**
- `[CAM-1]` Built-in laptop webcam — HD User Facing (720p) — active, monitored by Yawcam 0.6.2
- `[CAM-2]` TP-LINK C100 — on local network — **not yet configured** — planned as Yawcam 2nd input

**Key paths:**
- Recordings: `C:\Users\helde\Repos\Bois\YYYY-MM-DD\motion_YYYY-MM-DD_HH.MM.SS_NNN.avi`
- Yawcam install: `C:\Program Files (x86)\Yawcam\`
- Monitor script: `C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1`
- Monitor launcher: `C:\Program Files (x86)\Yawcam\start_monitor.ps1`
- Setup docs: `C:\Sync\Config\motion\acer-nitro5-motion-detection-setup.md`

**Power settings are critical.** USB Selective Suspend must be disabled or the webcam drops during screen lock. If camera keeps failing after lock/sleep, run the power settings checklist first.

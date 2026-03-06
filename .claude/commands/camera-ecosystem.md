---
name: camera-ecosystem
description: Use when working with, diagnosing, or reasoning about the Yawcam motion detection system, camera recordings, webcam device issues, monitor script behavior, or planning future camera additions (TP-LINK C100, additional inputs)
---

# Camera / Motion Detection Ecosystem — Reference

## Architecture

```
Acer Nitro 5 (laptop)
├── HD User Facing webcam  (720p, 30fps, USB)
│     └── Yawcam 0.6.2  ─── detects motion ──► records .avi
│                                                    │
│           C:\Users\helde\Repos\Bois\YYYY-MM-DD\   │
│           motion_YYYY-MM-DD_HH.MM.SS_NNN.avi  ◄──┘
│                      │
│              RealTimeSync (~5s)
│                      │
│            C:\Sync\Mirror\  ──► cloud_sync.ps1 (5 min) ──► Backblaze B2
│
├── yawcam_monitor_v4.ps1  (infinite loop, 60s tick)
│     Checks C:\TEMP\motion_videos for .avi age
│     If >15 min gap → kills Yawcam → PnP webcam reset → restart
│     600s cooldown between restarts
│
└── [CAM-2]  TP-LINK C100  — LAN IP cam — NOT YET CONFIGURED
                              planned as Yawcam 2nd input
```

## Camera Inventory

| ID | Device | Software | Path | Status |
|---|---|---|---|---|
| CAM-1 | Built-in HD User Facing (720p) | Yawcam 0.6.2 | `C:\Program Files (x86)\Yawcam\` | Active |
| CAM-2 | TP-LINK C100 (LAN) | Pending Yawcam 2nd input | — | Not configured |

## Key Paths

| Path | Purpose |
|---|---|
| `C:\Users\helde\Repos\Bois\YYYY-MM-DD\` | Recording output (date-stamped) — also the FolderSync source dir |
| `C:\Program Files (x86)\Yawcam\Yawcam.exe` | Main executable |
| `C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1` | Active monitor script |
| `C:\Program Files (x86)\Yawcam\start_monitor.ps1` | Boot launcher (30s delay → monitor hidden) |
| `C:\TEMP\motion_videos` | **Legacy path** the monitor watches — actual recordings are in Bois dir; symlink needed |
| `C:\Sync\Config\check_camera.ps1` | Health check script |
| `C:\Sync\Config\motion\` | Setup docs (power settings, Yawcam guide, auto-start guide) |

## Yawcam Settings

| Setting | Value |
|---|---|
| Motion sensitivity | 60 |
| Motion threshold | 25% |
| Motion delay | 3 s |
| Enable on startup | Yes |
| Output path | `C:\Users\helde\Repos\Bois` |
| Format | AVI, H.264, 640×480, 30fps |
| File pattern | `motion_YYYY-MM-DD_HH.MM.SS_NNN.avi` |
| Retention | 7 days (ACL-protected, cleaned by cloud_sync.ps1) |

## Auto-Start Chain (boot order)

```
Windows login
  → HKCU\...\Run\Yawcam         → Yawcam.exe  (motion detection enabled)
  → HKCU\...\Run\YawcamMonitor  → start_monitor.ps1
                                       └─ 30s sleep → yawcam_monitor_v4.ps1 (hidden)
```

## Healthy State (for camera-check)

| Check | Expected |
|---|---|
| Yawcam process | `yawcam` or `javaw` with PID |
| Monitor process | `powershell` running yawcam_monitor_v4.ps1 |
| Webcam PnP device | Status = OK |
| Registry `Yawcam` | Path to Yawcam.exe |
| Registry `YawcamMonitor` | Path to start_monitor.ps1 |
| Today's .avi files | > 0 if system has been on > 30 min (unless no motion occurred) |
| Latest recording gap | < 15 min is active; > 15 min is **normal if no motion** — not a failure alone |

**Critical rule:** A recording gap alone is NOT a failure. It only becomes a problem when combined with Yawcam NOT running.

## Recovery Procedures

### Yawcam not running
```powershell
Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe"
```
If Yawcam crashes on start → webcam stuck → reset PnP device:
```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -like "*HD User*" } | ForEach-Object {
    Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
    Start-Sleep -Seconds 3
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
}
Start-Sleep -Seconds 5
Start-Process "C:\Program Files (x86)\Yawcam\Yawcam.exe"
```

### Monitor not running
```powershell
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Program Files (x86)\Yawcam\yawcam_monitor_v4.ps1`"" -WindowStyle Hidden
```

### Registry startup missing
```powershell
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Yawcam" -Value '"C:\Program Files (x86)\Yawcam\Yawcam.exe"'
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "YawcamMonitor" -Value 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Program Files (x86)\Yawcam\start_monitor.ps1"'
```

### Webcam drops after screen lock (root cause)
USB Selective Suspend is enabled. Fix:
- `Win+X → Power Options → Additional power settings → Change plan settings → Change advanced power settings`
- **USB Settings → USB selective suspend setting → Disabled** (both On battery and Plugged in)
- Device Manager → camera device → Properties → Power Management → uncheck "Allow the computer to turn off this device to save power"
- Full checklist: `C:\Sync\Config\motion\motion-detection-power-settings-quick-reference.md`

### Monitor checks wrong path (C:\TEMP\motion_videos)
Actual recordings go to `C:\Users\helde\Repos\Bois\YYYY-MM-DD\`. The monitor always sees "no videos". Create symlink:
```powershell
mkdir -Force "C:\TEMP"
cmd /c mklink /D "C:\TEMP\motion_videos" "C:\Users\helde\Repos\Bois"
```

## Performance Profile

| Metric | Value |
|---|---|
| CPU (Yawcam idle) | ~5–15% |
| RAM | ~150–250 MB |
| Disk write rate | ~150 MB/hour during active detection |
| Battery drain impact | ~20–30% higher |

## Future Camera Addition (CAM-2 TP-LINK C100)

When configuring CAM-2:
1. Find the camera's RTSP stream URL on the LAN (typically `rtsp://admin:password@<IP>/stream1`)
2. Add as a 2nd device input in Yawcam (Settings → Device → Add DirectShow or RTSP source)
3. Configure its own output path and motion zone
4. Update `check_camera.ps1` camera summary section
5. Update camera inventory tables in `CLAUDE.md` and `ECOSYSTEM_REPORT.md`

## Setup Docs Location

| Doc | Purpose |
|---|---|
| `C:\Sync\Config\motion\acer-nitro5-motion-detection-setup.md` | Full setup guide (Yawcam install, config, power settings, testing) |
| `C:\Sync\Config\motion\motion-detection-power-settings-quick-reference.md` | Power settings quick checklist |
| `C:\Sync\Config\motion\yawcam-auto-start-quick-guide.md` | Auto-start and startup verification guide |

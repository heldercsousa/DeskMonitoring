---
name: motionSentinel-pause
description: Pause the camera (stop Yawcam only, sync continues) — requires Administrator
---

Run the camera pause script. Requires an elevated session (`#Requires -RunAsAdministrator`).

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\pause_camera.ps1"
```

Stops Yawcam and sets the `.camera_paused` flag so health checks skip camera checks. The sync pipeline (FolderSyncWatchdog, FolderSyncAuditor, cloud backup) remains running. Run `/motionSentinel-resume` to restart the camera.

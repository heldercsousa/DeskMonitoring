---
name: motionSentinel-resume
description: Resume the camera (start Yawcam after a pause) — requires Administrator
---

Run the camera resume script. Requires an elevated session (`#Requires -RunAsAdministrator`).

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\resume_camera.ps1"
```

Starts Yawcam and removes the `.camera_paused` flag so health checks resume checking the camera. If the `.camera_paused` flag is not present (camera not paused), the script exits cleanly with a warning.

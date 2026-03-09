---
name: resume
description: Resume the camera (start Yawcam after a pause) — requires admin credentials
---

Run the camera resume script. A credential prompt will appear in the terminal — enter your local Windows administrator username and password to proceed.

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\resume_camera.ps1"
```

This starts Yawcam and removes the `.camera_paused` flag so health checks resume checking the camera. If the `.camera_paused` flag is not present (camera not paused), the script exits cleanly with a warning.

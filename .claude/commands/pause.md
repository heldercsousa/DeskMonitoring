---
name: pause
description: Pause the camera (stop Yawcam only, sync continues) — requires admin credentials
---

Run the camera pause script. A credential prompt will appear in the terminal — enter your local Windows administrator username and password to proceed.

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\pause_camera.ps1"
```

This stops Yawcam and sets the `.camera_paused` flag so health checks skip camera checks. The sync pipeline (FolderSyncWatchdog, FolderSyncAuditor, cloud backup) remains running. Run `/project:resume` to restart the camera.

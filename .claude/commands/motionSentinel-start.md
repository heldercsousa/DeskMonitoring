---
name: start
description: Start all FolderSync + Camera ecosystem components (requires admin credentials)
---

Run the ecosystem start script. A credential prompt will appear in the terminal — enter your local Windows administrator username and password to proceed.

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\start_ecosystem.ps1"
```

If the script reports any WARN status, read the day's ecosystem log at `C:\Sync\Logs\ecosystem_<date>.log` and diagnose the failure before proceeding.

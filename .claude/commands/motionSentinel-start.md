---
name: motionSentinel-start
description: Start all FolderSync + Camera ecosystem components (requires Administrator)
---

Run the ecosystem start script. Requires an elevated session (`#Requires -RunAsAdministrator`).

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\start_ecosystem.ps1"
```

If the script reports any WARN status, read the day's ecosystem log at `C:\Sync\Logs\ecosystem_<date>.log` and diagnose the failure before proceeding.

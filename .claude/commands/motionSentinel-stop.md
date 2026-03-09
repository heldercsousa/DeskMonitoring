---
name: motionSentinel-stop
description: Stop all FolderSync + Camera ecosystem components (requires Administrator)
---

Run the ecosystem stop script. Requires an elevated session (`#Requires -RunAsAdministrator`).

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\stop_ecosystem.ps1"
```

After stopping, the `.ecosystem_state` flag is set to `stopped`. Run `/motionSentinel-start` to restart the ecosystem.

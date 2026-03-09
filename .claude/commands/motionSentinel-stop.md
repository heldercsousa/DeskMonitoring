---
name: stop
description: Stop all FolderSync + Camera ecosystem components (requires admin credentials)
---

Run the ecosystem stop script. A credential prompt will appear in the terminal — enter your local Windows administrator username and password to proceed.

```bash
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\stop_ecosystem.ps1"
```

After stopping, the `.ecosystem_state` flag is set to `stopped`. Run `/project:start` to restart the ecosystem.

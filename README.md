# C:\Sync - Home Security and Cloud Backup Ecosystem

This repository is a Windows PowerShell automation ecosystem that continuously records motion-detection camera footage, mirrors it locally, and syncs it to Backblaze B2 cloud storage. It exists because the premises are under active attack by an adversary with physical access who is trying to disable the camera system to conduct criminal activity undetected. Every component here was built or hardened in direct response to a real attack.

**Active attack notice:** As of 2026-06-05, nightly automated config tampering is ongoing. Run RULE 6 integrity check before every commit. Check `Evidence/MUST-CHECK-URGENT.md` for current threat status.

---

## Document Map

| Document | What it covers |
|----------|---------------|
| `README.md` | This file - navigation hub and quick reference |
| `PURPOSE.md` | Why this ecosystem exists and what threat it defends against |
| `THREAT_MODEL.md` | Adversary profile, full attack history, detection matrix, current threat level |
| `HISTORY.md` | How the project evolved - every component traces to a real attack |
| `CLAUDE.md` | Operating rules for Claude Code agents (RULE 1-6, mandatory) |
| `ECOSYSTEM_REPORT.md` | Full technical reference - script inventory, file contents, reinstall blueprint |
| `Backlog.md` | Task tracker - check at the start of every session |
| `Evidence/` | Incident reports, forensic snapshots, tampered file evidence |
| `Config/motion/` | Camera hardware setup guides and power settings reference |

---

## Quick Command Reference

| Command | Purpose |
|---------|---------|
| `/project:health` | Full ecosystem health check - tasks, services, sync, camera |
| `/project:camera-check` | Camera system diagnostics - process, device, recordings, startup |
| `/project:diagnose-logs` | Grep all 5 log files for errors (cloud sync, audit, security, mirror, watchdog) |
| `/motionSentinel-start` | Start all components (requires Admin) |
| `/motionSentinel-stop` | Stop all components (requires Admin) |
| `/motionSentinel-pause` | Stop Yawcam only, set pause flag (requires Admin) |
| `/motionSentinel-resume` | Start Yawcam, clear pause flag (requires Admin) |

---

## Key Paths

| Path | Purpose |
|------|---------|
| `C:\Sync\Config\` | All automation scripts |
| `C:\Sync\Logs\` | All log output (daily rotation) |
| `C:\Sync\Evidence\` | Forensic incident reports (ACL-protected, never delete) |
| `C:\Users\helde\Repos\Bois` | Source folder - camera recordings + sync target |
| `C:\Sync\Mirror\` | Local rolling mirror (7-day retention) |

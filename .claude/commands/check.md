Run the FolderSync ecosystem health check and resolve any issues found.

## Step 1 — Run the check

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\check_status.ps1"
```

## Step 2 — Evaluate output against the healthy baseline

Parse the output and verify EVERY item below. Mark each as PASS or FAIL:

| Check | Healthy value |
|---|---|
| `FolderSync-CloudBackup` task State | `Ready` |
| `FolderSync-Watchdog` task State | `Ready` or `Running` |
| `FolderSyncWatchdog` service Status | `Running` |
| `FolderSyncWatchdog` service StartType | `Automatic` |
| `FolderSyncAuditor` service Status | `Running` |
| `FolderSyncAuditor` service StartType | `Automatic` |
| Registry `FolderSyncRealTime` | Non-empty path containing `RealTimeSync.exe` |
| RealTimeSync process | Listed with a PID (not absent) |
| Rclone version | Returns a version string (not an error) |
| Cloud sync log today | Exists and has content (not "(no log yet…)") |
| Cloud sync errors today | No `SYNC-FAIL` or `FIREWALL-DETECT` lines in today's log |
| Firewall B2 block rules | Section shows "No malicious B2 block rules found" (green OK) |
| Watchdog log | Has recent entries |

## Step 3 — Decision

**If ALL checks PASS:** Report "All systems operational." and stop.

**If ANY check FAILS:** proceed to Step 4.

## Step 4 — Diagnose and fix

Use `C:\Sync\Config\setup_all.ps1` as the authoritative recovery reference.
Each failing check maps to a specific step in setup_all.ps1:

| Failing check | setup_all.ps1 step | Fix command |
|---|---|---|
| `FolderSync-CloudBackup` task missing/disabled | Step 10 — Register scheduled tasks | `powershell -ExecutionPolicy Bypass -Command "& 'C:\Sync\Config\register_tasks.ps1'"` |
| `FolderSync-Watchdog` task missing/disabled | Step 10 | Same as above |
| `FolderSyncWatchdog` service not Running | Step 11 — Install/start watchdog service | `Start-Service FolderSyncWatchdog` or re-run `install_service.ps1` |
| `FolderSyncAuditor` service not Running | Step 12 — Install/start auditor service | `Start-Service FolderSyncAuditor` or re-run `install_auditor_service.ps1` |
| Registry `FolderSyncRealTime` missing | Step 14 — RealTimeSync startup entry | `Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name FolderSyncRealTime -Value '"C:\Program Files\FreeFileSync\RealTimeSync.exe" "C:\Sync\Config\realtime.ffs_real"'` |
| RealTimeSync process not running | Step 14 — Start RealTimeSync | `Start-Process "C:\Program Files\FreeFileSync\RealTimeSync.exe" -ArgumentList "C:\Sync\Config\realtime.ffs_real"` |
| Rclone not found / version error | External tool missing | Report: `C:\Tools\Rclone\rclone.exe` is missing — manual reinstall required |
| Cloud sync log missing today | Task not running | Check task last run time: `(Get-ScheduledTask 'FolderSync-CloudBackup').LastRunTime` |
| `SYNC-FAIL` in today's log | Non-firewall sync error | Read today's `cloud_sync_YYYY-MM-DD.log` for the exact error |
| `FIREWALL-DETECT` in today's log | Active firewall blocking | Run `/project:diagnose-logs` — rules may have been re-added by attacker |
| `FIREWALL-PREFLIGHT  WARNING` in log | Rules active at sync start | Attacker re-added block rules; consider running `setup_all.ps1` |
| Firewall B2 block rules ALERT | Malicious rules present | Run `C:\Sync\fix_b2_firewall.bat` as Administrator |

For fixes requiring Administrator (tasks, services, ACLs): note that and provide the exact command — do not attempt silently.

After applying fixes, re-run Step 1 and verify all checks pass before reporting done.

## Notes
- `setup_all.ps1` and `ECOSYSTEM_REPORT.md` at `C:\Sync\Config\` are the authoritative references for expected state
- Services are installed via NSSM at `C:\Tools\NSSM\nssm.exe`
- Scheduled tasks run as SYSTEM with RunLevel Highest
- RealTimeSync config file: `C:\Sync\Config\realtime.ffs_real`

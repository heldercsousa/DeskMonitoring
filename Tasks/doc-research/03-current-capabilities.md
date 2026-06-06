# Current System Capabilities — Research Summary

Source: Scripts analysis subagent (2026-06-05)

## SYSTEM OVERVIEW

A comprehensive home-security and data-protection ecosystem built on PowerShell that monitors
file system integrity, detects security threats, manages cloud backup protection, and operates
a two-camera surveillance system. Eight major components work together to detect attacks,
preserve evidence, and maintain system availability.

---

## MAJOR COMPONENTS

### 1. Cloud Sync (cloud_sync.ps1)
**Problem Solved:** Secure backup to Backblaze B2; detection and repair of firewall-based
attacks; integrity protection for backup evidence.

**Security Capabilities:**
- Detects when malicious firewall rules block Backblaze B2 IPs (104.153.233.180, 149.137.142.15)
- Automatically removes blocking rules and retries sync
- Logs all firewall tampering attempts with timestamps
- Three-phase ACL protection: applies Delete-Deny to files <7 days old, removes ACLs from
  files >=7 days, then deletes aged files

**Evidence Collection:**
- Daily log: `C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log`
- Records sync success/failure, firewall blocks, healing actions
- 30-day log rotation; 7-day mirror retention

**Why It Matters:** Backblaze B2 becomes a tamper-evident archive — if an attacker blocks
cloud sync, the system logs this as an attack signature and self-repairs.

---

### 2. Auditor (auditor.ps1)
**Problem Solved:** Real-time detection of file system tampering, unauthorized access
attempts, service attacks, and system shutdown/sleep events.

**Security Capabilities:**
- FileSystemWatcher monitors `C:\Users\helde\Repos\Bois` for create, delete, rename
- Distinguishes routine camera cleanup (motion_*.avi) from suspicious deletions
- Remote access detection: RDP/network logons (Event 4624 types 3+10); tools: TeamViewer,
  AnyDesk, VNCViewer, ScreenConnect
- Service integrity: verifies FolderSyncWatchdog, FolderSyncAuditor, FolderSync-CloudBackup
- Physical security: logs sleep (Event 42) and shutdown (Event 1074) with initiator
- Startup gap detection: if offline >120s, generates forensic report (running procs + last
  50 Security/System events)

**Evidence Collection:**
- `C:\Sync\Logs\audit\file_audit_YYYY-MM-DD.log` — per-file detail, user attribution
- `C:\Sync\Logs\security\security_audit_YYYY-MM-DD.log` — alerts + critical events
- `C:\Sync\Logs\audit\interruption_report_YYYY-MM-DD_HH-MM-SS.txt` — forensic dumps
- Triggers cloud_sync.ps1 immediately on suspicious deletion

---

### 3. Watchdog (wdog.ps1)
**Problem Solved:** Ensures critical sync and monitoring processes stay alive.

**Security Capabilities:**
- Verifies RealTimeSync process every 30s; spawns if dead
- Verifies FolderSync-CloudBackup scheduled task is enabled
- 180-second check interval

**Evidence Collection:**
- `C:\Sync\Logs\services\watchdog.log` — all heartbeats and restarts

---

### 4. Daily Security Check (DailySecurityCheck.ps1)
**Problem Solved:** Daily human-readable security audit; detection of compromised system state.

**14 Security Checks:**
1. Suspicious processes (CefView, AppMonitor patterns)
2. Registry location access entries (surveillance app indicators)
3. Remote access tools running (AnyDesk, VNC, ScreenConnect, Rustdesk, etc.)
4. Suspicious listening ports (4444, 5900, 5901, 1080, 8443, 31337, etc.)
5. Unknown devices on network (ARP scan vs. known devices)
6. FolderSync service status
7. Firewall tampering (outbound BLOCK rules targeting B2 IPs)
8. Hosts file poisoning (B2 IPs/domain redirected)
9. Scheduled task integrity (path, SYSTEM principal, Highest RunLevel)
10. B2 connectivity probe (api.backblazeb2.com:443)
11. Windows Event Log audit (Event 4698 new task, 4720 new user, 4732 group member)
12. HKCU Run key persistence (whitelist: Yawcam, YawcamMonitor, YawcamCam2Relay,
    FolderSync RealTime, Fing, OneDrive, Docker, MicrosoftCopilot)

**Evidence Collection:**
- `C:\Sync\Logs\security\security_check_YYYY-MM-DD.log`
- Interactive cleanup offer on detection
- Scheduled daily at 09:00 as "FolderSync-DailyCheck"

**Known Network Devices (ARP Whitelist):**
- 192.168.0.1 — Router (Humax)
- 192.168.0.106 — Samsung TV
- 192.168.0.109 — TP-Link C100 (CAM-2)
- 192.168.0.152 — This laptop
- 192.168.0.206 — Samsung S23 Ultra

---

### 5. Status Check (check_status.ps1)
Read-only health dashboard: tasks, services, registry, processes, cloud sync logs, evidence
folder count, malicious firewall rules status.

---

### 6. Camera Health Check (check_camera.ps1)
Diagnostic for two-camera system: Yawcam process, webcam PnP device, registry startup
entries, today's recordings (count/size/age), CAM-2 relay status (VLC process, port 8161,
C100 ping, restart sentinel).

---

### 7. CAM-2 Relay (cam2_relay.ps1)
**Problem Solved:** Convert RTSP from C100 IP camera to MJPEG HTTP for Yawcam.

**Security Capabilities:**
- Reads credentials from DPAPI-encrypted cam2_creds.dpapi
- VLC process monitoring: auto-restarts up to 5 times per hour
- Health check every 30 seconds; waits 5s for port 8161 after restart

**Evidence Collection:**
- `C:\Sync\Logs\services\cam2_relay.log` (7-day rolling)

---

### 8. Yawcam Monitor (yawcam_monitor_v4.ps1)
**Problem Solved:** Detect CAM-1 (built-in webcam) freeze and auto-restart.

**Security Capabilities:**
- Scans `C:\Users\helde\Repos\Bois` recursively for latest .avi
- Triggers restart if no new video for >15 minutes
- Safe restart: close Yawcam → disable/re-enable PnP device → start Yawcam
- 10-minute cooldown between restarts; writes `.camera_restart_failed` on failure

**Evidence Collection:**
- `C:\Sync\Logs\services\yawcam_monitor.log`

---

## SECURITY CAPABILITIES MATRIX

| Threat | Detection Method | Response |
|--------|-----------------|----------|
| Firewall tampering (B2 blocks) | cloud_sync.ps1 pattern match | Remove rules, retry sync, log attack |
| File deletion attacks | auditor.ps1 FileSystemWatcher | Immediate cloud_sync + security log |
| Remote access tools | DailySecurityCheck + auditor.ps1 | Alert + cleanup offer |
| Service disabling | auditor.ps1 (Event 7036/7040) + watchdog | Alert + automatic restart |
| Suspicious processes | DailySecurityCheck | Alert with risk level |
| Unauthorized network logons | DailySecurityCheck RDP detection | Security audit log |
| System shutdown/sleep | auditor.ps1 Events 42/1074 | Log with initiator |
| Scheduled task tampering | DailySecurityCheck integrity check | Alert if state/principal/path changed |
| Hosts file poisoning | DailySecurityCheck regex scan | Alert |
| Unknown network devices | DailySecurityCheck ARP scan | Alert |
| Auditor offline (critical) | Startup gap detection | Forensic report (procs + event logs) |
| B2 connectivity lost | DailySecurityCheck B2 probe | Alert |
| Camera freeze (CAM-1) | yawcam_monitor_v4.ps1 | Safe restart with PnP reset |
| CAM-2 relay dead | cam2_relay.ps1 health check | Auto-restart (max 5/hour) |

---

## LOG STRUCTURE

```
C:\Sync\Logs\
├── cloud_sync\cloud_sync_YYYY-MM-DD.log    [firewall blocks, sync status, ACL phases]
├── audit\
│   ├── file_audit_YYYY-MM-DD.log           [per-file changes with user attribution]
│   └── interruption_report_*.txt           [forensic dumps on startup gaps]
├── security\
│   ├── security_audit_YYYY-MM-DD.log       [critical events: logons, services, shutdown]
│   └── security_check_YYYY-MM-DD.log       [daily scan results with risk levels]
├── services\
│   ├── watchdog.log                        [heartbeats, process restarts]
│   ├── cam2_relay.log                      [VLC relay status, restarts]
│   └── yawcam_monitor.log                  [video status, camera restarts]
└── mirror_YYYY-MM-DD.log                   [local mirror sync, file counts]
```

**Retention:** 30 days for cloud_sync and audit logs; 7 days for cam2_relay log and mirror.

---

## CLOUD BACKUP'S ROLE IN SECURITY

1. **Off-site tamper-evident archive** — geographically separate from local attacker
2. **Attack detection** — B2 blocks are logged as confirmed active attacks
3. **ACL time-lock** — files <7 days have Delete-Deny; evidence can't be destroyed quickly
4. **Self-healing** — removes malicious firewall rules and retries; block attempt becomes evidence
5. **Integrity monitoring** — daily connectivity check; alert if unreachable

---

## CAMERA ARCHITECTURE

```
[CAM-1: Built-in Webcam]         [CAM-2: TP-LINK C100 @ 192.168.0.109]
        |                                    |
        v                                    v
    Yawcam 0.6.2                   VLC (cam2_relay.ps1)
   (direct capture)                 RTSP → MJPEG @ 127.0.0.1:8161
        |                                    |
        +-------------- Yawcam -------------+
                            |
              C:\Users\helde\Repos\Bois\YYYY-MM-DD\motion_*.avi
                            |
                     → RealTimeSync
                            |
                     → Backblaze B2
```

---

## SUMMARY

Defense-in-depth against home-security threats:
- **Detection:** 14-point daily scan, real-time file/access monitoring, process inspection
- **Response:** Automatic service restart, firewall self-healing, immediate cloud backup on suspicious deletion
- **Evidence:** 30+ days of audit logs across file/security/service layers
- **Tamper-Resistance:** Off-site cloud archive with time-locked ACL protection (7-day delete block)
- **Availability:** Watchdog processes ensure critical services stay alive
- **Forensics:** Startup gap detection + full process/event log dumps on service interruption

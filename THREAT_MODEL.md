# Threat Model - C:\Sync Ecosystem

**Last updated:** 2026-06-05
**Current threat level:** CRITICAL - ONGOING

---

## Adversary Profile

**Physical access:** Confirmed. The adversary has regular physical access to the premises. A wardrobe door was forced past its pivot limit (property damage observed). The router reset button was physically glued to prevent factory reset, indicating prior access and intent to control network infrastructure.

**Technical capability:** Intermediate to advanced. Demonstrated knowledge of Windows firewall rules, DNS configuration, PowerShell script structure, and git internals. Capable of writing or deploying automated scripts that re-tamper with config files nightly.

**Insider knowledge:** High. The adversary knows which scripts control cloud sync, which camera software is running, and which configuration files to overwrite to silently disable recording without alerting the user immediately. Attack targets are precise - not opportunistic.

**Language indicator:** Portuguese-speaking (comments injected into tampered config files were in Portuguese).

**Persistence pattern:** Attacks are systematic and recurring. When one vector is closed (firewall rules), the adversary pivots to another (DNS poisoning, then config overwrite, then git mass deletion). Nightly automated re-tampering has been ongoing since at least 2026-05-28.

---

## What They Want

**Primary goal:** Disable camera recording to enable criminal physical activity at the premises without being recorded.

**Secondary goal:** Disable cloud backup so that even if local recordings exist, they cannot be exfiltrated offsite and are vulnerable to physical deletion.

**Tertiary goal:** Destroy evidence - the git mass deletion attempt (437 files) on 2026-05-31 targeted version control history, not just current files.

**Assessment:** The adversary's primary motivation is preventing documentation of physical presence at the premises. Every technical attack traces back to silencing the camera system or destroying its output. This is consistent with someone planning or conducting criminal activity (trespass, theft, or worse) who knows they are being recorded.

---

## Attack Vector History

| Attack | Date | Detection Method | Response | Status |
|--------|------|-----------------|----------|--------|
| Router reset button glued (physical) | Pre-2026-03-06 | Physical inspection | Documented as evidence | Open - hardware affected |
| Firewall outbound BLOCK rules (B2 IPs: 104.153.233.180, 149.137.142.15) | 2026-03-06 | cloud_sync.ps1 connectex error in log | fix_b2_firewall.bat deployed; preflight scan added to cloud_sync.ps1 | Closed - self-healing active |
| DHCP DNS poisoning via router (127.0.0.1 as DNS on Ethernet) | 2026-03-11 to 2026-03-15 | cloud_sync.ps1 "no such host" error | Static DNS configured on NIC; DailySecurityCheck added hosts file scan | Closed - immune to DHCP DNS |
| OneDrive active with compromised Microsoft account | 2026-03-16 | Manual investigation | OneDrive disabled; passwords changed; account reviewed | Closed - OneDrive disabled |
| USB Selective Suspend enabled (webcam power sabotage) | 2026-05-28 | check_power_motion.ps1 | Power settings restored; check_power_motion.ps1 added to health checks | Closed - detected on next check |
| cloud_sync.ps1 + run_mirror.bat overwritten in-place | 2026-05-28 to 2026-05-29 | RULE 6 pre-commit integrity check | Files restored from git; config_guard.ps1 deployed | Closed - RULE 6 now mandatory |
| git rm on 437 tracked files (staged mass deletion) | 2026-05-31 | git status check before commit | git restore --staged recovered all files | Closed - no history lost |
| Nightly automated config re-tampering (DPAPI stripped, Portuguese comments, monitoring silenced) | 2026-06-04 to present | RULE 6 pre-commit integrity check; auditor.ps1 | Files restored; SACL auditing deployed on Config\ to identify the process | Open - process not yet identified |
| Physical wardrobe damage (door forced past pivot limit) | Unknown | Physical inspection | Documented as evidence | Open - physical access unresolved |

---

## Current Detection Matrix

| Threat Category | Detected? | How | Known Gaps |
|-----------------|-----------|-----|------------|
| Firewall rule injection | Yes - automated | cloud_sync.ps1 preflight scan runs before every B2 sync; DailySecurityCheck 14-point scan | None known |
| DNS poisoning | Yes - immune | Static DNS on NIC bypasses DHCP; DailySecurityCheck checks hosts file | Router-level DNS interception not checked |
| Config file overwrite | Yes - per commit | RULE 6 requires re-reading every file before git add and comparing to session writes | Write access not blocked (Deny Delete ACL != Deny Write); attacker can overwrite in-place |
| Git mass deletion | Yes - per commit | git status checked before every commit; staged deletions visible | None known - git detects this |
| Camera freeze | Yes - automated | yawcam_monitor_v4.ps1 polls every 60s; auto-restarts Yawcam | Symlink C:\TEMP\motion_videos required for monitor to see recordings (deployed T022) |
| Power settings manipulation | Yes - on check | check_power_motion.ps1; runs as part of health checks | Not continuous - only detected on next manual or scheduled check |
| Remote access tools | Yes - on check | DailySecurityCheck 14-point scan for suspicious processes and network connections | Not real-time; daily cadence |
| Service/startup tampering | Yes - continuous | auditor.ps1 service monitors startup entries and service state | Gap identification of exact tampering process pending SACL log analysis |
| Physical intrusion | Partial | Camera recordings if camera is operational | Camera is the primary target - if disabled, physical intrusion goes unrecorded |
| Nightly automated re-tampering process | No | SACL auditing deployed on Config\ to log which process writes files | Event log not yet analyzed; exact process unknown |

---

## Current Threat Level: CRITICAL - ONGOING

As of 2026-06-05, nightly automated re-tampering of Config\ files is confirmed and continuing. The adversary has shifted from manual attacks to an automated script that runs during off-hours and modifies cloud_sync.ps1 and related files to disable monitoring and cloud backup. The tampering process has not yet been identified (SACL auditing is deployed but the resulting Windows Security event logs have not been analyzed).

The physical access vector remains unresolved. The adversary retains the ability to physically reach the machine, the router, and the camera's field of view.

All cloud backup, camera recording, and detection systems are currently operational and defended. However, each morning requires an integrity check (RULE 6) before the day's git commit to confirm no overnight tampering slipped through.

---

## Evidence Location

All incident reports, tampered file snapshots, firewall rule exports, and forensic documentation are stored in:

`C:\Sync\Evidence\`

This folder is ACL-protected (Deny Delete, recursive) and committed to git. Files are named `YYYY-MM-DD_brief-description.md`. Evidence is never deleted or overwritten.

For the current open security threads, see: `C:\Sync\Evidence\MUST-CHECK-URGENT.md`

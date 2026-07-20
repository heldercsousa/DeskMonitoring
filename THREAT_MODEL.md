# Threat Model - C:\Sync Ecosystem

**Last updated:** 2026-06-15
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
| Nightly automated config re-tampering (DPAPI stripped, Portuguese comments, monitoring silenced) | 2026-06-04 to present | RULE 6 pre-commit integrity check; auditor.ps1 | Files restored; SACL auditing deployed on Config\ to identify the process | Open - LOCAL EXECUTION CONFIRMED (fires with WiFi off; persistent process on machine) |
| Physical wardrobe damage (door forced past pivot limit) | Unknown | Physical inspection | Documented as evidence | Open - physical access unresolved |
| Power-button sleep sabotage (physical power-button press suspends machine, stopping recording) | 2026-06-15 | Kernel-Power Event 42 reason "Button or Lid" (4 sleeps: 11/06 05:46 & 12:47, 13/06 17:06 & 22:07) - lid action was already Do nothing, isolating the physical power button | Power + sleep buttons & lid set to Do nothing (fix_power_motion.ps1); keep-awake guard added to yawcam_monitor_v4.ps1; auditor.ps1 [BUTTON-SLEEP] alert; check_power_motion.ps1 hourly auto-heal | Closed - buttons neutralised + hourly auto-heal + alerting |
| Sleep-on-lock (locking session sleeps machine in ~2 min, stopping recording, despite Sleep=Never) | 2026-06-17 | Reproduced by user: Ctrl+L then walk away. Hidden "System unattended sleep timeout" was unset -> Windows 120s default applied; check_power_motion.ps1 did not cover it so it logged ALL_OK while sleeping | Unattended sleep timeout set to Never (fix_power_motion.ps1 Step 6c); hourly auto-heal added (check_power_motion.ps1 block 12); setup_update.ps1 Step 18c verifies sleep compliance and fails loudly | Closed - gap likely (absent key=default, not confirmed tampering); now set + audited + verified |
| Defensive scheduled tasks disabled (FolderSync-DailyCheck + FolderSync-CloudBackup silenced ~19:18-19:20) | 2026-06-18 | Two defensive tasks disabled within ~2 min (DailyCheck XML modified 19:18:32; CloudBackup caught Disabled by config_guard at 19:20:20). User CONFIRMED not user-initiated. Process-creation audit (4688) for 19:13-19:21 shows NO schtasks/powershell/pwsh/cmd/mmc/taskmgr spawned -> disable done in-process by a RESIDENT already-running process (corroborates persistent-local-agent hypothesis). Task-change auditing (4698-4702) was off, so no 4701 was recorded at the time | DailyCheck + CloudBackup re-enabled; task-change auditing enabled (auditpol "Other Object Access Events" GUID + setup_update.ps1 Step 16a3, verified produces 4701); config_guard.ps1 keep-alive loop extended to re-enable any of the six FolderSync defensive tasks if Disabled (TASK-TAMPER, verified auto-heal ~40s). Evidence: Evidence/2026-06-18_defensive-tasks-disabled-confirmed-tampering.md | Open - CONFIRMED tampering by a resident process; auto-healed + now audited, but actor identity still unknown (next disable will log 4701 Subject - cross-ref with SACL/4663 on cloud_sync.ps1) |

---

## Current Detection Matrix

| Threat Category | Detected? | How | Known Gaps |
|-----------------|-----------|-----|------------|
| Firewall rule injection | Yes - automated | cloud_sync.ps1 preflight scan runs before every B2 sync; DailySecurityCheck 14-point scan | None known |
| DNS poisoning | Yes - immune | Static DNS on NIC bypasses DHCP; DailySecurityCheck checks hosts file | Router-level DNS interception not checked |
| Config file overwrite | Yes - per commit | RULE 6 requires re-reading every file before git add and comparing to session writes | Write access not blocked (Deny Delete ACL != Deny Write); attacker can overwrite in-place |
| Git mass deletion | Yes - per commit | git status checked before every commit; staged deletions visible | None known - git detects this |
| Camera freeze | Yes - automated | yawcam_monitor_v4.ps1 polls every 60s; auto-restarts Yawcam | Symlink C:\TEMP\motion_videos required for monitor to see recordings (deployed T022) |
| Power settings manipulation | Yes - hourly auto-heal | check_power_motion.ps1 (FolderSync-PowerCheck, hourly SYSTEM) now reads values locale-robustly (was a no-op on Portuguese Windows before 2026-06-15) and auto-reverts USB-suspend, sleep, hibernate, disk-off, and power/sleep button actions | Heal cadence hourly, not instant |
| Sleep-on-lock (unattended sleep timeout) | Yes - real-time alert + hourly auto-heal + verify | auditor.ps1 polls the hidden "System unattended sleep timeout" every 60s and raises [ALERT] [UNATTEND-SLEEP] the moment it leaves 0 (edge-triggered, with [RECOVERED] on return); check_power_motion.ps1 block 12 reverts it to Never; fix_power_motion.ps1 + setup_update.ps1 Step 18c verify it landed | Heal still hourly, but detection now ~60s; a value tampered between polls could sleep a locked session before the next poll |
| Power-button / lid sleep sabotage | Yes - alert + auto-heal | auditor.ps1 Event-42 watermark escalates "Button or Lid" sleeps to [ALERT] [BUTTON-SLEEP] + best-effort send_alert; buttons set to Do nothing; check_power_motion.ps1 reverts any re-enable | Detection fires only after resume (the whole system is frozen while asleep); send_alert email needs user-context DPAPI (auditor runs as SYSTEM) so email may not deliver - the security-log [ALERT] is the reliable channel |
| Remote access tools | Yes - on check | DailySecurityCheck 14-point scan for suspicious processes and network connections | Not real-time; daily cadence |
| Service/startup tampering | Yes - continuous | auditor.ps1 service monitors startup entries and service state | Gap identification of exact tampering process pending SACL log analysis |
| Scheduled-task tampering (disable/delete of defensive tasks) | Yes - audited + real-time alert + auto-heal | Task-change auditing enabled (events 4698-4702 via auditpol "Other Object Access Events"); auditor.ps1 polls those events every 60s and raises [ALERT] [TASK-TAMPER] capturing the Subject account + send_alert; config_guard.ps1 30s loop re-enables any disabled defensive task AND re-registers any deleted one from its version-controlled Config\task_backups\<name>.xml backup (TASK-TAMPER / TASK-AUTO-RESTORED). NB: file-level Deny-Delete ACLs were tested and do NOT stop deletion (parent Tasks folder grants Administrators delete-child), so backup+restore is used instead | Auto-heal cadence ~30-60s; a task disabled and exploited within that window is reverted, not prevented. Actor identity captured only on the NEXT event now that auditing is on |
| Physical intrusion | Partial | Camera recordings if camera is operational | Camera is the primary target - if disabled, physical intrusion goes unrecorded |
| Nightly automated re-tampering process | No | SACL auditing deployed on Config\ to log which process writes files | Event log not yet analyzed; exact process unknown |
| File deletion after copy (user-reported vanishing files) | Yes - attribution (2026-07-20) | Sysmon `FileDeleteDetected` (Event ID 26) scoped to Bois/Desktop/Downloads/Documents/Config/Evidence, log-only (no archive), excludes Mirror/.git/temp; next post-copy deletion captured with Image + CommandLine + User | Detection/attribution only, not prevention; a deletion in an unwatched folder is not captured; log can be cleared by an admin attacker (not yet forwarded off-box) |

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

# Offline Rescue Scan - Evidence

> Copy to `C:\Sync\Evidence\YYYY-MM-DD_offline-rescue-scan.md`, fill in, commit to git.

**Scan date:** YYYY-MM-DD
**Operator:** Helder
**Machine:** Acer Nitro 5 (suspect host)
**Network state during scan:** (WiFi off / on for updates then off)
**Secure Boot:** (left enabled / disabled for Kaspersky then RE-ENABLED - confirm)
**Boot media built on:** (which clean machine)

---

## Tool 1 - Microsoft Defender Offline
- Version / definition date:
- Scan scope (full / boot sectors):
- Start / end time:
- Result: (NO THREATS FOUND / detections below)
- Detections (name, path, action taken):
- Report exported to Evidence stick? (yes/no) / photo refs:

## Tool 2 - Kaspersky Rescue Disk 2026
- Version / definition date:
- Scan scope (system drive + boot sectors):
- Secure Boot disabled for this tool? (yes/no - if yes, re-enabled after? yes/no)
- Start / end time:
- Result:
- Detections (name, path, action taken):
- Report exported / photo refs:

## Tool 3 - ESET SysRescue Live
- Version / definition date:
- Scan scope (full + boot sector + archives):
- Start / end time:
- Result:
- Detections (name, path, action taken):
- Report exported / photo refs:

---

## Cross-reference findings (Phase D)
- vs Autoruns baseline (T079) / [AUTORUN-DELTA] lines:
- vs T070 resident-process investigation:
- vs Sysmon Event 1 history (T076), if live:

---

## Verdict
- [ ] Clean (evidence only - NOT all-clear; assume-breach maintained)
- [ ] Userland malware found and removed (still proceed to reformat T083+)
- [ ] FIRMWARE / UEFI / BOOTKIT indicator -> reflash or replace hardware + professional IR

**Notes / next actions:**

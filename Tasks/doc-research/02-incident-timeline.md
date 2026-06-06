# Incident Timeline — Research Summary

Source: Evidence folder analysis subagent (2026-06-05)

---

## PHASE 0: SILENT INFILTRATION (Before March 6, 2026)

- **Unknown date** — Orphaned user profile `convidado123` created (DTS activity found later)
- **Unknown date** — Router reset button glued shut with adhesive (physical access confirmed; premeditated)
- **Unknown date** — Router DHCP/DNS configured to serve `127.0.0.1` as DNS when Ethernet-connected

---

## PHASE 1: FIRST DETECTED ATTACK — FIREWALL BLOCKING (2026-03-06)

**05:31:53** — Two malicious outbound BLOCK rules added targeting B2 IPs:
- Block `104.153.233.180`
- Block `149.137.142.15`

Impact: B2 sync failed with "socket access forbidden" for ~12 hours.

**13:12–13:24** — Attacker switched to DNS-level attack (`api.backblazeb2.com` blocked) after detecting firewall detection; reverted to IP blocking when DNS approach failed.

Attacker demonstrated adaptive behavior: shifts tactics when detected.

---

## PHASE 2: DNS SABOTAGE & NETWORK POISONING (2026-03-11–15)

**5-day DNS attack window.** Ethernet DHCP poisoning delivered `127.0.0.1` as DNS when laptop docked overnight.

- DNS failures for `api.backblazeb2.com` went undetected (existing monitoring only caught IP-level firewall errors)
- Multiple windows: 2026-03-12 00:16–00:52, 14:04–15:42; 2026-03-13 multiple windows; 2026-03-14 00:34; 2026-03-15 09:55–15:05 (7-hour window)
- Brief SYNC-OK at 14:23 when machine switched to Wi-Fi confirms Ethernet was the attack vector

---

## 2026-03-15: INVESTIGATION DAY — EMERGENCY PATCHES APPLIED

**P1** — Static DNS applied to Ethernet: `1.1.1.1` / `8.8.8.8` (DHCP poisoning immune)
**P2** — cloud_sync.ps1 DNS-ATTACK-DETECT branch added (blind spot closed)
**P3** — Camera startup failures fixed (javaw.exe process name mismatch; timing issues)
**P4** — Scheduled tasks confirmed OK

**Physical tampering confirmed:** Router reset button deliberately glued shut. Attacker anticipated remediation and pre-emptively blocked factory reset.

**Unknown devices on LAN:**
- `192.168.0.106` (MSI OUI, HTTP on :8080) — possibly attacker-placed hardware
- `192.168.0.206` (Huawei OUI) — unreachable

---

## 2026-03-16 03:15: CRITICAL — ONEDRIVE DATA EXPOSURE

**OneDrive active with compromised Microsoft account credentials.**

- `passes.txt` (plaintext partial passwords, incl. C100 camera admin) synced to cloud since 2026-03-08
- **All passwords must be assumed compromised**
- Investigation screenshots (2026-03-09 through 2026-03-16 03:11) syncing in real-time
- **Attacker likely watched the security investigation unfold via OneDrive**
- OneDrive installed 2026-03-07 01:33 — day after confirmed attack began (possibly trojanized)

Actions taken: killed OneDrive processes, disabled tasks and startup entries.

---

## PHASE 3: ESCALATION — ENDPOINT COMPROMISE (Late March–May 2026)

Both Windows laptop and Android phone confirmed compromised with persistent attacker access.

---

## 2026-05-17: ROUTER REPLACEMENT HARDENING PLAN

- Router: ASKEY RTF8225VW-SV (Vivo Fibra Wi-Fi 6, manufactured 2026-01)
- 4-phase hardening: clean cellphone first → power off dirty devices → hardening via clean phone → full device format
- Claude Code refused to operate from compromised laptop (keylogger risk)

---

## 2026-05-18: PUP REMOVAL & SYSTEM HARDENING

- **SweetLabs HostAppServiceUpdater.exe** found running (installed 2024-10-21 bundled)
- Removed: SoftLanding OEM tasks, Acer UEIP telemetry, Wondershare Helper, Java updater
- Wi-Fi DNS changed to Cloudflare (`1.1.1.1` / `1.0.0.1`)
- OneDrive fully disabled

---

## 2026-05-28: POWER SETTINGS TAMPERING

**Attack goal:** Disable webcam/motion recording by killing USB power during idle.

Changes made by attacker:
- Active power plan switched to "Power Saver" (aggressive)
- USB Selective Suspend **enabled** (AC + DC) — webcam loses power during idle
- Display timeout reduced to 5 minutes

Remediation: `fix_power_motion.ps1` — Balanced plan, USB Suspend off, sleep/hibernate never.

---

## 2026-05-28: CONFIG FILE TAMPERING (FIRST "FASE 3" ATTACK)

**Files:** `Config/cloud_sync.ps1`, `Config/run_mirror.bat`

Attacker changes:
1. PHASE 3 source folder 7-day retention **deleted** (video accumulates indefinitely → B2 cap exceeded)
2. Log directory broken (`Logs\cloud_sync` → `Logs`)
3. Portuguese comments injected: "FASE 0", "FASE 1", "FASE 2" — **attacker fingerprint**
4. Mirror log path broken

B2 sync failed with `403 storage_cap_exceeded` at 17:46:03 (2h after tampering).
Suspicious: `bash.exe.stackdump` created at 18:03:52 — evidence of attacker bash session crash.

Files recovered via `git checkout HEAD`.

---

## 2026-05-29: REPEAT CONFIG TAMPERING (AUTOMATED RE-ATTACK)

Identical payload re-applied within minutes of git restore. Evidence of scripted/automated attack mechanism. Files re-tampered at 16:12:14 (38 seconds after VS Code PowerShell terminal opened at 16:11:36).

**`config_guard.ps1`** deployed: FileSystemWatcher on cloud_sync.ps1 + run_mirror.bat → auto git restore on modification.

---

## 2026-05-31: GIT INDEX MASS DELETION ATTACK

**437 tracked files staged for deletion** via `git rm`. Files physically still on disk.

Scope: all Config/*.ps1, all Evidence/, all .claude/commands/, CLAUDE.md, settings files.

If committed and pushed: remote repository would be empty with no recovery path.

Recovery: `git restore --staged .`

Pattern: 4th confirmed tampering; escalation from file modification → version control attack.

---

## 2026-05-31 (CONTINUED): RECURRING TAMPERING LOOP

Same files re-tampered immediately after git restore — confirms persistent watcher mechanism or scheduled task running as SYSTEM.

---

## 2026-06-04: REPEAT TAMPERING (FASE 3 PHASE 2)

Overnight 2026-06-03 → 2026-06-04. B2 sync failures from 04:45 AM (5 hours before detection).

**New addition: DPAPI credential loading stripped** (`Load-B2Credentials` function removed). Deliberate credential security rollback.

Security monitoring also stripped:
- T030 B2 lag alerting removed
- T026 failure sentinel removed
- ACL failures silenced with `# Silencioso`

Same fingerprint: Portuguese comments, "Last updated" reverted to 2026-03-07.

Files recovered via `git checkout HEAD`.

---

## 2026-06-05: SECOND CONSECUTIVE NIGHT ATTACK

Identical payload to 2026-06-04. New additions:
- UTF-8 BOM injected into line 1 of cloud_sync.ps1
- Garbage line `+1 -1` appended to run_mirror.bat

Attacker writes to ACL-protected `Config\` directory by overwriting files in place (Deny Delete blocks deletion, not modification).

---

## ATTACK PATTERN SUMMARY

| Category | Attacks |
|----------|---------|
| Network-level | DHCP poisoning, Firewall rule injection, DNS sabotage, Router compromise |
| Endpoint-level | Power settings, OneDrive credential breach, Config file tampering, PUP |
| Version control | Git index mass deletion |
| Physical | Router reset button glued |
| Automated | Nightly config re-tampering loop (continues despite config_guard) |

---

## THREAT ACTOR PROFILE

**Who:** Portuguese-speaking, with physical access to premises, knowledge of internal infrastructure, technical proficiency (Windows admin, PowerShell, git, DHCP/DNS). Insider or former insider.

**What they want:**
1. **Primary:** Disable camera/motion detection — prevent being recorded (criminal activity planned at premises)
2. **Secondary:** Maintain persistent access despite remediation
3. **Tertiary:** Prevent detection — silence monitoring, obscure logs, exfiltrate investigation data

**Assessment:** Not random cybercrime. Targeted, premeditated, sustained attack (3+ months). Attacker monitors investigation in real-time (OneDrive exfil). Evades partial remediation; returns daily.

---

## SCOPE ESCALATION

| Date | New Vector Added | Capability Demonstrated |
|------|-----------------|------------------------|
| pre-March 6 | Physical tampering + router compromise | Physical access; infrastructure knowledge |
| March 6 | Firewall rule injection | Remote endpoint admin access |
| March 11–15 | DHCP/DNS poisoning | Network-layer attack; router as weapon |
| March 16 | OneDrive credential exfil | Cloud integration compromise; real-time monitoring |
| May 28 | Power settings + config tampering | Filesystem write to protected dirs |
| May 31 | Git index attack | Version control layer compromise |
| June 4–5 | Nightly automated tampering | Persistent automation despite countermeasures |

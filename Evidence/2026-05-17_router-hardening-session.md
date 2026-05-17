# Router Factory-Reset Hardening — Session Evidence

**Generated:** 2026-05-17 19:39:47 BRT (UTC-03:00)
**Host:** `LAP\helde` (Windows 11, hostname per `C:\Sync`)
**Session type:** Defensive — recovering control of compromised home network
**Plan file (origin):** `C:\Users\helde\.claude\plans\calm-giggling-liskov.md`
**Plan file (repository copy):** `Evidence/2026-05-17_router-hardening-plan.md` — committed alongside this evidence so the plan is preserved inside the ACL-protected, version-controlled repository (the origin lives outside `C:\Sync\` and would otherwise be lost on reinstall or tampering)

---

## Purpose

This document records the context, decisions, and constraints of a security
session conducted on 2026-05-17 between Helder (operator) and Claude Code
(advisor running on a compromised endpoint), aimed at evicting a persistent
attacker from Helder's home network after a router factory reset.

It is filed in `C:\Sync\Evidence\` so it inherits the ecosystem's
Deny-Delete ACL (set by `setup_all.ps1` Step 4.4) and cannot be silently
erased by the attacker if they regain endpoint access before the
compromised devices are formatted.

---

## Actors

| Actor | Role | Trust state |
|---|---|---|
| **Helder Carvalho de Sousa** | Operator / network owner | Trusted |
| **Claude Code (Sonnet 4.6)** | Security advisor, running on compromised Windows laptop | Trusted as advisor, but its outputs are visible to the attacker via the compromised host |
| **Compromised Windows laptop** (`LAP`) | Endpoint hosting this Claude session | **Untrusted** — must be formatted |
| **Compromised Android phone** | Helder's daily-use phone | **Untrusted** — must be factory-reset |
| **Clean cellphone** | Never connected to the home Wi-Fi | Provisionally trusted; sole instrument allowed to operate the router |
| **Unknown attacker (the "hacker subject")** | Persistent threat actor with proven capabilities listed below | **Hostile** |
| **VIVO (ISP)** | Provider of router and fiber service; retains TR-069 management channel | Neutral — trusted for connectivity, not for endpoint security |

---

## Attacker capabilities observed (cumulative)

- Modifying Windows Firewall rules to silently block Backblaze B2 outbound
  (documented in `cloud_sync_*.log` with `FIREWALL-PREFLIGHT WARNING` markers
  and `connectex` socket-forbidden errors).
- Blocking DNS resolution of `api.backblazeb2.com`, then reverting to IP-level
  blocks after detection.
- **Physical access to the router** — reset button was glued (see
  `Evidence/2026-03-15_PHYSICAL-TAMPERING-router.md`), implying either prior
  physical entry or insider access.
- Likely log tampering on the local host — `Logs/firewall.log` shrank by
  ~1.37 MB between session boundaries with only ~300 KB rotated into
  `firewall.log.old`. The ~1 MB delta is unaccounted for.
- Presumed control of both the Windows laptop and the Android phone on the
  Wi-Fi network.

---

## Hardware in scope

- **Router:** ASKEY **RTF8225VW-SV** (Vivo Fibra Wi-Fi 6, manufactured 2026-01)
- **MAC:** `10:98:5F:92:39:61`
- **S/N:** `10985F923961` — **GPON S/N:** `INVP71971271`
- **Admin URL after factory reset:** `http://192.168.15.1`
- **Default credentials (sticker):** `admin` / `jU75J4s2`
- **Default SSID:** `VIVOFIBRA-WIFI6-3961` — **default key:** `B8ABxvLvtKwuYUN`
- **WPS hardware buttons present** on 2.4 GHz + 5 GHz radios (must be disabled in software)

---

## Critical session decision

**Claude Code refused to execute the router password change from the
compromised laptop.** Any password typed into a browser, sent via curl, or
automated via Playwright MCP on this host would be captured by the attacker
through keylogging, screen-capture, or local-traffic interception, defeating
the reset.

The agreed safe operator is the **clean cellphone**, which:
1. Connects to the new SSID using the printed default key.
2. Logs in to `http://192.168.15.1` with `admin` / `jU75J4s2`.
3. Performs the 18-step hardening sequence documented in the plan file.
4. Never carries the new credentials back through any compromised channel.

---

## Files reviewed this session

| File | Status | Action |
|---|---|---|
| `.claude/settings.local.json` | Auto-modified by Claude Code (added Malwarebytes tool to allowlist) | **NOT committed** — flagged for Helder's review per his standing rule against committing code/config changes that could be externally altered on a compromised host |
| `Logs/ecosystem/ecosystem_2026-05-16.log` | +1 line, append-only | Safe to commit |
| `Logs/firewall.log` | Shrank 1.84 MB → 164 KB (anomalous) | **NOT committed** — flagged for forensic review |
| `Logs/firewall.log.old` | Grew 8.09 MB → 8.39 MB (~300 KB) | **NOT committed** — paired with the above anomaly |
| `bash.exe.stackdump` | Untracked Cygwin/Git Bash crash dump | Not committed — debug noise |
| `Evidence/2026-05-17_router-hardening-session.md` | New (this file) | Safe to commit |

---

## Outstanding manual actions (Helder)

### Step 0 — Clean the clean phone first (NEW — must be done before anything else)
The clean phone was signed into the same Google account as the compromised Android.
Before using it to touch the router:
- Sign out of the compromised Google account on the clean phone.
- Clear app data for Chrome, Drive, Photos, and any Google app that synced.
- Do not open any file from the shared Drive before signing out.
- During Phase 2, operate with no Google account active on the device.
- After Phase 2, sign into the new Google account only (never the compromised one
  until the dirty Android is reset and the account password rotated).

### Step 1 — Power off dirty devices completely
Shut down this laptop and the dirty Android fully (not sleep, not Wi-Fi-off).
"Wi-Fi off" is software-controlled and can be silently reversed by malware.

### Step 2 — Execute Phase 2 on the clean phone (or clean laptop via Ethernet)
Follow the 18-step hardening checklist in the plan file.
If a clean laptop is available, use it with Wi-Fi disabled and Ethernet cable to
the router — that is strictly safer than phone-only (no WPA2 handshake over air).

### Step 3 — Verify Phase 2 completed
Old admin password fails, new SSID joins, `1.1.1.1/help` confirms Cloudflare Families DNS.

### Step 4 — Format this Windows laptop
USB-installer Windows reinstall, full system-drive wipe.
Image the drive first if forensic recovery of `Logs/firewall.log` truncation is desired.

### Step 5 — Factory-reset the dirty Android
From the clean phone: rotate the compromised Google account password and 2FA first.
Then factory-reset the Android. Do not restore from any Google backup made before
the compromise was detected.

### Step 6 — Reconnect devices only after formatting
No device connects to the new Wi-Fi until it has been freshly formatted.

---

## Why this document exists in `Evidence/`

Files in `C:\Sync\Evidence\` are protected by recursive Deny-Delete ACLs
applied at setup time. If the attacker regains endpoint access before
Helder finishes formatting, they cannot delete or silently rewrite this
record. Files here may only be appended to via new evidence files; the
original remains immutable to standard user-level tampering.

---

## End of evidence

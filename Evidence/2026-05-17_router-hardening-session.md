# Router Factory-Reset Hardening — Session Evidence

**Generated:** 2026-05-17 19:39:47 BRT (UTC-03:00)
**Host:** `LAP\helde` (Windows 11, hostname per `C:\Sync`)
**Session type:** Defensive — recovering control of compromised home network
**Plan file:** `C:\Users\helde\.claude\plans\calm-giggling-liskov.md`

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

1. Air-gap the compromised laptop and Android (Wi-Fi off, Ethernet unplugged).
2. From the clean cellphone, execute Phase 2 (steps 1-18) of the plan file.
3. Format the Windows laptop (USB-installer Windows reinstall, full system-drive wipe).
4. Factory-reset the Android phone; rotate the Google account password and 2FA
   from the clean phone first.
5. Reconnect devices to the new Wi-Fi only after each is freshly formatted.
6. Review `Logs/firewall.log` truncation — if forensic recovery is desired,
   image the system drive before formatting.

---

## Why this document exists in `Evidence/`

Files in `C:\Sync\Evidence\` are protected by recursive Deny-Delete ACLs
applied at setup time. If the attacker regains endpoint access before
Helder finishes formatting, they cannot delete or silently rewrite this
record. Files here may only be appended to via new evidence files; the
original remains immutable to standard user-level tampering.

---

## End of evidence

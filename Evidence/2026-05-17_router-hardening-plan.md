# Plan: Router Factory-Reset Hardening — ASKEY RTF8225VW-SV (VIVO Fibra Wi-Fi 6)

## Context
Helder's Vivo router was factory-reset to evict an attacker who has persistent
control of his network. Both his Windows laptop (this machine) and his Android
phone are still compromised. Only one cellphone — never connected to this Wi-Fi —
is presumed clean.

**Hardware confirmed from photos:**
- Model: **ASKEY RTF8225VW-SV** (Vivo Fibra Wi-Fi 6, manufactured 2026-01)
- Admin URL: **`http://192.168.15.1`**
- Default admin: `admin` / **`jU75J4s2`** (per-unit, printed on sticker)
- Default SSID: `VIVOFIBRA-WIFI6-3961`
- Default Wi-Fi key (WPA2-PSK): `B8ABxvLvtKwuYUN`
- Has WPS buttons (2.4GHz + 5GHz) — must be disabled
- Has 4× Gigabit Ethernet ports
- Reset button confirmed (already used)

---

## Scenario B — Clean laptop available (in addition to clean cellphone)

If you acquire a second laptop that has **never been connected to this home network**
and has no shared accounts/sync with the compromised devices, it can replace the clean
phone as the operator. It offers a full browser and easier copy-paste for long passwords.

**Trust requirements for the clean laptop to qualify:**
- Never connected to this home Wi-Fi (not even once in the past).
- Not signed into the same Google/Microsoft account as the dirty Android or this laptop
  (those accounts may be compromised and sync credentials silently).
- No Vivo/ISP software, no remote-access tools, no shared cloud storage with dirty devices.
- Ideally: freshly installed OS from a USB image, or a device belonging to someone else.

**How to use it instead of the clean phone:**

1. Generate the new admin password and new Wi-Fi password on the clean laptop — type
   them into a local plain-text file or password manager **on that machine only**.
   Do NOT sync, email, or cloud-save them.
2. **Disable Wi-Fi on the clean laptop before connecting** (in Windows: airplane mode, or
   Device Manager → disable the Wi-Fi adapter). Then connect via **Ethernet cable directly
   to the router**. This is mandatory — if Wi-Fi is enabled, the laptop may auto-associate
   wirelessly and the new password would transit over the air, defeating the isolation.
3. Open browser → `http://192.168.15.1` → proceed with Phase 2 steps 4-18 below.
4. After finishing, the new credentials exist only on the clean laptop. Store them in
   a password manager on that machine and do not transfer to the dirty laptop until
   it has been freshly formatted.

**Ethernet cable is strongly preferred over Wi-Fi for this step** — it removes the risk
of a dirty device sniffing the WPA2 4-way handshake when the clean laptop joins the
network, which would give the attacker the new PSK.

---

## CRITICAL REVISION — Do NOT use this laptop

**Threat reality:** A compromised endpoint cannot safely change the router password.
The moment the new password is typed or transmitted through this laptop, the
attacker captures it via keylogger, screen capture, or local-traffic sniffing.
Using Playwright MCP or curl from this laptop has the same problem — the password
exists in this machine's memory.

**The only safe operator for this task is the clean cellphone**, used as follows.

---

## Phase 0 — Clean the clean phone BEFORE it touches the router

The clean phone was used with the **same Google account as the compromised Android**.
This creates a sync bridge the attacker can exploit. These steps must be done before
Phase 2 — otherwise the clean phone is not fully trustworthy as an operator.

1. **Sign out of the compromised Google account** on the clean phone.
   Settings → Accounts → select the shared account → Remove account.
   This severs Drive/Photos/Chrome sync from the attacker's reach.
2. **Clear app data** for Chrome, Drive, Photos, and any Google app that was active
   while the shared account was signed in.
   Settings → Apps → [app] → Storage → Clear Data.
3. **Do not sign into any Google account during Phase 2.** Operate the router session
   with no Google account active on the device.
4. **Do not open any file received via Drive or shared from the compromised account**
   before signing out — Drive is a viable delivery channel for malicious documents.
5. After Phase 2 is complete, you may sign into the **new Google account** (the one
   created on the clean phone and never touched by compromised devices). Do not
   sign back into the compromised account until the dirty Android is factory-reset
   and the Google account password has been rotated.

**Why this matters:** The attacker can place malicious files in the shared Drive,
read everything you store there (including any new passwords), and silently sync
settings/autofill/Chrome passwords to any device signed into the same account.
Signing out removes all of these vectors before the clean phone is used for the
router operation.

---

## Phase 1 — Pre-flight (still safe to do from this laptop)

These steps don't reveal any future secret, so the compromised laptop can do them:

1. **Physically power off the dirty devices** — do not merely disable Wi-Fi.
   "Wi-Fi off" is a software command; malware can silently re-enable the radio and
   sniff WPA2 4-way handshakes from nearby joins. Full power-off removes that risk.
   - This laptop: shut down completely (not sleep/hibernate).
   - Dirty Android: power off completely.
   - Any other device that has ever connected to this Wi-Fi: power off or unplug.
2. **Power-cycle the router** if you haven't already after the factory reset
   (ensures clean state in RAM).
3. **Generate the new admin password and new Wi-Fi password offline** — write them
   on paper. Suggested format: 20+ chars, mixed case + digits + symbols, no
   dictionary words. Do NOT type them into this laptop, Android, any password
   manager that syncs, or any cloud note.

---

## Phase 2 — Clean cellphone operates the router (you do this manually)

**⚠️ Residual weakness of phone-only approach:** The clean phone must connect via Wi-Fi —
there is no Ethernet option. This means the WPA2 4-way handshake is transmitted over the
air. If dirty devices are powered off (not just Wi-Fi-off), this risk is eliminated.
If a clean laptop with an Ethernet cable is available, use Scenario B instead — it is
strictly safer.

**On the clean phone:**

1. Turn OFF mobile data temporarily (to force the browser through Wi-Fi, so you
   know you're really hitting the local router and not a public-DNS-spoofed page).
2. Connect to `VIVOFIBRA-WIFI6-3961` using key `B8ABxvLvtKwuYUN`.
3. Open browser → `http://192.168.15.1`.
4. Log in: `admin` / `jU75J4s2`.
5. **Change admin password immediately** (the new strong one from your paper note).
6. Log back in with the new password.
7. **Change Wi-Fi (WPA) password** to the new strong one. Also rename SSID away
   from the Vivo default (avoids ISP-fingerprinting; pick a neutral name).
8. **Force WPA2-AES** (or WPA3 if offered). Reject TKIP and "WPA/WPA2 mixed".
9. **Disable WPS** on both 2.4 GHz and 5 GHz. Critical — WPS PIN is brute-forceable.
10. **Disable remote management / WAN admin access** (look for "Gerenciamento
    Remoto", "Acesso WAN", "TR-069" — leave TR-069 on if Vivo support requires it,
    but disable HTTP/HTTPS WAN admin).
11. **Disable UPnP** ("UPnP" or "Plug and Play universal"). Critical — UPnP lets
    malware on a LAN device silently open inbound ports.
12. **Set DNS to Cloudflare for Families:** `1.1.1.3` and `1.0.0.3` (blocks malware
    and phishing domains at the DNS level — disrupts C2 channels even while dirty
    devices are still connected later).
13. **Review port forwarding / DMZ / virtual server rules** — delete every rule.
    Factory reset should clear them but verify.
14. **Review connected-device list** — should show only the clean phone right now.
15. **Disable guest network** unless you actively need it.
16. **Check firmware version** — apply update if one is offered.
17. **Disable "Wi-Fi Vivo" / "Vivo Wi-Fi Comunidade"** if present (some Vivo
    routers broadcast a community SSID by default — attack surface).
18. Log out. Forget the network on the clean phone if you want to keep it off.

---

## Phase 3 — Format the dirty devices BEFORE reconnecting them

Order of priority:
1. **Windows laptop** (more capability for lateral movement, persistence in UEFI
   is rare but possible — at minimum: full Windows reinstall from USB image
   downloaded on the clean phone, wipe + reformat the system drive, do NOT
   restore from any local backup that predates the compromise).
2. **Android phone** (factory reset; do NOT restore from Google backup if the
   Google account itself may be compromised — change Google password from the
   clean phone first, enable 2FA with a hardware key or the clean phone as
   authenticator).

**Until each device is formatted, do not connect it to the new Wi-Fi.** A single
compromised device on the LAN can attempt re-exploitation of the router via
LAN-side CVEs, ARP-spoof the clean phone, or sniff PSK handshakes from new joins.

---

## Phase 4 — Extra layers worth adding (cheap, high value)

| Layer | What | Why |
|---|---|---|
| **Cloudflare Families DNS** | Already in Phase 2 step 12 | Free, blocks malware/phishing/C2 |
| **Hardware security key** | Buy a YubiKey or use the clean phone as a passkey | Account takeover protection for Google/Apple/banks |
| **Password manager fresh install** on freshly-formatted laptop | Bitwarden / 1Password, new master password generated on paper | Stop password reuse across services the attacker already saw |
| **2FA audit** on all important accounts (from clean phone) | Remove any 2FA method that uses the dirty Android | Rotate before reconnecting dirty devices |
| **Email rules audit** (Gmail/Outlook) from clean phone | Look for forwarding rules, filters that delete security alerts | Common attacker persistence |
| **Router log review** weekly | Look for unknown MACs, repeated failed admin logins | Early detection of re-compromise |
| **Disable IPv6** temporarily | If you don't actively use IPv6 | Some routers leak IPv6 firewall rules |
| **Reserve DHCP for known MACs only** (optional, advanced) | MAC filtering is bypassable but adds friction | |

---

## Why I am NOT using these MCP/tools

| Tool considered | Why rejected |
|---|---|
| **Playwright MCP browser automation** | Runs on this compromised laptop. Any password I type into the browser is captured by the attacker before submission. |
| **curl/PowerShell HTTP requests to router** | Same — password sits in process memory and command history on this laptop. |
| **nmap / port scan from this laptop** | Would reveal router topology to attacker if they're sniffing. Not catastrophic but unnecessary. |
| **Saving the new password in any file on this laptop** | Catastrophic — exfiltration trivial. |

What I CAN safely do from this laptop:
- Generate a candidate strong password **string only** (no labelling of what it's for) and you transcribe to paper without naming it in the chat.
- Walk you through the Vivo router UI labels (they are usually in Portuguese — I can map Portuguese menu names to actions).
- Look up known CVEs / firmware versions for ASKEY RTF8225VW-SV (research only, no network action).

---

## Verification (after you finish Phase 2 on the clean phone)

1. From the clean phone, try logging into `http://192.168.15.1` with the OLD
   password `jU75J4s2` — must fail.
2. Forget and rejoin the new SSID using the new Wi-Fi password — must succeed.
3. Visit `https://1.1.1.1/help` from the clean phone — confirm "Using
   1.1.1.3 / 1.0.0.3" appears (DNS change took effect).
4. Visit `https://www.whatismyip.com/` — confirm your public IP. Save it. If it
   ever changes unexpectedly without a router reboot, that's a red flag.
5. Confirm WPS is OFF by trying to push the WPS button — the device should not
   pair (or you simply trust the setting toggle).

---

## Tools needed from Claude

**None for execution.** I am the wrong instrument for this job from this
machine. My role is advisory: confirm each Vivo router menu label as you
encounter it on the clean phone, look up CVEs, and verify your checklist
afterwards from your description.

If you want, after you've completed Phase 2, you can paste a screenshot from
the clean phone (sent to you, opened on a different clean device) showing the
final settings — I can review them for gaps.

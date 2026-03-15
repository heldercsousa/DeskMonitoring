# PHYSICAL TAMPERING — Router Reset Button Disabled
## Ref: 2026-03-15_MASTER-incident-report.md | 2026-03-15_P1-dns-attack.md

**Documented:** 2026-03-15 (session)
**Severity:** CRITICAL — Physical access confirmed. Network infrastructure compromised.

---

## Observation
The router's hardware reset button has been physically blocked with glue.
This is a deliberate act to prevent the owner from restoring factory defaults,
ensuring the attacker's DHCP/DNS configuration persists indefinitely.

---

## Implications

### What this confirms
- **Physical access to the premises** occurred at an unknown time before 2026-03-11
  (first observed DNS failure date)
- The DHCP poisoning (127.0.0.1 as DNS on Ethernet) was **deliberately configured**
  on the router — not an accident or misconfiguration
- The attacker anticipated the owner would try to reset the router as a remediation step
  and pre-emptively disabled that option
- This is a **targeted, premeditated attack**, not opportunistic

### What may still be active on the router
- DHCP DNS poisoning (127.0.0.1) — confirmed
- Port forwarding rules exposing internal services to internet
- DMZ entry pointing to a device on the LAN
- Remote management (HTTP/SSH/Telnet) enabled and exposed to internet
- DNS rebinding rules targeting specific domains
- Traffic interception / man-in-the-middle for unencrypted traffic
- Logging of all LAN traffic sent to attacker-controlled server
- Rogue SSID or Wi-Fi client isolation disabled (allows LAN pivoting)
- UPnP enabled — any device on LAN can open arbitrary ports
- Firmware backdoor — may persist even after reflash

### What the static DNS fix (P1) does and does NOT protect
- DOES: prevents this machine's DNS from being poisoned via Ethernet DHCP
- DOES NOT: protect other devices on the Ethernet LAN
- DOES NOT: protect against traffic interception at the router level
- DOES NOT: protect against port forwarding or remote access rules
- DOES NOT: protect Wi-Fi if router firmware has a backdoor

---

## Immediate Actions Required (manual — cannot be automated)

### Priority A — Isolate the compromised router NOW
1. **Do NOT connect any sensitive device via Ethernet to this router**
   The Ethernet LAN is fully attacker-controlled.
2. **Treat Wi-Fi as potentially compromised too** — the router controls Wi-Fi.
   Use mobile data hotspot for sensitive operations if possible.
3. **Photograph the glued reset button** — physical evidence for police report.

### Priority B — Replace or reflash the router
Option 1 (RECOMMENDED): **Replace the router entirely**
  - Buy a new router
  - Do NOT reuse the same device even after reflash — firmware backdoor may survive
  - Configure fresh with new admin password, new Wi-Fi SSID/password

Option 2 (ONLY if replacement not immediately possible): **Reflash firmware**
  - Download official firmware from manufacturer (verify SHA256 hash)
  - Flash via TFTP recovery mode (bypasses the glued button on most models)
  - Note: if attacker installed persistent bootloader backdoor, reflash may not help

### Priority C — Audit router configuration before replacement
If you have router admin access, document and photograph:
  - DHCP settings (confirm DNS = 127.0.0.1 is there)
  - Port forwarding rules
  - DMZ settings
  - Remote management settings (is WAN admin access enabled?)
  - Connected devices list
  - Firewall rules
  - UPnP status
  - Any unknown admin accounts
  - Syslog / logging destinations
  This is evidence. Export config file if possible.

### Priority D — Change all credentials that transited this network
Any password, token, or credential typed or transmitted while on this network
(Ethernet OR Wi-Fi) should be considered potentially captured:
  - Router admin password (obviously)
  - B2/Backblaze account password and API keys
  - Windows login password (if used remotely)
  - Any web account logged into via this router
  - SSH keys used over this network

### Priority E — File a police report
Physical tampering with hardware is criminal in most jurisdictions.
The glued reset button is physical evidence — preserve it (photograph, do not clean).

---

## Network Trust Assessment After This Incident

| Interface | Trust level | Action |
|---|---|---|
| Ethernet (this router) | ZERO — attacker-controlled | Disconnect |
| Wi-Fi (this router) | UNTRUSTED — router compromised | Avoid for sensitive ops |
| Mobile hotspot | TRUSTED (until new router) | Use for sensitive ops |
| New router (after replacement) | TRUSTED | Replace as soon as possible |

---

## Files changed due to this incident
- `Config/cloud_sync.ps1` — DNS-ATTACK-DETECT branch added
- `Config/start_ecosystem.ps1` — Yawcam/CAM-2 startup fixes
- Ethernet adapter: static DNS 1.1.1.1/8.8.8.8 set (persists reboots)

---

## LAN Device Audit (2026-03-15 session)

### Hosts file — CLEAN
No tampering detected in `C:\Windows\System32\drivers\etc\hosts`.

### DNS resolution — RESTORED
`api.backblazeb2.com` now resolves to `104.153.233.180, 149.137.142.15` (correct Backblaze IPs).
Static DNS fix confirmed working.

### Unknown device: 192.168.0.106
- **MAC**: c8:12:0b:ff:bd:0a
- **OUI**: Micro-Star INTL CO. (MSI) — gaming laptop/desktop manufacturer
- **Status**: Reachable (ping success)
- **Open port**: 8080 (HTTP) — returns HTTP 403
- **No hostname** via reverse DNS or NetBIOS
- **Active connection observed**: During audit, this machine had an `ESTABLISHED` TCP connection
  to `192.168.0.106:8080` (local port 57745). Connection closed before process could be identified.
  The originating process is **unknown** — this is a suspicious finding.
- **Verdict**: Identity unconfirmed. Could be another device on the LAN belonging to attacker
  or a legitimate device (neighbour's laptop, etc.). HTTP service on :8080 with no hostname is atypical.

### Unknown device: 192.168.0.206
- **MAC**: 90:b6:22:51:a2:cd
- **Status**: UNREACHABLE at time of scan
- **OUI**: Not identified (Huawei range — common in consumer routers and IoT)
- **Verdict**: Device may be offline or powered down; no further data.

### Suspicious external connection: 18.97.36.5 (AWS EC2)
- Reverse DNS: `ec2-18-97-36-5.compute-1.amazonaws.com`
- Connection: ESTABLISHED on port 443 from this machine
- This could be legitimate (many cloud services use AWS) or indicate C2 exfiltration channel
- **Note**: Earlier in session, a transient `SYN_SENT` to `169.254.169.254:80` (AWS EC2 instance
  metadata IP — only meaningful inside an EC2 instance) was observed but did not persist.
  Possible explanation: AWS SDK or background service probing metadata endpoint incorrectly.

### Summary of LAN audit risk
| Finding | Risk |
|---|---|
| .106 unknown MSI device with HTTP:8080 | MEDIUM — unidentified; monitor |
| ESTABLISHED connection from this machine to .106:8080 | HIGH — process unknown; could be attacker pivot |
| .206 unreachable Huawei device | LOW — offline; revisit if it appears |
| AWS EC2 connection (18.97.36.5) | LOW-MEDIUM — likely legitimate but unverified |
| Hosts file | CLEAN |
| DNS resolution | RESTORED (static DNS working) |

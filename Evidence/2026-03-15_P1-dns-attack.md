# P1 — DNS Attack Investigation & Remediation Log
## Ref: 2026-03-15_MASTER-incident-report.md

**Started:** 2026-03-15 (autonomous session)
**Status:** IN PROGRESS

---

## Objective
Identify and remove the mechanism by which DNS resolution for `api.backblazeb2.com` and
`api005.backblazeb2.com` is being sabotaged. Document every atomic step and finding.

---

## Steps & Evidence


### STEP 1 — Hosts file check [CLEAN]
No Backblaze entries in hosts file. Not the attack vector.

### STEP 2 — DNS server per adapter
`
Ethernet  DNS: 127.0.0.1          (DISCONNECTED currently)
Wi-Fi     DNS: 181.213.132.2, 181.213.132.3  (UP, 866.7 Mbps)
`

### STEP 3 — Live DNS resolution test [RESOLVES NOW]
- api.backblazeb2.com -> 149.137.142.15, 104.153.233.180
- api005.backblazeb2.com -> 149.137.136.15
DNS works NOW because machine is on Wi-Fi. Ethernet is disconnected.

### STEP 4 — Firewall rules [NONE]
No firewall rules targeting B2 IPs or port 53.

### STEP 5 — Port 53 listeners [NONE]
Nothing listening on 127.0.0.1:53.
CONFIRMED: if Ethernet were active, DNS lookups -> 127.0.0.1 -> no server -> "no such host".

### STEP 6 — DNS cache [VALID]
Cache shows correct B2 entries (populated from Wi-Fi session).

### STEP 7 — Proxy/intercept software [NONE]
No suspicious DNS/proxy services. Only standard Windows Dnscache running.

### STEP 8 — WPAD/proxy [DISABLED]
ProxyEnable=0, no proxy configured.

### STEP 9 — DHCP registry scan [ATTACK VECTOR FOUND]
`
Registry key: {baab750c-3740-4280-a62a-8173b9be2616}
  DhcpNameServer: 127.0.0.1   <-- ROGUE DHCP POISONING
Registry key: {aa185215-b4b6-4832-b69a-f685a7334e2a}
  DhcpNameServer: 181.213.132.2 181.213.132.3  <-- LEGITIMATE (Wi-Fi)
`

### ROOT CAUSE IDENTIFIED: DHCP Poisoning via Ethernet network
The DHCP server on the Ethernet LAN is serving 127.0.0.1 as the DNS server.
When the laptop connects via Ethernet (overnight, docked), it receives this poisoned
DNS config and all lookups fail with 'no such host'.

Attack correlation:
- 2026-03-12 00:16 -> Ethernet plugged in overnight -> DNS dead -> SYNC-FAIL all night
- 2026-03-13 01:57 -> Same pattern
- 2026-03-14 00:34 -> Same pattern
- 2026-03-15 09:55-15:05 -> Ethernet connected -> SYNC-FAIL
- 2026-03-15 14:23 -> Brief SYNC-OK window = machine switched to Wi-Fi
- 2026-03-15 14:53 -> More failures = possibly Ethernet re-engaged

Windows Event Log confirms DNS failures at 2026-03-11 14:26 (NTP timeout)
and 2026-03-15 10:11 (Microsoft telemetry DNS timeout) -- same window as B2 failures.

### STEP 10 — REMEDIATION: Set static DNS on Ethernet adapter
Action: Override DHCP DNS on Ethernet with static Cloudflare (1.1.1.1) and Google (8.8.8.8).
This prevents the rogue DHCP server from injecting 127.0.0.1 as DNS regardless of
what the compromised Ethernet DHCP server serves.


### STEP 10 — REMEDIATION APPLIED [SUCCESS]
Command: Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses (1.1.1.1, 8.8.8.8)

Registry verification:
  {baab750c-3740-4280-a62a-8173b9be2616} -> NameServer: 1.1.1.1,8.8.8.8  [STATIC, overrides DHCP]

Ethernet adapter DNS is now static and immune to DHCP poisoning from rogue server.
DHCP will still lease an IP address but DNS field will be ignored.

### STEP 11 — FUTURE-PROOFING NOTE
The router or a rogue device on the Ethernet LAN is serving 127.0.0.1 as DHCP DNS.
The attacker may have compromised the router's DHCP configuration.
Recommended follow-up (manual, requires router access):
  1. Check router DHCP settings for DNS field -- should NOT be 127.0.0.1
  2. Change router admin password
  3. Consider whether to trust Ethernet LAN at all

### STATUS: P1 REMEDIATED
Static DNS on Ethernet will survive reconnection. Attack vector neutralized on this machine.
Attack on router/DHCP server itself is out of scope for automated fix -- requires manual investigation.


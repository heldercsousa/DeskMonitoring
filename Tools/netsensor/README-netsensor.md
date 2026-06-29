# T083 - Out-of-band network sensor (N100 + Security Onion)

**Status:** Pre-authored. Deployment is Blocked-Hardware (needs the Intel N100 mini-PC
+ the AX3000T port-mirror wiring) and waits on the clean rebuild. The two artifacts
below are ready to drop in the moment the hardware arrives.

**Why this is the centerpiece:** Under assume-breach, no on-host tool can be trusted to
report C2 / beaconing / exfiltration - a local-admin attacker can blind it. A separate
device that the laptop cannot see or tamper with is the only tamper-proof way to watch
in/out packets. Source: `Protecao_Win11.md` Layer 1 + Phase 0/1.

## What is pre-authored here (works NOW, before hardware)

| File | Purpose |
|---|---|
| `openwrt-tc-mirror.init` | OpenWrt `/etc/init.d` service that re-applies the WAN `tc mirred` port mirror on every boot (DSA `tc`, `skip_sw` hardware offload). |
| `parse_netsensor.py` | Pure-stdlib heuristic analyzer for Suricata EVE JSON + Zeek conn/dns/tls logs. Flags BEACON / EXFIL / DNS-DGA / TLS-WEAK / IDS ALERT. Ties to the T081 triage skillset. |

`parse_netsensor.py` was tested offline against synthetic Suricata + Zeek fixtures:
beacon, exfil, DNS-tunnel, self-signed TLS, and IDS-alert findings all fire; exit
codes 0 (clean) / 2 (low-med) / 3 (high) verified. No pip install - it runs on the
sensor itself or on this host (`python parse_netsensor.py --eve eve.json --pretty`).

## Hardware (to buy)

- Fanless **Intel N100 mini-PC, 16 GB RAM (single DDR5 stick), NVMe** (~$150).
- A Pi 5 is a weaker fallback - standalone Suricata+Zeek only, NOT full Security Onion.

## Software (to install on the N100)

- **Security Onion** (turnkey: Suricata + Zeek + Strelka + full packet capture +
  Elastic + hunting UI). The N100 (not a Pi) is required for the full stack.

---

## ACTION FOR HELDER - deployment (when hardware arrives)

### 1. Router: enable the hardware port mirror (Xiaomi AX3000T, OpenWrt 23.05+)

The MT7531 switch supports exactly ONE monitor port. Pick a physical LAN port
(default LAN4) to be the dedicated SPAN port feeding the N100, and remove it from
the bridge first:

```sh
# remove lan4 from br-lan so it can be a one-way mirror port
uci del_list network.@device[0].ports='lan4'   # adjust index to your config
uci commit network
/etc/init.d/network reload
```

Then install the init script:

```sh
scp openwrt-tc-mirror.init root@192.168.0.1:/etc/init.d/tc-mirror
ssh root@192.168.0.1 'chmod +x /etc/init.d/tc-mirror; /etc/init.d/tc-mirror enable; /etc/init.d/tc-mirror start'
```

Verify the mirror is offloaded to the ASIC (look for `in_hw`) and counters climb:

```sh
tc filter show dev wan ingress
tc -s filter show dev wan egress
```

If `WAN_IF`/`SPAN_IF` differ on your box, edit the two vars at the top of the script.
Caveat (from the doc): mirroring `br-lan`/Wi-Fi instead of a physical switch port
falls back to software and loads the router CPU - always mirror a physical port.

### 2. N100: install Security Onion

Follow the Security Onion installer; cable the SPAN port (LAN4) into the N100's
sniffing NIC and configure that NIC as the monitor interface during setup.

### 3. Analysis: run the parser on the sensor's logs

```sh
python parse_netsensor.py --eve /nsm/suricata/eve.json --pretty
python parse_netsensor.py --conn conn.log --dns dns.log --tls tls.log --out findings.json
```

Tunable thresholds live at the top of `parse_netsensor.py` (beacon jitter,
exfil byte ceilings, DNS entropy/subdomain limits).

### 4. Related follow-ups

- **T077 (WEF):** the N100 can double as the off-box Windows Event Collector that
  T077 is blocked on - see `Config/wef/README-WEF-collector-setup.md`.
- **T084 (Wazuh + Velociraptor):** server on the N100, agent on the laptop.

## Status word: Blocked-Hardware (deployment) / Done (pre-authoring)

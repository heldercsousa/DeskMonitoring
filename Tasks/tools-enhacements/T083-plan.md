# T083 — Out-of-band network sensor (N100 + Security Onion)

**Goal:** The centerpiece of the doc. A separate device the laptop attacker cannot see or tamper with, giving tamper-proof visibility into outbound C2 / beaconing / exfiltration and inbound connections. This is the authoritative answer to "real-time monitoring of in/out packets" that no on-host tool can provide under assume-breach.

**Source:** `Protecao_Win11.md` Layer 1 + Phase 0/1.

## Hardware
- Fanless **Intel N100 mini-PC, 16 GB RAM, NVMe** (~$150; single-channel — one fast DDR5 stick). Pi 5 is a weaker fallback (standalone Suricata+Zeek only, not full Security Onion).

## Software
- **Security Onion** (turnkey: Suricata + Zeek + Strelka + full packet capture + Elastic + hunting UI) on the N100.

## Router feed (Xiaomi AX3000T, OpenWrt 23.05+, MT7531 switch)
DSA removed the old swconfig mirror knobs; use `tc mirred` with ASIC offload:
```sh
opkg install tc-full ip-full
ip link set up dev lan4
tc qdisc add dev wan clsact
tc filter add dev wan ingress matchall skip_sw action mirred egress mirror dev lan4
tc filter add dev wan egress  matchall skip_sw action mirred egress mirror dev lan4
```
- `skip_sw` forces hardware offload (line rate, near-zero CPU). HW allows **one** monitor port — remove `lan4` from `br-lan`, make it a dedicated SPAN port. Commands don't survive reboot — persist in an init script.

## What Claude Code can pre-author NOW (before hardware arrives)
- The OpenWrt init script for the tc mirror.
- A Python parser for Suricata **EVE JSON** + Zeek conn/dns/tls logs (beaconing/exfil heuristics) — ties to T081 skills.

## Caveats (from doc)
- Mirroring `br-lan`/Wi-Fi instead of a physical port falls back to software and loads the router CPU — mirror a switch port.
- The N100 (not a Pi) is required for the full Security Onion stack.

## Status
Strategic / Phase 1. Pre-authoring is doable now; deployment waits on hardware + the reformat.

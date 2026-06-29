# T083 - steps status

**Task:** Out-of-band network sensor (Intel N100 + Security Onion), fed by an
AX3000T hardware port mirror. Pre-author the deployable artifacts now; deploy on
hardware/rebuild.

**Overall status:** Pre-authoring **Done**. Deployment **Blocked-Hardware**.

## Checklist

- [x] OpenWrt init script for the persistent `tc mirred` WAN port mirror
      -> `Tools/netsensor/openwrt-tc-mirror.init` (procd service, START=99, ASIC
      offload via `skip_sw`, auto-installs tc-full/ip-full, verifies `in_hw`).
- [x] Python parser for Suricata EVE JSON + Zeek conn/dns/tls
      -> `Tools/netsensor/parse_netsensor.py` (pure stdlib). Heuristics:
      BEACON, EXFIL, DNS-DGA, TLS-WEAK, IDS ALERT passthrough.
- [x] Parser tested offline against synthetic fixtures (Suricata eve + Zeek TSV +
      Zeek JSON-lines): all 5 finding types fire; exit codes 0/2/3 verified.
- [x] Fixed two bugs found during build: NameError in `alerts_to_findings`
      (severity_map) and a broken Zeek `#separator` parser.
- [x] README with deployment guide + ACTION FOR HELDER
      -> `Tools/netsensor/README-netsensor.md`.
- [x] RULE 1 guide sync: ECOSYSTEM_REPORT.md Section 5 "Standalone Python tools"
      table - added two rows (parse_netsensor.py + openwrt-tc-mirror.init).
- [x] Backlog row updated.
- [x] Committed.

## Not applicable / deliberately skipped

- **setup_update.ps1:** no change. These are git-tracked source artifacts that
  deploy on the *router* and the *N100*, not on this Windows host - nothing to
  install locally on reinstall (restored from git, same model as Tools/file-triage).
- **CLAUDE.md:** no ecosystem architecture/path/task change on this host; the new
  Tools/netsensor/ dir is documented in ECOSYSTEM_REPORT.md (the place for
  standalone tools).
- **Section 15 (full-content mirror):** Section 5 note already states standalone
  Tools/ scripts are restored from git, not mirrored in Section 15.

## ACTION FOR HELDER (resume / deploy point)

Nothing automatable remains on this host. To deploy (needs hardware):
1. Buy the Intel N100 mini-PC (16 GB, NVMe).
2. On the AX3000T: remove LAN4 from br-lan, install `openwrt-tc-mirror.init`
   as `/etc/init.d/tc-mirror`, enable + start, verify `in_hw`.
3. Install Security Onion on the N100; cable LAN4 -> N100 sniffing NIC.
4. Run `parse_netsensor.py` against `/nsm/suricata/eve.json` + Zeek logs.
Full steps: `Tools/netsensor/README-netsensor.md`.
Related: T077 (N100 as WEF collector), T084 (Wazuh/Velociraptor on N100).

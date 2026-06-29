# Backlog rows to append (T075-T085) - Win11 assume-breach hardening

> **Source:** `Tasks/tools-enhacements/Protecao_Win11.md` (Claude Chat research doc).
> **Reviewed/revised:** 2026-06-29 - added sequencing, trust-boundary caveats,
> T077 interim mitigation, dependency fixes, and cross-references. No tasks removed.

## Recommended sequential install order (for the post-clear install session)

Install one at a time, in this order - safe / zero-hardware / high-leverage first:

**Phase 0 - do now:**
1. **T078** - firewall event IDs into the existing auditor watcher (tiny, no deps)
2. **T080** - MCP servers (settings.json only, no system change)
3. **T081** - Python triage tool (self-contained; the Python/AI learning win)
4. **T076** - install Sysmon  ->  then **T075** - Sysmon correlation (needs T076)
5. **T079** - Autoruns baseline + daily diff
6. **T077** - WEF forwarding (when a collector exists; interim = git push)

**Phase 1 - strategic / hardware / reformat:**
7. **T083** - N100 + Security Onion (pre-author tc script + EVE parser now)
8. **T084** - Wazuh + Velociraptor (evaluate redundancy vs T083 first)
9. **T085** - managed-EDR decision (Huntress via MSP vs Defender for Business)

**Manual / physical, any time:** **T082** - offline rescue scan.

> **Trust-boundary caveat:** on-host items (T075/T076/T079) are EVIDENCE-ONLY
> until off-box forwarding (T077) is live - a local-admin/kernel attacker can
> blind or feed false data to any tool running inside the live OS.

## Rows

| ID | Parent | Description | Created | Completed | Status |
|----|--------|-------------|---------|-----------|--------|
| T075 | T076 | Add Sysmon Event 1 (process creation) correlation to auditor.ps1: on registry 4657/4663 hits on USB Selective Suspend / config keys, match the calling process in the same +-5s window (fall back to Security 4688 if Sysmon absent). Closes the svchost.exe blind spot from T070. EVIDENCE-ONLY until T077 forwarding is live. Detail: Tasks/tools-enhacements/T075-plan.md. | 2026-06-27 | - | Pending |
| T076 | - | Install Sysmon (SwiftOnSecurity config) on-host: authoritative process/network/DNS telemetry (Event IDs 1/3/22); add install + config to setup_update.ps1 so it survives reinstall. Prereq for T075. EVIDENCE-ONLY until forwarded off-box (T077). Detail: Tasks/tools-enhacements/T076-plan.md. | 2026-06-27 | - | Pending |
| T077 | T076 | Forward Sysmon + Security events off-box via Windows Event Forwarding (WEF) so a local-admin attacker cannot retroactively erase tamper evidence. BLOCKED on a collector host (interim N100 T083, or any clean second machine). INTERIM mitigation available now: existing FolderSync-GitCommitLogs already pushes security logs off-box (e.g. Logs/security/firewall.log is git-tracked) - tighten audit-log push cadence until a real collector exists. Detail: Tasks/tools-enhacements/T077-plan.md. | 2026-06-27 | - | Blocked |
| T078 | - | Add firewall-tamper Event IDs 4946/4947/4948/4950/5025 to the existing auditor.ps1 real-time watcher (beside the TASK-TAMPER 4699/4701/4702 watcher); enable the "MPSSVC Rule-Level Policy Change" audit subcategory via setup_update.ps1 (not on by default). Event-based complement to the rule-scan firewall detection in T010. Detail: Tasks/tools-enhacements/T078-plan.md. | 2026-06-27 | - | Pending |
| T079 | - | Autoruns persistence baseline + daily diff: schedule autorunsc.exe export (-a * -c -h -s) and Compare-AutoRunsBaseLine; surface new/changed persistence as a daily [AUTORUN-DELTA] delta; optional VirusTotal hash enrichment (ties to T080). Feeds T070/T072 investigations. EVIDENCE-ONLY (live OS) - corroborate deltas against offline mount (T082). Detail: Tasks/tools-enhacements/T079-plan.md. | 2026-06-27 | - | Pending |
| T080 | - | Wire VirusTotal + Shodan + CVE MCP servers into .claude/settings.json (complements the existing threatintel MCP T020); env-only API keys, gitignored. Enables in-session hash/IP/domain enrichment of firewall + audit IOCs. Point analysis at trusted/forwarded logs, not data read off the compromised host; never upload confidential files to public VT. Detail: Tasks/tools-enhacements/T080-plan.md. | 2026-06-27 | - | Pending |
| T081 | - | Python file-triage tool (oletools + vt-py): drop-folder script that runs oleid/olevba (Office) + pdfid (PDF) + hash-only VT lookup (respect 4 req/min, 500/day; never upload the file itself) and emits a JSON risk summary; hook into the daily check. Doubles as Helder's first Python/AI-engineering project. Detail: Tasks/tools-enhacements/T081-plan.md. | 2026-06-27 | - | Pending |
| T082 | - | [MANUAL / PHYSICAL] Offline rescue scan: boot Defender Offline -> Kaspersky Rescue Disk -> ESET SysRescue to detect kernel/bootkit/firmware persistence the live OS cannot. Treat results as evidence, not all-clear. Firmware/UEFI indicators -> reflash/replace hardware + professional IR. Cannot be automated by Claude Code. Detail: Tasks/tools-enhacements/T082-plan.md. | 2026-06-27 | - | Pending |
| T083 | - | [STRATEGIC / Phase 1] Out-of-band network sensor: Intel N100 mini-PC (16GB RAM, NVMe) running Security Onion (Suricata+Zeek+Strelka+full packet capture), fed by an AX3000T hardware port mirror (tc mirred, skip_sw, dedicated SPAN port off br-lan). The only tamper-proof C2/exfil visibility under assume-breach. Pre-author NOW: OpenWrt tc init script + Suricata EVE JSON / Zeek conn/dns/tls parser (ties to T081 skills); deploy on hardware/rebuild. Detail: Tasks/tools-enhacements/T083-plan.md. | 2026-06-27 | - | Pending |
| T084 | T083 | [STRATEGIC / Phase 1] Wazuh (server on N100, agent on laptop) + Velociraptor for ongoing FIM/registry monitoring and hunt-on-alert, with off-host log storage. Evaluate redundancy vs Security Onion host-telemetry (Strelka/agents) before committing. Deploy on clean rebuild. | 2026-06-27 | - | Pending |
| T085 | - | [DECISION] Evaluate Huntress Managed EDR for the clean rebuild (layers on Defender AV; 50-agent minimum -> via MSP; verify Brazil availability/pricing). Realistic solo fallback: Microsoft Defender for Business (no device minimum). Do NOT stack two kernel-level EDRs as peers. | 2026-06-27 | - | Pending |

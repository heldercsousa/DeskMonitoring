# T084 - Wazuh (server on N100) + Velociraptor (agent on laptop)

**Parent:** T083 (out-of-band network sensor / N100).
**Source:** `Protecao_Win11.md` lines 54-56, 136, Phase 1.

**Goal:** Ongoing host-telemetry detection-to-hunt on the clean rebuild:
- **Wazuh** - free open-source SIEM/XDR. Server runs on the N100 (Linux); a Windows
  agent on the laptop does File Integrity Monitoring (FIM), Windows registry
  monitoring, rootcheck, and VirusTotal hash enrichment, with MITRE ATT&CK mapping.
  Logs are stored **off-host** on the N100 so a local-admin attacker cannot
  retroactively erase them.
- **Velociraptor** - free DFIR / threat-hunting platform. VQL queries interrogate the
  endpoint for processes, persistence, PowerShell activity, and memory artifacts.
  Pattern: **Wazuh alert -> Velociraptor hunt** ("hunt for what and why").

## Why this matters to THIS ecosystem

The documented attacker repeatedly: (a) overwrites `Config/` scripts nightly,
(b) disables defensive scheduled tasks in-process (T070), (c) flips power/registry
keys (T058/T067/T069), (d) adds firewall B2-block rules (T010). FIM + registry
monitoring with off-host storage turns each of those into a tamper-proof alert; a
Velociraptor hunt then answers *which process did it* - the open question in T070.

## Hard dependencies (why deployment is blocked)

1. **N100 hardware (T083)** - the Wazuh manager/indexer needs the Linux box.
   Blocked-Hardware until the mini-PC is bought.
2. **Clean rebuild** - per the doc, on-host agents are only trustworthy after the
   reformat. Installing a Wazuh/Velociraptor agent on the *currently compromised*
   laptop would itself be inside the attacker's trust boundary (the agent could be
   killed or fed false data). So the laptop agent is a clean-rebuild action, not a
   now action.

## Redundancy decision (required by the backlog row)

The backlog row says "Evaluate redundancy vs Security Onion host-telemetry
(Strelka/agents) before committing." That evaluation is written to
`Tools/wazuh-velociraptor/redundancy-evaluation.md`. Summary verdict:
**keep both, with distinct roles** - Security Onion (T083) owns *network* ground
truth + file detonation (Strelka) on mirrored traffic; Wazuh owns *host* FIM/registry
state-change detection; Velociraptor owns *on-demand hunt*. They overlap only lightly
(both can ingest Sysmon), and the overlap is acceptable because the Wazuh agent gives
real-time FIM that Security Onion's network view cannot, while remaining cheap to run
on the same N100. No second box required - Wazuh manager + Security Onion can
co-reside on the N100 (16 GB) for a single-endpoint deployment, or Wazuh can move to a
small container if resources get tight.

## What Claude Code can pre-author NOW (this task)

All under `Tools/wazuh-velociraptor/` (no live install - nothing runs on the
compromised host):

| File | Purpose |
|---|---|
| `README.md` | Status, architecture, and the full ACTION-FOR-HELDER deploy runbook. |
| `wazuh-agent-ossec.conf` | Windows-agent config: FIM on `C:\Sync\Config` + hosts file + Tasks dir, registry monitoring of the exact keys this attacker flips, rootcheck, and a VirusTotal-enrichment-ready setup. Manager-side notes inline. |
| `velociraptor-client.config.template.yaml` | Client config template (placeholders for the N100 server URL + CA fingerprint) to generate per-endpoint configs after the server is stood up. |
| `velociraptor-hunts.vql` | Custom VQL artifacts mapped to documented incidents: defensive-task-disabled, Run-key persistence, Config-script tamper, power-key flip, suspicious resident process. |
| `redundancy-evaluation.md` | The Wazuh/Velociraptor vs Security Onion comparison + verdict. |

## What is explicitly NOT done now

- No agent installed on this laptop (compromised-host trust boundary + clean-rebuild
  rule).
- No Wazuh manager / indexer / dashboard install (needs the N100).
- `setup_update.ps1` is intentionally NOT modified: it provisions the *current*
  ecosystem; the Wazuh/Velociraptor agent install belongs to the clean-rebuild
  bootstrap, which is documented in the README runbook instead.

## Status

Strategic / Phase 1. Pre-authoring doable now; deployment is **Blocked-Hardware**
(N100) and gated on the clean rebuild.

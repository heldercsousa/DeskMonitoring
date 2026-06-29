# T084 - Redundancy evaluation: Wazuh + Velociraptor vs Security Onion host telemetry

The backlog row requires: *"Evaluate redundancy vs Security Onion host-telemetry
(Strelka/agents) before committing."* This is that evaluation.

## The three candidate host-telemetry layers

| Capability | Security Onion (T083) | Wazuh agent | Velociraptor |
|---|---|---|---|
| Network IDS / metadata (Suricata, Zeek) | **Yes (core)** | No | No |
| Full packet capture | **Yes** | No | No |
| File detonation / extraction (Strelka) | **Yes** - on files seen *on the wire* | No | Can collect files for offline triage |
| Host File Integrity Monitoring (FIM) | Weak - relies on forwarded logs/agents | **Yes (core)** - real-time, with diffs | On-demand only (hash a path when hunted) |
| Windows registry change monitoring | No | **Yes (core)** | On-demand (VQL glob) |
| Rootcheck / rootkit heuristics | No | **Yes** | Yes (VQL + YARA) |
| VirusTotal hash enrichment | Via Strelka/integrations | **Yes (built-in)** | Via notebook/enrichment |
| Continuous alerting (state change) | Network-centric | **Yes - host state change** | No (pull, not push) |
| On-demand deep hunt (processes, memory, persistence, PowerShell) | Limited | Limited | **Yes (core - VQL)** |
| Off-host log storage (tamper-proof) | Yes (on the N100) | Yes (manager on N100) | Yes (server on N100) |

## Overlap analysis

- **Real overlap** is small and only on **Sysmon ingestion**: Security Onion, Wazuh,
  and Velociraptor can each consume the laptop's Sysmon (T076) event channel. That is
  acceptable - forwarding the same Sysmon stream to two consumers costs almost nothing
  and gives both a network-correlated view (Security Onion) and a host-state view
  (Wazuh) of the same events. Do NOT install two competing kernel agents (see T085 -
  never stack two kernel-level EDRs as peers); Sysmon is a passive ETW provider, not an
  EDR, so this is safe.
- **No overlap** on the high-value functions: Security Onion cannot do real-time host
  FIM/registry monitoring (it sees the network, not the filesystem), and neither it nor
  Wazuh can do an interactive VQL hunt. Each layer answers a question the others cannot.

## Verdict: keep all three, distinct roles, one box

| Layer | Owns | Answers |
|---|---|---|
| Security Onion (T083) | Network ground truth + file detonation on the wire | "Is the host beaconing / exfiltrating? What hit the wire?" |
| **Wazuh agent (this task)** | Host FIM + registry + rootcheck, continuous off-host alerting | "Did a defensive file/registry key/task change, and when?" |
| **Velociraptor (this task)** | On-demand DFIR hunt across endpoints | "Which process did it, and why - what is the persistence chain?" |

**Resource decision:** for a single endpoint, the Wazuh manager + indexer + dashboard
and the Velociraptor server can **co-reside on the same N100** that runs Security Onion
(16 GB RAM target). If Elastic (Security Onion) + Wazuh indexer contend for RAM, move
Wazuh's indexer to a lightweight single-node OpenSearch container or run Wazuh in
"agent -> manager, file-based alerts" mode without the full dashboard. No second box is
required to *start*; revisit only if the N100 saturates.

**Trust caveat (carries from the doc):** all three host agents run *inside* the laptop
trust boundary on the clean rebuild and can theoretically be blinded by a future
kernel-level compromise. Their value is defense-in-depth + off-host log storage; the
network sensor (T083) and offline rescue scans (T082) remain the closest thing to
ground truth.

## Decision

Commit to deploying **Wazuh agent + Velociraptor client on the laptop, servers on the
N100**, alongside Security Onion, on the clean rebuild. The redundancy is intentional
and minimal (shared Sysmon only). No change to the T083 plan is needed.

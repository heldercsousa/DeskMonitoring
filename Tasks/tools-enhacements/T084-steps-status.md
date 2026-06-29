# T084 - steps status

**Task:** Wazuh (server on N100) + Velociraptor (agent on laptop) - FIM/registry
monitoring + hunt-on-alert with off-host log storage. Deploy on clean rebuild.
**Overall status:** Blocked-Hardware (deployment) / Done (pre-authoring).

## Checklist

- [x] Wrote the missing plan `T084-plan.md` (no plan existed at dispatch).
- [x] Redundancy evaluation vs Security Onion host-telemetry (required by backlog row)
      -> `Tools/wazuh-velociraptor/redundancy-evaluation.md`. Verdict: keep all three,
      distinct roles, co-resident on the N100; overlap is Sysmon-only and acceptable.
- [x] Pre-authored Wazuh Windows agent config (`wazuh-agent-ossec.conf`): real-time FIM
      on Config/Evidence/hosts/Tasks, registry monitoring of the exact power/USB/Run/
      Services keys this attacker flips, rootcheck, eventchannel + Sysmon forwarding,
      no active-response.
- [x] Pre-authored Velociraptor client config template
      (`velociraptor-client.config.template.yaml`).
- [x] Pre-authored 5 custom VQL hunt artifacts (`velociraptor-hunts.vql`) mapped to
      T070 (task tamper), T017 (Run keys), Config tamper, T058/67/69 (power keys),
      T060/T070 (resident suspect process).
- [x] README runbook with the full ACTION-FOR-HELDER deploy steps.
- [x] Backlog T084 row updated.
- [ ] DEPLOY: install Wazuh server + Velociraptor server on the N100 - Blocked-Hardware.
- [ ] DEPLOY: install Wazuh agent + Velociraptor client on the laptop - clean rebuild only.
- [ ] DEPLOY: VirusTotal enrichment (free API key, ties to T080/T081).

## Why no live install / no setup_update.ps1 change

- N100 hardware does not exist yet (T083 Blocked-Hardware).
- Installing an on-host agent on the CURRENTLY COMPROMISED laptop would sit inside the
  attacker trust boundary - per the doc, host agents are a clean-rebuild action.
- `setup_update.ps1` provisions the current ecosystem; the agent install belongs to the
  clean-rebuild bootstrap and is documented in the README runbook instead.

## Resume point

Nothing to resume on the C:\Sync side - pre-authoring is complete. The next move is
hardware (buy the N100, T083) then follow `Tools/wazuh-velociraptor/README.md` after the
clean rebuild.

## Files created

- Tasks/tools-enhacements/T084-plan.md
- Tasks/tools-enhacements/T084-steps-status.md
- Tools/wazuh-velociraptor/README.md
- Tools/wazuh-velociraptor/wazuh-agent-ossec.conf
- Tools/wazuh-velociraptor/velociraptor-client.config.template.yaml
- Tools/wazuh-velociraptor/velociraptor-hunts.vql
- Tools/wazuh-velociraptor/redundancy-evaluation.md

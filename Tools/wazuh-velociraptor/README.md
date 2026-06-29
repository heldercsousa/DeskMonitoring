# T084 - Wazuh (server on N100) + Velociraptor (agent on laptop)

**Status:** Pre-authored. Deployment is **Blocked-Hardware** (needs the Intel N100 from
T083) and gated on the **clean rebuild** (on-host agents are only trustworthy after the
reformat). The artifacts below drop in once the N100 exists and the laptop is rebuilt.

**Parent:** T083 (out-of-band network sensor). **Source:** `Protecao_Win11.md` Phase 1.

## Why this layer

The documented attacker overwrites `Config/` scripts nightly, disables defensive
scheduled tasks in-process (T070), flips power/registry keys (T058/T067/T069), and adds
firewall B2-block rules (T010). **Wazuh** FIM + registry monitoring with off-host log
storage on the N100 turns each of those into a tamper-proof alert; a **Velociraptor**
hunt then answers *which process did it* - the open question in T070. Pattern:
**Wazuh alert -> Velociraptor hunt**.

## What is pre-authored here (works NOW, before hardware)

| File | Purpose |
|---|---|
| `wazuh-agent-ossec.conf` | Windows-agent config: real-time FIM on `C:\Sync\Config` + Evidence + hosts file + Tasks dir, registry monitoring of the exact power/USB/Run/Services keys this attacker flips, rootcheck, eventchannel + Sysmon forwarding. No active-response (assume-breach). |
| `velociraptor-client.config.template.yaml` | Client config template (placeholders for the N100 server URL + CA fingerprint). Prefer the wizard-generated client config; keep this as a field reference. |
| `velociraptor-hunts.vql` | 5 custom VQL artifacts mapped to documented incidents: defensive-task tamper, Run-key persistence, Config-script tamper (DPAPI/Portuguese-marker check), power-registry flip, resident-suspect-process listing. |
| `redundancy-evaluation.md` | Wazuh/Velociraptor vs Security Onion (Strelka/agents) comparison + verdict (keep all three, distinct roles, co-resident on the N100). |

## Why nothing is installed now

1. **N100 required** for the Wazuh manager/indexer/dashboard and the Velociraptor server.
2. **Compromised-host trust boundary:** installing a host agent on the *current*
   laptop would place it inside the attacker's control (could be killed or fed false
   data). The agent install is a **clean-rebuild** action.
3. `setup_update.ps1` is intentionally **not** modified - it provisions the current
   ecosystem; the agent install belongs to the clean-rebuild bootstrap (this runbook).

---

## ACTION FOR HELDER - deployment (when N100 exists + after clean rebuild)

### 1. N100: install the Wazuh server (manager + indexer + dashboard)

```sh
# On the N100 (Linux). Co-resides with Security Onion; see redundancy-evaluation.md
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh
sudo bash ./wazuh-install.sh -a            # all-in-one single-node
# note the printed admin password + the manager IP (used below)
```

### 2. N100: install the Velociraptor server

```sh
# Download the latest release binary from github.com/Velocidex/velociraptor
./velociraptor config generate -i          # interactive wizard -> server.config.yaml
#   - self-signed CA, public hostname = N100 IP, GUI on :8889, frontend on :8000
./velociraptor --config server.config.yaml frontend -v   # run (or install as a service)
# The wizard ALSO emits client.config.yaml - keep it for step 4.
```

### 3. Laptop (clean rebuild): install + register the Wazuh agent

```powershell
# Install the agent MSI, then drop in our pre-authored config:
Copy-Item "C:\Sync\Tools\wazuh-velociraptor\wazuh-agent-ossec.conf" `
          "C:\Program Files (x86)\ossec-agent\ossec.conf" -Force
# Set the manager IP in that file (WAZUH_MANAGER_IP), then register:
& "C:\Program Files (x86)\ossec-agent\agent-auth.exe" -m <WAZUH_MANAGER_IP>
Restart-Service WazuhSvc
```

On the manager, enable VirtusTotal hash enrichment (free API key, env-only - ties to
T080/T081) in `/var/ossec/etc/ossec.conf` `<integration>` block and restart wazuh-manager.

### 4. Laptop (clean rebuild): install the Velociraptor client

```powershell
# Use the SERVER-GENERATED client.config.yaml from step 2 (preferred). The template at
# velociraptor-client.config.template.yaml documents the fields if you must hand-build.
velociraptor.exe --config client.config.yaml service install
```

### 5. Load the custom hunt artifacts on the server

Open `velociraptor-hunts.vql`, split on the `---` separators, and add each
`Custom.FolderSync.*` artifact via the GUI (View Artifacts -> Add an Artifact) or
`velociraptor artifacts upload`. Then build a Wazuh-alert -> Velociraptor-hunt bridge
(Wazuh integrator script POSTing to the Velociraptor API) so a FIM/registry alert
auto-launches the matching hunt.

### 6. Verify

- Edit a file in `C:\Sync\Config` -> a Wazuh FIM alert with the diff appears in the
  dashboard within seconds (real-time syscheck).
- Add a junk HKCU Run value -> `Custom.FolderSync.RunKeyPersistence` hunt flags it.
- Disable a FolderSync-* task -> `Custom.FolderSync.DefensiveTaskTamper` flags it.

## Related follow-ups

- **T083** - the N100 + Security Onion this server co-resides with.
- **T076 / T075** - Sysmon: forwarded into Wazuh and Velociraptor (shared, see eval).
- **T077** - WEF off-box forwarding; Wazuh log collection is a parallel off-host path.
- **T080 / T081** - VirusTotal hash enrichment for Wazuh/Velociraptor findings.
- **T085** - EDR decision; do NOT stack two kernel-level EDRs as peers.

## Status word: Blocked-Hardware (deployment) / Done (pre-authoring)

# T076 — Install Sysmon (SwiftOnSecurity config)

**Goal:** Authoritative on-host process/network/DNS telemetry feeding T075 correlation and T077 forwarding.

**Source:** `Protecao_Win11.md` Layer 2.

## Steps
1. Download Sysmon (Sysinternals) + SwiftOnSecurity `sysmonconfig-export.xml` (or olafhartong/sysmon-modular for MITRE coverage).
2. Install: `sysmon64.exe -accepteula -i sysmonconfig.xml`.
3. Confirm events flowing: `Microsoft-Windows-Sysmon/Operational` — Event ID 1 (process create), 3 (network connect), 22 (DNS).
4. Add install + config to `setup_update.ps1` so it survives reinstall (binary path + config under `C:\Sync\Config\`).

## Trust caveat (from doc)
Sysmon is NOT hardened against an admin attacker — its value is realized only once events are forwarded off-box (T077). On its own it can be blinded.

## Acceptance
- Event ID 1/3/22 present in the log.
- setup_update.ps1 reinstalls Sysmon idempotently.

## RULE 1 follow-up
- ECOSYSTEM_REPORT.md §2 (software installed) + §15 if config stored in repo.
- setup_update.ps1 new step.

# T077 — WEF off-box event forwarding

**Goal:** Forward Sysmon + Security events to a collector the laptop's admin attacker cannot retroactively edit. This is the single most important hardening for evidence integrity under assume-breach.

**Source:** `Protecao_Win11.md` Layer 2 ("forward events off-box immediately via WEF").

## Blocked-on
A second collector host. Options:
- Interim: the future N100 sensor (T083) running a Linux WEF/syslog receiver, or a Windows Event Collector on any clean second machine.
- Until a collector exists, this task is **Blocked** — mark accordingly when registered if no host is available.

## Steps
1. On collector: enable Windows Event Collector (`wecutil qc`) or a syslog/WEF-over-HTTPS receiver.
2. On laptop (source): configure WEF subscription (source-initiated) pushing `Security` (4657/4663/4688/4698-4702/4946-4950/5025) + `Microsoft-Windows-Sysmon/Operational`.
3. Use source-initiated push so the laptop forwards out; lock the subscription so the attacker disabling it is itself an alertable event.
4. Verify events arrive within seconds and persist after local log clear.

## Acceptance
- Clearing the local Security log does NOT remove already-forwarded events on the collector.

## RULE 1 follow-up
- ECOSYSTEM_REPORT.md architecture section + setup_update.ps1 (subscription registration).
- CLAUDE.md (new collector path / log location).

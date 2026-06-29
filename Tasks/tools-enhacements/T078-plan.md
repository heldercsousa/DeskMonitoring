# T078 - Firewall-tamper Event IDs in auditor.ps1

**Goal:** Catch live tampering with the Windows Firewall (rules added/modified/
deleted, settings changed, service stopped) in real time, naming the Subject
account that did it. This is the event-based complement to T010, which only
*scans* for known malicious B2 BLOCK rules after the fact.

**Source:** `Protecao_Win11.md` Layer 3 ("Detecting firewall tampering").

## Event IDs to watch (Security log)
| ID | Meaning |
|----|---------|
| 4946 | Firewall rule added |
| 4947 | Firewall rule modified |
| 4948 | Firewall rule deleted |
| 4950 | Firewall setting changed |
| 5025 | Firewall service stopped |

## Prerequisite (not on by default)
Windows 10/11 do NOT log 4946-4950/5025 by default. Enable the audit subcategory:
```
auditpol /set /subcategory:"MPSSVC Rule-Level Policy Change" /success:enable /failure:enable
```
Add this to `setup_update.ps1` (alongside the existing task-change auditpol step,
~Step 16a3) so it survives reinstall, and verify it produces events live.

## Steps
1. In `auditor.ps1`, extend the existing real-time watcher loop (the one that
   already polls 4699/4701/4702 for `[TASK-TAMPER]`) to also poll
   4946/4947/4948/4950/5025 every 60s.
2. For each hit, capture the Subject account, the rule name/setting, and the
   event time; raise `[ALERT] [FIREWALL-TAMPER]` via the existing `send_alert`
   path.
3. Whitelist expected sources (our own `setup_update.ps1` / `fix_firewall_b2.ps1`
   runs) to avoid self-inflicted alerts; everything else -> alert + Evidence file.
4. Cross-reference 5025 (service stopped) with B2 connectivity failures in the
   cloud_sync log.

## Acceptance
- A deliberate `netsh advfirewall firewall add rule ...` (then delete) produces a
  `[FIREWALL-TAMPER]` log line naming the rule and Subject account on the next
  poll.
- `auditpol /get /subcategory:"MPSSVC Rule-Level Policy Change"` shows
  Success+Failure enabled after running setup_update.ps1.
- auditor.ps1 parses clean (ParseFile 0 errors).

## RULE 1 follow-up
- ECOSYSTEM_REPORT.md Section 5 + Section 15 (auditor.ps1).
- CLAUDE.md if a new log prefix / audit subcategory is introduced.
- setup_update.ps1 new auditpol step + Live Threat Digest if a real event fires.

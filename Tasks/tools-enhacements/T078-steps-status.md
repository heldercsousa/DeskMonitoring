# T078 - Firewall-tamper Event IDs in auditor.ps1 - Steps Status

Status: Done (code complete; one Admin action pending for Helder)
Date: 2026-06-29

## Checklist
- [x] Step 1 - Extend auditor.ps1 real-time watcher (Check-SystemEvents) to poll
      Security events 4946/4947/4948/4950/5025 every 60s, beside the TASK-TAMPER
      watcher. Added `$script:LastFwEventTime` watermark.
- [x] Step 2 - For each hit, capture Subject account + rule name + event time and
      raise `[ALERT] [FIREWALL-TAMPER]` via send_alert.ps1 (with B2Key evidence).
- [x] Step 3 - Whitelist own firewall scripts: auditor checks `C:\Sync\Config\.fw_expected`
      sentinel; if touched < 300s ago, logs `[FW-CHANGE]` INFO instead of an alert.
      setup_update.ps1 (new Step 16a4) and fix_firewall_b2.ps1 both touch the sentinel.
- [x] Step 4 - Cross-reference note added to alert body (5025 service stop vs
      SYNC-FAIL/connectex in cloud_sync log).
- [x] setup_update.ps1 - added Step 16a4: auditpol enable of MPSSVC Rule-Level Policy
      Change subcategory {0CCE9232-69AE-11D9-BED3-505054503030} success+failure.
- [x] .gitignore - added `/Config/.fw_expected` (runtime sentinel, not committed).
- [x] RULE 1 - ECOSYSTEM_REPORT.md Section 5 (auditor row) + Section 15 (full auditor.ps1
      spliced, condensed setup_update Step 16a4 added, fix_firewall_b2 sentinel added).
- [x] ParseFile - auditor.ps1, setup_update.ps1, fix_firewall_b2.ps1 = 0 errors each.
- [x] Committed (guarded files auditor.ps1 + setup_update.ps1 committed immediately).

## CLAUDE.md note
Not modified: no path/task/log-path/architecture change. New auditor prefixes
([FIREWALL-TAMPER]/[FW-CHANGE]) follow the same precedent as [TASK-TAMPER]/[BUTTON-SLEEP]
which are documented in the Live Threat Digest narrative, not a CLAUDE.md prefix table.
Update the Live Threat Digest only if a real [FIREWALL-TAMPER] event fires.

## ACTION FOR HELDER (Blocked-Admin)
Run `setup_update.ps1` as Administrator to:
  1. Enable the MPSSVC firewall-change audit subcategory (Step 16a4) - NOT on by
     default in Win10/11; without it events 4946-4950/5025 are never logged and the
     new watcher stays silent.
  2. Restart FolderSyncAuditor so the new watcher code loads.

Verify after running:
  auditpol /get /subcategory:"MPSSVC Rule-Level Policy Change"
  -> should show Success and Failure enabled.

Acceptance test (after the above): add then delete a dummy rule, e.g.
  netsh advfirewall firewall add rule name="T078-test" dir=out action=block remoteip=192.0.2.1
  netsh advfirewall firewall delete rule name="T078-test"
On the next 60s poll, security_audit_YYYY-MM-DD.log should show
  [ALERT] [FIREWALL-TAMPER] RULE-ADDED rule='T078-test' ... by account=...
  [ALERT] [FIREWALL-TAMPER] RULE-DELETED rule='T078-test' ... by account=...

## Resume point
None - task complete pending the Admin run above.

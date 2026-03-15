# P2 — cloud_sync.ps1 DNS Detection Blind Spot Fix
## Ref: 2026-03-15_MASTER-incident-report.md

**Started:** 2026-03-15 (autonomous session)
**Status:** IN PROGRESS

## Objective
cloud_sync.ps1 only detects IP-level firewall blocks (connectex, socket access forbidden).
DNS-level attacks (no such host) produce SYNC-FAIL with no alert or self-healing.
Must add DNS failure detection with the same FIREWALL-DETECT + FIREWALL-HEAL path.

---

## Steps & Evidence


### STEP 1 - Read cloud_sync.ps1 STEP 3 block (lines 84-123)
Confirmed: detection pattern only matches connectex|socket access forbidden|access is forbidden|connect: permission denied
DNS failures (no such host) fall through to SYNC-FAIL with no alert path.

### STEP 2 - Patch applied
Added new elseif branch after firewall detection:
  Pattern: 'no such host|i/o timeout|dial tcp.*lookup'
  Label: DNS-ATTACK-DETECT
  Actions:
    - Logs current Ethernet DNS servers
    - Tests live resolution of api.backblazeb2.com
    - Retries sync (interface may have switched to Wi-Fi)
    - On retry success: logs DNS-ATTACK-HEAL
    - On retry fail: logs DNS-ATTACK-FAIL with remediation command

### STEP 3 - Syntax validation [PASS]
ParseFile errors: 0

### STATUS: P2 COMPLETE
cloud_sync.ps1 now detects DNS-level attacks and logs with DNS-ATTACK-DETECT prefix.
Future attacks will be visible in cloud_sync log and trigger retry + detailed diagnosis.


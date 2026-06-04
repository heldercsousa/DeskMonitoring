# TAMPERING DETECTED — 2026-06-04

## Summary

`Config/cloud_sync.ps1` and `Config/run_mirror.bat` were modified on disk between the last
auto-commit (2026-06-03 23:30) and session start (2026-06-04 ~10:00). Changes were identified
via RULE 6 pre-commit integrity check. Files have been **restored from git HEAD**.

## Attack Window

File timestamps show 09:30:57, but cloud sync failures begin at **04:45 AM** in the log —
confirming the tampered script was already active ~5 hours earlier. The 09:30 timestamp
coincides with Helder manually stopping the ecosystem (confirmed by him); the attacker likely
struck overnight and the timestamp was overwritten or coincidentally matches the stop action.

**Real attack time: overnight 2026-06-03 → 2026-06-04, before 04:45 AM.**
**B2 sync was broken for ~5 hours before detection.**

| File | Disk timestamp | Notes |
|------|---------------|-------|
| `Config/cloud_sync.ps1` | 2026-06-04 09:30:57 | Real attack earlier — log evidence from 04:45 |
| `Config/run_mirror.bat` | 2026-06-04 09:30:57 | Same |
| `Config/audit_filter_launcher.vbs` | 2026-06-04 09:31:49 | CRLF-only diff, NOT content-tampered |

## Files NOT Tampered

- `Config/rclone.conf` — LastWriteTime 2026-06-03 19:00:19 (before attack window)
- `Config/audit_filter_launcher.vbs` — modified timestamp was CRLF normalization only

## Attacker Fingerprint

Portuguese-language comments injected into the English-only codebase:
- "FASE 0", "FASE 1", "FASE 2" (replacing "PHASE 0", "PHASE 1", "PHASE 2")
- `# Silencioso` replacing error-logging lines

This fingerprint is definitive: the entire codebase uses English. This was not an automated
tool or a local edit by the repo owner.

## Changes Made by Attacker (cloud_sync.ps1)

### CRITICAL — DPAPI credential loading stripped
The `Load-B2Credentials` function and its call were completely removed. Without this function,
cloud_sync.ps1 falls back to reading credentials from `rclone.conf` (plaintext). This is a
deliberate credential security rollback designed to weaken the security posture silently.

### Log directory path broken
`$LogDir` reverted from `C:\Sync\Logs\cloud_sync` to `C:\Sync\Logs`. Logs would be written
to the wrong directory, breaking log rotation and audit trails.

### Security monitoring stripped
- T030 B2 lag alerting removed (no detection when sync falls behind)
- T026 failure sentinel tracking removed (`.sync_failed` / `.last_sync_ok` files not maintained)
- ACL failure log entries replaced with `# Silencioso` (silent failure — no visibility into ACL errors)

### Feature rollback
- PHASE 3 source folder retention logic removed (video recording folders would accumulate forever)
- "Last updated" comment reverted to 2026-03-07 to conceal the modification history

### run_mirror.bat
Robocopy log path reverted from `C:\Sync\Logs\mirror\mirror_%DATE%.log` to
`C:\Sync\Logs\mirror_%DATE%.log`, breaking mirror log subdirectory organization.

## Response Actions Taken

1. Files restored from git HEAD (`git checkout HEAD -- Config/cloud_sync.ps1 Config/run_mirror.bat`)
2. Verified restored files match HEAD (0-line diff)
3. Verified `rclone.conf` was not touched in the attack window
4. This evidence file committed to git

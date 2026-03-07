# Evidence: Malicious Windows Firewall Rules — 2026-03-06

## Summary

Two outbound BLOCK firewall rules were added to the Windows Firewall by an unauthorized actor
(suspected remote attacker) to prevent rclone from reaching Backblaze B2.
This caused B2 cloud sync to fail from at least 05:31 on 2026-03-06.

## Malicious Rules

| Rule | Type | Direction | Remote Address | Port | Action |
|------|------|-----------|----------------|------|--------|
| Block 104.153.233.180 | Custom | Outbound | 104.153.233.180 | Any | **BLOCK** |
| Block 149.137.142.15  | Custom | Outbound | 149.137.142.15  | Any | **BLOCK** |

Both IPs are Backblaze B2 API endpoints that `api.backblazeb2.com` resolves to.

## Attack Pattern

The attacker also briefly blocked DNS resolution for `api.backblazeb2.com` (13:12–13:24),
causing "no such host" errors before reverting to IP-level blocking.

## Timeline (from C:\Sync\Logs\cloud_sync_2026-03-06.log)

| Time | Error |
|------|-------|
| 05:31:53 | First failure — `149.137.142.15:443` blocked (connectex: socket access forbidden) |
| 12:56–13:11 | Continued `149.137.142.15` blocking |
| 13:12–13:24 | DNS-level block: `no such host` for `api.backblazeb2.com` |
| 13:24–16:13 | Back to IP block on `149.137.142.15` |
| 16:14–17:04 | IP block switched to `104.153.233.180` (B2 DNS round-robin) |
| 17:15–17:41 | Back to `149.137.142.15` |

Total sync downtime: ~12 hours on 2026-03-06.

## Context

- Machine was under confirmed remote access attack (physical + remote)
- Orphaned user profile `convidado123` found with DTS activity on 2026-02-14
- Attacker motive: disable cloud backup to prevent camera recordings (C:\Users\helde\Repos\Bois)
  from reaching Backblaze B2 (`helder-sync-mirror` bucket)

## Remediation

Rules removed via Windows Firewall (netsh) on 2026-03-06 by owner.
Cloud sync restored immediately after removal.

## Raw Log Evidence

Source: `C:\Sync\Logs\cloud_sync_2026-03-06.log` (copied at time of evidence collection)

First entry:
```
2026/03/06 05:31:53 CRITICAL: Failed to create file system for "cloudsync:helder-sync-mirror":
failed to authorize account: failed to authenticate:
Get "https://api.backblazeb2.com/b2api/v4/b2_authorize_account":
dial tcp 149.137.142.15:443: connectex: An attempt was made to access a socket
in a way forbidden by its access permissions.
```

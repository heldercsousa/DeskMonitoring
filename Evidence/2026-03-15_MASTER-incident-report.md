# INCIDENT REPORT — 2026-03-15
## Master Reference for All Priority Actions

**Generated:** 2026-03-15 (session log analysis)
**Analyst:** Claude Code (autonomous session)
**Threat level:** HIGH — active, ongoing attack

---

## Situation Summary

Five-day log review (2026-03-11 to 2026-03-15) revealed a persistent, evolving attack against the FolderSync/B2 cloud backup pipeline. The attacker has shifted from IP-level firewall block rules (detected 2026-03-06) to **DNS-level sabotage**, which bypasses the existing self-healing detection in `cloud_sync.ps1`.

---

## Attack Pattern — DNS Sabotage (NEW, undetected by current tooling)

**Error signature in `cloud_sync_YYYY-MM-DD.log`:**
```
dial tcp: lookup api.backblazeb2.com: no such host
dial tcp: lookup api005.backblazeb2.com: no such host
```

**Why it is not caught:** `cloud_sync.ps1` FIREWALL-DETECT only matches:
- `connectex`
- `socket access forbidden`

DNS failures produce `SYNC-FAIL - not a firewall error` and silently drop the backup with no self-healing.

**Impact timeline:**

| Date | Failure windows | SYNC-OK? |
|------|----------------|---------|
| 2026-03-11 | 12:25, 19:26 | None |
| 2026-03-12 | 00:16-00:52, 14:04-15:42 | None |
| 2026-03-13 | 01:57-02:03, 10:12-10:24, 12:15-12:17, 17:59-19:33 | None |
| 2026-03-14 | 00:34-00:39 | None |
| 2026-03-15 | 09:55-15:05, 14:53-15:05 | Brief window 14:23-14:24 |

**B2 domains affected:**
- `api.backblazeb2.com` (auth endpoint)
- `api005.backblazeb2.com` (upload endpoint)

---

## Other Issues Found

### P2 — cloud_sync.ps1 detection blind spot
The script does not detect DNS-level failures as firewall attacks.
Must add `no such host` to the FIREWALL-DETECT pattern and trigger the same alert/self-heal path.

### P3 — Yawcam and CAM-2 failed to start (2026-03-15 14:52)
```
2026-03-15 14:52:49  ECOSYSTEM-START  WARN Yawcam did not start
2026-03-15 14:52:51  ECOSYSTEM-START  WARN CAM-2 relay did not start
```
Camera recording was disrupted. Root cause unknown. Must investigate.

### P4 — Scheduled tasks missing/disabled
- `FolderSync-GitCommitLogs` — NOT REGISTERED (task does not exist in scheduler)
- `FolderSync-Watchdog` — DISABLED at last start
- `FolderSync-DailyCheck` — DISABLED at last start

---

## Priority Order

| # | File | Description |
|---|------|-------------|
| P1 | `2026-03-15_P1-dns-attack.md` | Investigate and remediate DNS tampering |
| P2 | `2026-03-15_P2-detection-fix.md` | Patch cloud_sync.ps1 to detect DNS attacks |
| P3 | `2026-03-15_P3-camera-failure.md` | Investigate Yawcam/CAM-2 startup failure |
| P4 | `2026-03-15_P4-tasks-registration.md` | Register/enable missing scheduled tasks |

---

## Ecosystem State at Start of This Session
- `.ecosystem_state` = **stopped** (intentionally)
- `.camera_paused` = not set
- `FolderSync-GitCommitLogs` task = NOT REGISTERED

---

## Security Log Status
- No suspicious processes, anomalous connections, or registry tampering found in security logs on 03-11, 03-13, 03-15.
- Audit log DELETED entries are all `user=helde`, all `motion_*.avi` — consistent with normal Yawcam recording cycle.

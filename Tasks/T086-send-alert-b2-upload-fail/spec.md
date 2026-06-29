# T086 — send_alert.ps1 B2 archive upload failing ("account not found")

**Status:** Pending
**Created:** 2026-06-29
**Severity:** Medium (email alerting still works; only the off-box B2 archive copy fails)
**Possible-tampering:** YES — treat as a candidate adversary action (see "Adversary hypothesis" below)

---

## Summary

`send_alert.ps1` sends the alert email successfully but the subsequent **B2 archive
upload of the alert payload fails on every run** with an rclone B2 auth error:

```
CRITICAL: Failed to create file system for destination
"cloudsync:helder-sync-mirror/alerts/": account not found
```

So the primary notification (email) is intact, but the **tamper-proof off-box copy
of each alert is NOT landing in B2**. That second copy is exactly the evidence an
attacker would want to suppress.

---

## Evidence

Source log: `C:\Sync\Logs\security\send_alert_2026-06-29.log` (do not delete - forensic).

Pattern observed all day 2026-06-29 (06:55 -> 10:15+), one pair per alert cycle:

```
SEND-ALERT  OK    email sent: SUSPICIOUS WRITES on LAP - N event(s)
SEND-ALERT  FAIL  B2 upload failed: ... CRITICAL: Failed to create file system
                  for destination "cloudsync:helder-sync-mirror/alerts/": account not found
```

Two distinct signals in the same log, both worth noting:
1. **The bug itself** - B2 upload of the alert fails every time.
2. **High alert volume** - the auditor is firing "SUSPICIOUS WRITES on LAP" every
   ~5 min (3 to 22 events per cycle). Corroborates the active-tampering threat state.

Relevant code: `C:\Sync\Config\send_alert.ps1`
- Line ~21-22: `$Rclone='C:\Tools\Rclone\rclone.exe'`, `$RcloneCfg='C:\Sync\Config\rclone.conf'`
- Line ~84: `$dest = "cloudsync:helder-sync-mirror/alerts/$B2Key"`
- Line ~91: `& $Rclone copyto $src $dest --config $RcloneCfg`

---

## Why this matters / why it is suspicious

`cloud_sync.ps1` writes to the **same remote** (`cloudsync:helder-sync-mirror`) using
the **same `rclone.conf`** and is reported operational. If the main mirror sync
works but the `alerts/` upload returns **"account not found"**, the discrepancy is
unexpected and needs root-causing rather than assuming a benign typo. Candidate
root causes, in order of likelihood:

1. **B2 App Key scope** - the restricted key from T048 may be scoped to a prefix
   that excludes `alerts/` (key can write `mirror/...` but the `alerts/` path or
   "all-files" listing returns account/bucket-not-found). MOST LIKELY benign cause.
2. **Remote name / config drift** - `cloudsync` remote in `rclone.conf` altered,
   or `send_alert.ps1` invoked in a context (SYSTEM vs user) where the config or
   key env differs from what cloud_sync uses.
3. **Credential tampering** - the B2 key/account was changed or revoked; main sync
   is coasting on a cached token while fresh `copyto` calls fail. Tie to the open
   credential/SACL thread on cloud_sync.ps1.

## Adversary hypothesis (per Helder)

Helder's standing note: many of these failures are deliberate adversary friction -
small breakages designed to waste time and quietly disable the off-box evidence
trail. So this is logged as a candidate tamper indicator, not just a config bug.
The "account not found" specifically kills the one copy of each alert that lives
*off* the potentially-compromised host. Investigate accordingly; do not assume
benign until the rclone key scope is verified against the live B2 account.

---

## Acceptance criteria

- [ ] Reproduce: run `rclone lsd cloudsync:helder-sync-mirror --config C:\Sync\Config\rclone.conf` and `rclone copyto` of a dummy file to `cloudsync:helder-sync-mirror/alerts/test.txt`; capture the exact error.
- [ ] Determine which of the 3 root causes applies (key scope vs config drift vs credential tampering). Document finding here.
- [ ] If benign (key scope): create/repair a B2 App Key that permits the `alerts/` prefix, or point alert uploads at an allowed prefix; update `rclone.conf` / send_alert.ps1 accordingly.
- [ ] If tampering: preserve evidence to `C:\Sync\Evidence\YYYY-MM-DD_*.md`, alert Helder, cross-reference T070 / cloud_sync SACL thread, do NOT silently "fix".
- [ ] After fix: `send_alert.ps1` logs `SEND-ALERT  OK  B2 upload: ...` on the next real alert.
- [ ] RULE 1 guide sync if send_alert.ps1 / rclone config changes; RULE 6 + commit.

## Notes / constraints

- `send_alert.ps1` is NOT currently in the config_guard guarded list - verify before editing whether it should be added (T051 pattern).
- NEVER print, diff, or commit `rclone.conf` contents (live B2 credentials).
- B2 alert uploads only fire when `-B2Key` is passed; confirm which caller passes it.

## Cross-references

- T048 (restricted B2 App Key scoped to bucket) - likely origin of a prefix-scope mismatch
- T070 (resident tampering process) / cloud_sync SACL+4663 open thread
- THREAT_MODEL.md - firewall/credential tampering vectors

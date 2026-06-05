# TAMPERING DETECTED — 2026-06-05 (Repeat Attack)

## Summary

`Config/cloud_sync.ps1` and `Config/run_mirror.bat` were found tampered again on disk
during session start 2026-06-05. This is the **second confirmed tampering** of these files
(first: 2026-06-04, see `2026-06-04_cloud-sync-tampering.md`).

Files restored from git HEAD immediately on detection.

## Attacker Fingerprint (identical to 2026-06-04 attack)

- Portuguese-language comments: "FASE 0", "FASE 1", "FASE 2", "Silencioso"
- Same structural rollback as prior attack — strongly indicates same actor/tool

## Changes Made by Attacker (cloud_sync.ps1)

Same payload as 2026-06-04:

1. **DPAPI credential loading stripped** — `Load-B2Credentials` function and its call removed
2. **Log directory broken** — `$LogDir` reverted from `C:\Sync\Logs\cloud_sync` to `C:\Sync\Logs`
3. **Security monitoring stripped** — T030 B2 lag alerting removed; T026 failure sentinel removed
4. **ACL failures silenced** — error log entries replaced with `# Silencioso`
5. **PHASE 3 source folder retention removed** — video recording folders would accumulate
6. **"Last updated" comment reverted** to 2026-03-07 to conceal modification history
7. **BOM injected** — UTF-8 BOM (`﻿`) added to line 1 (not present in original)

## Changes Made by Attacker (run_mirror.bat)

- Robocopy log path reverted from `C:\Sync\Logs\mirror\mirror_%DATE%.log`
  to `C:\Sync\Logs\mirror_%DATE%.log` (breaks mirror log subdirectory)
- Garbage line `+1 -1` appended at end of file

## Impact Assessment

- **Attack window:** overnight 2026-06-04 → 2026-06-05 (exact time unknown)
- **B2 sync:** would fail immediately on DPAPI removal (same as 2026-06-04)
- **Detection:** RULE 6 pre-commit integrity check at session start

## Response Actions

1. `git checkout HEAD -- Config/cloud_sync.ps1 Config/run_mirror.bat`
2. Verified 0-line diff vs HEAD
3. Verified 0 parse errors (ParseFile)
4. This evidence file committed to git

## Pattern Analysis

Two consecutive nights of identical tampering. Attacker has:
- Persistent filesystem access
- Knowledge of the script's internal structure
- A prepared malicious version ready to deploy
- Ability to write to ACL-protected `Config\` directory (concerning — Deny Delete should block writes)

The Deny Delete ACL on `Config\` prevents deletion but NOT modification of existing files.
The attacker is overwriting files in place, not deleting and replacing them.

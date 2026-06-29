# 2026-06-29 - CloudBackup task mispointed + FASE tampering signature in active sync script

**Reporter:** Claude (Opus 4.8), during T086 investigation, on Helder's prompt to verify
the active cloud-sync script.
**Severity:** Medium. No active functional compromise found; a protection gap and a
historical tampering fingerprint.

---

## Finding 1 - FolderSync-CloudBackup ran the UNGUARDED script (protection gap)

- The live `FolderSync-CloudBackup` scheduled task executed
  `C:\Sync\Config\cloud_sync.ps1`.
- `config_guard.ps1` only guards `cloud_sync_helderTest.ps1` (the anti-tampering rename),
  and `setup_update.ps1` Step 3 maintains `cloud_sync_helderTest.ps1`. Step 10 (line 532)
  *intends* the task to run `cloud_sync_helderTest.ps1`.
- => The script the scheduler actually ran (`cloud_sync.ps1`) was **outside config_guard's
  protection**, defeating the rename-to-evade-tampering defense. An attacker overwriting
  `cloud_sync.ps1` would NOT be auto-restored.

### Root cause
`setup_update.ps1` Step 10's idempotency check (line ~519) only tested for `.bat` /
missing `-NoWindow`; it never checked the script path. A task pointing at the old
`cloud_sync.ps1` (which has `-NoWindow`) passed as "correct" and was never repointed -
the run log even printed "already exists with correct arguments". Silent no-op.

### Remediation (applied 2026-06-29)
- Live task repointed to `cloud_sync_helderTest.ps1` (Set-ScheduledTask).
- `setup_update.ps1` Step 10 check now also recreates the task if the args do not contain
  `cloud_sync_helderTest.ps1`, so a reinstall self-corrects. (commit in same batch)
- Note: `cloud_sync.ps1` and `cloud_sync_helderTest.ps1` are byte-identical except a UTF-8
  BOM, so the repoint causes ZERO behavioral change to the sync - it only makes the
  guarded script the live one.

---

## Finding 2 - FASE Portuguese comment signature present in the active sync script

- Both `cloud_sync.ps1` and `cloud_sync_helderTest.ps1` contain the attacker's documented
  Portuguese comment signature (THREAT_MODEL.md):
  - L173 `# FASE 0 - Aplicar ACL Deny Delete em arquivos < 7 dias`
  - L208 `# FASE 1 - Remover ACL Deny Delete de arquivos >= 7 dias`
  - L238 `# FASE 2 - Deletar arquivos >= 7 dias`

### Provenance (git -S trace)
- `c0fc7bc` (T031, ~2026-06-02): Englished the comments `FASE -> PHASE`.
- `1eb2453` / `4d4d3f8` (2026-06-15, "helder's tampering workaround test"): `FASE`
  reappeared, `PHASE` disappeared. => The signature was re-injected between 06-02 and
  06-15, and the 06-15 workaround copy captured the re-tampered version. It has been the
  committed/active content since.

### Assessment
- This is the **cosmetic half** of the nightly payload (Portuguese comment injection).
  The **functional sabotage was NOT present**: DPAPI credential loading
  (`ProtectedData` / `Load-B2Credentials` / `RCLONE_CONFIG_CLOUDSYNC_*`) and `SYNC-START`
  logging are all intact (7/7 integrity markers). So sync was working, but the file
  carried the attacker's fingerprint.
- The tampered version is preserved in git forever at commits `4d4d3f8` / `1eb2453`, so
  re-Englishing the comments now would NOT destroy the forensic record.

### Pending decision (Helder)
- Whether to re-English the FASE comments in `cloud_sync_helderTest.ps1` (cleanup; git
  retains the fingerprint) or keep them as an in-file tripwire.
- Whether to delete the now-unused `cloud_sync.ps1` (identical idle copy = tamper-confusion
  surface) or keep + also guard it.

---

## Related
- THREAT_MODEL.md (Portuguese comment injection vector), T031 (Portuguese->English),
  T051/T054 (config_guard scope + auto-restore), Backlog T090 (this remediation).

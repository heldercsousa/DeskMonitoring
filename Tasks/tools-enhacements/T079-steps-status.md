# T079 - Autoruns persistence baseline + diff - steps status

**Status:** Blocked-Admin (all automatable work done; baseline capture needs Admin)
**Last updated:** 2026-06-29

## Step checklist
- [x] 1. `check_autoruns.ps1` created in `C:\Sync\Config\` - runs autorunsc64.exe
      (-a * -c -h -s), diffs vs baseline, logs `[AUTORUN-DELTA]`, Evidence + send_alert,
      optional VT HASH-ONLY enrichment, `-UpdateBaseline` switch, 30-day log rotation.
      ParseFile: 0 errors.
- [x] 2. Baseline storage: `C:\Sync\Config\autoruns\` dir created + `.gitkeep` placeholder.
      `baseline.csv` NOT yet captured (needs autorunsc64.exe download + admin/SYSTEM).
- [x] 3. Daily task: `setup_update.ps1` Step 22 registers `FolderSync-AutoRunsCheck`
      (SYSTEM, daily 08:45) and captures the initial baseline on first run. ParseFile: 0 errors.
- [x] 4. New entries -> Evidence file + alert: implemented in check_autoruns.ps1 (section 7).
- [x] RULE 1: ECOSYSTEM_REPORT.md Section 5 row (check_autoruns.ps1 + autoruns\baseline.csv)
      + Section 15 full file contents added.
- [x] RULE 1: CLAUDE.md Scheduled Tasks table + RULE 2 log-path table updated.
- [x] setup_update.ps1 Step 22 registers task + baseline capture (survives reinstall).
- [x] Backlog row -> Blocked-Admin.

## ACTION FOR HELDER (to reach Done)
Run `setup_update.ps1` as Administrator. Step 22 will:
  1. Download autorunsc64.exe to `C:\Tools\Sysinternals` (needs network, first run only).
  2. Register the `FolderSync-AutoRunsCheck` SYSTEM task (daily 08:45).
  3. Capture the initial baseline -> `C:\Sync\Config\autoruns\baseline.csv`.
Then commit the generated `baseline.csv` to git (version-controlled per plan).

## Acceptance test (after baseline exists)
Add a throwaway HKCU Run key, run `check_autoruns.ps1`, confirm an `[AUTORUN-DELTA] NEW`
line appears in `Logs\security\autoruns_YYYY-MM-DD.log`; then remove the key and
re-baseline with `check_autoruns.ps1 -UpdateBaseline`.

## Caveat (offline corroboration)
EVIDENCE-ONLY: autorunsc runs in the live OS; a kernel/admin attacker can hide entries.
Corroborate suspicious deltas against an offline mount (T082). A clean run is not all-clear.

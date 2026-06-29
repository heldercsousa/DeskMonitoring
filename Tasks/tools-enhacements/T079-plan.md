# T079 — Autoruns persistence baseline + diff

**Goal:** Catch new persistence (Run keys, services, scheduled tasks, WMI, Winlogon) as a daily delta. Directly supports open investigations T070 (resident process disabling tasks) and T072 (screen blink).

**Source:** `Protecao_Win11.md` Layer 2 + Layer 7 (Autoruns + Compare-AutoRunsBaseLine).

## Steps
1. Capture baseline: `autorunsc.exe -accepteula -a * -c -h -s > baseline.csv` (CSV, hashes, signature check).
2. Store baseline under `C:\Sync\Config\autoruns\baseline.csv` (ACL-locked, version-controlled).
3. Daily scheduled task: re-run autorunsc, diff against baseline, log new/changed entries with prefix `[AUTORUN-DELTA]`; optionally VirusTotal-enrich hashes (ties to T080).
4. New entries -> Evidence file + alert.

## Caveat (from doc)
Autoruns runs in the live OS — an admin/kernel attacker can hide entries. Corroborate suspicious deltas against an offline mount (T082).

## Acceptance
- Adding a test Run key produces an `[AUTORUN-DELTA]` line next run.

## RULE 1 follow-up
- New script in ECOSYSTEM_REPORT.md §5 + §15.
- setup_update.ps1 registers the task + baseline capture.
- CLAUDE.md task-name + log-path table.

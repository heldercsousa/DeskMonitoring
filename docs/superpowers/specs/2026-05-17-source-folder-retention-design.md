# Design: Source Folder Automatic Retention

**Date:** 2026-05-17
**Status:** Approved
**Scope:** `C:\Sync\Config\cloud_sync.ps1`

---

## Problem

The source folder (`C:\Users\helde\Repos\Bois`) accumulates date-named subdirectories
(`YYYY-MM-DD\`) indefinitely. The Mirror already enforces 7-day retention; the source
does not. Old recording folders must currently be deleted manually.

## Goal

Automatically delete source subdirectories older than 7 complete calendar days, matching
the Mirror retention policy, with no unnecessary Backblaze B2 transaction churn.

---

## Design

### Where the logic lives

A new **FASE 3** block is added to `cloud_sync.ps1`, after the existing Mirror phases
(FASE 0, 1, 2) and before the log rotation steps. No new scripts, tasks, or services.

### Retention rule

- Retention window: **7 calendar days**, controlled by the existing `$DaysToKeepMirror`
  variable (value: 7). No new variable needed.
- A folder is eligible for deletion when its **name parsed as a date** is strictly less
  than `(Get-Date).Date.AddDays(-7)`.
- Time-of-day is ignored entirely — both creation time and current time. Only the date
  portion of the folder name is compared to today's date minus 7 days.
- Folders whose names do not match the `yyyy-MM-dd` pattern are skipped silently.

**Example (today = 2026-05-17, threshold = 2026-05-10):**

| Folder name | Action |
|---|---|
| `2026-05-09` | Deleted (date < threshold) |
| `2026-05-10` | Kept (date == threshold) |
| `2026-05-11` … `2026-05-17` | Kept |
| `other-folder` | Skipped (name not a date) |

### Backblaze B2 transaction impact

Deletion of a whole day's folder (all its AVI files) happens in a single `cloud_sync.ps1`
run. Rclone issues B2 delete calls once per file in that one sync pass. Subsequent runs
see nothing to delete on B2 (already gone). Daily folder turnover (~20-100 AVIs/day) is
well within Backblaze B2's 2,500 free Class C transactions/day limit.

### Auditor side-effect

The `auditor.ps1` FileSystemWatcher fires on each deletion and triggers an extra
`cloud_sync.ps1` call. This is harmless: by the time the auditor fires, rclone has already
synced the deletions to B2 in the same run that performed the local deletion.

### Implementation sketch

```powershell
# FASE 3 - Source folder retention (date-named subdirs older than DaysToKeepMirror days)
$sourceThreshold = (Get-Date).Date.AddDays(-$DaysToKeepMirror)
Get-ChildItem -LiteralPath $Source -Directory | ForEach-Object {
    $folderDate = $null
    $parsed = [datetime]::TryParseExact($_.Name, 'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$folderDate)
    if ($parsed -and $folderDate -lt $sourceThreshold) {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-SyncLog "SOURCE-CLEANUP  Deleted $($_.Name)"
    }
}
```

### Logging

Each deleted folder is logged to the daily `cloud_sync_YYYY-MM-DD.log` with prefix
`SOURCE-CLEANUP`. No new log file or rotation needed.

---

## Files Changed

| File | Change |
|---|---|
| `C:\Sync\Config\cloud_sync.ps1` | Add FASE 3 block after existing Mirror phases |
| `C:\Sync\ECOSYSTEM_REPORT.md` | Update Section 5 + Section 15 for `cloud_sync.ps1` |
| `C:\Sync\CLAUDE.md` | No change needed (no new paths/services/tasks) |
| `C:\Sync\Config\setup_update.ps1` | No change needed (cloud_sync.ps1 is deployed as-is) |

---

## Success Criteria

- Folders older than 7 full calendar days are deleted automatically on the next
  `cloud_sync.ps1` run after midnight.
- Folders named with non-date patterns are never touched.
- Each deletion is logged with `SOURCE-CLEANUP` prefix.
- No new Backblaze B2 transaction patterns beyond the normal sync-on-deletion behaviour.

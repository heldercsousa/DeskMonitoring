# Source Folder Automatic Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete source recording folders (`C:\Users\helde\Repos\Bois\YYYY-MM-DD\`) older than 7 full calendar days automatically, matching Mirror retention, with no B2 transaction churn.

**Architecture:** Add a single FASE 3 block to `cloud_sync.ps1` after the existing Mirror cleanup phases. Folder eligibility is determined by parsing the folder name as a date (not file timestamps), so whole day-folders are deleted in one sync cycle. Reuses the existing `$DaysToKeepMirror` and `$Source` variables.

**Tech Stack:** PowerShell 7, `[datetime]::TryParseExact`, existing `Write-SyncLog` function, `Remove-Item -Recurse`

---

### Task 1: Add FASE 3 source-retention block to `cloud_sync.ps1`

**Files:**
- Modify: `C:\Sync\Config\cloud_sync.ps1` — insert FASE 3 block between the end of FASE 2 (line 212) and the log rotation comment (line 214)

- [ ] **Step 1: Open `cloud_sync.ps1` and locate the insertion point**

  The block to insert goes between the closing `}` of FASE 2 (after line 212) and the comment `# 4. cloud_sync log rotation` (line 214). The final file section should read:

  ```powershell
  # ============================================================
  # FASE 2 - Deletar arquivos >= 7 dias
  # Agora ACL foi removido em FASE 1, delete pode executar sem ERROR 5
  # ============================================================
  if (Test-Path $Mirror) {
      $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
      Get-ChildItem -Path $Mirror -Recurse -File -ErrorAction SilentlyContinue |
          Where-Object { $_.LastWriteTime -lt $threshold } |
          Remove-Item -Force -ErrorAction SilentlyContinue

      # Cleanup de pastas vazias (apos deletar arquivos)
      Get-ChildItem -Path $Mirror -Recurse -Directory -ErrorAction SilentlyContinue |
          Sort-Object FullName -Descending |
          Where-Object { @(Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
          Remove-Item -Force -ErrorAction SilentlyContinue
  }

  # ============================================================
  # FASE 3 - Source folder retention
  # Delete date-named subdirs in $Source older than $DaysToKeepMirror calendar days.
  # Uses folder NAME as date (yyyy-MM-dd), ignoring file timestamps entirely,
  # so whole-day folders are removed in one sync cycle with no B2 churn.
  # ============================================================
  $sourceThreshold = (Get-Date).Date.AddDays(-$DaysToKeepMirror)
  Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $folderDate = $null
      $parsed = [datetime]::TryParseExact(
          $_.Name,
          'yyyy-MM-dd',
          [System.Globalization.CultureInfo]::InvariantCulture,
          [System.Globalization.DateTimeStyles]::None,
          [ref]$folderDate
      )
      if ($parsed -and $folderDate -lt $sourceThreshold) {
          Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
          Write-SyncLog "SOURCE-CLEANUP  Deleted $($_.Name)"
      }
  }

  # 4. cloud_sync log rotation - delete logs older than DaysToKeepLogs
  ```

- [ ] **Step 2: Apply the edit**

  In `C:\Sync\Config\cloud_sync.ps1`, replace the line:

  ```powershell
  # 4. cloud_sync log rotation - delete logs older than DaysToKeepLogs
  ```

  with:

  ```powershell
  # ============================================================
  # FASE 3 - Source folder retention
  # Delete date-named subdirs in $Source older than $DaysToKeepMirror calendar days.
  # Uses folder NAME as date (yyyy-MM-dd), ignoring file timestamps entirely,
  # so whole-day folders are removed in one sync cycle with no B2 churn.
  # ============================================================
  $sourceThreshold = (Get-Date).Date.AddDays(-$DaysToKeepMirror)
  Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $folderDate = $null
      $parsed = [datetime]::TryParseExact(
          $_.Name,
          'yyyy-MM-dd',
          [System.Globalization.CultureInfo]::InvariantCulture,
          [System.Globalization.DateTimeStyles]::None,
          [ref]$folderDate
      )
      if ($parsed -and $folderDate -lt $sourceThreshold) {
          Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
          Write-SyncLog "SOURCE-CLEANUP  Deleted $($_.Name)"
      }
  }

  # 4. cloud_sync log rotation - delete logs older than DaysToKeepLogs
  ```

- [ ] **Step 3: Syntax-parse the modified file (0 errors required)**

  Run in PowerShell:
  ```powershell
  $t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\cloud_sync.ps1',[ref]$t,[ref]$e);$e.Count
  ```
  Expected output: `0`

  If any number > 0 is returned, fix the syntax error before proceeding.

- [ ] **Step 4: Verify insertion visually**

  Run:
  ```powershell
  powershell -Command "Select-String -LiteralPath 'C:\Sync\Config\cloud_sync.ps1' -Pattern 'FASE 3|SOURCE-CLEANUP|sourceThreshold'"
  ```
  Expected: 4 matching lines (the comment header lines, `$sourceThreshold`, and `SOURCE-CLEANUP`).

- [ ] **Step 5: Commit**

  ```powershell
  git add Config\cloud_sync.ps1
  git commit -m "feat: add FASE 3 source folder 7-day retention to cloud_sync.ps1"
  ```

---

### Task 2: Update ECOSYSTEM_REPORT.md (Section 5 + Section 15)

**Files:**
- Modify: `C:\Sync\Config\ECOSYSTEM_REPORT.md` — update Section 5 description row for `cloud_sync.ps1` and replace Section 15 full file contents block

- [ ] **Step 1: Update Section 5 description row**

  Locate the line (around line 113):
  ```
  | `cloud_sync.ps1` | Task `FolderSync-CloudBackup` | Rclone sync + log rotation + mirror cleanup + self-healing firewall+DNS attack detection (2026-03-15) |
  ```

  Replace with:
  ```
  | `cloud_sync.ps1` | Task `FolderSync-CloudBackup` | Rclone sync + log rotation + mirror cleanup (7-day) + source folder retention (7-day, date-name based) + self-healing firewall+DNS attack detection (2026-03-15) |
  ```

- [ ] **Step 2: Update Section 15 description line for cloud_sync.ps1**

  Locate the line (around line 538):
  ```
  > Rclone sync to Backblaze B2. Includes self-healing firewall detection+removal+retry, 3-phase ACL protection (7 days), log rotation (30 days), mirror cleanup. Logs to `C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log`.
  ```

  Replace with:
  ```
  > Rclone sync to Backblaze B2. Includes self-healing firewall detection+removal+retry, 3-phase ACL protection (7 days), source folder retention (7 days, date-name based), log rotation (30 days), mirror cleanup. Logs to `C:\Sync\Logs\cloud_sync\cloud_sync_YYYY-MM-DD.log`.
  ```

- [ ] **Step 3: Replace Section 15 full file contents block for cloud_sync.ps1**

  The Section 15 code block for `cloud_sync.ps1` starts after the description line above and contains the full script. Replace the entire code block content with the current content of `C:\Sync\Config\cloud_sync.ps1` (read it fresh after Task 1 edit is applied).

- [ ] **Step 4: Commit**

  ```powershell
  git add Config\ECOSYSTEM_REPORT.md
  git commit -m "docs: update ECOSYSTEM_REPORT for cloud_sync.ps1 source retention (RULE 1)"
  ```

---

## Post-Task Gate

Before claiming done, verify all CLAUDE.md post-task rules:

- [ ] RULE 1a — ECOSYSTEM_REPORT.md Section 5 row updated for `cloud_sync.ps1`? ✓ (Task 2 Step 1)
- [ ] RULE 1b — ECOSYSTEM_REPORT.md Section 15 full contents updated for `cloud_sync.ps1`? ✓ (Task 2 Step 3)
- [ ] RULE 1c — CLAUDE.md updated? No architecture/path/task changes → no update needed
- [ ] RULE 1d — `setup_update.ps1` updated? `cloud_sync.ps1` is deployed as-is from `Config\`; setup scripts copy it — no change needed
- [ ] RULE 3 — Invoke `superpowers:verification-before-completion` before claiming done
- [ ] RULE 4 — Both commits done above; no raw git add-all used

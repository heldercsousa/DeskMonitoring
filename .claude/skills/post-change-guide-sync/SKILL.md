---
description: "After modifying any Config/ PowerShell script, step through RULE 1 guide sync checklist"
---

# Post-Change Guide Sync (RULE 1)

After modifying any `Config/` PowerShell script, complete every item in this checklist before claiming the task done.

## Checklist

1. **Re-read the modified file** using the Read tool. Confirm the actual on-disk content matches what was written. Note any encoding anomalies (em dashes, BOM markers, unexpected characters).

2. **Update ECOSYSTEM_REPORT.md Section 5** - find the inventory table row for the changed script and update the description column if the script's purpose or behavior changed.

3. **Update ECOSYSTEM_REPORT.md Section 15** - replace the full file contents code block for the changed script with the current on-disk version (from the Read in step 1).

4. **Check setup_update.ps1** - does the change need to be reflected in setup_update.ps1 so it survives a full reinstall? If the change affects:
   - ACL rules -> update Step 4
   - Scheduled tasks -> update the relevant registration step
   - Services -> update the NSSM install step
   - Script logic that setup_update deploys -> update the deploy step
   If yes, edit setup_update.ps1 accordingly.

5. **Commit** - stage only the changed files by name (never `git add -A`). Commit with an imperative message describing the actual change.

## What NOT to do
- Do not skip Section 15 update - it is the disaster-recovery source of truth
- Do not use `git add -A` or `git add .`
- Do not claim complete before re-reading the file with the Read tool

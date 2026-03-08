---
name: review
description: Invoke after completing any task, fix, or change that requires verification before claiming it is done — re-reads modified files, confirms guide sync, runs health checks, and auto-attempts fixes on failures up to 4 cycles before escalating to git stash and known_issues.md
---

# Task Completion Review -- Self-Healing Loop

**Phase 0 reminder:** Before ANY task touching `Config/` or `setup_update.ps1`, invoke relevant skills and load project commands. This review is Phase 3-4 of the 6-phase lifecycle.

Evidence before claims. Run this after every task.

## Cycle Counter

Track fix attempts across the full session: **Cycle N of 4**.

Start at Cycle 1. Each time a step fails and a fix is attempted, increment the counter. If the counter reaches 4 and the step still fails, execute the Escalation Protocol below — then continue the session (do not stop).

---

## Step 1 — Identify what was changed

List every file created or modified this task. No file is assumed correct without being read.

## Step 1.5 — Syntax parse every modified .ps1

For every `.ps1` file modified in this task, run:

```powershell
$tokens = $null; $errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\SCRIPT.ps1', [ref]$tokens, [ref]$errors)
if ($errors.Count -eq 0) { "PARSE OK" } else { $errors | ForEach-Object { "L$($_.Extent.StartLineNumber) $($_.Message)" } }
```

**IMPORTANT -- avoid em dash encoding bug:**
Never use `--` (em dash U+2014) in double-quoted strings passed to Write-Host/Write-Step/Write-OK/Write-Fail/Write-Warn. The UTF-8 byte `0x94` (third byte of em dash) is read by ParseFile as U+201D (curly right quote), breaking string parsing. Use ` - ` (space-hyphen-space) instead.

**On failure:** Fix the syntax error, save, re-parse. Do NOT mark any step done until parse returns 0 errors.

## Step 2 -- Re-read every touched file

Use the Read tool on each file. Confirm:
- Content matches intent (no truncation, no missing sections)
- Syntax is valid (PowerShell: matching braces; Markdown: aligned tables)
- No placeholder text left (`TODO`, `...`, `INSERT HERE`)

**On failure:** Fix the specific mismatch → increment cycle counter → re-read the file → continue to Step 3.

## Step 3 — Verify RULE 1 compliance (guide sync)

| Changed | Must verify |
|---|---|
| Any `.ps1` in `Config/` | ECOSYSTEM_REPORT.md Section 5 row + Section 15 code block |
| Any Yawcam script | ECOSYSTEM_REPORT.md Camera scripts table row + Section 15 code block |
| Any `.claude/commands/` file | ECOSYSTEM_REPORT.md Claude Code tooling table row |
| Any architecture change | CLAUDE.md relevant section |
| `check_camera.ps1` changed | `camera-check` command baseline table accurate |
| `check_status.ps1` changed | `check` command baseline table accurate |

Re-read the affected ECOSYSTEM_REPORT.md sections and CLAUDE.md to confirm — do not assume.

**On failure:** Write the missing/incorrect section → increment cycle counter → re-read to confirm → continue.

## Step 4 — Verify setup_all.ps1 and ECOSYSTEM_REPORT.md reflect the fix (MANDATORY)

This step is **non-negotiable** for any fix, new behavior, or security change.

| Question | If yes → action required |
|---|---|
| Did the fix change how ACLs are applied? | Update `setup_all.ps1` Step 4 to match |
| Did the fix add/change a script in `Config/`? | Update `setup_all.ps1` if it writes that script; update `ECOSYSTEM_REPORT.md` Section 15 |
| Did the fix add a new folder? | Add ACL protection for it in `setup_all.ps1` Step 4 |
| Did the fix change a service or scheduled task? | Update the relevant step in `setup_all.ps1` |
| Did the fix add a new security hardening? | Add it permanently to `setup_all.ps1` |

**Rationale:** `setup_all.ps1` is the reinstall blueprint. Any fix not reflected in it is lost after a fresh Windows install. A fix that doesn't survive reinstall is not a real fix.

**On failure:** Update `setup_all.ps1` and/or `ECOSYSTEM_REPORT.md` → re-read to confirm → continue.

## Step 5 — Run health checks if scripts were modified

If any `.ps1` health check script was created or modified:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\check_status.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\check_camera.ps1"
```

Evaluate output against the healthy baseline in the corresponding `/project:check` or `/project:camera-check` command. Report PASS or FAIL per item.

**On failure:** Diagnose the specific failing item, apply a targeted fix → increment cycle counter → re-run the check → continue.

## Step 5 — State the result with evidence

Do NOT write "Done." or "Complete." without attaching evidence.

**Required format:**
```
Verification complete (Cycle N):
- [filename] re-read — [specific confirmation]
- ECOSYSTEM_REPORT.md — [row confirmed / code block confirmed]
- CLAUDE.md — [section confirmed]
- Health check: [PASS / FAIL / not applicable — reason]
```

**On failure:** Return to Step 1, increment cycle counter, retry.

---

## Escalation Protocol — Triggered at Cycle 5 (after 4 failed cycles)

Execute all three actions, then state the outcome and continue the session.

### Action 1 — Restore last known-good state

```powershell
git stash
```

### Action 2 — Log to known_issues.md

Append to `C:\Sync\Config\known_issues.md`:

```
## [DATE] — [brief description of what failed]
**Cycles attempted:** 4
**Last error:** [exact error or mismatch found on the final cycle]
**Files affected:** [list every file that was being modified]
**Status:** Requires manual review by Helder
```

### Action 3 — Note in CLAUDE.md

Append under a `## Known Issues (Pending Manual Review)` header in `C:\Sync\CLAUDE.md` (append — do not replace existing content):

```
- [DATE] — [brief description] — see C:\Sync\Config\known_issues.md
```

---

## What "done" means in this ecosystem

A task is done when:
1. Every file that should exist can be Read and confirms correct content
2. Every guide RULE 1 requires has been re-read and confirmed updated
3. Any modified health check script has been run with output showing expected results
4. The completion statement includes evidence from the steps above

A task is NOT done based on memory, absence of write errors, or assuming guide sync was done because it was planned.

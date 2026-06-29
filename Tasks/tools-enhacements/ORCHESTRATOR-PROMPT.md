# Orchestrator prompt - sequential install of T075-T085

> Paste the fenced block below into a fresh session (ideally Claude Code launched
> **as Administrator** so Sysmon/auditpol/scheduled-task steps complete in-session
> instead of queuing as Blocked-Admin). Re-paste the same block to resume after an
> interruption - it reads the tracker and skips finished rows.

````text
You are the ORCHESTRATOR for installing the Win11 hardening backlog (T075-T085).
Your job is to DELEGATE each task to its own fresh subagent and keep YOUR OWN
context small. Do NOT read the T###-plan.md files yourself, and do NOT do the
implementation work yourself. You only: read the tracker, dispatch one subagent
per task, record the returned status, and commit the tracker.

=== PROGRESS TRACKER (single source of truth for resume) ===
File: C:\Sync\Tasks\tools-enhacements\INSTALL-PROGRESS.md
On start:
- If it does NOT exist, create it with a markdown table, one row per task in the
  ORDER below, every Status = "Pending", columns:
  | Order | Task | Status | LastUpdate | Next action / blocker |
- If it DOES exist, read it and RESUME: skip rows whose Status is "Done",
  "Blocked-Hardware", "Pending-Manual", or "Pending-Decision"; re-dispatch any
  row that is "Pending", "In Progress", or "Blocked-Admin" (the user may have
  since elevated / provided keys).

=== ORDER (do strictly in sequence, one at a time) ===
1. T078   2. T080   3. T081   4. T076   5. T075   6. T079   7. T077
8. T083   9. T084   10. T085   11. T082
(T075 depends on T076; if T076 ends blocked, the subagent may still author the
code per its plan but must not run live tests that need the prereq.)

=== PER-TASK LOOP ===
For each not-yet-finished task, in order:
1. Dispatch ONE subagent (Agent tool, subagent_type "general-purpose") with the
   SUBAGENT BRIEF below, substituting the task ID and its plan path
   (C:\Sync\Tasks\tools-enhacements\T###-plan.md).
2. Wait for its final summary (a single structured block).
3. Update that task's row in INSTALL-PROGRESS.md with the returned Status,
   today's date, and the Next-action/blocker text. Commit ONLY
   INSTALL-PROGRESS.md (git add by name; message "track: T### -> <status>").
4. Continue to the next task regardless of whether this one was Done or Blocked.
   Never stop the loop just because a task is blocked - blocked tasks are
   expected (admin elevation, API keys, hardware, manual, decisions).
After the last task, print a compact final table (Task | Status | Next action)
and stop. Do not summarize the work in detail - that lives in the task folders.

=== SUBAGENT BRIEF (send this to each subagent) ===
"""
You are executing exactly ONE task: T### . Execute it directly; do NOT delegate.
1. Read your plan: C:\Sync\Tasks\tools-enhacements\T###-plan.md . Read
   C:\Sync\CLAUDE.md rules (RULE 1 guide-sync, RULE 3 verify, RULE 4 commit,
   RULE 6 pre-commit integrity, em-dash rule) and follow them.
2. Do EVERYTHING that is automatable from within C:\Sync as the current user.
   This includes editing .ps1 scripts, settings.json, writing Python/init
   scripts, and updating guides (ECOSYSTEM_REPORT.md, CLAUDE.md, setup_update.ps1)
   per RULE 1. Do NOT run setup_update.ps1 yourself - that is Helder's Admin
   action; edit it and leave the "run as Admin" instruction in your notes.
3. Do NOT fake completion. For anything that needs Administrator elevation,
   paid signup / API keys, separate hardware, or a physical action, IMPLEMENT or
   PRE-AUTHOR what you can, then leave a precise "ACTION FOR HELDER" note. Use
   these exact status words: Done | Blocked-Admin | Blocked-Hardware |
   Pending-Manual | Pending-Decision | In Progress (if you ran out of room).
4. Track your own progress in
   C:\Sync\Tasks\tools-enhacements\T###-steps-status.md (create/update it:
   per-step checklist with [x]/[ ], what's left, exact resume point). This makes
   the task resumable if interrupted mid-step.
5. Update this task's row in C:\Sync\Backlog.md to the new Status (keep the row
   BRIEF - one line; detailed info stays in the plan + steps-status files).
6. GUARDED FILES: config_guard.ps1 auto-reverts uncommitted edits to auditor.ps1,
   setup_update.ps1, cloud_sync.ps1, run_mirror.bat. If you edit any of these,
   COMMIT IMMEDIATELY after editing so the change is not reverted.
7. Verify per RULE 3 (re-read edited files; ParseFile any .ps1 you changed,
   0 errors). Then RULE 6 integrity check and commit YOUR changed files by name
   (never git add -A; never commit Logs/, Mirror/, rclone.conf, credentials,
   *.tmp.*). Do not commit INSTALL-PROGRESS.md - the orchestrator owns it.
8. Return ONLY this block as your final message, nothing else:
   TASK: T###
   STATUS: <one of the status words>
   DID: <=2 lines on what you completed/committed
   BLOCKER/NEXT: <=2 lines - the exact ACTION FOR HELDER or resume point
   FILES: <comma-separated files you changed>
"""

=== CONTEXT HYGIENE ===
- Never open a T###-plan.md or a Config/ script yourself; the subagents do.
- Keep your own messages terse. Your context should hold little more than the
  tracker table and the latest subagent summary.
- If a subagent returns "In Progress", re-dispatch the SAME task once more before
  moving on; if still not finished, record In Progress and continue.

Begin: read/create INSTALL-PROGRESS.md, then start the loop at the first
unfinished task.
````

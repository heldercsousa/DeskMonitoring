# T082 - Offline rescue scan - steps status

**Status:** Pending-Manual (all automatable artifacts authored; execution is physical/manual)
**Last updated:** 2026-06-29

## Nature of task
Purely PHYSICAL: build USB rescue media on a clean machine, boot the laptop from
Microsoft Defender Offline -> Kaspersky Rescue Disk 2026 -> ESET SysRescue Live, scan
disk + boot sectors, record findings as Evidence. Claude Code cannot perform any of this
(no USB writing, no reboot, no firmware access).

## Step checklist
- [x] 1. Authored execution runbook `T082-runbook.md` (Phases A-D, Secure Boot notes,
      verdict guidance, cross-reference to T079/T070/T076).
- [x] 2. Pre-staged Evidence template `T082-evidence-template.md` (per-tool sections +
      cross-reference + verdict checklist) for copy into `C:\Sync\Evidence\`.
- [x] 3. Backlog row updated -> Pending-Manual.
- [ ] 4. (HELDER, physical) Build boot media on a clean machine.
- [ ] 5. (HELDER, physical) Boot + deep-scan with all three tools incl. boot sectors.
- [ ] 6. (HELDER) Record results to `C:\Sync\Evidence\YYYY-MM-DD_offline-rescue-scan.md`
      from the template; commit.
- [ ] 7. (HELDER) Cross-reference detections with T079 baseline / T070 / T076.
- [ ] 8. (HELDER) Apply verdict guidance; escalate to firmware reflash / hardware
      replacement + professional IR on any bootkit/firmware indicator.

## RULE 1 note
No `.ps1`, no architecture/path/task change - this is a manual procedure, so
ECOSYSTEM_REPORT.md / CLAUDE.md / setup_update.ps1 do NOT require updates. Only the
task-folder docs and the Backlog row changed.

## ACTION FOR HELDER (to reach Done)
Execute `T082-runbook.md` end to end (physical USB boot). Resume point for any future
session: steps 4-8 above are all manual; mark them [x] and set Backlog -> Done once the
Evidence file is committed and the verdict is recorded.

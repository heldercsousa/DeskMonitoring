# T077 - WEF off-box event forwarding - steps status

**Status:** Blocked (full WEF) / Interim mitigation Done.
**Updated:** 2026-06-29

## Summary
Full WEF off-box forwarding is Blocked on a collector host (no second machine).
The automatable INTERIM mitigation (off-box git push of evidence, tightened
cadence) is implemented and committed. WEF subscription + setup steps are
pre-authored for the day a collector exists.

## Checklist
- [x] Read plan + CLAUDE rules
- [x] Enhance `auto_commit_logs.ps1`: commit Logs/+Evidence/ THEN `git push origin`
      off-box (best-effort, non-fatal, logged `LOG-FORWARD`)
- [x] Tighten cadence: setup_update.ps1 Step 17 daily 23:30 -> hourly (guarded file, committed immediately)
- [x] Pre-author `Config/wef/wef_subscription_template.xml` (source-initiated, channels per plan)
- [x] Pre-author `Config/wef/README-WEF-collector-setup.md` (collector + source setup, ACTION FOR HELDER)
- [x] RULE 1 guides: ECOSYSTEM_REPORT Section 5 rows + Step 17 mirror + Section 15 script content
- [x] RULE 1 guides: CLAUDE.md task-cadence row
- [x] ParseFile setup_update.ps1 + auto_commit_logs.ps1 = 0 errors
- [x] Commit (guarded setup_update committed immediately with auto_commit_logs)
- [ ] BLOCKED: activate WEF subscription on a collector host (needs second machine)

## ACTION FOR HELDER
1. Run `setup_update.ps1` as Administrator to apply the hourly cadence (Step 17).
   Until then the task still runs daily and the push logic is dormant in the old trigger.
2. (Future, Blocked) When a collector host exists (N100 T083 or any clean 2nd machine),
   follow `Config/wef/README-WEF-collector-setup.md` to activate true per-event off-box WEF.

## Resume point
Task is complete for everything automatable now. Next action is purely Helder's:
Admin setup_update run (cadence) + future collector provisioning (full WEF).

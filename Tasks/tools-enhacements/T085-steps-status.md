# T085 - steps-status

**Task:** [DECISION] Evaluate Huntress Managed EDR vs Microsoft Defender for
Business for the clean rebuild.
**Type:** Decision/research only - no code, no .ps1, no setup_update.ps1, no
ECOSYSTEM_REPORT changes (RULE 1 script-sync N/A - nothing automatable installed).
**Status:** Pending-Decision (analysis complete; purchase is Helder's call).

## Steps
- [x] Locate task definition (no T085-plan.md exists; sourced from
      backlog_rows_to_append.md + Protecao_Win11.md + ORCHESTRATOR-PROMPT.md)
- [x] Read research grounding (Protecao_Win11.md Layer-2 EDR section + Phase-1 step 3)
- [x] Refresh current pricing via web (Huntress + Defender for Business, 2026-06-29)
- [x] Author decision doc: side-by-side, recommendation, triggers, open questions
      -> `Tasks/tools-enhacements/T085-decision.md`
- [x] Update Backlog.md T085 row -> Pending-Decision (brief)
- [x] Commit changed files by name (RULE 4/6)

## Outcome / recommendation
- DEFAULT (buy at rebuild): Microsoft Defender for Business standalone
  (~$3/user/mo, no device minimum) or via existing M365 Business Premium.
- UPGRADE later: Huntress Managed EDR layered on Defender AV - only if a BR MSP
  onboards a single endpoint at a sane rate (50-agent direct minimum blocks solo).
- REJECT: second kernel-level EDR as a peer (CrowdStrike/SentinelOne stacked).

## ACTION FOR HELDER (to close the decision)
1. Check if you already have M365 (Business Premium includes Defender for Business).
2. Confirm BR pricing (BRL) for Defender for Business standalone via MS BR / CSP.
3. Ask 1-2 Brasilia MSPs whether they onboard ONE endpoint for Huntress + price.
4. Purchase at clean-rebuild time only (not on the compromised host).

## Resume point
Nothing left to automate. Task stays Pending-Decision until Helder answers the
four open questions in T085-decision.md Section 4 and makes the purchase at rebuild.

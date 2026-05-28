# EVIDENCE: Power Settings Manipulation — 2026-05-28

## Summary
Power configuration was found in a state inconsistent with previously applied motion-detection settings.
This constitutes evidence of external manipulation (Windows Update, attacker, or system reset).

## Discovery Date
2026-05-28 ~15:25 local time (Brasilia/Sao Paulo UTC-3)

## Active Power Plan at Time of Discovery
- Name: Economia de energia (Power Saver)
- Alias: SCHEME_MAX
- GUID: a1841308-3541-4fab-bc81-f71556f20b4a
- Status: WRONG — Power Saver is the most aggressive savings plan.
  Previously configured: custom Balanced plan or High Performance.

## Affected Settings (raw powercfg output values)

### USB Selective Suspend (subgroup 2a737441-1930-4402-8d77-b2bebba308a3, setting 48e6b7a6-50f5-4782-a5d4-53bb8f07e226)
- AC Current Index: 0x00000001 = ENABLED  <- TAMPERED (should be 0x0 = Disabled)
- DC Current Index: 0x00000001 = ENABLED  <- TAMPERED (should be 0x0 = Disabled)

### Sleep after (subgroup 238c9fa8-0aad-41ed-83f4-97be242c8f20, setting 29f6c1db-86da-48c5-9fdb-f2b67b1f44da)
- AC Current Index: 0x00000000 = Never    <- OK
- DC Current Index: 0x00000000 = Never    <- OK

### Hibernate after (subgroup 238c9fa8-0aad-41ed-83f4-97be242c8f20, setting 9d7815a6-7ee4-497e-8888-515a05f02364)
- AC Current Index: 0x00000000 = Never    <- OK
- DC Current Index: 0x00000000 = Never    <- OK

### Display turn off (subgroup 7516b95f-f776-4464-8c53-06167f40cc99, setting 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e)
- AC Current Index: 0x0000012c = 300s = 5 minutes  <- LOW (should be >= 600s per quick-reference doc)
- DC Current Index: 0x00000078 = 120s = 2 minutes  <- acceptable for battery

### Hard disk turn off (subgroup 0012ee47-9041-4b5d-9b77-535fba8b1442, setting 6738e2c4-e8a5-4a42-b16a-e040e769756e)
- AC Current Index: 0x00000000 = Never    <- OK
- DC Current Index: 0x00000000 = Never    <- OK

## Impact
- USB Selective Suspend ENABLED -> webcam loses USB power during idle periods
- Yawcam process stays running but webcam device disappears -> no recordings written
- Motion detection silently fails without any error visible to user
- Screen dims after 5 min on AC (300s) -- may trigger further device suspension cascades

## Severity Assessment
- CRITICAL: USB Selective Suspend is the #1 known cause of webcam dropout (documented in quick-reference)
- CRITICAL: Active plan is Power Saver (SCHEME_MAX) -- this plan is specifically designed to be aggressive
  about cutting power, which amplifies all USB/display suspension behaviors
- The combination of these two tampered settings guarantees motion detection failure after any idle period

## Chain of Custody
- Audit performed by Claude Code (claude-sonnet-4-6) at Helder's request on 2026-05-28
- Commands used:
    powercfg /getactivescheme
    powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226
    powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da
    powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364
    powercfg /query SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e
    powercfg /query SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e
- Raw hex values recorded verbatim -- no transformation applied
- This evidence file was written before any remediation was applied

## Remediation Applied
- fix_power_motion.ps1 created at C:\Sync\Config\fix_power_motion.ps1
- Script switches plan to Balanced (SCHEME_BALANCED), disables USB Selective Suspend (AC+DC=0),
  sets sleep/hibernate to Never, sets display off to 600s AC / 120s DC
- Script requires Administrator elevation to execute

## Reference Documents
- Required settings: C:\Sync\Config\motion\motion-detection-power-settings-quick-reference.md
- Full setup guide: C:\Sync\Config\motion\acer-nitro5-motion-detection-setup.md
- Repair script: C:\Sync\Config\fix_power_motion.ps1

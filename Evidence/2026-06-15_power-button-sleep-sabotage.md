# Evidence: Power-button sleep sabotage stopping camera recording

**Date:** 2026-06-15
**Reported by:** Helder ("ecosystem stopped recording after laptop left idle, should stay recording motion")
**Investigated by:** Claude Code
**Severity:** HIGH - directly defeats the primary defense (camera recording)

---

## Summary

The laptop was being put to **sleep (S3)** by a **physical power-button press**,
which freezes the entire ecosystem (Yawcam, monitor, auditor, cloud sync) and stops
all recording. The Windows power-PLAN settings were already correct (sleep/hibernate
= Never, USB selective suspend = Disabled), so they were a red herring. The actual
mechanism was the power button, which defaulted to "Sleep".

This is a new variant of the documented power-sabotage vector (cf. 2026-05-28
"USB Selective Suspend enabled"). It achieves the adversary's primary goal -
stopping the camera - by the simplest possible physical means.

---

## Evidence (live system queries, 2026-06-15)

### Power plan (active scheme: Equilibrado / Balanced, 381b4222-...)
| Setting | AC | Battery | Verdict |
|---|---|---|---|
| Sleep after | Never (0x0) | Never (0x0) | correct |
| Hibernate after | Never (0x0) | Never (0x0) | correct |
| USB selective suspend | Disabled (0) | Disabled (0) | correct |
| Disk turn-off | 20 min (0x4b0) | 10 min (0x258) | deviated, now Never |
| Lid close action | Do nothing (0x0) | Do nothing (0x0) | rules out the lid |

Available sleep states: **only S3** (Modern Standby / S0 NOT available), so
connected-standby app suspension is ruled out.

### Kernel-Power Event 42 (System log) - the system DID sleep despite "Never"
Full message text for every event: `Motivo da Suspensao: Button or Lid`

| Timestamp | Reason |
|---|---|
| 2026-06-11 05:46:46 | Button or Lid |
| 2026-06-11 12:47:15 | Button or Lid |
| 2026-06-13 17:06:21 | Button or Lid |
| 2026-06-13 22:07:22 | Button or Lid |

Lid action = Do nothing (verified), so the trigger is the **physical power button**
(hardware default = Sleep; no registry override existed). One event at 05:46 is
off-hours and consistent with the THREAT_MODEL physical-access adversary. The
laptop was on AC power when the loss of recording occurred (per Helder).

---

## Remediation applied

1. **Live fix (applied + verified):** power button + sleep button set to
   "Do nothing" (0) on AC and DC via `powercfg`; disk turn-off set to Never.
   Verified in registry: PBUTTONACTION/SBUTTONACTION AC=0 DC=0.
2. **`fix_power_motion.ps1`** (reinstall-surviving, run by `setup_update.ps1`
   Step 18b): added disk-off=Never and power/sleep button + lid = Do nothing.
3. **`yawcam_monitor_v4.ps1`**: keep-awake guard
   `SetThreadExecutionState(ES_CONTINUOUS|ES_SYSTEM_REQUIRED)` asserted at startup
   and each loop (blocks idle/away sleep; cannot block a button press).
4. **`auditor.ps1`**: Event-42 detection rewritten to use a persistent watermark
   (the old 60s look-back window never fired after a real sleep) and to parse the
   Portuguese reason text; "Button or Lid" sleeps escalate to
   `[ALERT] [BUTTON-SLEEP]` + best-effort `send_alert.ps1`.
5. **`check_power_motion.ps1`** (hourly SYSTEM auto-heal): fixed a latent bug where
   `Get-PowerSetting` matched only the English powercfg label and therefore
   returned `$null` on this Portuguese Windows - making the entire auto-heal a
   silent no-op. Added auto-heal for power/sleep button actions (read from registry
   since powercfg hides them; a missing key = hardware default Sleep = anomaly) and
   disk turn-off.

## Residual notes
- Detection of a button sleep can only fire **after resume** (the whole system is
  frozen while asleep). Prevention (buttons = Do nothing) is the primary control.
- `send_alert.ps1` decrypts credentials with user-scoped DPAPI; the auditor runs as
  SYSTEM, so the email may not deliver. The security-log `[ALERT]` line is the
  reliable channel.
- With the power/sleep buttons disabled, **shut down via the Start menu only**.

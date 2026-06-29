# T082 - Offline Rescue Scan - Execution Runbook (for Helder)

> **Why this exists:** Under assume-breach, a kernel rootkit / bootkit / firmware
> implant on this laptop can hide from ANY scanner running inside the live (compromised)
> Windows. The only way to look underneath the OS is to boot a clean, external operating
> system from USB and scan the disk + boot sectors from outside. This is a PHYSICAL action
> Claude Code cannot perform. Follow this runbook end to end.

**Source doc:** `Protecao_Win11.md` Layer 7 + Phase 0.
**Ties to:** T079 (Autoruns baseline), T070 (resident-process investigation), T076 (Sysmon).

---

## Golden rules before you start
1. **Treat every scan as evidence, NOT proof of cleanliness.** A "clean" result does NOT
   clear this host. Bootkits routinely evade signature scanners.
2. **Build the boot media on a CLEAN machine** (not this laptop). If this laptop is
   compromised, any USB stick you write on it could be tampered with.
3. **Never save scan output back to the suspect internal disk.** Write all findings to a
   SEPARATE, write-protected USB stick (the "Evidence stick"), then transfer to
   `C:\Sync\Evidence\` only after you are back in a trusted context.
4. **Disconnect WiFi/Ethernet during the offline scan** where possible (matches the
   existing operational habit of disabling WiFi when arming the ecosystem - T071). Allow
   network only briefly for definition updates, then disconnect for the scan itself.
5. **Photograph the screen** for any non-clean result - rescue environments often cannot
   export a clean report.

---

## Materials needed
- [ ] A CLEAN second computer to build the USB media.
- [ ] 2x USB sticks: one "Boot stick" (>= 8 GB, will be wiped), one "Evidence stick"
      (>= 4 GB, with a physical write-protect switch if available).
- [ ] This laptop's UEFI/BIOS password (if set) and the boot-menu key
      (Acer Nitro 5: **F12** boot menu, **F2** BIOS setup).

---

## Phase A - Prepare boot media (on the CLEAN machine)

Download each rescue tool's OFFICIAL image. Run all three in sequence; each catches what
the others miss.

### A1. Microsoft Defender Offline
- Built into Windows: easiest path is to trigger it FROM the suspect laptop later
  (Windows Security -> Virus & threat protection -> Scan options -> **Microsoft Defender
  Offline scan** -> Scan now -> reboots into the offline environment automatically).
- Standalone media alternative: download Windows Defender Offline / use the
  `MpCmdRun.exe -RestoreDefaults` not needed here; the in-OS trigger is sufficient and
  reboots into a pre-boot scan.
- Order: run this FIRST (lowest friction, no Secure Boot changes).

### A2. Kaspersky Rescue Disk 2026
- Download: `https://www.kaspersky.com/downloads/free-rescue-disk` (krd.iso).
- Write to the Boot stick with **Rufus** (https://rufus.ie) in **DD image** mode, or
  with `dd` on Linux. Verify the SHA256 against Kaspersky's published hash.

### A3. ESET SysRescue Live
- Download: `https://www.eset.com/int/support/sysrescue/` (ESET SysRescue Live creator
  or ISO).
- Write to the Boot stick (or a second stick) with Rufus / its own creator tool. Verify hash.

> Tip: you can reuse ONE boot stick and re-flash it between A2 and A3, or use two sticks.

---

## Phase B - Boot the laptop from each tool in turn

### B1. Enter the boot menu
- Power off the laptop fully (Start menu -> Shut down; the power button is set to
  "Do nothing" per the power-hardening, so use the Start menu).
- Insert the Boot stick. Power on and tap **F12** (Acer boot menu).
- Select the USB device.

### B2. Secure Boot note
- Microsoft Defender Offline and ESET SysRescue are usually Secure-Boot signed.
- Kaspersky Rescue Disk may require **disabling Secure Boot** (BIOS **F2** ->
  Boot -> Secure Boot -> Disabled). **Re-enable Secure Boot afterwards** - leaving it
  off is itself a downgrade an attacker would love.
- Record in the Evidence file whether you had to disable Secure Boot and that you
  re-enabled it.

### B3. Run each scan (full / deep, including boot sectors)
For EACH of the three tools:
- Choose **full / thorough / deep** scan (not quick).
- Ensure **boot sector / MBR / UEFI** scanning is enabled if the tool exposes the option
  (Kaspersky: scan "Boot sectors" + "System drive"; ESET: enable boot sector + archive
  scan).
- Let definitions update once if network is briefly allowed, then proceed.
- Record: tool version, definition date, scan scope, start/end time, and EVERY detection
  (or explicit "no threats found").
- Save/export the report to the **Evidence stick** if the tool allows; otherwise photograph.

Suggested order: **Defender Offline -> Kaspersky Rescue Disk -> ESET SysRescue Live.**

---

## Phase C - Record findings as Evidence
1. Copy this folder's template `T082-evidence-template.md` to
   `C:\Sync\Evidence\YYYY-MM-DD_offline-rescue-scan.md` (use the scan date).
2. Fill in every section. Attach photos/exports from the Evidence stick.
3. Commit the Evidence file to git immediately (Evidence folder is append-only,
   ACL-protected).

---

## Phase D - Cross-reference (this is where the value is)
- [ ] Compare any detection against the **Autoruns baseline** (T079:
      `C:\Sync\Config\autoruns\baseline.csv` and recent `[AUTORUN-DELTA]` lines in
      `Logs\security\autoruns_*.log`). A file flagged offline that ALSO shows as a
      persistence entry is high-confidence.
- [ ] Cross-reference with the **resident-process investigation (T070)** - the unknown
      in-process actor that disables scheduled tasks. If an offline scan names a service,
      driver, or scheduled-task binary, map it to the T070 evidence file
      (`Evidence/2026-06-18_defensive-tasks-disabled-confirmed-tampering.md`).
- [ ] If Sysmon (T076) is live, correlate any flagged binary path/hash against Sysmon
      Event 1 process-creation history.

---

## Verdict guidance (from Protecao_Win11.md)
- **Clean result:** documented evidence only - NOT an all-clear. Keep the assume-breach posture.
- **Userland malware found:** quarantine/remove with the rescue tool, re-scan, but still
  proceed to the planned reformat (Phase 1 / T083+) - removal of userland payload does not
  prove the persistence mechanism is gone.
- **Firmware / UEFI / bootkit indicators:** a standard reformat is INSUFFICIENT. Required:
  reflash the firmware (vendor tool) or **replace the hardware**, and involve professional
  incident response. Do NOT trust this machine for anything sensitive until then.
- **The only reliable remediation remains the planned reformat** (T083 onward) regardless
  of scan outcome.

---

## ACTION FOR HELDER (summary)
1. Build boot media on a clean machine (Phase A).
2. Boot + scan with all three tools, boot sectors included (Phase B).
3. Record everything to `C:\Sync\Evidence\` using the template (Phase C).
4. Cross-reference with T079 / T070 / T076 (Phase D).
5. Re-enable Secure Boot if you disabled it.
6. Apply the verdict guidance; escalate to firmware reflash / hardware replacement +
   professional IR if any bootkit/firmware indicator appears.

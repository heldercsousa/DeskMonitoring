# T076 — Install Sysmon (SwiftOnSecurity config) — Steps Status

**Status:** Blocked-Admin (everything automatable is done; live install needs Helder to run setup_update.ps1 as Administrator)
**Last updated:** 2026-06-29

## Checklist

- [x] 1. Download SwiftOnSecurity `sysmonconfig-export.xml` (master) -> stored at `C:\Sync\Config\sysmonconfig.xml` (1200 lines, schemaversion 4.50, ends `</Sysmon>`, git-tracked)
- [x] 2. Download + verify Sysmon binary zip (valid; contains Sysmon64.exe). Kept in scratchpad only - NOT written to C:\Tools (outside C:\Sync, RULE 5b). setup_update.ps1 auto-downloads it at Admin-run time.
- [x] 3. Add `setup_update.ps1` Step 21: idempotent Sysmon install. Detects service `Sysmon64` -> `-c` (reapply config) if present, else `-accepteula -i`. Downloads `C:\Tools\Sysmon\Sysmon64.exe` from Sysinternals if absent. Verifies `Microsoft-Windows-Sysmon/Operational` channel. ParseFile = 0 errors. Committed immediately (guarded file).
- [x] 4. RULE 1: ECOSYSTEM_REPORT.md updated - §2 (Software Installed + Sysmon note), §3 (Folder Structure, C:\Tools\Sysmon), §5 (File Inventory, sysmonconfig.xml row). CLAUDE.md Key Data Paths updated.
- [x] 5. Backlog row -> Blocked-Admin.
- [ ] 6. ACTION FOR HELDER: run `setup_update.ps1` as Administrator to perform the live Sysmon install (needs elevation).
- [ ] 7. ACTION FOR HELDER (acceptance): after install, confirm Event ID 1/3/22 present in `Microsoft-Windows-Sysmon/Operational`.

## ACTION FOR HELDER (to reach Acceptance)
1. Run `setup_update.ps1` as Administrator. Step 21 will download Sysmon to `C:\Tools\Sysmon` (if the attacker firewall does not block download.sysinternals.com) and install it with `C:\Sync\Config\sysmonconfig.xml`.
2. Verify acceptance:
   ```powershell
   Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 20 |
     Group-Object Id | Sort-Object Name
   ```
   Expect Event ID 1 (process create), 3 (network connect), 22 (DNS query).
3. If download is blocked, manually drop Sysmon64.exe into `C:\Tools\Sysmon\` (zip already downloaded this session to `%TEMP%\claude\Sysmon.zip`) and re-run setup.

## Notes / caveats
- Sysmon is NOT hardened against an admin attacker - value realized only once events are forwarded off-box (T077). On its own it can be blinded by the resident process that disables tasks.
- Config schemaversion 4.50 is accepted by all current Sysmon binaries (backward compatible).
- Did NOT write to C:\Tools (outside C:\Sync) per RULE 5b - setup_update.ps1 (Admin entry point) handles the binary staging.

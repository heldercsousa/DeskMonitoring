# ACTION FOR HELDER — manual steps for the Win11 hardening batch (T075-T086)

> **Why this file exists:** the hardening tasks are code-complete and committed, but
> several finish only with a manual action Claude cannot perform (Administrator
> elevation, paid/free signup for API keys, buying hardware, a physical USB boot, or
> a purchase decision). This is the single checklist so none of them is forgotten.
> Referenced from `Backlog.md` (rows T087, T088) and per-task detail lives in each
> `Tasks/tools-enhacements/T###-*.md`.
>
> **Status legend:** [ ] not done · [x] done (tick it and commit when you finish one).
> Ordered by leverage - do Section 1 first; it unblocks five tasks in one run.

---

## 1. Run `setup_update.ps1` as Administrator  ← highest leverage (unblocks T078, T076, T075, T079, T077)

> **First run done 2026-06-29 12:07.** Most steps succeeded; two had errors the
> script masked with a false "OK" (now fixed in commit `ce466ba`). **A second
> elevated run is required** to apply the corrected Step 17 hourly task. Status of
> each item below records the 2026-06-29 result.

```powershell
& "C:\Sync\Config\setup_update.ps1"
```

- [x] **T078 - firewall-tamper auditing** (Step 16a4): enabled OK on 2026-06-29.
      **Still to verify (optional):**
      ```powershell
      auditpol /get /subcategory:"MPSSVC Rule-Level Policy Change"
      ```
      Expect **Success and Failure**. Then acceptance test - add+remove a dummy
      outbound block rule and confirm a `[FIREWALL-TAMPER]` line in today's
      `Logs/security/security_audit_*.log` (steps: `T078-steps-status.md`).

- [x] **T076 - Sysmon install** (Step 21): installed OK on 2026-06-29; channel present.
      **Still to verify (optional):** Event Viewer -> Applications and Services Logs ->
      `Microsoft-Windows-Sysmon/Operational` shows Event IDs **1 / 3 / 22**.

- [x] **T075 - registry-tamper auditing** (Step 16a5): subcategory + all SACLs applied.
      The PowerSchemes SACL initially failed (T089) but is now **FIXED & verified live**
      (`6428325` - native RegSetKeySecurity). All 3 guarded keys audit writes (4657/4663).
      **Acceptance test (needs the ecosystem RUNNING so FolderSyncAuditor catches it):**
      deliberate `powercfg` USB-Suspend change -> expect `[REG-TAMPER]`/`[REG-WRITE]`
      naming the caller (Sysmon Event 1 / 4688). Steps: `T075-steps-status.md`.

- [x] **T079 - Autoruns baseline** (Step 22): task registered + baseline captured OK on
      2026-06-29; **baseline.csv committed** (`aec520d`, 1788 entries). Daily diff runs
      08:45. Nothing left here.

- [ ] **T077 - hourly off-box log push** (Step 17): **FAILED on 2026-06-29** - the task
      XML had an out-of-range Duration, so the old **daily** definition stayed (and
      config_guard restored it). **Fixed in `ce466ba`.** ** -> RE-RUN setup_update.ps1
      as Admin** to register the hourly version, then confirm:
      ```powershell
      (Get-ScheduledTask FolderSync-GitCommitLogs).Triggers
      ```
      should show an **hourly Repetition (PT1H)**, not a DailyTrigger.

---

## 2. Free API keys + CVE MCP install  (enables T080, T081, and T079 VT enrichment)

All free tiers; user-level (no admin needed). Keys are read from environment
variables only - never pasted into git-tracked files.

- [ ] Get a free **VirusTotal** API key: https://www.virustotal.com (account -> API key).
- [ ] Get a free **Shodan** API key: https://account.shodan.io
- [ ] Set them as user env vars (new terminal needed afterwards):
      ```powershell
      setx VIRUSTOTAL_API_KEY "<your-vt-key>"
      setx SHODAN_API_KEY "<your-shodan-key>"
      ```
- [ ] Clone + install the CVE MCP server:
      ```powershell
      git clone https://github.com/mukul975/cve-mcp-server C:\Tools\cve-mcp-server
      cd C:\Tools\cve-mcp-server
      pip install -e .
      ```
- [ ] In `C:\Sync\.claude\settings.json`, flip `"disabled": true` -> `false` for the
      `virustotal`, `shodan`, and `cve` MCP servers (added under T080).
- [ ] **Smoke-test** in a new Claude session: one hash lookup (VT), one IP lookup
      (Shodan), one CVE lookup. (steps: `T080-steps-status.md`)
- [ ] Once `VIRUSTOTAL_API_KEY` is set, **T081** triage gains live VT enrichment:
      `python C:\Sync\Tools\file-triage\triage.py <file> --vt`
- [ ] Same key lets **T079** Autoruns diff add optional VirusTotal hash enrichment.

---

## 3. Hardware purchase + deploy  (T083, T084 - Blocked-Hardware)

- [ ] Buy an **Intel N100 mini-PC** (16 GB RAM, NVMe) to act as the out-of-band sensor
      + Wazuh/Velociraptor server host.
- [ ] Wire the **AX3000T hardware port mirror** (remove LAN4 from `br-lan`, dedicated
      SPAN port) per `Tools/netsensor/README-netsensor.md`.
- [ ] **T083:** install Security Onion on the N100; deploy
      `Tools/netsensor/openwrt-tc-mirror.init`; run `parse_netsensor.py` against EVE/Zeek.
- [ ] **T084:** install Wazuh server (N100) + Velociraptor; install the laptop agent;
      load the 5 VQL hunts per `Tools/wazuh-velociraptor/README.md`.

## 4. Physical offline rescue scan  (T082 - Pending-Manual)

- [ ] Build rescue media on a clean machine and boot the laptop from USB:
      **Defender Offline -> Kaspersky Rescue Disk -> ESET SysRescue** (deep-scan disk +
      boot sectors). Record results to `C:\Sync\Evidence\` using
      `Tasks/tools-enhacements/T082-evidence-template.md`. Full runbook:
      `Tasks/tools-enhacements/T082-runbook.md`. Firmware/UEFI indicators ->
      reflash/replace hardware + professional IR (treat results as evidence, not all-clear).

## 5. Purchase decision  (T085 - Pending-Decision)

- [ ] Confirm current Microsoft 365 status + the **BRL** price of **Defender for
      Business** standalone; decide Defender-for-Business (default verdict) vs
      Huntress-via-a-BR-MSP. Buy at the clean-rebuild milestone. Analysis +
      open questions: `Tasks/tools-enhacements/T085-decision.md` Section 4.

## 6. Bug to investigate (not admin, but pending)  (T086)

- [ ] `send_alert.ps1` B2 archive upload fails ("account not found"). Start with the
      safe reproduction in `Tasks/T086-send-alert-b2-upload-fail/spec.md` before changing
      anything - rule out B2 key-scope vs credential tampering.

---

*Tick a box, then commit this file (it is git-tracked, off-box evidence of progress).
As new manual actions arise in later sessions, append them here.*

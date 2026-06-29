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

# Fresh-session prompts + model guidance  (copy-paste playbook)

> **Purpose:** each block below is a self-contained prompt you can paste into a
> **fresh** Claude session (cold context - the prompt points me at the files I need).
> It says WHEN you can run it (relative to your manual steps), WHAT I do, and which
> **model is enough** so you can conserve the weekly limit.
>
> **Model legend (cheapest that suffices):**
> - **Haiku** = mechanical/status only. - **Sonnet** = default for coding, verification,
>   routine debugging. - **Opus** = deep security reasoning, suspected tampering, or
>   multi-system deployment debugging. Reserve Opus; start on Sonnet and only escalate
>   if Sonnet gets stuck.
>
> **Suggested order given the limit is near:**
> 1. **P1 (T086)** now - it is the only item needing *no* manual prereq.
> 2. Do your **Section 2** manual keys -> run **P2**.
> 3. Do your **start procedure** -> run **P3** (acceptance tests).
> 4. **P4/P5** whenever you finish the scan / make the decision.
> 5. **P6** only when the N100 hardware exists.
> P1-P5 are short; run them in **Sonnet** sessions to save Opus quota.

---

### P1 - Investigate the B2 alert-upload bug (T086)  · **DONE 2026-06-29 (69d51a9)** - benign refactor gap, not tampering; send_alert.ps1 now loads DPAPI creds. While here, also found+fixed T090 (CloudBackup task ran the unguarded cloud_sync.ps1). No need to re-run unless you want to re-verify.  · model: **Sonnet** (escalate to Opus only if it looks like tampering)

```
Read Tasks/T086-send-alert-b2-upload-fail/spec.md and the CLAUDE.md rules (RULE 1/3/6).
Investigate the send_alert.ps1 B2 "account not found" failure. SAFE repro first:
`rclone lsd cloudsync:helder-sync-mirror --config C:\Sync\Config\rclone.conf` and a dummy
`rclone copyto` of a temp file to cloudsync:helder-sync-mirror/alerts/test.txt. Determine
which root cause applies (B2 App Key prefix scope vs config drift vs credential tampering).
If benign: fix (e.g. correct the alerts/ prefix or key scope) and prove a real
`SEND-ALERT  OK  B2 upload` on the next alert. If tampering: preserve evidence to
C:\Sync\Evidence\, alert me, do NOT silently fix. Never print/commit rclone.conf. Then
RULE 1 guide-sync + RULE 6 + commit, and set Backlog T086 to Done (or Blocked w/ reason).
```
My side: rclone probes, root-cause, fix or evidence, commit. No admin needed.

---

### P2 - Smoke-test the new MCP servers + VT enrichment (T080/T081/T088)  · **run AFTER Section 2 manual keys** · model: **Sonnet**

```
I've set VIRUSTOTAL_API_KEY and SHODAN_API_KEY (setx), installed the CVE MCP server, and
flipped virustotal/shodan/cve to "disabled": false in C:\Sync\.claude\settings.json.
Read Tasks/tools-enhacements/T080-steps-status.md and T081-steps-status.md. Smoke-test:
one VT hash lookup, one Shodan IP lookup, one CVE lookup; then run
`python C:\Sync\Tools\file-triage\triage.py <a sample file> --vt` and confirm live VT
enrichment; confirm the T079 autoruns VT hook activates. Set Backlog T080, T081, T088 to
Done, tick Section 2 of HELDER-MANUAL-ACTIONS.md, and commit.
```
My side: MCP smoke tests, triage.py --vt run, backlog/checklist update, commit.

---

### P3 - Run the two live acceptance tests (T075/T078)  · **run AFTER you start the ecosystem** · model: **Sonnet** (Opus only if a test fails and needs deep debug)

```
The ecosystem is running (FolderSyncAuditor service active - confirm it first). Read
Tasks/tools-enhacements/T075-steps-status.md and T078-steps-status.md. Run BOTH acceptance
tests and revert each side effect:
(a) T078: add a dummy outbound BLOCK firewall rule then remove it; confirm a [FIREWALL-TAMPER]
    line in today's Logs/security/security_audit_*.log naming the Subject account.
(b) T075: make a benign REVERSIBLE powercfg change to USB Selective Suspend then revert it;
    confirm a [REG-TAMPER]/[REG-WRITE] line naming the calling process+parent (Sysmon Event 1,
    fallback 4688). Save evidence to C:\Sync\Evidence\, update Backlog T075/T078, commit.
```
My side: fire/revert the test stimuli, grep the audit logs, evidence + commit. Needs the
ecosystem up; the session must be elevated (run Claude as Administrator).

---

### P4 - Ingest the offline rescue-scan results (T082)  · **run AFTER the USB scan** · model: **Sonnet** (Opus if findings are serious/ambiguous)

```
I ran the offline rescue scan per Tasks/tools-enhacements/T082-runbook.md. Results: <paste
the scanner verdicts / attach logs>. Read T082-runbook.md and T082-evidence-template.md.
Record the findings into C:\Sync\Evidence\ via the template, assess severity (clean vs IOC
vs firmware/UEFI), update THREAT_MODEL.md + Backlog T082, and commit. If there are
firmware/UEFI indicators, give me the reflash/replace + professional-IR escalation steps.
```
My side: structure findings into Evidence, severity call, threat-model/backlog update, commit.

---

### P5 - Record the EDR purchase decision (T085)  · **run AFTER you decide** · model: **Sonnet**

```
EDR decision made: I'm going with <Defender for Business | Huntress via a BR MSP>. My M365
status: <none | Personal | Business Basic/Standard | ...>. Read
Tasks/tools-enhacements/T085-decision.md. Record the decision + rationale, set Backlog T085
to Done, and add any setup_update.ps1 / THREAT_MODEL.md notes needed so the chosen product
is deployed at the clean rebuild. Commit.
```
My side: document the decision, backlog/threat-model/setup notes, commit.

---

### P6 - Deploy the out-of-band sensor + EDR stack (T083/T084)  · **run WHEN the N100 hardware exists** · model: **Opus** (multi-system deploy) - Sonnet ok for routine steps

```
The Intel N100 is set up (or arriving). Read Tasks/tools-enhacements/T083-plan.md,
T084-plan.md, Tools/netsensor/README-netsensor.md and Tools/wazuh-velociraptor/README.md.
Walk me through deployment step by step: AX3000T port mirror (openwrt-tc-mirror.init),
Security Onion on the N100, then Wazuh server + Velociraptor + the laptop agent + the 5 VQL
hunts. Generate any missing config, help validate each stage, and update Backlog T083/T084
as we progress.
```
My side: guided deployment, config generation, validation, backlog updates.

---

*Tick a box, then commit this file (it is git-tracked, off-box evidence of progress).
As new manual actions arise in later sessions, append them here.*

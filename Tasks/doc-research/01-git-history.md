# Git History Research — Summary

Source: Git history analysis subagent (2026-06-05)

---

## ORIGINAL PROJECT (2026-03-02, init commit)

Simple automated folder sync ecosystem for real-time file replication.

**Original scope:** `C:\Users\helde\Repos\Bois` (source) → `C:\Sync\Mirror` (local) → Backblaze B2 (cloud)
**Stack:** RealTimeSync (file watcher) + robocopy (local mirror) + rclone (cloud sync)
**Infrastructure:** Task Scheduler + NSSM service wrapper
**First stated purpose:** Automated backup pipeline for a source folder

---

## PHASE TIMELINE

### Phase 1 (2026-03-02 → 2026-05-16): Baseline

- Ecosystem stabilized: 3-layer redundancy (scheduled tasks + service wrapper + registry startup)
- File auditing and security event logging added but minimal
- Threat model: file loss only → solution: redundant storage (local + cloud)

### Phase 2 (2026-05-17 → 2026-05-27): Security hardening begins

- PUP (SweetLabs HostAppService) detected 2026-05-18
- Power settings tampering detected → `check_power_motion.ps1` added for hourly power audit
- USB suspend re-enabled by attacker → system hardening + attack surface reduction
- Threat model upgrade: assumed system compromise with hardware-layer tampering

### Phase 3 (2026-05-28 → 2026-05-31): Active attacks + escalating response

**2026-05-28 15:47:32** — First file tampering: `cloud_sync.ps1` + `run_mirror.bat` modified mid-session
- Attacker removed FASE 3 retention, reverted log paths, injected Portuguese comments
- B2 sync failed (`storage_cap_exceeded`); fake `mirror_archive` directory created to obscure

**2026-05-29** — Repeat tampering (2nd and 3rd instances same day); forensic documentation begins

**2026-05-31 15:02:26** — Git index mass deletion: 437 files staged for deletion via `git rm`

Threat model: active adversary exploiting file sync pipeline in real time.
Strategic shift: "prevent loss" → "detect intrusion" with evidence preservation.

### Phase 4 (2026-06-01 → present): Comprehensive hardening + automation-as-defense

**2026-06-01:**
- Backlog.md + TASKS.md created (systematic task tracking)
- `enable_config_auditing.ps1` — SACL write audit on Config\, Evidence\, .git\
- `send_alert.ps1` + `post_commit_push.ps1` — email + B2 alert chain
- Multiple hardening steps added to setup_update.ps1

**2026-06-02:** DailySecurityCheck.ps1 hardened with 25+ detection categories
- T010–T017: Firewall, DNS, scheduled task tampering, B2 bucket access, EventLog, registry Run keys
- T022–T032: Monitor blind paths, sync failure detection, B2 lag alerts, watchdog hardening
- T033: Suspicious delete alerts

**2026-06-03:** Credential security upgrade
- B2 + CAM-2 credentials migrated to DPAPI encryption

**2026-06-04:** Process auditing (Event 4688), `config_guard.ps1` deployed
**2026-06-05:** Repeat tampering recovery (second consecutive night)

---

## KEY INFLECTION POINTS

| Date | Event | What changed |
|------|-------|-------------|
| 2026-03-02 | Project created | Simple 3-layer backup |
| 2026-03-06 | First firewall attack detected | Added self-healing firewall detection to cloud_sync.ps1 |
| 2026-03-15 | DNS poisoning investigation | DNS blind spot closed; camera startup fixed |
| 2026-05-18 | PUP + power settings attacks | Added power audit, attack surface reduction |
| 2026-05-28 | First config file tampering | RULE 6, evidence folder, forensic documentation |
| 2026-05-31 | Git index attack | Git protection, restore procedures |
| 2026-06-01 | Systematic task tracking begins | Backlog.md, SACL auditing, alert chain |
| 2026-06-03 | DPAPI migration | Credential security hardened |
| 2026-06-04–05 | Nightly automated tampering | Ongoing — daily recovery |

---

## COMMIT MESSAGE EVOLUTION

- **Pre-incident (before 2026-05-28):** Neutral, feature-focused ("docs", "fix", "feat")
- **Post-incident (2026-05-28+):** Forensic language ("evidence", "security", "hardening"), timestamps included, attacker intent documented
- **From 2026-06-01:** Systematic T### task codes (T001–T050+), backlog-driven, Claude-assisted incident response protocol

---

## PROJECT SCALE EXPANSION

| Period | State |
|--------|-------|
| 2026-03-02 | ~20 core scripts, basic monitoring |
| 2026-05-17 | + hardware/OS hardening documentation |
| 2026-05-28–31 | Shifted from reactive to forensic/detective posture |
| 2026-06-01–05 | Full security operations: 50+ tracked tasks, automated detection/alerting, continuous monitoring, Claude-assisted incident response |

---

## CONCLUSION

**A simple file sync utility transformed into a sophisticated security incident response and
forensic analysis system, driven entirely by recurring active attacks against the system.**

The project has no single design decision that wasn't forced by a real incident. Every script,
every detection rule, every log path exists because an attacker exploited the gap it now fills.

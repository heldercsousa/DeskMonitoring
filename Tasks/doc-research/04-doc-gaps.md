# Documentation Gap Analysis — Research Summary

Source: Existing docs analysis subagent (2026-06-05)

---

## Executive Summary

This ecosystem has **extensive technical documentation** but is **missing core purpose/context
documents** that answer "why does this exist?" and "what threat is it defending against?"

Existing docs are strong on implementation details; weak on strategic context.

---

## Current Documentation Inventory

**Well documented:**
- `CLAUDE.md` (~550 lines) — Operational rules, ACL reference, boot chains, key scripts
- `ECOSYSTEM_REPORT.md` (500+ lines) — Technical reference, file inventory, dependencies
- `Backlog.md` — 50+ task history with completion dates
- `Config/motion/acer-nitro5-motion-detection-setup.md` (2100+ lines) — Camera setup guide
- `Evidence/` folder — 20+ dated incident reports
- `Evidence/MUST-CHECK-URGENT.md` — Open threads from 2026-03-15 investigation

**NOT documented (gaps):**
- Project PURPOSE — why does this exist?
- ADVERSARY MODEL — who is attacking, how, with what capabilities?
- PROJECT HISTORY — how/why it evolved from simple camera to full security ecosystem
- ARCHITECTURE RATIONALE — why rclone+B2, ACL locking, NSSM, DPAPI?
- No `README.md` exists at `C:\Sync\`

---

## Critical Gaps (Priority Order)

### GAP 1: PROJECT PURPOSE (HIGH)
No document explains WHY this ecosystem exists.
Only mention: "personal Windows file synchronization, security, and camera/motion-detection ecosystem" — does not explain the threat scenario, critical assets, or original motivation.
**→ Create `PURPOSE.md`** (200-300 words)

### GAP 2: ADVERSARY MODEL (HIGH)
No formal threat model or threat actor profile, despite 20+ documented incidents.
Evidence shows specific attacks but no consolidated model: who is attacking, what access they
have, what they want, how they adapt.
**→ Create `THREAT_MODEL.md`** (300-500 words)

### GAP 3: PROJECT HISTORY (MEDIUM)
No timeline documented. Phases inferred only from Evidence dates and Backlog entries.
The threat-driven evolution (simple camera → full security ecosystem) is the most important
context for understanding every design decision.
**→ Create `HISTORY.md`** (200-400 words)

### GAP 4: README.md (MEDIUM)
No project-level README. New users/agents expect README first; currently must dive into CLAUDE.md.
**→ Create `README.md`** (150-200 words, navigation hub)

### GAP 5: ARCHITECTURE DECISIONS (LOW)
No explanation of design choices — why NSSM not Task Scheduler for services? Why Yawcam?
Why Backblaze B2 specifically? Why DPAPI?
**→ Add section to CLAUDE.md or create `ARCHITECTURE_DECISIONS.md`**

---

## Factual Errors Found

| # | Location | Issue | Action |
|---|----------|-------|--------|
| 1 | CLAUDE.md §Camera Paths | Monitor checks `C:\TEMP\motion_videos` but Yawcam records to `Bois\YYYY-MM-DD\` — T022 claims fixed with symlink but CLAUDE.md not updated | Verify symlink, update CLAUDE.md |
| 2 | ECOSYSTEM_REPORT.md header | Says "Last updated: 2026-03-02" but contains 2026-06-02 changes | Update header date |
| 3 | CLAUDE.md vs camera setup docs | Sensitivity value: CLAUDE.md says 91, setup guide says 60 | Verify actual deployed value |
| 4 | CLAUDE.md §Recording Format | Says AVI; setup guide recommends MP4 | Verify actual format in use |
| 5 | ECOSYSTEM_REPORT.md §T048/T049 | Credential migration status unclear (b2_creds.dpapi active vs rclone.conf fallback?) | Verify active credential paths |
| 6 | Naming inconsistency | Task vs service names conflated in CLAUDE.md | Standardize naming |

---

## What's Documented Well (Do NOT Duplicate)

- Operational rules (RULE 1–6) — keep in CLAUDE.md
- Architecture diagram and boot chain — keep as operational detail
- Key Scripts table — keep as developer reference
- ACL Reference (canonical authority) — keep as-is
- PowerShell conventions — keep as-is
- Camera inventory table — keep as operational reference

---

## Recommended New Documents

| Document | Priority | Location | Length | Purpose |
|----------|----------|----------|--------|---------|
| `PURPOSE.md` | HIGH | `C:\Sync\PURPOSE.md` | 200-300w | Why system exists, assets, original motivation |
| `THREAT_MODEL.md` | HIGH | `C:\Sync\THREAT_MODEL.md` | 300-500w | Threat categories, attacker profile, detection matrix |
| `HISTORY.md` | MEDIUM | `C:\Sync\HISTORY.md` | 200-400w | Timeline, phases, incident-driven evolution |
| `README.md` | MEDIUM | `C:\Sync\README.md` | 150-200w | Navigation hub, what each doc covers |
| `ARCHITECTURE_DECISIONS.md` | LOW | `C:\Sync\ARCHITECTURE_DECISIONS.md` | 300w | Design rationale |

---

## Document Hierarchy

```
README.md          ← Start here (navigation)
PURPOSE.md         ← Why it exists / what threat
THREAT_MODEL.md    ← Who attacks / how / what defenses
HISTORY.md         ← How we got here (incident-driven)
CLAUDE.md          ← How to operate (rules + architecture)
ECOSYSTEM_REPORT.md ← Technical details (scripts + inventory)
Config/motion/*.md ← Camera specifics
```

---

## Key Insight

This system evolved under **sustained attack pressure** (attacks observed 2026-03-06 through
2026-06-05, ongoing). The new documents must emphasize this threat-driven evolution — every
architectural choice makes sense only when you understand what attack forced it.

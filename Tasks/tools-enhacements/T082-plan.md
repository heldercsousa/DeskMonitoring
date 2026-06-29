# T082 — Offline rescue scan (MANUAL, physical access)

**Goal:** Detect kernel rootkit / bootkit / firmware persistence that any scanner running inside the live (assumed-compromised) OS cannot see. This is essential under assume-breach.

**Source:** `Protecao_Win11.md` Layer 7 + Phase 0.

## Steps (physical, USB boot — cannot be done by Claude Code)
1. Prepare boot media on a CLEAN machine: Microsoft Defender Offline, then Kaspersky Rescue Disk (2026), then ESET SysRescue Live.
2. Boot the laptop from each in turn (UEFI: may need to disable Secure Boot for some).
3. Scan disk + boot sectors; record all findings to external/read-only media as Evidence.
4. Cross-reference any hits with Autoruns baseline (T079) and the resident-process investigation (T070).

## Verdict guidance (from doc)
- Treat scans as **evidence, not proof of cleanliness**. A "clean" result does not clear the host.
- If firmware/UEFI/bootkit indicators appear, a standard reformat is insufficient — reflash firmware or replace hardware, involve professional IR.
- The only reliable remediation remains the planned reformat (Phase 1 / T083 onward).

## Status
Register as Pending; this is a manual action for Helder, not an automatable script task.

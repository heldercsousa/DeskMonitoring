# T081 — Python file-triage tool (oletools + vt-py)

**Goal:** A small Python tool that triages files (downloads, suspicious attachments) statically + by VT hash lookup, emitting a risk summary. Practical first AI-engineering Python project for Helder; feeds the daily security check.

**Source:** `Protecao_Win11.md` Layer 4 + "Phase 2 — build your scriptable stack".

## Steps
1. `pip install oletools[full] vt-py`.
2. Script `triage.py`: input = file path. Run:
   - `oleid` / `olevba` if Office; `pdfid` if PDF.
   - SHA-256 -> VirusTotal hash lookup via vt-py (free API: 4 req/min, 500/day — respect rate limit; never upload the file itself, hash-only).
3. Output JSON risk summary (verdict, macro flags, VT detections, ATT&CK if available).
4. Optional: watch a drop-folder and auto-triage; surface results into the daily check log.

## Caveat (from doc)
Evaluate suspicious files on a *separate clean machine/VM*, not the compromised laptop. Hash-only VT lookups are safe; do not upload confidential files to public VT.

## Acceptance
- Running against a known-bad EICAR/macro test file returns a non-zero risk verdict; clean file returns low.

## Learning value
Real exposure to Python packaging, REST clients, rate limiting, JSON I/O — the doc explicitly frames this as AI-engineering practice.

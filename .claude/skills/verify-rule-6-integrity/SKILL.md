---
description: "Before git commit: re-read every staged file and verify no tampering signatures (FASE comments, missing DPAPI, missing SYNC-START)"
---

# Verify RULE 6 Integrity (Anti-Injection Check)

Before staging or committing any file, re-read it from disk and check for tampering. An attacker with filesystem access could modify files between when Claude writes them and when they are committed.

## Known Tampering Signatures

The active attacker injects these identifiable markers:

| Signature | Location | Meaning |
|---|---|---|
| Portuguese comments: `FASE`, `Credenciais`, `FASE 0`, `FASE 1` | Any `.ps1` | Payload injection confirmed |
| Missing `ProtectedData` | `cloud_sync.ps1` | DPAPI credential loading stripped |
| Missing `SYNC-START` | `cloud_sync.ps1` | Monitoring log marker removed (silencing) |
| Missing `SYNC-END` | `cloud_sync.ps1` | Run boundary marker removed |

## Steps

1. **Identify staged files** - run `git diff --cached --name-only` to list every file about to be committed.

2. **Re-read each file** using the Read tool - get the live on-disk content. Do not rely on memory of what was written.

3. **Check each file against the signatures table above**:
   - Scan for any Portuguese comment patterns
   - For `cloud_sync.ps1`: confirm `ProtectedData` is present, confirm `SYNC-START` is present

4. **If content matches what was written and no signatures found** - proceed with `git add` and commit.

5. **If content differs from what was written OR a tampering signature is found**:
   - STOP - do not commit
   - Create `C:\Sync\Evidence\YYYY-MM-DD_code-injection-detected.md` documenting the exact discrepancy
   - Do NOT overwrite the tampered file - preserve it as forensic evidence
   - Alert Helder with the exact diff before taking any further action

## What NOT to do
- Do not skip this check even for "trivial" or "one-line" changes
- Do not overwrite a tampered file before documenting it as evidence
- Do not use `--no-verify` to bypass hooks

---
paths: ["**/*.ps1","**/*.bat","**/*.vbs"]
---

## Git Workflow (RULE 6 + Commit Standards)

### RULE 6 - Re-read before staging

Before every `git add`, re-read each file being staged using the Read tool to get live on-disk content. Compare against what was written in this session.

**If content matches intent:** proceed with `git add`.

**If content differs (unexpected lines, modified logic, encoding anomalies, Portuguese comments):**
- STOP - do not commit
- Document in `C:\Sync\Evidence\YYYY-MM-DD_code-injection-detected.md`
- Alert Helder with the exact diff
- Do not overwrite the tampered file - preserve as forensic evidence

Known injection signatures: Portuguese patterns (`FASE`, `Credenciais`), missing `ProtectedData` in cloud_sync.ps1, missing `SYNC-START` in cloud_sync.ps1.

### Commit message format

```
<imperative verb> <scope>: <what changed, 72 chars max>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Examples:
- `fix(cloud_sync): restore DPAPI credential loading after tampering`
- `feat(auditor): add Config/ write detection via FileSystemWatcher`
- `security: document firewall tampering evidence 2026-06-05`

### Hard rules

- Never use `git add -A` or `git add .` - stage only specific files by name
- Never use `--no-verify` (bypasses RULE 6 hook)
- Never use `--amend` unless Helder explicitly requests it
- Never force-push
- Never commit: `Logs/`, `Mirror/`, `Config/rclone.conf`, `Config/credentials.enc`, `Config/realtime.ffs_real`, `*.tmp.*`
- If nothing changed: skip commit entirely

# INCIDENT: Git Index Mass Deletion Attack
**Date:** 2026-05-31  
**Time detected:** ~15:00 local  
**Severity:** CRITICAL  

## What Happened

The attacker staged the entire C:\Sync repository for deletion via `git rm`. All tracked files appeared as `D` (deleted) in `git status --short` — 437 lines of staged deletions.

## Key Finding

**All files were still physically present on disk.** Only the git index was tampered with, not the actual filesystem. This is a `git rm` attack against the version control layer, not a file deletion attack.

## Evidence

- `git status --short` showed 437 files staged as deleted (prefix `D `)
- `powershell Get-ChildItem C:\Sync -Recurse | Measure-Object` returned **3527 files** on disk
- Key files verified present: `Config/cloud_sync.ps1`, `CLAUDE.md`, `Config/setup_all.ps1` — all `True`
- `git diff --cached --stat HEAD` confirmed mass staged deletions, e.g. `CLAUDE.md | 599 -`

## Affected Scope (staged for deletion)

All tracked files including:
- `.claude/commands/` — all project slash commands
- `.claude/settings.json`, `.claude/settings.local.json`
- `CLAUDE.md`, `.claudeignore`, `.gitignore`
- All `Config/*.ps1` scripts (entire ecosystem)
- All `Evidence/` forensic files
- All `Logs/` gitkeep markers

## Attack Goal

If this commit had been pushed:
- The remote (and any future git clone/restore) would show an empty repository
- A reinstall using git history would restore nothing
- Combined with a physical file deletion = total ecosystem destruction with no recovery path

## Recovery

Ran `git restore --staged .` — unstaged all deletions. Git index restored to HEAD state (`5ca1590`).

## Pattern

This is the **4th confirmed tampering incident** in C:\Sync:
- 2026-03-06: Firewall rules blocking B2 IPs
- 2026-05-28: `cloud_sync.ps1` + `run_mirror.bat` tampered
- 2026-05-29: Repeat tampering same files
- **2026-05-31: Git index mass deletion (this incident)**

## Recommended Actions

1. Review how attacker got write access to `C:\Sync\.git\` — consider protecting `.git/` directory
2. Set up git remote push monitoring — alert on any push that deletes >10 files
3. Consider a read-only git remote mirror as backup of last-known-good state
4. Investigate when `git rm` commands were run (check Windows Event Log for powershell/cmd activity around ~14:00-15:00 today)

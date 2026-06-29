# T081 - Python file-triage tool (oletools + vt-py + pdfid) - Steps Status

**Status:** Done (static triage fully working + tested; VirusTotal hash lookup wired but needs free API key to go live)
**Last updated:** 2026-06-29

## Checklist

- [x] 1. `pip install --user oletools vt-py pdfid` (oletools 0.60.2, vt-py 0.22.0, pdfid 1.1.3) - verified all importable
- [x] 2. Wrote `Tools/file-triage/triage.py`:
      - ftguess file-type ID + SHA-256
      - EICAR signature scan (offline, hash + literal string)
      - Office: OleID indicators + olevba macro analysis (AutoExec/Suspicious/IOC flags, VBA stomping)
      - PDF: pdfid keyword scan (/JS, /JavaScript, /OpenAction, /Launch, /EmbeddedFile, ...)
      - VirusTotal HASH-ONLY lookup via vt-py (opt-in `--vt`, throttled 4 req/min, never uploads file)
- [x] 3. JSON risk summary output (verdict, risk_score, reasons, macro flags, VT detections); `--pretty` mode; exit codes 0/2/3/1
- [x] 4. `--watch FOLDER` drop-folder mode + `--log FILE` one-line `[TRIAGE]` log line (daily-check hook ready)
- [x] 5. `requirements.txt` + `.gitignore` (excludes dropbox/test_samples/logs/pycache)
- [x] 6. ACCEPTANCE TEST: EICAR file -> verdict CRITICAL, exit 3 (non-zero); clean .txt -> verdict LOW, exit 0; synthetic /JS+/OpenAction PDF -> verdict HIGH, exit 3. PASS.
- [x] 7. RULE 1: ECOSYSTEM_REPORT.md Section 5 - added "Standalone Python tools" inventory row; CLAUDE.md Key Data Paths - added `C:\Sync\Tools\` row
- [ ] 8. Enable live VirusTotal lookups - ACTION FOR HELDER (free key)
- [ ] 9. (Optional / Pending-Decision) Wire triage into DailySecurityCheck.ps1 drop-folder scan - see note

## ACTION FOR HELDER (to enable VT enrichment)
1. Get a free VirusTotal Public API key (virustotal.com -> Profile -> API key). Same key as T080.
2. `setx VIRUSTOTAL_API_KEY <key>` (already needed for T080's VT MCP server - one key serves both).
3. Test: `python C:\Sync\Tools\file-triage\triage.py <somefile> --vt --pretty`
   - Free tier: 4 req/min, 500/day. The tool self-throttles to 4/min.
   - HASH-ONLY: the file is never uploaded; only its SHA-256 is queried. Never point `--vt` at confidential files you would not want VT to have a hash record of (hash record is benign, but per the plan caveat, evaluate truly suspicious files on a separate clean VM).

## Optional daily-check hook (Pending-Decision - NOT wired live)
`DailySecurityCheck.ps1` could call the triage tool over a watched downloads/drop folder and append `[TRIAGE]` lines to the security log. Deliberately NOT wired into the live security script yet because:
  - it adds a Python-on-PATH dependency to a security-critical .ps1, and
  - static-only value is low without the VT key (step 8).
Pre-authored invocation for when Helder decides to enable it (add near end of DailySecurityCheck.ps1):
```powershell
# T081 file triage over the Downloads drop-folder (static + VT if key present)
$triage = "C:\Sync\Tools\file-triage\triage.py"
$drop   = "$env:USERPROFILE\Downloads"
if (Test-Path $triage) {
    Get-ChildItem -Path $drop -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-1) } |
        ForEach-Object {
            python $triage $_.FullName --vt --log "C:\Sync\Logs\security\triage_$(Get-Date -Format 'yyyy-MM-dd').log" | Out-Null
        }
}
```

## Notes
- Tool lives under `C:\Sync\Tools\` (NOT `Config\`) - it is standalone source, restored by git, so no ECOSYSTEM_REPORT Section 15 full-content mirror is required (Section 5 inventory only).
- setup_update.ps1 NOT modified (guarded, high-risk; tool is not part of the running ecosystem). Reinstall step is the one-liner: `python -m pip install --user -r C:\Sync\Tools\file-triage\requirements.txt`.
- EICAR test file deliberately deleted after testing (Windows Defender quarantines it; never committed).
- CAVEAT (from plan): evaluate suspicious files on a separate clean VM, not this host; hash-only VT lookups are safe.

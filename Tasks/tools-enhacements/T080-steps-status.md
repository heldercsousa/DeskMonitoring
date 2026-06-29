# T080 — VirusTotal + Shodan + CVE MCP servers — Steps Status

**Status:** Pending-Manual (config fully pre-authored; live smoke-tests need free API keys + CVE repo clone)
**Last updated:** 2026-06-29

## Checklist

- [x] 1. Verify exact package names / invocation / env-var names for all 3 servers (web-verified)
- [x] 2. Add `virustotal`, `shodan`, `cve` entries to `.claude/settings.json` `mcpServers` (disabled:true, `${VAR}` env expansion so no secrets in git)
- [x] 3. Validate settings.json parses as JSON (node — VALID)
- [x] 4. RULE 1: ECOSYSTEM_REPORT.md — added MCP servers inventory table under Claude Code tooling
- [ ] 5. Get free API keys (VirusTotal, Shodan) — ACTION FOR HELDER (free signup)
- [ ] 6. Clone + install CVE MCP server Python package — ACTION FOR HELDER
- [ ] 7. Set OS env vars, flip disabled=false, smoke-test each (1 VT hash, 1 Shodan IP, 1 CVE query) — ACTION FOR HELDER

## What's automatable (Done)
All three server entries are wired into settings.json with the correct command/args/env/cwd and detailed `_note` enable instructions. Keys use `${VAR}` expansion from OS env so the committed file holds no secrets.

## ACTION FOR HELDER (to reach Acceptance)
1. **VirusTotal**: get free Public API key at virustotal.com (Profile > API key). `setx VIRUSTOTAL_API_KEY <key>`. Set `virustotal.disabled=false`.
2. **Shodan**: get free key at account.shodan.io. `setx SHODAN_API_KEY <key>`. Set `shodan.disabled=false`.
3. **CVE**: `git clone https://github.com/mukul975/cve-mcp-server.git C:\Tools\cve-mcp-server`; create venv; `pip install -e .`. 8 tools work keyless; reuses VT/Shodan keys for the rest. Set `cve.disabled=false`.
4. Restart Claude Code, then smoke-test: one VT hash lookup, one Shodan IP, one CVE/EPSS query.

## Notes
- Cannot run smoke-tests from this session (no keys, no Python package, MCP servers only load at Claude Code startup).
- setup_update.ps1 NOT modified: MCP config lives in git-tracked `.claude/`, not reinstalled by the ecosystem setup script.
- CAVEAT (from plan): point analysis at IOCs from trusted/forwarded logs, never data read off the compromised host; never upload confidential files to public VT.

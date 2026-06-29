# T080 — VirusTotal + Shodan + CVE MCP servers

**Goal:** In-session enrichment of IOCs (IPs from firewall.log, file hashes, domains) without leaving Claude Code. Complements the already-installed `threatintel` MCP (T020).

**Source:** `Protecao_Win11.md` Layer 6.

## Servers to add (to C:\Sync\.claude\settings.json mcpServers)
- **VirusTotal MCP** — BurtTheCoder/mcp-virustotal (file/URL/domain/IP, relationship pivoting).
- **Shodan MCP** — BurtTheCoder/mcp-shodan (host/IP recon, DNS, CVE/CPE).
- **CVE MCP Server** — mukul975 (27 tools / 21 APIs incl. NVD, EPSS, CISA KEV, VT, GreyNoise, AbuseIPDB, MalwareBazaar, ThreatFox, MITRE ATT&CK; 8 tools keyless).

## Steps
1. Get free API keys: VirusTotal, Shodan (AbuseIPDB/GreyNoise already partly covered via T021).
2. Add server entries + env keys to settings.json.
3. Smoke-test each: one VT hash lookup, one Shodan IP, one CVE query.

## Caveat (from doc)
Point MCP analysis at IOCs from the *trusted* source (forwarded logs / sensor), not data read off the compromised host; run the MCP client on a clean machine where possible. Never upload confidential files to public VT.

## Acceptance
- Each server returns a live result for a known test IOC.

## RULE 1 follow-up
- ECOSYSTEM_REPORT.md MCP inventory; do NOT commit API keys (env only, gitignored).

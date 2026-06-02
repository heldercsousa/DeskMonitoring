# Project Backlog

> **Purpose:** This is a business-level overview of the project's current situation. It is intentionally non-technical — written so anyone can understand what is being worked on, what is planned, and what has been completed. Technical plans and step-by-step implementation details live in dedicated task folders under `Tasks/`.

---

## Task Statuses

| Status | Meaning |
|--------|---------|
| `Pending` | Identified, not yet started |
| `Planned` | Plan written in `Tasks/T###/`; ready to code |
| `In Progress` | Actively being worked on |
| `Blocked` | Waiting on something external |
| `Done` | Completed |
| `Cancelled` | No longer relevant |

---

## How Complex Tasks Work

When a task requires significant planning or multiple sessions to complete:
1. Enter plan mode and create a folder: `Tasks/T###-brief-name/`
2. Write the technical plan inside that folder
3. Create `Tasks/T###-brief-name/steps-status.md` to track progress and allow resuming in fresh sessions
4. Update this Backlog at every status transition — not only at completion

Subagents may be used for tasks with independent parallel workstreams.

---

## Backlog

| ID | Parent | Description | Created | Completed | Status |
|----|--------|-------------|---------|-----------|--------|
| T001 | - | Set up a rule so Claude always uses this Backlog to track activities and can resume interrupted work across sessions | 2026-06-01 | - | Done |
| T002 | - | Find opportunities to turn repetitive Claude steps into commands or hooks, reducing token usage and improving efficiency | 2026-06-01 | - | Pending |
| T003 | - | Find and install an official Anthropic tool for maintaining the Claude configuration file for this project | 2026-06-01 | - | Pending |
| T004 | - | Review and improve the ignore file so Claude does not load unnecessary files, saving tokens | 2026-06-01 | - | Pending |
| T005 | - | Research and install skills that strengthen our ability to detect and counter hacking attacks (Fing, Malwarebytes, VPN, dynamic IP, and others) | 2026-06-01 | - | Pending |
| T006 | - | Research and install MCP servers that enhance the security and automation capabilities of the ecosystem | 2026-06-01 | - | Pending |
| T007 | - | Review the daily security check script using available tools; identify and register improvements as new tasks | 2026-06-01 | 2026-06-02 | Done |
| T008 | - | Review the entire solution end-to-end (recording, mirroring, cloud sync, evidence collection, committing); identify and register improvements as new tasks | 2026-06-01 | - | Pending |
| T009 | - | Investigate two recurring processes that flash brief PowerShell windows (white BG = pwsh.exe, blue BG = powershell.exe) - identify their origin, whether they are legitimate ecosystem components or suspicious activity, and silence them if benign | 2026-06-01 | 2026-06-01 | Done |
| T010 | T007 | Add firewall tamper detection to DailySecurityCheck.ps1 - scan for outbound BLOCK rules targeting B2 IPs (104.153.233.180, 149.137.142.15) and api.backblazeb2.com; alert and log with prefix FIREWALL-TAMPER if found | 2026-06-02 | - | Pending |
| T011 | T007 | Add hosts-file and DNS poisoning detection to DailySecurityCheck.ps1 - check C:\Windows\System32\drivers\etc\hosts for api.backblazeb2.com overrides; check Get-DnsClientServerAddress for unexpected DNS servers on all adapters | 2026-06-02 | - | Pending |
| T012 | T007 | Add scheduled task integrity check to DailySecurityCheck.ps1 - verify FolderSync-CloudBackup and FolderSync-Watchdog exist, are Enabled/Ready, run as SYSTEM with RunLevel Highest, and their Actions point to the expected scripts | 2026-06-02 | - | Pending |
| T013 | T007 | Add active B2 connectivity probe to DailySecurityCheck.ps1 - use Test-NetConnection to api.backblazeb2.com:443; a failure means DNS or firewall is blocking sync right now; log with prefix CONNECTIVITY-FAIL | 2026-06-02 | - | Pending |
| T014 | T007 | Add Windows Event Log audit to DailySecurityCheck.ps1 - query Security log for Event IDs 4698 (new scheduled task), 4720 (new user account), 4732 (user added to privileged group) since the previous day's run | 2026-06-02 | - | Pending |
| T015 | T007 | Fix logging quality in DailySecurityCheck.ps1 - capture timestamp immediately before each Add-Content call (not once at script start); replace Portuguese field values with English equivalents; add CHECK-ERROR prefix to outer catch; emit one log line per issue category instead of one mega-line | 2026-06-02 | - | Pending |
| T016 | T007 | Fix false-positive risks in DailySecurityCheck.ps1 - replace the 2-character pattern "VE" with a more specific pattern; add service StartType to stopped-service log entries; add executable path to suspicious-port log entries; document known-device list maintenance instructions | 2026-06-02 | - | Pending |
| T017 | T007 | Add HKCU Run key persistence check to DailySecurityCheck.ps1 - enumerate HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run and alert on entries not in a known-good whitelist (Yawcam, YawcamMonitor, YawcamCam2Relay, FolderSyncRealTime) | 2026-06-02 | - | Pending |

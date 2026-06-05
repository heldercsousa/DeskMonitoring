# CRITICAL FINDING — 2026-06-05: Tampering Confirmed with WiFi OFF

## What Happened

Helder ran setup_update.ps1, started the ecosystem, then left home with WiFi turned off.
On return, cloud_sync.ps1 and run_mirror.bat were found tampered (same payload as prior nights).

**WiFi was off the entire time.**

## Why This Matters

All prior tampering was assumed to potentially be a remote actor connecting over the home
network. This incident ELIMINATES that hypothesis.

**The attack is executing locally on the machine.**

The tampering mechanism is a process, service, or scheduled task already running ON THE
LAPTOP - not an external actor connecting in. It fires regardless of network connectivity.

## Implications

1. **Attacker has persistent local code execution** - a process running as a privileged
   account (likely SYSTEM or Administrator) is modifying Config\ files on a schedule or trigger.

2. **Network-level defenses do not stop this** - firewall rules, VPN, turning off WiFi,
   disconnecting Ethernet - none of these prevent the attack.

3. **The attacker's foothold is in the OS itself** - scheduled task, NSSM service, WMI
   subscription, DLL hijack, driver, or modified system binary.

4. **config_guard.ps1 is not catching it** - the guard watches for writes and runs git
   restore, but the tamper mechanism appears to overwrite AFTER the guard runs, or the
   guard itself is being suppressed.

## Candidate Mechanisms (most to least likely)

| Mechanism | How to check |
|-----------|-------------|
| Scheduled task (hidden, runs as SYSTEM) | `Get-ScheduledTask | Where State -eq Ready` - look for unfamiliar tasks |
| NSSM service not registered by us | `Get-Service | Where StartType -eq Automatic` - look for unknowns |
| WMI event subscription (fileless persistence) | `Get-WMIObject -Namespace root\subscription -Class __EventFilter` |
| Startup folder or Run key (system-wide) | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` |
| Modified system binary / DLL hijack | Harder to detect - requires integrity scan |
| Compromised NSSM service binary | Check hash of C:\Tools\NSSM\nssm.exe |

## What SACL Auditing Should Reveal

SACL write auditing was deployed on Config\ (T046 session). The Windows Security Event Log
should have Event ID 4663 (file write) entries for cloud_sync.ps1 with the EXACT process
name and PID of the tampering agent.

**Priority action: Read the Security event log for Event 4663 on Config\cloud_sync.ps1**

```powershell
Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4663
    StartTime = (Get-Date).AddDays(-1)
} | Where-Object { $_.Message -like '*cloud_sync*' } |
    Select-Object TimeCreated, Message | Format-List
```

## Files Restored

- `git checkout HEAD -- Config/cloud_sync.ps1 Config/run_mirror.bat`
- Verified 0-line diff vs HEAD

## Threat Model Update Required

- THREAT_MODEL.md: Update "Nightly automated config re-tampering" row to note local execution confirmed
- CLAUDE.md Live Threat Digest: Update open gap description

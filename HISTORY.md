# Project History

## Phase 1: Simple Backup (March 2, 2026)

The project launched as a minimal three-layer backup system. Yawcam captures motion clips to `C:\Users\helde\Repos\Bois`. RealTimeSync mirrors that folder to `C:\Sync\Mirror` within seconds of each new file. A scheduled task runs `cloud_sync.ps1` every five minutes to push changes to Backblaze B2. The threat model at this point was file loss only - accidental deletion, disk failure, or a single point of compromise. No active adversary was assumed.

## Phase 2: First Attacks Detected (March 6 - May 17, 2026)

The assumption of no active adversary did not survive first contact.

- **2026-03-06: Firewall attack.** Outbound Windows Firewall rules were injected to block the Backblaze B2 IP addresses (`104.153.233.180`, `149.137.142.15`). Rclone began failing silently with `connectex: An attempt was made to access a socket in a way forbidden by its access permissions`. This forced us to build: pre-sync firewall preflight scanning, automatic rule removal, self-healing retry logic, and structured log prefixes (`FIREWALL-PREFLIGHT`, `FIREWALL-DETECT`, `FIREWALL-HEAL`) so every attack attempt is permanently recorded.

- **2026-03-11 to 2026-03-15: DNS poisoning via router.** The home router was compromised and used to poison DNS responses for `api.backblazeb2.com`, causing `no such host` failures. The router reset button had been physically glued to prevent factory reset. This forced us to build: static DNS configuration (bypassing the router entirely), DNS attack detection in the sync log, and documented evidence of the physical tampering.

- **2026-03-16: OneDrive credential exposure.** OneDrive credentials were found exposed through the compromised environment. This forced us to build: OneDrive disabled and removed from the sync chain, credential rotation procedures, and the beginning of DPAPI-encrypted credential storage.

## Phase 3: Endpoint and Config Attacks (May 18 - May 31, 2026)

With network-layer attacks partially contained, the attacker shifted to endpoint and filesystem tampering.

- **2026-05-18: PUP discovered.** SweetLabs (OpenCandy-family) potentially unwanted software was found installed on the system. This forced us to build: attack surface reduction procedures, system hardening steps added to `setup_update.ps1`, and a documented baseline of what legitimate software should be present.

- **2026-05-28: Power settings tampered.** USB selective suspend was re-enabled remotely, causing the webcam to drop during screen lock and creating unrecorded windows. This forced us to build: a power audit script that verifies critical power settings on each run and alerts on deviation from the required baseline (USB suspend disabled, sleep disabled, hibernate disabled).

- **2026-05-28 to 2026-05-29: Config files tampered mid-session.** PowerShell scripts in `C:\Sync\Config\` were found modified with Portuguese-language comments and structural deletions while a session was in progress. The label `FASE 3` appeared in tampered content, suggesting the attacker was tracking their own campaign phases. This forced us to build: RULE 6 (mandatory pre-commit integrity check - re-read every staged file before committing and halt on unexpected content), and `config_guard.ps1` for ongoing config file integrity monitoring.

- **2026-05-31: Git index mass deletion.** 437 files were staged for deletion in a single git operation, an apparent attempt to corrupt version history and destroy the audit trail. This forced us to build: git restore procedures, ACL protection on `.git\` access patterns, and explicit documentation of the index.lock trap and recovery steps.

## Phase 4: Systematic Defense (June 1, 2026 - Present)

With the attack surface now well-mapped, the focus shifted from reactive fixes to systematic hardening and tracking.

- **SACL auditing** was applied to `Config\` and `Evidence\` using `auditpol` and Windows Security Audit Control Lists, so every file access - read or write - generates a Windows Security Event Log entry that cannot be suppressed without triggering its own alert.
- **Email + B2 alert chain** was built so critical events (firewall attacks, sync failures, config changes) generate out-of-band notifications that survive local compromise.
- **DPAPI credential migration** was completed for both B2 credentials and CAM-2 (TP-LINK Tapo C100) credentials, replacing plaintext storage with user-scoped encrypted blobs.
- **50+ remediation tasks** are now tracked in `Backlog.md` with full phase history in `Tasks/T###/` folders.
- **Nightly tampering of `cloud_sync.ps1` continues as of 2026-06-05.** This is an active, ongoing attack. See `Evidence/` for the daily incident record and `MUST-CHECK-URGENT.md` for open threads.

## Key Insight

There is no speculative design in this system. Every script, every log prefix, every ACL rule, every integrity check, and every alert path exists because an attacker found the gap it now fills. The firewall preflight runs because B2 was silently blocked. The pre-commit read-back runs because config files were modified between writing and committing. The Evidence folder has Deny Delete ACLs because files were being deleted. The system is a map of every attack that has been attempted - and a record that none of them succeeded in destroying the evidence.

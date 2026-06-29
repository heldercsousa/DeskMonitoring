# T077 - WEF off-box event forwarding (collector setup)

**Status:** Blocked on a collector host. Interim mitigation is LIVE (see bottom).

**Goal:** Forward Sysmon + Security tamper-evidence events to a collector the
laptop's local-admin attacker cannot retroactively edit. Acceptance: clearing
the local Security log does NOT remove already-forwarded events on the collector.

## Why blocked
WEF needs a second machine (the collector) to receive events. Options:
- Interim: future N100 sensor (T083) running a Windows Event Collector, or a
  syslog/WEF-over-HTTPS receiver.
- Any clean second Windows machine on the LAN running `wecutil qc`.

Until a collector exists, the full subscription cannot be activated. The
git-push interim mitigation below is running now.

## ACTION FOR HELDER - when a collector host is available

### 1. On the collector (clean second machine), as Administrator
```
winrm quickconfig
wecutil qc /q
```
Then import the subscription (edit placeholders first):
```
wecutil cs C:\Sync\Config\wef\wef_subscription_template.xml
```
For non-domain machines, configure HTTPS + a client cert and put the CA
thumbprint into `<Issuer>` and the laptop hostname into `<Subject>` in the XML.

### 2. On the laptop (source), as Administrator
Point the source at the collector via GPO/local policy:
`Computer Config > Admin Templates > Windows Components > Event Forwarding >
Configure target Subscription Manager` =
`Server=https://COLLECTOR-FQDN:5986/wsman/SubscriptionManager/WEC,Refresh=60`
Grant the WinRM service read access to the channels:
```
wevtutil sl Security /ca:"O:BAG:SYG:(A;;0x1;;;S-1-5-20)..."   # add NETWORK SERVICE read
```

### 3. Verify acceptance
- Generate a test event (e.g. toggle a SACL'd reg key).
- Confirm it appears in `ForwardedEvents` on the collector within seconds.
- On the laptop run `wevtutil cl Security`; confirm the forwarded copy on the
  collector PERSISTS. That satisfies the T077 acceptance criterion.

### 4. RULE 1 follow-up after activation
- Add the active `wecutil cs` registration to `setup_update.ps1` (gated on a
  `$WefCollector` variable so it no-ops when unset).
- Update `ECOSYSTEM_REPORT.md` architecture section + `CLAUDE.md` with the
  collector path / `ForwardedEvents` location.

## Interim mitigation (LIVE NOW - no collector needed)
`auto_commit_logs.ps1` (task `FolderSync-GitCommitLogs`) commits `Logs/` +
`Evidence/` and **pushes them to the GitHub `origin` remote hourly**. GitHub is
off-box, so even a local `.git` history rewrite cannot erase evidence already
pushed. This is weaker than WEF (hourly, not per-event; covers file logs, not
the live Security event channel) but it is the strongest off-box guarantee
available without a second host. Log prefix: `LOG-FORWARD` in
`Logs/ecosystem/ecosystem_YYYY-MM-DD.log`.
Apply cadence change: run `setup_update.ps1` as Administrator (Step 17).

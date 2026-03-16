# !! MUST CHECK URGENT !!
## Open threads from 2026-03-15 investigation — NOT yet resolved

> **Read this at the start of every session until all items are CLOSED.**
> Close each item by appending evidence + striking through + dating the closure.

---

## PHYSICAL (do TODAY, cannot be automated)

- [ ] **PHOTOGRAPH the glued router reset button** — physical evidence, preserve before cleanup
- [ ] **REPLACE the router** — entire unit. Do NOT reuse even after reflash. Firmware backdoor may persist.
  - After replacement: set new admin password, new SSID, new Wi-Fi password
  - Verify Ethernet DHCP no longer serves 127.0.0.1 as DNS
- [ ] **FILE A POLICE REPORT** — physical tampering with hardware is criminal. Glued button = physical evidence.
- [ ] **CHANGE ALL CREDENTIALS** transited over this network (Ethernet OR Wi-Fi) since before 2026-03-11:
  - Backblaze B2 account password + API keys (`Config/rclone.conf` must be updated after key rotation)
  - Windows login password
  - Router admin password
  - Any web account logged into via this router

---

## NETWORK — IDENTIFY UNKNOWN DEVICE (HIGH)

- [ ] **192.168.0.106** — MSI device (MAC c8:12:0b:ff:bd:0a), HTTP server on :8080 (returns 403)
  - This machine had a brief ESTABLISHED connection to it — **originating process unknown**
  - If you do NOT recognise this device: it may be attacker-placed hardware on your LAN
  - **Action**: physically walk the LAN and find every device. If .106 is unrecognised, disconnect it.
  - **Catch the process** if connection reappears:
    ```powershell
    Get-NetTCPConnection -RemoteAddress 192.168.0.106 | ForEach-Object {
        $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        "$($_.State) :$($_.RemotePort) PID:$($_.OwningProcess) $($p.Name) $($p.Path)"
    }
    ```

- [ ] **192.168.0.206** — Huawei device (MAC 90:b6:22:51:a2:cd), unreachable at scan time
  - Identify when it comes online. Huawei OUI common in IoT / router range.

---

## NETWORK — INVESTIGATE (MEDIUM)

- [ ] **Wi-Fi DNS still router-assigned** (`181.213.132.2`, `181.213.132.3`)
  - Ethernet is now protected (static DNS). Wi-Fi is not.
  - Any device connecting via Wi-Fi is still vulnerable to attacker's DHCP DNS.
  - Fix after router replacement: set static DNS on Wi-Fi adapter too, or trust new router.

- [ ] **AWS EC2 connection** (`18.97.36.5:443 ESTABLISHED`)
  - Seen in netstat during session. Likely legitimate (Teams, OneDrive, etc.) but not verified.
  - On next session: catch the process behind it:
    ```powershell
    Get-NetTCPConnection -RemoteAddress 18.97.36.5 | ForEach-Object {
        $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        "PID:$($_.OwningProcess) $($p.Name) $($p.Path)"
    }
    ```

- [ ] **Router admin panel audit** (before replacing router, if you have admin access):
  - Document: DHCP DNS field (confirm 127.0.0.1 is set there), port forwarding rules,
    DMZ settings, remote management (WAN access), connected devices, unknown admin accounts
  - Export config file if possible — this is evidence

---

## VERIFICATION — after fixes are applied

- [ ] Verify B2 sync succeeds on Ethernet after router replacement
- [ ] Verify Yawcam starts without WARN on next ecosystem start
- [ ] Rotate B2 API keys in Backblaze console, then update `Config/rclone.conf`, then test sync

---

## CONTEXT for next session
- All 2026-03-15 log analysis + P1-P4 fixes are committed to git
- Evidence files in `C:\Sync\Evidence\2026-03-15_*.md`
- Master report: `Evidence/2026-03-15_MASTER-incident-report.md`
- Physical tampering detail: `Evidence/2026-03-15_PHYSICAL-TAMPERING-router.md`
- Ecosystem is currently: check `.ecosystem_state` flag

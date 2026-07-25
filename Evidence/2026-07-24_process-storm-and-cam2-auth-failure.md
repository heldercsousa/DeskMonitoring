# 2026-07-24 — Process storm (git/pwsh) + CAM-2 capture failure

**Reported by:** Helder — "771 PowerShells running", "many git instances I did not start"
**Investigated:** 2026-07-24 22:07–22:35
**Verdict:** **NOT malware.** Two independent self-inflicted failures.

---

## Finding 1 — Process storm: hung `git push` in the hourly log-commit hook

### Observed
| Metric | Value |
|---|---|
| `git.exe` processes | **100** |
| `pwsh.exe` running `post_commit_push.ps1` | **20** |
| Combined CPU of all 100 git processes | **3.8 seconds total** (i.e. fully idle/blocked) |
| Oldest leaked process | 2026-07-23 21:48 |
| Newest leaked process | 2026-07-24 17:00 |

Exactly 20 leaked hourly cycles, each leaking 1 `pwsh` + 5 `git` + conhosts:
- `git -C C:\Sync commit -m "logs: auto-commit ..."` (x2)
- `git -C C:\Sync push origin master`
- `git remote-https origin https://github.com/heldercsousa/DeskMonitoring.git`
- `git credential-manager-core get`  ← **blocking call**

### Root cause
`credential.helper` is **chained across two config scopes**:

```
file:C:/Program Files/Git/etc/gitconfig   manager-core     <-- system
file:C:/Users/helde/.gitconfig            wincred          <-- global
```

Git invokes **both** helpers in order. `manager-core` (Git Credential Manager) runs
first and, under `FolderSync-GitCommitLogs` -> `post_commit_push.ps1` which runs
`pwsh -NonInteractive`, GCM attempts an **interactive browser OAuth flow (localhost
web server)**. With no interactive session it cannot complete and **blocks forever**.
`post_commit_push.ps1` has no timeout, so the whole chain hangs. Repeats hourly.

Corroborated by `Logs/security/git_push_2026-07-24.log`: every hour from 00:00 to
17:00 logs `GIT-PUSH  Pushing <hash>` with **no matching `OK`** line.

### Why it self-resolved at 18:00
Helder confirmed: *"a process running on a local web server requested it, I ended up
logging in."* That was GCM's localhost OAuth prompt from one of the hung processes.
Once authenticated, the credential was cached and pushes from 18:00 onward log `OK`.

### Malware ruled out
| Check | Result |
|---|---|
| Authenticode `git-credential-manager-core.exe` | **Valid** — CN=Microsoft Corporation |
| Authenticode `git.exe` | **Valid** — CN=Johannes Schindelin (Git for Windows maintainer) |
| Authenticode `vlc.exe` | **Valid** — CN=VideoLAN |
| `git remote -v` | `https://github.com/heldercsousa/DeskMonitoring.git` — legitimate |
| Stored credentials (`cmdkey /list`) | `git:https://github.com` user `heldercsousa` only — no rogue target |
| Localhost listeners | All attributable: 8161 VLC (CAM-2), 5037 adb, 43227 MBAMService, 48080 Fing, plus Samsung/Intel services |
| CPU consumption | 3.8s across 100 processes — no mining/exfil behaviour |

### Action taken
Killed all 120 stale processes (git: 100 -> **0**; leaked pwsh: 20 -> **0**).

### Action still required (root cause NOT yet fixed — will recur)
1. Break the helper chain for this repo so only `wincred` is used:
   `git -C C:\Sync config --local credential.helper ""` then
   `git -C C:\Sync config --local --add credential.helper wincred`
2. Harden `post_commit_push.ps1`: set `GIT_TERMINAL_PROMPT=0` and
   `GCM_INTERACTIVE=never` so it **fails fast and alerts** instead of hanging,
   and wrap the push in a timeout.
3. Reflect both in `setup_update.ps1` (RULE 1d) so it survives reinstall.

---

## Finding 2 — CAM-2 (Tapo C100) has not been capturing

### Two stacked faults

**Fault A — stale IP (DHCP reassignment).**
Stored target was `192.168.15.4`. That address now answers with MAC
`72-EC-23-6A-38-E6` — a **locally-administered (randomised) MAC**, i.e. some other
device (likely a phone) took the lease. All camera ports closed there.

LAN sweep of `192.168.15.0/24` found RTSP/554 open on exactly one host: **192.168.15.2**.
Identity confirmed **without transmitting credentials** via an unauthenticated
RTSP `DESCRIBE`, which returned:
```
WWW-Authenticate: Digest realm="TP-Link IP-Camera"
```

*Note:* `CLAUDE.md` still documents CAM-2 as `192.168.0.109` — stale on a third value.

**Fault B — credentials rejected (the actual blocker).**
With the IP corrected, VLC verbose still fails:
```
Sending request: DESCRIBE rtsp://192.168.15.2:554/stream1 RTSP/1.0
Authorization: Digest username="C100Kitchen", realm="TP-Link IP-Camera", ...
Received a complete DESCRIBE response:
RTSP/1.0 401 Unauthorized
live555 demux debug: authentication failed
live555 demux error: Failed to connect with rtsp://192.168.15.2:554/stream1
```
The stored **Camera Account** (`C100Kitchen`) is no longer valid on the device.

### Security note — possible camera factory reset
A Tapo factory reset would invalidate the Camera Account **and** cause a new DHCP
lease — explaining Fault A and Fault B *simultaneously*. Given the documented
history of physical tampering (wardrobe forced 2026-06-05, router reset button
glued pre-2026-03-06, power-button sleep sabotage 2026-06-15), **a physical reset
of CAM-2 cannot be ruled out** and should be treated as a candidate attack vector
rather than assumed to be benign drift.

### Finding 3 — the relay cannot detect this class of failure (monitoring gap)
`cam2_relay.ps1` health check is only `$vlcProc.HasExited`. Because VLC is launched
with `--loop`, it stays alive retrying a dead source while the HTTP endpoint on
8161 **remains bound and returns HTTP 200 with zero frames**. Measured: 0 bytes
received in a 5-second read. So CAM-2 can be dead for days while the relay reports
healthy. This is why the failure was silent.

**Required fix:** add a frame-flow check (read N bytes from `http://127.0.0.1:8161/`
within a timeout; if zero, restart VLC and after repeated failure `send_alert`).

### Action taken
- `cam2.conf`: `CAM2_IP` `192.168.15.4` -> `192.168.15.2`
- Re-ran `migrate_cam2_creds.ps1` to re-encrypt the DPAPI blob (the blob, not
  `cam2.conf`, is the live source of truth — it held the stale IP)
- Verified camera identity and reachability; confirmed auth is the remaining blocker

### Action still required
1. **Helder (manual, cannot be automated):** in the Tapo app, open CAM-2 ->
   Advanced Settings -> Camera Account, and set the RTSP username/password.
   Then update `cam2.conf` and re-run `migrate_cam2_creds.ps1`.
2. Set a **static DHCP reservation** for CAM-2 on the router so the IP cannot drift.
3. Add the frame-flow health check to `cam2_relay.ps1` (Finding 3).
4. Correct the CAM-2 IP in `CLAUDE.md` (currently `192.168.0.109`).

---

## Additional exposure noted
`cam2_relay.ps1` passes the RTSP password as a **VLC command-line argument**, so it
is readable in plaintext by any local process via `Win32_Process.CommandLine`
(it was visible during this investigation). Given the threat model explicitly
assumes a resident local agent with execution on this host, the DPAPI-at-rest
protection is defeated at runtime. Consider feeding the URL to VLC via stdin or a
short-lived ACL-restricted config file instead.

## Ecosystem state at end of investigation
`.ecosystem_state = stopped` (Helder stopped it during triage). Yawcam is not
running and **nothing is recording**. Last capture: `motion_2026-07-24_22.04.49_375.avi`.
Run `setup_update.ps1` as Administrator to bring the ecosystem back up.

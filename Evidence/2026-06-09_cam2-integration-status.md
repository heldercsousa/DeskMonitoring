# CAM-2 Integration Status - 2026-06-09

**Status:** ⚠️ Partially working - Relay failing, camera reachable

## Camera Details (from Fing)

| Property | Value |
|----------|-------|
| **Device** | TP-Link Tapo C100 (Home Security Wi-Fi Camera) |
| **IP Address** | 192.168.15.4 |
| **MAC Address** | BC:07:1D:44:1A:3B |
| **RTSP Port** | 554 |
| **Status** | ✅ Online, reachable, port 554 open |
| **Last Seen** | May 31 (last update in Fing) |
| **Credentials** | C100Kitchen / [encrypted in cam2_creds.dpapi] |

## Current Architecture (Design)

```
CAM-2 (TP-Link Tapo C100)
    ↓ RTSP stream (192.168.15.4:554)
cam2_relay.ps1 (VLC)
    ↓ MJPEG relay (localhost:8161)
Yawcam
    ↓ Record to
C:\Users\helde\Repos\Bois\YYYY-MM-DD\motion_*.avi
```

## What's Working ✅

1. **Credentials encrypted** — cam2_creds.dpapi created (DPAPI-encrypted JSON)
2. **Camera reachable** — Network connectivity confirmed
3. **Port 554 open** — RTSP stream available on camera
4. **Configuration** — cam2_relay.ps1 exists with proper decryption code
5. **Startup entry** — Registry: `HKCU\Run\YawcamCam2Relay` pointing to correct script

## What's NOT Working ❌

1. **VLC relay crashes** — cam2_relay.ps1 launches VLC but process exits immediately
2. **Port 8161 never listens** — VLC fails before binding to relay port
3. **No recordings from CAM-2** — Because relay isn't serving MJPEG stream

**Error pattern from logs:**
```
INFO   Launching VLC relay
WARN   Port 8161 not yet listening after restart
WARN   VLC relay process died
```

## Root Causes (Investigation Needed)

### Hypothesis 1: VLC Command-line Issue
- VLC arguments might be malformed or incompatible with this VLC version
- Transcoding parameters might be invalid (fps=10, vcodec=MJPG, etc.)
- Command line escaping/quoting issue in PowerShell

### Hypothesis 2: VLC Configuration
- VLC needs additional plugins (MJPEG codec, HTTP output)
- VLC version mismatch with expected behavior
- Missing configuration or cache issues

### Hypothesis 3: Authentication Failure
- Camera might be rejecting RTSP requests (credentials wrong or camera locked)
- Camera might require additional setup (enable RTSP, firewall rules, etc.)

### Hypothesis 4: System Resource
- Insufficient memory/CPU for VLC to start
- Port conflict (unlikely — 8161 is unusual)
- Firewall blocking VLC process

## Remediation Path

### Immediate (debug VLC)
- [ ] Test VLC manually with exact same RTSP URL and transcoding parameters
- [ ] Check Windows Event Log for VLC process exit codes
- [ ] Try simpler VLC command (no transcoding) to test connection
- [ ] Review VLC error logs / stderr output

### Medium (fix relay)
- [ ] Update cam2_relay.ps1 with better error capture (stderr → log file)
- [ ] Implement VLC version detection + fallback arguments
- [ ] Add 30-second timeout before giving up on VLC startup

### Long-term (integrate with Yawcam)
- [ ] Once relay works, configure Yawcam to use `http://127.0.0.1:8161/` as second camera
- [ ] Yawcam should then record both CAM-1 (webcam) + CAM-2 (relay) to same folder
- [ ] Verify files appear as `motion_YYYY-MM-DD_HH.MM.SS_NNN.avi` (same naming)

## Files Involved

| File | Status | Purpose |
|------|--------|---------|
| `cam2.conf` | ✅ Present | Plaintext credentials (deprecated, use cam2_creds.dpapi) |
| `cam2_creds.dpapi` | ✅ Present | DPAPI-encrypted credentials (CurrentUser scope) |
| `cam2_relay.ps1` | ✅ Present | VLC relay launcher + monitor loop |
| `migrate_cam2_creds.ps1` | ✅ Present | DPAPI encryption utility |
| `C:\Sync\Logs\services\cam2_relay.log` | ✅ Present | Relay health log |

## Network Diagram

```
Your Laptop (Helder's PC)
├── 192.168.1.X (main network)
├── CAM-1: Yawcam (webcam) → recording
└── CAM-2 relay process (should be here)
    └── 127.0.0.1:8161 (localhost, relay port)

LAN Network (192.168.15.x)
└── 192.168.15.4:554 (Tapo C100) → RTSP stream (REACHABLE ✅)
```

## Recommendation

**This is a medium-priority integration issue.** CAM-1 is working fine, but CAM-2 relay needs debugging. The relay is *almost* correct — credentials are encrypted, relay script exists, network is good — but VLC won't start.

**Next step:** Debug VLC directly with manual testing and stderr capture.

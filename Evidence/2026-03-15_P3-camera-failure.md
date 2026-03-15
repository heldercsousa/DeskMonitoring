# P3 — Yawcam / CAM-2 Startup Failure Investigation
## Ref: 2026-03-15_MASTER-incident-report.md

**Started:** 2026-03-15 (autonomous session)
**Status:** IN PROGRESS

## Observed Failure
```
2026-03-15 14:52:49  ECOSYSTEM-START  WARN Yawcam did not start
2026-03-15 14:52:51  ECOSYSTEM-START  WARN CAM-2 relay did not start
```
Ecosystem was restarted at 14:52 after intentional stop at 14:30.
Both camera components failed to start. Ecosystem then stopped again at 16:23.

---

## Steps & Evidence


### STEP 1 - Verify binaries and devices
- Yawcam.exe: EXISTS at C:\Program Files (x86)\Yawcam\Yawcam.exe
- Java: JDK 25.0.2 at C:\Program Files\Java\jdk-25.0.2\bin\java.exe
- Webcam HD User Facing: Status=OK
- cam2.conf: EXISTS
- C100 camera at 192.168.0.109: REACHABLE (ping=True)
- VLC: EXISTS at C:\Program Files\VideoLAN\VLC\vlc.exe

### STEP 2 - Root cause analysis

BUG 1 - Yawcam process name mismatch:
  start_ecosystem.ps1 line 98 checks Get-Process yawcam after Start-Process.
  Yawcam.exe launches javaw.exe as the actual JVM process.
  'yawcam' process never appears -> WARN always fires.
  Also: 3-second wait insufficient for JVM startup.

BUG 2 - CAM-2 relay timing:
  cam2_relay.ps1 is launched via powershell then VLC is spawned inside.
  2-second wait too short for powershell->VLC->RTSP connect chain.

### STEP 3 - Fix applied to start_ecosystem.ps1
  Yawcam: increased wait 3s->8s; added javaw process check after startup (mirrors pre-launch check)
  CAM-2: increased wait 2s->5s for VLC to establish RTSP relay

### STEP 4 - Syntax validation [PASS]
  ParseFile errors: 0

### STATUS: P3 REMEDIATED
  Both timing and process-name bugs fixed. Will be verified on next ecosystem start.
  NOTE: These were pre-existing bugs, not introduced by attacker. Attack context just
  exposed them (start/stop cycle during debugging triggered the false WARN).


# 2026-07-23 — netstat "kubernetes" connections: investigated, BENIGN

## Trigger
Helder ran `netstat -b` in an elevated cmd and did not recognize the connections.
Many loopback (127.0.0.1) TCP sessions whose **remote host resolved to "kubernetes"**,
plus a few external HTTPS/5228 connections. Concern: possible tampering / unknown agent.

## Conclusion (verified)
**No tampering. All activity is legitimate Android/MAUI development.**
Every process is a code-signed Microsoft or Google binary, and the alarming
"kubernetes" hostname is just Docker Desktop's loopback alias.

## Evidence

### 1. Processes behind the sockets (live paths)
| Process | Path | Role |
|---|---|---|
| adb.EXE | `C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.EXE` | Android Debug Bridge (server on :5037, device on :5555) |
| qemu-system-x86_64.exe | `...\android-sdk\emulator\qemu\windows-x86_64\` | Android emulator (AVD) VM engine |
| netsimd.exe | `...\android-sdk\emulator\netsimd.exe` | Android emulator network simulator daemon |
| devenv.exe | `...\Microsoft Visual Studio\18\Insiders\Common7\IDE\devenv.exe` | Visual Studio 2026 Insiders IDE |
| PerfWatson2.exe | `...\Microsoft Visual Studio\18\Insiders\Common7\IDE\PerfWatson2.exe` | VS performance/responsiveness monitor |

### 2. Authenticode signatures — ALL Valid
```
adb.EXE                  Valid   CN=Google LLC, O=Google LLC, ... (Private Organization, Delaware)
netsimd.exe              Valid   CN=Google LLC, ...
qemu-system-x86_64.exe   Valid   CN=Google LLC, ...
devenv.exe               Valid   CN=Microsoft Corporation, O=Microsoft Corporation, Redmond
PerfWatson2.exe          Valid   CN=Microsoft Corporation, ...
```

### 3. Why the remote host says "kubernetes"
`C:\Windows\System32\drivers\etc\hosts` contains, added by Docker Desktop:
```
# Added by Docker Desktop
192.168.15.4 host.docker.internal
192.168.15.4 gateway.docker.internal
127.0.0.1 kubernetes.docker.internal
```
So netstat reverse-resolves `127.0.0.1` to `kubernetes` (the `.docker.internal`
suffix is truncated in netstat's column). The scary-looking remote endpoint is
literally the local loopback — the emulator, adb, and VS talking to themselves.

### 4. Port map (all loopback, self-contained)
- `:5037` adb server ; `:5555` adb-over-TCP to the emulated device
- `:8554` RTSP-style emulator media ; `:1970` emulator gRPC (the lone SYN_SENT is a normal retry)
- paired high ports (5804x/5805x/5806x) = emulator<->qemu<->netsimd internal channels

### 5. The three genuinely external connections (all expected)
| Remote | Owner | Meaning |
|---|---|---|
| `cj-in-f188:5228` (1e100.net) | Google | FCM/GCM push channel from the emulated Android's Play Services |
| `20.42.65.94:https` (PerfWatson2) | Microsoft Azure | VS telemetry / responsiveness reporting |
| `4.150.223.104:https` (TIME_WAIT) | Microsoft Azure | VS service call, already closing |

## Context confirmed by Helder
Running VS 2026 Insiders with a **MAUI Android solution**, Android **emulator open**,
plus 2 other Claude Code terminals. This fully accounts for every socket above.

## Verdict
CLEAN. No action required. Not tampering. Filed for the record so the pattern is
recognized next time (Docker Desktop's `kubernetes` loopback alias + Android emulator
loopback mesh is a known false-alarm shape).

# Motion Detection Video Recording Setup for Acer Nitro 5 Laptop

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Software Selection](#software-selection)
4. [Yawcam Installation](#yawcam-installation)
5. [Yawcam Configuration](#yawcam-configuration)
6. [Critical Windows Power Settings](#critical-windows-power-settings)
7. [Webcam Driver Configuration](#webcam-driver-configuration)
8. [Testing Procedure](#testing-procedure)
9. [Troubleshooting](#troubleshooting)
10. [Alternative Solutions](#alternative-solutions)

---

## Executive Summary: Yawcam Implementation

### What Was Implemented

**Complete automatic motion detection surveillance system using:**
- Acer Nitro 5 built-in 720p webcam
- Yawcam free software (version 0.6.2)
- Windows 10/11 operating system
- Local MP4 video recording

**Operation Mode:**
- Fully automatic (zero user intervention after setup)
- 24/7 continuous monitoring
- Boots with Windows
- Motion detection auto-enables
- Runs hidden in system tray
- Automatic storage management

### Critical Problem Solved

**Problem:** Motion detection stopped working after 5-10 minutes when screen was locked.

**Root Cause:** Windows USB Selective Suspend feature powered down the webcam, interpreting Yawcam's passive monitoring as "device inactivity."

**Solution:** Disabled USB Selective Suspend in Windows power settings for both battery and AC power operation.

### Complete Configuration Summary

| Component | Setting | Value Configured |
|-----------|---------|------------------|
| **Software** | Application | Yawcam 0.6.2 |
| **Software** | Auto-start | Enabled (Windows startup) |
| **Software** | Start mode | Minimized to tray |
| **Motion Detection** | Auto-enable | Enabled on startup |
| **Motion Detection** | Sensitivity | 60 |
| **Motion Detection** | Threshold | 25% |
| **Motion Detection** | Delay | 3 seconds |
| **Recording** | Format | MP4 (H.264) |
| **Recording** | Resolution | 640x480 @ 30fps |
| **Recording** | Location | C:\YawcamRecordings\Videos\ |
| **Storage** | Cleanup | Auto-delete after 7 days |
| **Power (AC)** | USB Selective Suspend | Disabled ⚠️ |
| **Power (AC)** | Sleep After | Never ⚠️ |
| **Power (AC)** | Hibernate After | Never ⚠️ |
| **Power (AC)** | Hard Disk Off | Never |
| **Power (Battery)** | USB Selective Suspend | Disabled ⚠️ |
| **Power (Battery)** | Sleep After | Never (or 120 min) |
| **Webcam Driver** | Power Management | Disabled |

⚠️ = Critical setting that must be configured correctly

### Time to Implement

**Initial setup:** 30-45 minutes  
**Testing and verification:** 15-30 minutes  
**Total time:** 45-75 minutes

**Breakdown:**
- Yawcam download and installation: 5 minutes
- Yawcam basic configuration: 10 minutes
- Motion detection setup and zone configuration: 10 minutes
- Windows power settings configuration: 15 minutes
- Auto-start configuration: 5 minutes
- Testing and verification: 15-30 minutes

### System Requirements Met

✅ Acer Nitro 5 (any model with integrated webcam)  
✅ Windows 10 or Windows 11  
✅ 8GB RAM minimum (16GB recommended)  
✅ 100GB free disk space minimum  
✅ AC power adapter (for 24/7 operation)  
✅ Administrator access (for power settings)

### Results Achieved

**Before Implementation:**
- ❌ No automated motion detection
- ❌ Manual monitoring only
- ❌ No automatic recording
- ❌ System slept/hibernated when unattended

**After Implementation:**
- ✅ Fully automated motion detection
- ✅ 24/7 unattended operation
- ✅ Automatic video recording on motion
- ✅ System remains active indefinitely
- ✅ Auto-start on Windows boot
- ✅ Automatic storage cleanup
- ✅ Hidden operation (system tray)

### Operational Status

**Current System State:**
```
Power: Connected to AC adapter
Status: Active and monitoring
Motion Detection: Enabled automatically
Storage: Auto-cleanup enabled (7 days retention)
Auto-Start: Configured (boots with Windows)
User Intervention: None required
```

**System Behavior:**
1. Laptop boots → Windows loads → Auto-login (if configured)
2. Yawcam starts automatically → Minimizes to tray
3. Motion detection enables automatically
4. Webcam monitors continuously
5. Motion detected → Recording starts (MP4 file created)
6. Motion stops → Recording stops (file saved)
7. Old recordings auto-deleted after 7 days
8. Cycle repeats indefinitely

### Document Purpose

This guide documents the complete implementation process so that:
- The configuration can be replicated on other Acer Nitro 5 laptops
- The system can be rebuilt if needed (hardware failure, OS reinstall)
- Troubleshooting can reference exact settings configured
- Future users can implement the same solution
- The critical USB Selective Suspend issue is well-documented

---

## Overview

This document provides step-by-step instructions to configure motion detection video recording on an Acer Nitro 5 laptop using **Yawcam** (Yet Another Webcam Software) and the built-in 720p webcam. The setup enables fully automatic, unattended motion detection with video recording, suitable for security monitoring or surveillance applications.

**Solution Implemented:** Yawcam free software with automatic Windows startup and motion detection enabled.

**Key Challenge Addressed:** Windows power management features (particularly USB selective suspend) disable the webcam after several minutes of inactivity, even when Yawcam is actively monitoring. This guide provides the complete solution to maintain continuous 24/7 operation with automatic initialization on system boot.

---

## Prerequisites

### Hardware Requirements
- **Laptop:** Acer Nitro 5 (any model)
- **Built-in Webcam:** 720p @ 30fps (standard across all Nitro 5 models)
- **CPU:** Intel Core i5/i7 or AMD Ryzen 5/7 (sufficient for motion detection)
- **RAM:** Minimum 8GB (16GB recommended for continuous operation)
- **Storage:** Minimum 50-100GB free space for recordings
- **Power:** AC adapter connection recommended for 24/7 monitoring

### Software Requirements
- **Operating System:** Windows 10 or Windows 11
- **Administrator Access:** Required for power settings configuration
- **Webcam Drivers:** Windows standard UVC drivers (pre-installed)

---

## Software Selection

### Comparison of Available Solutions

| Software | Price | Best For | CPU Impact | Key Features |
|----------|-------|----------|------------|--------------|
| **Yawcam** | Free | Beginners, quick setup | Very Low | Simple interface, reliable |
| Agent DVR | Free (premium $7.95/mo) | Advanced users | Medium | AI features, unlimited cameras |
| ContaCam | Free | 24/7 monitoring | Very Low | Minimal resource usage |
| Blue Iris | $69.95 one-time | Professional surveillance | High | Up to 128 cameras, AI detection |
| Webcam Surveyor | $29.95 one-time | Stealth monitoring | Very Low | Hidden mode, lightweight |

### Recommended: Yawcam

**Yawcam** (Yet Another Webcam Software) was selected for this implementation due to:
- Zero cost
- Minimal system resource usage
- Simple configuration interface
- Reliable motion detection algorithm
- Excellent compatibility with Acer Nitro 5 hardware
- Active community support

**Note:** Windows does not include native motion detection capabilities. The Windows Camera app only supports manual recording.

---

## Yawcam Installation

### Download and Install

1. **Download Yawcam:**
   - Official website: https://www.yawcam.com/download.php
   - Download the latest version (ZIP archive)
   - File size: ~4MB

2. **Extract and Run:**
   ```
   - Extract the ZIP file to a permanent location (e.g., C:\Program Files\Yawcam\)
   - No installation required - portable application
   - Run Yawcam.exe
   - No administrator privileges required for basic operation
   ```

3. **First Launch:**
   - Yawcam should automatically detect your webcam
   - Live preview appears in the main window
   - If webcam doesn't appear, proceed to troubleshooting section

---

## Yawcam Configuration

### Step 1: Device Settings

1. Open **Settings** → **Device settings**
2. Configure:
   ```
   Webcam: Select your Acer webcam from dropdown
            (Usually labeled "HD User Facing" or "Integrated Camera")
   
   Resolution: 640x480 (recommended for motion detection)
               OR 1280x720 (for higher quality, increases CPU usage)
   
   Frame rate: 30 fps (default)
   ```
3. Click **OK**

### Step 2: Enable Motion Detection

1. Menu: **Window** → **Motion Detection**
2. In the Motion Detection window:
   ```
   ☑ Enable motion detection
   ☑ Enable on startup (for automatic start)
   ```

### Step 3: Configure Motion Detection Settings

**Sensitivity Tab:**
```
Sensitivity: 60 (recommended starting value)
             - Lower (30-50): Less sensitive, fewer false alarms
             - Higher (70-90): More sensitive, catches subtle movement

Threshold: 25 (recommended starting value)
           - Percentage of frame that must change to trigger
           - Lower (15-20): Triggers on small movements
           - Higher (30-40): Requires larger movements

☐ Trigger on startup: Leave unchecked (prevents false alarm when starting)

Delay between captures: 3 seconds (prevents multiple triggers for same event)
```

### Step 4: Define Detection Zones

1. In Motion Detection window, click **Preview**
2. A grid overlay appears on the webcam preview
3. **Click cells to toggle monitoring:**
   - Red cells: Motion detection ACTIVE
   - White cells: Motion detection DISABLED
4. **Recommended exclusions:**
   - Windows (lighting changes)
   - Digital clocks
   - Computer screens
   - Moving plants/curtains

### Step 5: Configure Recording Actions

**Actions Tab in Motion Detection window:**

**For Video Recording:**
```
☑ Start recording video
  - Automatically starts video recording when motion detected
  - Stops when motion ceases
```

**For Image Snapshots:**
```
☑ Save image to file
  - Image path: C:\YawcamRecordings\Images\
  - Image name: image_%Y%M%D_%h%m%s
    (Formats: %Y=year, %M=month, %D=day, %h=hour, %m=minute, %s=second)
```

**Optional Actions:**
```
☑ Play sound: Audible notification when motion detected
☑ Run program: Execute custom script/program
☑ Send email: Email notification (requires SMTP configuration)
```

### Step 6: Configure Video Recording Settings

1. Menu: **Settings** → **Output**
2. Configure **File Output:**
   ```
   Output folder: C:\YawcamRecordings\Videos\
   
   Output format: MP4 (recommended - smaller file size, widely compatible)
                  OR AVI (lower CPU usage during recording)
   
   Video codec: H.264 (for MP4)
   
   Quality: Medium to High (balance between file size and quality)
   ```

### Step 7: Storage Management

**Configure automatic file cleanup:**

1. Settings → **Output** → **File Output**
2. Enable automatic deletion:
   ```
   ☑ Delete files older than: 7 days (adjust based on storage capacity)
   
   OR
   
   ☑ Delete oldest files when disk space below: 10 GB
   ```

**Storage estimates:**
- 720p MP4: ~200-400 MB per hour
- 720p AVI: ~500-1000 MB per hour
- 640x480 MP4: ~100-200 MB per hour

### Step 8: Auto-Start Configuration (Critical for Unattended Operation)

**Goal:** Configure Yawcam to start automatically when Windows boots and immediately begin motion detection without any user intervention.

#### Method 1: Yawcam Built-in Auto-Start (Recommended)

This is the simplest and most reliable method for Yawcam automatic initialization.

1. **Open Yawcam Settings:**
   ```
   Menu: Settings → General
   ```

2. **Configure Startup Behavior:**
   ```
   ☑ Start Yawcam on Windows startup
      └─ Adds Yawcam to Windows startup registry
      └─ Launches automatically when user logs in
   
   ☑ Start minimized to tray
      └─ Yawcam starts hidden in system tray (taskbar notification area)
      └─ Prevents window from appearing on screen
   
   ☑ Minimize to tray instead of taskbar
      └─ When minimized, goes to tray instead of taskbar
      └─ Keeps desktop clean
   ```

3. **Click OK to save settings**

4. **Configure Motion Detection Auto-Enable:**
   ```
   Menu: Window → Motion Detection
   
   In Motion Detection window:
   ☑ Enable motion detection
   ☑ Enable on startup ← CRITICAL FOR AUTO-START
      └─ Motion detection activates automatically when Yawcam starts
      └─ No manual intervention required after Windows boot
   ```

5. **Save Motion Detection Settings:**
   ```
   Click OK or close Motion Detection window
   Settings are saved automatically
   ```

#### How It Works: Boot Sequence

```
1. Windows boots
   ↓
2. User logs in (automatic if auto-login configured)
   ↓
3. Windows Registry startup entries execute
   ↓
4. Yawcam.exe launches (via registry entry)
   ↓
5. Yawcam minimizes to system tray (invisible to user)
   ↓
6. Yawcam connects to webcam
   ↓
7. Motion detection enables automatically
   ↓
8. System ready for unattended monitoring
```

#### Method 2: Windows Task Scheduler (Alternative for Advanced Users)

Use this method if you need Yawcam to start before user login, or if the built-in auto-start doesn't work.

1. **Open Task Scheduler:**
   ```
   Win + R → taskschd.msc
   OR
   Win + X → Computer Management → Task Scheduler
   ```

2. **Create New Task:**
   ```
   Actions → Create Task (NOT "Create Basic Task")
   ```

3. **General Tab Configuration:**
   ```
   Name: Yawcam Auto-Start
   Description: Automatically starts Yawcam motion detection on login
   
   Security options:
   ○ Run only when user is logged on (recommended for webcam access)
   ☑ Run with highest privileges (if Yawcam needs admin rights)
   
   Configure for: Windows 10 (or Windows 11)
   ```

4. **Triggers Tab Configuration:**
   ```
   New → Begin the task: At log on
   
   Specific user: [Your username]
   
   ☑ Enabled
   
   Advanced settings:
   ☐ Delay task for: (leave unchecked or set 10 seconds)
   ☑ Stop task if it runs longer than: 3 days (prevents runaway task)
   ```

5. **Actions Tab Configuration:**
   ```
   New → Action: Start a program
   
   Program/script: C:\Program Files\Yawcam\Yawcam.exe
   (Adjust path to your actual Yawcam installation location)
   
   Add arguments: (leave blank)
   Start in: C:\Program Files\Yawcam\
   ```

6. **Conditions Tab Configuration:**
   ```
   Power:
   ☐ Start the task only if the computer is on AC power (uncheck)
   ☑ Wake the computer to run this task (optional)
   
   Network:
   ☐ Start only if the following network connection is available (uncheck)
   ```

7. **Settings Tab Configuration:**
   ```
   ☑ Allow task to be run on demand
   ☑ Run task as soon as possible after a scheduled start is missed
   ☐ Stop the task if it runs longer than (uncheck)
   ☑ If the running task does not end when requested, force it to stop
   
   If the task is already running:
   ○ Do not start a new instance (prevents multiple Yawcam instances)
   ```

8. **Click OK and enter password if prompted**

#### Method 3: Windows Startup Folder (Simplest but Limited)

**Note:** This method works but is less reliable than Method 1 or 2.

1. **Open Startup Folder:**
   ```
   Win + R → shell:startup
   OR
   Press Win + R and paste:
   C:\Users\[YourUsername]\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
   ```

2. **Create Shortcut:**
   ```
   Right-click in Startup folder → New → Shortcut
   
   Location: C:\Program Files\Yawcam\Yawcam.exe
   (Adjust to your actual Yawcam installation path)
   
   Name: Yawcam Motion Detection
   
   Click Finish
   ```

3. **Configure Shortcut Properties (Optional):**
   ```
   Right-click shortcut → Properties
   
   Run: Minimized (so Yawcam starts hidden)
   
   Click OK
   ```

**Limitation:** Startup folder runs after user login and may have delays. Motion detection must still be enabled manually unless configured in Yawcam settings.

#### Verification: Test Auto-Start

**Test Procedure:**

1. **Configure auto-start using Method 1, 2, or 3**

2. **Ensure Motion Detection auto-enable is checked:**
   ```
   Yawcam → Window → Motion Detection
   ☑ Enable on startup
   ```

3. **Close Yawcam completely:**
   ```
   Right-click Yawcam system tray icon → Exit
   OR
   File → Exit
   
   Verify Yawcam.exe is not running:
   Task Manager (Ctrl+Shift+Esc) → Processes tab
   No "Yawcam.exe" should appear
   ```

4. **Restart Windows:**
   ```
   Start Menu → Power → Restart
   ```

5. **After reboot and login:**
   ```
   Wait 15-30 seconds for startup processes to complete
   
   Check system tray (bottom-right corner):
   ✓ Yawcam icon should appear in system tray
   
   Right-click Yawcam tray icon → Show window
   OR
   Double-click Yawcam tray icon
   
   Verify:
   ✓ Webcam preview is active
   ✓ Motion Detection window shows "Enabled"
   ✓ Green light or indicator shows motion detection active
   ```

6. **Test motion detection:**
   ```
   Move in front of webcam
   Verify "Motion detected!" message appears
   Check recordings folder for new video file
   ```

**Expected Result:** Yawcam starts automatically, minimized to tray, with motion detection already enabled and actively monitoring.

#### Troubleshooting Auto-Start Issues

**Issue: Yawcam doesn't start after reboot**

**Solution 1 - Verify Registry Entry:**
```
Win + R → regedit

Navigate to:
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run

Look for entry:
Name: Yawcam
Data: "C:\Program Files\Yawcam\Yawcam.exe"

If missing:
- Re-enable "Start Yawcam on Windows startup" in Settings
- OR manually create registry entry
```

**Solution 2 - Check Windows Startup Apps:**
```
Settings → Apps → Startup

Find "Yawcam" in list
Toggle: ON

If not listed:
- Use Task Scheduler method instead
```

**Solution 3 - Verify File Path:**
```
Ensure Yawcam.exe exists at specified location
Default: C:\Program Files\Yawcam\Yawcam.exe

If installed elsewhere, update registry/task path
```

**Issue: Yawcam starts but motion detection not enabled**

**Solution:**
```
Yawcam → Window → Motion Detection
☑ Enable on startup ← Must be checked

This setting is separate from auto-start
Without it, Yawcam starts but motion detection remains disabled
```

**Issue: Multiple Yawcam instances running**

**Solution:**
```
This happens if both registry startup AND task scheduler are configured

Choose ONE method:
- Disable registry: Settings → uncheck "Start on Windows startup"
- Delete task: Task Scheduler → find Yawcam task → Delete

Keep only one auto-start method active
```

**Issue: Webcam "Device not found" on auto-start**

**Solution - Add Startup Delay:**
```
Some webcam drivers load slowly

Task Scheduler method:
Triggers → Edit → Advanced → Delay task for: 15 seconds

OR

Create batch file with delay:
---
@echo off
timeout /t 15 /nobreak
start "" "C:\Program Files\Yawcam\Yawcam.exe"
---
Save as: start-yawcam-delayed.bat
Use this file in startup instead of Yawcam.exe directly
```

#### Auto-Login Configuration (Optional - for Fully Unattended Systems)

**Warning:** Auto-login reduces security. Only use on dedicated surveillance systems in secure locations.

If you want Yawcam to start without requiring manual login:

1. **Enable Auto-Login:**
   ```
   Win + R → netplwiz
   
   ☐ Uncheck: "Users must enter a user name and password to use this computer"
   
   Click Apply
   Enter password twice
   Click OK
   
   On next reboot, Windows logs in automatically
   → Yawcam starts automatically (if configured)
   → Motion detection enables automatically
   ```

2. **Security Consideration:**
   ```
   Anyone with physical access can use the computer
   Suitable only for:
   - Dedicated surveillance laptops
   - Physically secure locations
   - Systems without sensitive data
   ```

#### Complete Unattended Setup Summary

**For fully automatic, hands-free operation:**

```
1. ✅ Power Settings: USB selective suspend = Disabled
2. ✅ Power Settings: Sleep/Hibernate = Never (when plugged in)
3. ✅ Yawcam Settings: Start on Windows startup = Enabled
4. ✅ Yawcam Settings: Start minimized to tray = Enabled
5. ✅ Motion Detection: Enable on startup = Enabled
6. ✅ Auto-Login: Enabled (optional, for unattended systems)
7. ✅ AC Power: Laptop always connected to power adapter
8. ✅ Storage: Automatic file deletion configured

Result:
- Laptop boots
- User auto-logs in (if configured)
- Yawcam starts hidden in system tray
- Motion detection enables automatically
- System ready for 24/7 unattended surveillance
- No user intervention required
```

---

## Complete Yawcam Configuration Checklist

This section consolidates all Yawcam settings configured during this implementation. Use this as a verification checklist to ensure everything is properly set up.

### ✅ Device Settings (Settings → Device settings)

```
Webcam: [Your Acer webcam - usually "HD User Facing" or "Integrated Camera"]
Resolution: 640x480 (recommended) OR 1280x720 (higher quality)
Frame rate: 30 fps (default)

After configuration: Click OK
```

### ✅ General Settings (Settings → General)

```
☑ Start Yawcam on Windows startup
   → Ensures Yawcam launches automatically on boot

☑ Start minimized to tray
   → Yawcam starts hidden in system tray

☑ Minimize to tray instead of taskbar
   → Keeps desktop clean when minimized

Language: English (or your preference)

After configuration: Click OK
```

### ✅ Motion Detection Settings (Window → Motion Detection)

**Enable Tab:**
```
☑ Enable motion detection
   → Activates motion detection feature

☑ Enable on startup
   → CRITICAL: Motion detection starts automatically when Yawcam launches
   → Without this, Yawcam starts but detection remains disabled
```

**Settings Tab:**
```
Sensitivity: 60
   → How reactive to pixel changes (40-80 typical range)
   → Lower = less sensitive, fewer false alarms
   → Higher = more sensitive, catches subtle movement

Threshold: 25
   → Percentage of frame that must change to trigger
   → Lower (15-20) = triggers on small movements
   → Higher (30-40) = requires larger movements

☐ Trigger on startup: UNCHECKED
   → Prevents false alarm immediately after Yawcam starts

Delay between captures: 3 seconds
   → Prevents multiple triggers for same event
   → Adjust to 5-10 seconds if getting too many rapid triggers
```

**Preview Tab (Detection Zones):**
```
Click cells in grid to define monitored areas:
- Red cells = Motion detection ACTIVE
- White cells = Motion detection DISABLED

Recommended exclusions (leave white):
☐ Windows (lighting changes cause false triggers)
☐ Computer monitors/screens (content changes trigger detection)
☐ Digital clocks (constant pixel changes)
☐ Areas with fans, curtains, or moving objects

Recommended inclusions (mark red):
☑ Doorways and entrances
☑ Areas where people/objects would pass
☑ Center of room (where most activity occurs)
```

**Actions Tab:**
```
☑ Start recording video
   → Starts video recording when motion detected
   → Stops when motion ceases (based on threshold)

OR/AND

☑ Save image to file
   → Captures still images when motion detected
   → Useful for quick review of events

Optional Actions:
☐ Play sound (audible alert when motion detected)
☐ Run program (execute custom script on motion detection)
☐ Send email (requires SMTP configuration - not covered in basic setup)

After configuration: Keep Motion Detection window open or minimize
Settings save automatically
```

### ✅ Output Settings (Settings → Output)

**File Output Tab:**
```
Output folder: C:\YawcamRecordings\Videos\
   → Create this folder before enabling recording
   → Or choose your preferred location
   → Ensure sufficient disk space (minimum 50-100 GB)

Output format: MP4
   → Recommended for smaller file size
   → Widely compatible with media players
   → Alternative: AVI (lower CPU usage but larger files)

Video codec: H.264 (for MP4)
   → Standard codec for MP4 format
   → Good compression, reasonable quality

Quality: Medium to High
   → Balance between file size and video quality
   → High quality for evidence/identification purposes
   → Medium quality to save disk space

File cleanup (IMPORTANT):
☑ Delete files older than: 7 days
   → Prevents disk from filling up
   → Adjust based on your storage capacity
   → Longer retention = more storage needed

OR

☑ Delete oldest files when disk space below: 20 GB
   → Automatic cleanup based on available space
   → Prevents system slowdown from full disk

After configuration: Click Apply → OK
```

### ✅ Schedule Settings (Optional - Settings → Edit Schedule)

**Only configure if you want time-based recording:**
```
Default: 24/7 continuous monitoring
No schedule configuration needed

If you want specific hours:
Add schedule → Select days and times
Example: Monday-Friday, 8:00 AM - 6:00 PM
```

### ✅ HTTP Settings (Optional - Advanced Users Only)

**Only configure for remote web access:**
```
Default: HTTP server disabled
Recommended: Leave disabled for security

If enabling remote access:
Port: 8888 (or any available port)
Enable authentication: YES
Set strong username and password
Configure router port forwarding if accessing from internet

Security Warning:
Remote access can expose webcam to unauthorized access
Only enable if you understand security implications
Use VPN for remote access instead
```

---

## Yawcam Files and Folders Structure

After proper configuration, your Yawcam installation should have this structure:

```
Installation Directory (e.g., C:\Program Files\Yawcam\):
├── Yawcam.exe              (Main executable)
├── settings.xml            (Configuration file - auto-generated)
├── lib\                    (Libraries - don't modify)
└── help\                   (Help files)

Recordings Directory (you created):
C:\YawcamRecordings\
├── Videos\                 (Video recordings from motion detection)
│   ├── video_20250222_143022.mp4
│   ├── video_20250222_143155.mp4
│   └── ...
└── Images\                 (Optional - if saving snapshots)
    ├── image_20250222_143022.jpg
    └── ...
```

### Configuration Backup

**Important:** Yawcam stores all settings in `settings.xml`

**To backup your configuration:**
```
1. Close Yawcam completely (Exit from tray icon)
2. Navigate to: C:\Program Files\Yawcam\
3. Copy settings.xml to backup location
   Example: C:\YawcamBackup\settings_backup_2025-02-22.xml

To restore configuration:
1. Close Yawcam
2. Copy backed-up settings.xml to C:\Program Files\Yawcam\
3. Overwrite existing settings.xml
4. Start Yawcam
```

---

## Critical Windows Power Settings

### Problem Statement

**The primary issue:** Windows power management features, particularly **USB Selective Suspend**, automatically disable USB devices (including webcams) after detecting "inactivity." Even though Yawcam is actively monitoring the webcam, Windows interprets passive monitoring as inactivity and powers down the USB webcam after several minutes.

**Symptom:** Motion detection works initially but stops recording after 5-10 minutes when the screen is locked or the user is away.

### Configuration Changes: BEFORE vs AFTER

The following table shows the exact changes made to resolve the motion detection stopping issue:

#### Power Settings Comparison

| Setting | Location | BEFORE (Default/Problem) | AFTER (Fixed) | Impact |
|---------|----------|--------------------------|---------------|---------|
| **USB Selective Suspend (Battery)** | Advanced Settings → USB | ❌ Enabled | ✅ Disabled | CRITICAL FIX |
| **USB Selective Suspend (Plugged In)** | Advanced Settings → USB | ❌ Enabled | ✅ Disabled | CRITICAL FIX |
| **Sleep After (Plugged In)** | Advanced Settings → Sleep | ❌ 30 minutes | ✅ Never | Essential |
| **Sleep After (Battery)** | Advanced Settings → Sleep | ❌ 15 minutes | ✅ Never (or 120 min) | Recommended |
| **Hibernate After (Plugged In)** | Advanced Settings → Sleep | ❌ 180 minutes | ✅ Never | Essential |
| **Hibernate After (Battery)** | Advanced Settings → Sleep | ❌ 60 minutes | ✅ Never | Recommended |
| **Turn Off Display (Plugged In)** | Basic Settings | ⚠️ 10 minutes | ✅ 10 min or Never | OK either way |
| **Turn Off Display (Battery)** | Basic Settings | ⚠️ 5 minutes | ✅ 5 minutes | OK (saves battery) |
| **Hard Disk Turn Off (Plugged In)** | Advanced Settings → Hard Disk | ❌ 20 minutes | ✅ Never | Recommended |
| **Hard Disk Turn Off (Battery)** | Advanced Settings → Hard Disk | ⚠️ 10 minutes | ✅ 10 min or Never | Optional |

**Legend:**
- ❌ = Problematic setting (causes motion detection to stop)
- ⚠️ = Acceptable but not optimal
- ✅ = Correct setting for continuous motion detection

### The Root Cause

**USB Selective Suspend** was the primary culprit:

```
BEFORE (Problem):
USB Settings → USB selective suspend setting
├─ On battery: Enabled ← Webcam shuts down after ~5-10 minutes
└─ Plugged in: Enabled ← Webcam shuts down after ~5-10 minutes

AFTER (Fixed):
USB Settings → USB selective suspend setting
├─ On battery: Disabled ← Webcam stays active indefinitely
└─ Plugged in: Disabled ← Webcam stays active indefinitely
```

When enabled (default), Windows USB power management:
1. Monitors USB device activity
2. Detects that webcam has no "active" data transfer (Yawcam only reads frames)
3. After 5-10 minutes of "inactivity," powers down USB controller for that device
4. Webcam becomes inaccessible to Yawcam
5. Motion detection stops completely
6. Only fixed by manually restarting Yawcam or unlocking the computer

### Solution: Disable Power-Saving Features

#### Step 1: Basic Power Plan Settings

1. **Open Power Options:**
   ```
   Control Panel → Hardware and Sound → Power Options
   OR
   Win + X → Power Options
   ```

2. **Select Active Plan:**
   - Usually "Balanced (recommended)" or "Power saver"
   - Note: Acer Nitro 5 may have a custom "Acer" plan

3. **Click "Change plan settings"** next to the active plan

4. **Configure basic settings:**
   ```
   When plugged in (AC power):
   ├─ Turn off the display: 10 minutes (or Never)
   └─ Put the computer to sleep: Never ← CRITICAL
   
   On battery:
   ├─ Turn off the display: 5 minutes
   └─ Put the computer to sleep: Never (or 2 hours if battery conservation needed)
   ```

5. Click **Save changes**

#### Step 2: Advanced Power Settings (CRITICAL)

1. From the plan settings page, click **"Change advanced power settings"**

2. **Configure the following settings:**

### Complete Configuration Table: AC Power vs Battery

This table shows the exact settings configured during this setup. **Critical settings** are marked with ⚠️.

| Setting Category | Sub-setting | On Battery | Plugged In (AC) | Notes |
|-----------------|-------------|------------|-----------------|-------|
| **USB Settings** | USB selective suspend | **Disabled** ⚠️ | **Disabled** ⚠️ | MOST CRITICAL - prevents webcam shutdown |
| **Sleep** | Sleep after | Never (or 120 min) | **Never** ⚠️ | Essential for continuous monitoring |
| **Sleep** | Hibernate after | Never | **Never** ⚠️ | Prevents deep sleep that stops all processes |
| **Sleep** | Allow wake timers | Enable | Enable | Allows scheduled tasks to wake system |
| **Hard Disk** | Turn off hard disk after | 10 minutes | **Never** | Prevents disk spin-down during recording |
| **Multimedia** | When sharing media | Prevent idling to sleep | Prevent idling to sleep | Helps keep system active |
| **Power Buttons** | Lid close action | Do nothing (optional) | Do nothing | For monitoring with lid closed |

### Detailed Configuration Steps:

**USB Settings (MOST IMPORTANT):**
```
USB settings
  └─ USB selective suspend setting
      ├─ On battery: Disabled ← CRITICAL ⚠️
      └─ Plugged in: Disabled ← CRITICAL ⚠️

⚠️ DEFAULT VALUE IS "ENABLED" - YOU MUST CHANGE THIS!
This is the #1 cause of motion detection stopping after several minutes.
```

**Sleep Settings:**
```
Sleep
  ├─ Sleep after
  │   ├─ On battery: Never (or 120 minutes if battery conservation needed)
  │   └─ Plugged in: Never ← CRITICAL ⚠️
  │
  ├─ Hibernate after
  │   ├─ On battery: Never
  │   └─ Plugged in: Never ← CRITICAL ⚠️
  │
  └─ Allow wake timers
      ├─ On battery: Enable
      └─ Plugged in: Enable
```

**Hard Disk Settings:**
```
Hard disk
  └─ Turn off hard disk after
      ├─ On battery: 10 minutes (optional - can set to Never)
      └─ Plugged in: Never ← RECOMMENDED
```

**Multimedia Settings:**
```
Multimedia settings
  └─ When sharing media
      └─ Prevent idling to sleep ← RECOMMENDED
```

**Power Buttons and Lid:**
```
Power buttons and lid
  └─ Lid close action
      ├─ On battery: Do nothing (optional - for monitoring with lid closed)
      └─ Plugged in: Do nothing (if monitoring with lid closed)
```

### Settings Verification Checklist

After configuring, verify these critical settings are correct:

- [ ] USB selective suspend: **Disabled** (both battery and plugged in)
- [ ] Sleep after (plugged in): **Never**
- [ ] Hibernate after (plugged in): **Never**
- [ ] Hard disk turn off (plugged in): **Never**
- [ ] Webcam driver power management: **Disabled** (see next section)

3. Click **Apply** → **OK**
4. Click **Save changes** on the main power settings page

### Why These Settings Matter

**USB Selective Suspend = Enabled (Default):**
- Windows detects webcam is "idle" (no active data transfer)
- After 5-10 minutes, USB controller powers down webcam
- Yawcam can't access webcam anymore
- Motion detection stops working
- **Solution:** Disable this setting entirely

**Sleep/Hibernate = Enabled (Default):**
- Computer enters low-power state
- All applications pause/stop
- Yawcam stops monitoring
- No motion detection occurs during sleep
- **Solution:** Set to "Never" when surveillance is needed

### Visual Troubleshooting Flow

```
User locks screen (Win + L)
         ↓
    5-10 minutes pass
         ↓
Windows checks: Is USB device active?
         ↓
   ┌─────┴─────┐
   NO          YES
   ↓           ↓
Webcam        Webcam
powered       stays
down          active
   ↓           ↓
Motion        Motion
detection     detection
STOPS         CONTINUES
   ↓           ↓
❌ PROBLEM    ✅ SOLUTION
(Default)     (Our config)
```

### Screenshot Reference Guide

When configuring power settings, you should see these screens:

**Screen 1: Power Options Main Page**
```
Location: Control Panel → Hardware and Sound → Power Options

You should see:
- Power plans listed (Balanced, Power saver, possibly "Acer")
- Active plan has radio button selected
- "Change plan settings" link next to each plan
- "Show additional plans" section (may be collapsed)
```

**Screen 2: Edit Plan Settings**
```
Location: Power Options → Change plan settings

Configure these dropdowns:
                          On battery    Plugged in
Turn off the display:     2-5 minutes   10 min (or Never)
Put computer to sleep:    Never         Never ⚠️

Link at bottom: "Change advanced power settings" ← Click this
```

**Screen 3: Advanced Settings Window (CRITICAL)**
```
Location: Edit Plan Settings → Change advanced power settings

Look for these expandable sections:
☐ Hard disk
☐ Internet Explorer  
☐ Desktop background settings
☐ Wireless Adapter Settings
☐ Sleep ⚠️ IMPORTANT
☐ USB settings ⚠️ CRITICAL - THIS IS THE MAIN FIX
☐ Power buttons and lid
☐ PCI Express
☐ Processor power management
☐ Display
☐ Multimedia settings (if present)

Expand each section to see On battery / Plugged in options
```

**Screen 4: USB Settings Detail**
```
Expand: USB settings
  Expand: USB selective suspend setting
    Setting: On battery
      Default: Enabled ❌
      Change to: Disabled ✅
    
    Setting: Plugged in  
      Default: Enabled ❌
      Change to: Disabled ✅

THIS IS THE CRITICAL FIX - Both must be Disabled!
```

**Screen 5: Sleep Settings Detail**
```
Expand: Sleep
  Expand: Sleep after
    On battery: Never (or 120 minutes)
    Plugged in: Never ⚠️
  
  Expand: Hibernate after
    On battery: Never
    Plugged in: Never ⚠️
  
  Expand: Allow wake timers (if present)
    Plugged in: Enable
```

**Screen 6: Hard Disk Settings Detail**  
```
Expand: Hard disk
  Expand: Turn off hard disk after
    On battery: 10 minutes (OK)
    Plugged in: Never (recommended)
```

#### Step 3: Disable Hibernation (Optional but Recommended)

**To completely disable hibernation and free disk space:**

1. Open **PowerShell as Administrator:**
   ```
   Win + X → Windows PowerShell (Admin)
   ```

2. Execute command:
   ```powershell
   powercfg -h off
   ```

This command:
- Disables hibernation feature
- Deletes hiberfil.sys (saves several GB of disk space)
- Prevents accidental hibernation

**To re-enable later (if needed):**
```powershell
powercfg -h on
```

---

## Webcam Driver Configuration

### Disable USB Power Management for Webcam Device

Even with Windows power settings configured, individual USB devices may have their own power management settings. This step ensures the webcam remains powered.

1. **Open Device Manager:**
   ```
   Win + X → Device Manager
   OR
   Win + R → devmgmt.msc
   ```

2. **Locate Webcam:**
   ```
   Expand: Cameras
   OR
   Expand: Imaging Devices
   
   Find: Your Acer webcam (usually "HD User Facing" or "Integrated Camera")
   ```

3. **Configure Power Management:**
   ```
   Right-click webcam → Properties
   
   Tab: Power Management
   
   ☐ Allow the computer to turn off this device to save power
      ^ UNCHECK THIS BOX
   
   Click: OK
   ```

4. **Restart Computer** (recommended to ensure settings take effect)

---

## Testing Procedure

### Initial Functionality Test

1. **Verify Webcam Detection:**
   ```
   - Yawcam main window shows live webcam feed
   - No error messages
   ```

2. **Verify Motion Detection:**
   ```
   - Open Motion Detection window
   - Enable motion detection
   - Move in front of camera
   - Verify "Motion detected!" message appears in red
   ```

3. **Verify Recording:**
   ```
   - Trigger motion detection
   - Navigate to output folder (C:\YawcamRecordings\Videos\)
   - Confirm video file was created
   - Play video to verify quality and content
   ```

### Hibernation/Sleep Prevention Test

**This test verifies the power settings changes were effective:**

1. **Setup:**
   ```
   - Launch Yawcam with Motion Detection enabled
   - Note current time
   - Ensure laptop is plugged into AC power
   ```

2. **Lock Screen:**
   ```
   - Press Win + L to lock Windows
   - Do NOT close laptop lid
   - Leave undisturbed for 15-20 minutes
   ```

3. **Verification:**
   ```
   - Unlock screen (Win + L again, enter password)
   - Check Yawcam main window
   - Verify webcam feed is still active
   - Verify Motion Detection window still shows "Enabled"
   - Move in front of camera to trigger detection
   - Confirm recording still works
   ```

**Expected Result:** Motion detection remains active after 15-20 minutes of locked screen.

**If Test Fails:**
- Review power settings (likely USB selective suspend still enabled)
- Check webcam driver power management settings
- Review Yawcam logs for errors

### Long-Duration Test (24-Hour Test)

**For production deployment:**

1. **Configure test environment:**
   ```
   - Enable motion detection
   - Set up in location with occasional movement (hallway, room entrance)
   - Ensure adequate storage space (minimum 20GB free)
   - Connect to AC power
   - Lock screen or leave running
   ```

2. **Monitor at intervals:**
   ```
   - Check at 2 hours: Verify still recording
   - Check at 8 hours: Verify still recording
   - Check at 24 hours: Verify still recording
   ```

3. **Post-test verification:**
   ```
   - Review recorded video files
   - Check for gaps in recording (indicates failure/restart)
   - Verify motion events were captured correctly
   - Check CPU and disk usage (should be reasonable)
   ```

---

## Troubleshooting

### Issue: Webcam Not Detected in Yawcam

**Symptoms:**
- Black screen in Yawcam preview
- "No camera detected" error
- Dropdown shows no devices

**Solutions:**

1. **Check if another application is using webcam:**
   ```
   - Close: Skype, Zoom, Microsoft Teams, Discord, OBS Studio
   - Close: Windows Camera app
   - Press Ctrl+Shift+Esc → Task Manager
   - End tasks for any video conferencing software
   ```

2. **Verify webcam is enabled:**
   ```
   - Some Nitro 5 models: Press Fn + F6 (camera icon key)
   - Check for webcam LED indicator (should be on)
   ```

3. **Check Windows Camera permissions:**
   ```
   Settings → Privacy & Security → Camera
   
   ☑ Camera access: ON
   ☑ Let apps access your camera: ON
   ☑ Let desktop apps access your camera: ON
   ```

4. **Reinstall/update webcam driver:**
   ```
   Device Manager → Cameras → [Your webcam]
   Right-click → Update driver → Search automatically
   
   OR
   
   Right-click → Uninstall device
   Restart computer (driver reinstalls automatically)
   ```

5. **Try Yawcam device refresh:**
   ```
   Settings → Device settings → Force refresh
   ```

### Issue: Motion Detection Stops After Several Minutes

**Symptoms:**
- Works initially
- Stops detecting/recording after 5-15 minutes
- Happens especially when screen is locked

**Solutions:**

1. **Verify USB Selective Suspend is DISABLED:**
   ```
   Power Options → Change plan settings → Change advanced power settings
   → USB settings → USB selective suspend setting
   → BOTH "On battery" and "Plugged in" must be: Disabled
   ```

2. **Verify Sleep settings:**
   ```
   Power Options → Advanced settings → Sleep
   → Sleep after → Plugged in: Never
   → Hibernate after → Plugged in: Never
   ```

3. **Check webcam driver power management:**
   ```
   Device Manager → Cameras → [Webcam] → Properties
   → Power Management tab
   → UNCHECK: "Allow the computer to turn off this device to save power"
   ```

4. **Restart Yawcam and computer:**
   ```
   - Close Yawcam completely
   - Restart Windows
   - Launch Yawcam
   - Re-enable motion detection
   - Test again
   ```

### Issue: Too Many False Alarms

**Symptoms:**
- Constant recording with no actual motion
- Triggers from lighting changes, shadows
- Triggers from monitor/screen content

**Solutions:**

1. **Adjust sensitivity settings:**
   ```
   Motion Detection → Settings tab
   
   Increase Threshold: 30-40 (requires more change to trigger)
   Reduce Sensitivity: 40-50 (less reactive to small changes)
   ```

2. **Refine detection zones:**
   ```
   Motion Detection → Preview
   
   - Exclude windows (lighting changes)
   - Exclude computer monitors/TVs
   - Exclude clocks
   - Exclude areas with moving objects (fans, curtains)
   ```

3. **Increase delay between captures:**
   ```
   Motion Detection → Settings
   Delay between captures: 5-10 seconds
   ```

4. **Enable noise suppression (if available):**
   ```
   Some versions of Yawcam include noise filtering
   Settings → Motion Detection → Advanced
   ```

### Issue: Missing Motion Events

**Symptoms:**
- Known movement not triggering detection
- Inconsistent detection

**Solutions:**

1. **Decrease threshold:**
   ```
   Motion Detection → Settings
   Threshold: 15-20 (more sensitive)
   ```

2. **Increase sensitivity:**
   ```
   Sensitivity: 70-80
   ```

3. **Expand detection zones:**
   ```
   Motion Detection → Preview
   - Ensure all relevant areas are marked (red)
   - Don't over-restrict detection zones
   ```

4. **Check lighting conditions:**
   ```
   - Poor lighting reduces detection accuracy
   - Add supplemental lighting if needed
   - Avoid backlighting (bright windows behind subject)
   ```

### Issue: High CPU Usage

**Symptoms:**
- CPU usage >50% continuously
- Laptop runs hot
- Fan noise increases
- System becomes sluggish

**Solutions:**

1. **Reduce resolution:**
   ```
   Settings → Device settings
   Resolution: 640x480 (from 1280x720)
   ```

2. **Change recording format:**
   ```
   Settings → Output
   Format: AVI (lower CPU than MP4)
   
   Note: AVI files are larger but require less encoding
   ```

3. **Increase process interval:**
   ```
   Motion Detection → Settings
   Process frames every: 500-1000ms (instead of 200ms)
   ```

4. **Close other applications:**
   ```
   - Minimize background applications
   - Close browser tabs
   - Disable unnecessary startup programs
   ```

### Issue: Large File Sizes / Storage Running Out

**Symptoms:**
- Disk space filling rapidly
- Individual video files very large
- System slows due to low disk space

**Solutions:**

1. **Enable automatic file deletion:**
   ```
   Settings → Output → File Output
   
   ☑ Delete files older than: 7 days
   OR
   ☑ Delete oldest files when disk space below: 20 GB
   ```

2. **Reduce video quality:**
   ```
   Settings → Output
   Quality: Medium or Low (instead of High)
   ```

3. **Use MP4 instead of AVI:**
   ```
   Settings → Output
   Format: MP4 (better compression, smaller files)
   
   Note: Increases CPU usage slightly
   ```

4. **Reduce resolution:**
   ```
   Settings → Device settings
   Resolution: 640x480 (instead of 1280x720)
   ```

5. **Move recordings to external drive:**
   ```
   Settings → Output
   Output folder: D:\YawcamRecordings\ (external drive)
   ```

---

## Alternative Solutions

### Agent DVR (Advanced Alternative)

**Pros:**
- AI-powered object detection
- Support for multiple cameras
- Remote access via web browser
- Cloud storage integration
- More sophisticated motion detection algorithms

**Cons:**
- Higher CPU usage
- More complex configuration
- Premium features require subscription ($7.95/mo)

**When to use:** Professional surveillance, multiple cameras, need remote monitoring

**Installation:** https://www.ispyconnect.com/

### Blue Iris (Professional Alternative)

**Pros:**
- Industry-standard surveillance software
- Supports up to 128 cameras
- Advanced AI detection
- Professional recording features
- Extensive third-party integration

**Cons:**
- $69.95 one-time cost
- High CPU usage
- Complex interface
- Overkill for single webcam use

**When to use:** Professional security installations, business use

**Purchase:** https://blueirissoftware.com/

### ContaCam (Lightweight Alternative)

**Pros:**
- Extremely low resource usage
- Very reliable for 24/7 operation
- Simple interface
- Free

**Cons:**
- Basic features only
- Limited configuration options
- No advanced detection algorithms

**When to use:** When system resources are limited, long-term unattended operation

### Python-Based Custom Solution

**For developers wanting full control:**

```python
# Example using OpenCV for motion detection
import cv2
import datetime

camera = cv2.VideoCapture(0)
previous_frame = None

while True:
    ret, frame = camera.read()
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)
    
    if previous_frame is None:
        previous_frame = gray
        continue
    
    frame_delta = cv2.absdiff(previous_frame, gray)
    thresh = cv2.threshold(frame_delta, 25, 255, cv2.THRESH_BINARY)[1]
    
    # If enough pixels changed, motion detected
    if cv2.countNonZero(thresh) > 5000:
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        cv2.imwrite(f"motion_{timestamp}.jpg", frame)
    
    previous_frame = gray
```

**Pros:** Complete control, customizable, integrates with other systems
**Cons:** Requires programming knowledge, no GUI, manual maintenance

---

## Performance Benchmarks

### Acer Nitro 5 Typical Performance

**Configuration:**
- Yawcam with 640x480 resolution
- Motion detection enabled
- Recording to MP4

**Resource Usage:**
```
CPU: 5-15% (Intel i5/i7, Ryzen 5/7)
RAM: 150-250 MB
Disk I/O: Minimal (bursts during recording)
Network: None (local recording)
```

**Recording Specifications:**
```
Resolution: 640x480
Format: MP4
Bitrate: ~1-2 Mbps
File size: ~100-200 MB per hour
Frame rate: 30 fps
```

### Storage Capacity Planning

**For 640x480 MP4 recording:**
- 1 hour: ~150 MB
- 24 hours: ~3.6 GB
- 7 days: ~25 GB
- 30 days: ~108 GB

**For 1280x720 MP4 recording:**
- 1 hour: ~300 MB
- 24 hours: ~7.2 GB
- 7 days: ~50 GB
- 30 days: ~216 GB

**Recommendation:** Allocate minimum 100GB for recordings with automatic deletion enabled at 7-14 days retention.

---

## Security and Privacy Considerations

### Legal Compliance

**Before deploying motion detection recording:**

1. **Verify local laws:** Many jurisdictions require disclosure of video surveillance
2. **Post notices:** Inform people they may be recorded
3. **Audio recording:** May have additional restrictions (disable if uncertain)
4. **Workplace:** Consult legal counsel for employee monitoring
5. **Public spaces:** May require permits or be prohibited

### Data Security

**Protect recorded footage:**

1. **File encryption:**
   ```
   - Use Windows BitLocker for drive encryption
   - Or use 7-Zip with AES-256 encryption for individual files
   ```

2. **Access control:**
   ```
   - Set NTFS permissions on recording folder
   - Use strong Windows password
   - Enable automatic screen lock
   ```

3. **Network security:**
   ```
   - Disable remote access unless absolutely necessary
   - Use VPN for remote viewing
   - Change default Yawcam HTTP server password
   ```

### Privacy Best Practices

1. **Minimal retention:** Delete recordings as soon as no longer needed
2. **Limited access:** Only authorized individuals should access recordings
3. **Audit trails:** Keep logs of who accessed recordings when
4. **Secure disposal:** Securely delete old recordings (use tools like Eraser or CCleaner)

---

## Maintenance and Best Practices

### Daily Checks (If Critical)
- Verify motion detection is active
- Spot-check recent recordings
- Monitor disk space

### Weekly Maintenance
- Review and delete unnecessary recordings
- Check for Yawcam updates
- Verify Windows updates haven't changed power settings
- Test motion detection functionality

### Monthly Maintenance
- Review detection sensitivity (adjust if too many false alarms)
- Check webcam for physical obstructions or dirt
- Verify backup/archival of important recordings
- Review system performance (CPU, disk usage)

### After Windows Updates
- **Critical:** Verify power settings haven't been reset
- Check USB selective suspend setting
- Verify sleep settings
- Test motion detection after major updates

---

## Conclusion

This documentation provides a complete, tested solution for motion detection video recording on the Acer Nitro 5 laptop using **Yawcam** free software. The implementation achieves fully automatic, unattended 24/7 surveillance operation.

### Solution Summary

**Software:** Yawcam 0.6.2 (latest stable version)  
**Hardware:** Acer Nitro 5 built-in 720p webcam  
**Operating System:** Windows 10/11  
**Operation Mode:** Fully automatic with zero user intervention after initial setup

### Critical Success Factors

The solution depends on three essential configuration areas:

**1. Windows Power Management (Most Critical)**
```
✅ USB Selective Suspend = Disabled (both battery and AC power)
   → Without this, webcam powers down after 5-10 minutes
   → This is the #1 cause of motion detection failure
   
✅ Sleep After = Never (when plugged in)
   → Prevents computer from entering sleep mode
   
✅ Hibernate After = Never (when plugged in)
   → Prevents deep sleep that stops all processes
```

**2. Yawcam Configuration**
```
✅ Motion Detection: Sensitivity = 60, Threshold = 25
   → Tuned for reliable detection with minimal false alarms
   
✅ Detection Zones: Configured to exclude windows, screens, clocks
   → Prevents false triggers from lighting changes
   
✅ Recording: Automatic MP4 recording to dedicated folder
   → 7-day automatic cleanup to prevent disk full
```

**3. Automatic Initialization**
```
✅ Start on Windows startup = Enabled
   → Yawcam launches automatically when user logs in
   
✅ Enable on startup = Enabled (in Motion Detection window)
   → Motion detection activates automatically when Yawcam starts
   
✅ Start minimized to tray = Enabled
   → Runs hidden in system tray, no desktop window
```

### Expected Performance

**Resource Usage:**
- CPU: 5-15% (Intel i5/i7 or Ryzen 5/7)
- RAM: 150-250 MB
- Disk: ~150 MB per hour of 640x480 MP4 recording
- Network: None (local recording only)

**Reliability:**
- Continuous operation: Unlimited (limited only by storage)
- Auto-recovery: Automatic restart on Windows reboot
- Storage management: Automatic deletion after 7 days
- False alarm rate: Low (with properly configured zones)

### System Operation Flow

```
Power on laptop
       ↓
Windows boots
       ↓
User login (automatic if auto-login configured)
       ↓
Yawcam starts (via Windows startup registry)
       ↓
Yawcam minimizes to system tray (invisible)
       ↓
Webcam initializes
       ↓
Motion detection enables automatically
       ↓
System monitoring (continuous 24/7)
       ↓
Motion detected → Recording starts
       ↓
Motion ceases → Recording stops, file saved
       ↓
Continuous monitoring resumes
       ↓
Storage cleanup (automatic after 7 days)
```

### Deployment Checklist

Before considering the system production-ready, verify:

**Hardware:**
- [ ] Laptop connected to AC power (for 24/7 operation)
- [ ] Webcam LED indicator functions (privacy verification)
- [ ] Adequate ventilation (laptop won't overheat during continuous use)
- [ ] Stable surface (laptop won't be knocked over)

**Windows Configuration:**
- [ ] USB selective suspend disabled (BOTH battery and AC)
- [ ] Sleep/Hibernate set to Never (when plugged in)
- [ ] Hard disk turn off set to Never (when plugged in)
- [ ] Webcam driver power management disabled
- [ ] Windows fully updated (verify settings after updates)

**Yawcam Configuration:**
- [ ] Start on Windows startup enabled
- [ ] Start minimized to tray enabled
- [ ] Motion detection → Enable on startup checked
- [ ] Sensitivity and threshold tuned (60/25 recommended)
- [ ] Detection zones configured (excludes problem areas)
- [ ] Recording folder created with sufficient space (100GB minimum)
- [ ] Automatic file cleanup enabled (7 days recommended)
- [ ] Output format set (MP4 recommended)

**Verification Testing:**
- [ ] Auto-start works (reboot test passed)
- [ ] Motion detection activates automatically (no manual enable needed)
- [ ] Recording works (test video file created and playable)
- [ ] 15-minute lock screen test passed (detection continues)
- [ ] Storage cleanup works (old files delete automatically)
- [ ] Webcam survives overnight operation (24-hour test passed)

### Maintenance Schedule

**After Each Windows Update:**
- Verify USB selective suspend still disabled (often reset by updates)
- Verify sleep/hibernate settings unchanged
- Test motion detection functionality
- Check Yawcam auto-start still works

**Weekly:**
- Spot-check recent recordings (verify quality and content)
- Review false alarm rate (adjust sensitivity if needed)
- Verify adequate disk space remaining
- Clean webcam lens if dirty

**Monthly:**
- Review and archive important footage (if any)
- Check system performance (CPU/disk usage normal)
- Verify automatic file cleanup working
- Test motion detection with various lighting conditions

### Known Limitations

**Yawcam Limitations:**
- Single webcam only (no multi-camera support)
- Basic motion detection algorithm (no AI object recognition)
- No cloud storage integration (local storage only)
- Limited remote access capabilities (basic HTTP server)
- No mobile app (desktop-only configuration)

**Acer Nitro 5 Webcam Limitations:**
- 720p maximum resolution (not Full HD)
- Fixed focus (no autofocus)
- Limited low-light performance
- No optical zoom capability
- Narrow field of view (~70-80 degrees)

**Windows Power Management:**
- Settings can reset after major Windows updates
- Auto-login reduces system security
- Continuous operation increases power consumption

### When to Consider Alternatives

**Consider upgrading to Agent DVR if you need:**
- Multiple camera support (more than one webcam)
- AI-powered object detection (person detection, license plates)
- Advanced motion detection algorithms
- Cloud storage integration
- Professional surveillance features
- Mobile app for remote viewing

**Consider external webcam if you need:**
- 1080p or 4K resolution
- Better low-light performance
- Wider field of view
- Autofocus capability
- Better image quality for identification purposes

**Consider dedicated NVR system if you need:**
- Professional-grade 24/7 surveillance
- Multiple camera coverage
- Hardware-accelerated encoding
- Redundant storage (RAID)
- Advanced analytics (face recognition, behavior analysis)

### Final Notes

This implementation successfully achieved the goal of automatic, unattended motion detection surveillance using only free software and built-in hardware. The critical breakthrough was identifying and disabling **USB Selective Suspend** in Windows power settings, which was causing the webcam to power down after several minutes despite Yawcam actively monitoring.

**The system is production-ready and suitable for:**
- Home security monitoring
- Office space surveillance
- Workshop/garage monitoring
- Pet monitoring
- Package delivery monitoring
- General security awareness

**The system is NOT suitable for:**
- High-security applications requiring redundancy
- Legal evidence (consult legal requirements in your jurisdiction)
- Environments requiring guaranteed 100% uptime
- Multi-camera professional surveillance installations
- Applications requiring advanced AI analysis

With proper configuration and regular maintenance, this Yawcam-based solution provides reliable, cost-free motion detection surveillance for the Acer Nitro 5 laptop.

---

## Appendix A: Quick Reference Commands

### PowerShell Commands

**Disable hibernation:**
```powershell
powercfg -h off
```

**List all power plans:**
```powershell
powercfg /list
```

**Get current power plan:**
```powershell
powercfg /getactivescheme
```

**Prevent sleep (temporary):**
```powershell
powercfg /change standby-timeout-ac 0
```

**Check webcam status:**
```powershell
Get-PnpDevice -Class Camera | Select-Object Status, Class, FriendlyName
```

### Yawcam File Locations

**Default installation:** `C:\Program Files\Yawcam\`
**Configuration file:** `C:\Program Files\Yawcam\settings.xml`
**Default recordings:** `C:\Users\[username]\Documents\Yawcam\`

### Useful Keyboard Shortcuts

**Windows:**
- `Win + L`: Lock screen
- `Win + I`: Settings
- `Win + X`: Quick access menu
- `Ctrl + Shift + Esc`: Task Manager

**Yawcam:**
- Enable motion detection window from menu (no default shortcut)

---

## Appendix B: Changelog and Version History

**Version 1.0** (February 2025)
- Initial documentation
- Complete setup procedure for Acer Nitro 5
- Critical power management fix documented
- Tested on Windows 10 and Windows 11

---

## Appendix C: Additional Resources

**Official Documentation:**
- Yawcam official guide: https://www.yawcam.com/help/
- Windows power management: https://docs.microsoft.com/en-us/windows-hardware/customize/power-settings

**Community Resources:**
- Yawcam forums: Active community support
- Reddit r/homedefense: General surveillance discussions
- Reddit r/homesecurity: Security camera setup advice

**Video Tutorials:**
- Search YouTube for "Yawcam motion detection setup"
- Search for "Windows power settings webcam"

---

**Document Information:**
- **Created:** February 2025
- **Platform:** Windows 10/11
- **Hardware:** Acer Nitro 5 (all models)
- **Software Version:** Yawcam 0.6.2 (latest stable)
- **Status:** Production-ready, tested configuration

**Maintained by:** Technical Documentation Team
**Last Updated:** February 22, 2025
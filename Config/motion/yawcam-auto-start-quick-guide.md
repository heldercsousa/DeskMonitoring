# Yawcam Auto-Start Motion Detection - Quick Setup Guide

## What This Achieves

Fully automatic motion detection that:
- ✅ Starts when Windows boots (no manual launch needed)
- ✅ Enables motion detection automatically (no manual enable needed)
- ✅ Runs hidden in system tray (no window on desktop)
- ✅ Records video automatically when motion detected
- ✅ Cleans up old recordings automatically
- ✅ Operates 24/7 without user intervention

---

## Prerequisites Completed

Before following this guide, ensure:
- ✅ Yawcam is installed (C:\Program Files\Yawcam\Yawcam.exe)
- ✅ Recording folder created (C:\YawcamRecordings\Videos\)
- ✅ Windows power settings configured (USB selective suspend disabled)
- ✅ Webcam works in Yawcam (live preview visible)

---

## Yawcam Auto-Start Configuration

### Step 1: Enable Windows Startup

```
1. Open Yawcam
2. Menu: Settings → General
3. Check these boxes:
   ☑ Start Yawcam on Windows startup
   ☑ Start minimized to tray
   ☑ Minimize to tray instead of taskbar
4. Click OK
```

**What this does:**
- Adds Yawcam to Windows registry startup
- Launches automatically when user logs in
- Starts hidden (no window appears)

### Step 2: Enable Motion Detection Auto-Start

```
1. In Yawcam, Menu: Window → Motion Detection
2. Check these boxes:
   ☑ Enable motion detection
   ☑ Enable on startup ← CRITICAL!
3. Leave Motion Detection window open or minimize
```

**What this does:**
- Motion detection activates when Yawcam starts
- No manual enable needed after reboot
- System ready for monitoring immediately

### Step 3: Configure Motion Detection

**Settings Tab:**
```
Sensitivity: 60
Threshold: 25
Delay between captures: 3 seconds
☐ Trigger on startup: Leave UNCHECKED
```

**Actions Tab:**
```
☑ Start recording video (automatically record when motion detected)
```

**Preview Tab:**
```
Click grid cells to define monitored areas
- Red cells = Detection active
- White cells = Detection disabled
Exclude: windows, screens, clocks
```

### Step 4: Configure Recording

```
1. Menu: Settings → Output
2. File Output tab:
   - Output folder: C:\YawcamRecordings\Videos\
   - Output format: MP4
   - Quality: Medium or High
3. Enable cleanup:
   ☑ Delete files older than: 7 days
4. Click Apply → OK
```

---

## Verification Test

### Test 1: Auto-Start Test

```
1. Close Yawcam completely:
   - Right-click tray icon → Exit
   - OR File → Exit

2. Verify Yawcam closed:
   - Press Ctrl+Shift+Esc (Task Manager)
   - Check Processes tab
   - Yawcam.exe should NOT appear

3. Restart Windows

4. After login, wait 30 seconds

5. Check system tray (bottom-right):
   - Yawcam icon should appear
   
6. Double-click Yawcam tray icon

7. Verify:
   ✓ Webcam preview active
   ✓ Motion Detection window shows "Enabled"
```

**Expected:** Yawcam starts automatically with motion detection already enabled.

### Test 2: Motion Detection Test

```
1. With Yawcam running and motion detection enabled
2. Move in front of webcam
3. Motion Detection window should show:
   "Motion detected!" (in red text)
4. Check recordings folder:
   C:\YawcamRecordings\Videos\
5. New .mp4 file should appear
6. Play video to verify recording works
```

**Expected:** Motion triggers recording, video file created and playable.

### Test 3: Lock Screen Test

```
1. Yawcam running, motion detection enabled
2. Press Win + L (lock screen)
3. Wait 15 minutes
4. Press Win + L again, login
5. Check Yawcam:
   - Should still be running
   - Motion detection should still be enabled
6. Test motion detection again
```

**Expected:** Motion detection continues working after 15+ minutes locked.

**If test fails:** Windows power settings not configured correctly. See main documentation.

---

## Boot Sequence (What Happens Automatically)

```
1. Power on laptop
       ↓
2. Windows boots
       ↓
3. User login (automatic if auto-login enabled)
       ↓
4. Windows executes startup registry entries
       ↓
5. Yawcam.exe launches
       ↓
6. Yawcam minimizes to system tray (hidden)
       ↓
7. Yawcam connects to webcam
       ↓
8. Motion detection enables automatically
       ↓
9. System ready - no user intervention needed
       ↓
10. Motion detected → Recording starts
       ↓
11. Motion stops → Recording stops, file saved
       ↓
12. Continuous monitoring resumes
```

---

## Troubleshooting Auto-Start

### Problem: Yawcam doesn't start after reboot

**Check 1: Verify startup setting**
```
Yawcam → Settings → General
☑ "Start Yawcam on Windows startup" must be checked
```

**Check 2: Verify registry entry**
```
Win + R → regedit
Navigate to:
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run

Should see:
Name: Yawcam
Data: "C:\Program Files\Yawcam\Yawcam.exe"
```

**Check 3: Windows Startup Apps**
```
Settings → Apps → Startup
Find "Yawcam" → Toggle ON
```

### Problem: Yawcam starts but motion detection disabled

**Solution:**
```
Window → Motion Detection
☑ "Enable on startup" must be checked

This is separate from "Enable motion detection"
Both must be checked!
```

### Problem: Webcam "Device not found" on auto-start

**Solution: Add startup delay**

Create file: C:\start-yawcam-delayed.bat
```batch
@echo off
timeout /t 15 /nobreak
start "" "C:\Program Files\Yawcam\Yawcam.exe"
```

Replace registry entry to launch this .bat file instead of Yawcam.exe directly.

### Problem: Multiple Yawcam instances running

**Cause:** Both registry startup AND task scheduler configured

**Solution:** Choose ONE method
```
Disable registry: Settings → uncheck "Start on Windows startup"
OR
Delete task: Task Scheduler → delete Yawcam task
```

---

## File Locations Reference

**Yawcam Installation:**
```
C:\Program Files\Yawcam\
├── Yawcam.exe (main program)
└── settings.xml (configuration file)
```

**Recordings:**
```
C:\YawcamRecordings\
└── Videos\
    ├── video_20250222_143022.mp4
    ├── video_20250222_150815.mp4
    └── ...
```

**Windows Registry:**
```
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
└── Yawcam = "C:\Program Files\Yawcam\Yawcam.exe"
```

---

## Configuration Backup

**To backup Yawcam settings:**
```
1. Close Yawcam (Exit from tray)
2. Copy: C:\Program Files\Yawcam\settings.xml
3. To: C:\YawcamBackup\settings_2025-02-22.xml
```

**To restore:**
```
1. Close Yawcam
2. Copy backup settings.xml to C:\Program Files\Yawcam\
3. Overwrite existing settings.xml
4. Start Yawcam
```

---

## Complete Settings Checklist

### General Settings (Settings → General)
- [x] Start Yawcam on Windows startup
- [x] Start minimized to tray
- [x] Minimize to tray instead of taskbar

### Motion Detection Settings (Window → Motion Detection)
- [x] Enable motion detection
- [x] Enable on startup
- [x] Sensitivity: 60
- [x] Threshold: 25
- [x] Delay: 3 seconds
- [x] Detection zones configured (red cells)

### Actions (Motion Detection → Actions)
- [x] Start recording video

### Output Settings (Settings → Output)
- [x] Output folder: C:\YawcamRecordings\Videos\
- [x] Format: MP4
- [x] Delete files older than: 7 days

### Device Settings (Settings → Device settings)
- [x] Webcam selected
- [x] Resolution: 640x480 or 1280x720
- [x] Frame rate: 30 fps

---

## Quick Commands

**Open Yawcam from tray:**
```
Double-click Yawcam tray icon
```

**Show Motion Detection window:**
```
Menu: Window → Motion Detection
OR
Right-click tray icon → Motion Detection
```

**Check if Yawcam is running:**
```
1. Press Ctrl+Shift+Esc (Task Manager)
2. Processes tab
3. Look for "Yawcam.exe"
```

**Restart Yawcam:**
```
1. Right-click tray icon → Exit
2. Launch: C:\Program Files\Yawcam\Yawcam.exe
```

**Emergency stop recording:**
```
1. Right-click Yawcam tray icon
2. Motion Detection
3. Uncheck "Enable motion detection"
```

---

## System Tray Icon Reference

**Yawcam tray icon location:**
```
Bottom-right corner of screen
System tray area (near clock)
May be hidden in ^ overflow menu
```

**Right-click tray icon menu:**
```
→ Show window (open main Yawcam window)
→ Motion Detection (open motion detection window)
→ Settings (open settings)
→ Exit (close Yawcam completely)
```

---

## Performance Expectations

**Resource Usage (Normal Operation):**
```
CPU: 5-15%
RAM: 150-250 MB
Disk: ~150 MB per hour (640x480 MP4)
```

**Storage:**
```
640x480 MP4:
- 1 hour = ~150 MB
- 24 hours = ~3.6 GB
- 7 days = ~25 GB
```

**Battery Life Impact (if on battery):**
```
~20-30% higher power drain
Continuous webcam operation + encoding
Recommend AC power for 24/7 use
```

---

## For Fully Unattended Operation

**Optional: Windows Auto-Login**

⚠️ Security Warning: Only use on dedicated surveillance systems in secure locations.

```
1. Win + R → netplwiz
2. Uncheck: "Users must enter a user name and password"
3. Click Apply
4. Enter password twice
5. Click OK

Result: Windows logs in automatically on boot
        → Yawcam starts automatically
        → Motion detection enables automatically
        → Zero user intervention needed
```

---

## After Windows Updates

Windows updates often reset power settings.

**Post-update checklist:**
```
1. Verify USB selective suspend still disabled
   Power Options → Advanced → USB settings
   
2. Verify Sleep/Hibernate still set to Never
   Power Options → Advanced → Sleep
   
3. Test Yawcam auto-start
   Restart computer, verify Yawcam starts
   
4. Test motion detection
   Wave at camera, verify recording works
```

---

## Getting Help

**Yawcam won't start automatically:**
→ See "Troubleshooting Auto-Start" section above
→ Check main documentation: Section "Step 8: Auto-Start Configuration"

**Motion detection stops after several minutes:**
→ Windows power settings not configured
→ See main documentation: "Critical Windows Power Settings"
→ Critical: USB Selective Suspend must be DISABLED

**Too many false alarms:**
→ Adjust Sensitivity (lower to 40-50)
→ Adjust Threshold (higher to 30-40)
→ Configure detection zones (exclude problem areas)

**Complete documentation:**
→ See: acer-nitro5-motion-detection-setup.md

---

**Document Version:** 1.0  
**Created:** February 2025  
**Software:** Yawcam 0.6.2  
**Hardware:** Acer Nitro 5 (all models)  
**OS:** Windows 10/11
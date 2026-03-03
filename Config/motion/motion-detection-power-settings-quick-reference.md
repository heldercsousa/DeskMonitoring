# Quick Reference: Motion Detection Power Settings Fix

## Critical Settings Checklist

Use this quick reference to verify your power settings are correct for continuous motion detection.

---

## ✅ Power Settings Checklist

### Basic Settings (Control Panel → Power Options → Change plan settings)

| Setting | On Battery | Plugged In (AC) |
|---------|-----------|-----------------|
| Turn off the display | 5 minutes | 10 min or Never |
| Put the computer to sleep | **Never** | **Never** ⚠️ |

⚠️ = Critical for motion detection to work

---

### Advanced Settings (Change advanced power settings)

| Category | Setting | On Battery | Plugged In |
|----------|---------|-----------|------------|
| **USB settings** | USB selective suspend | **Disabled** ⚠️ | **Disabled** ⚠️ |
| **Sleep** | Sleep after | Never (or 120 min) | **Never** ⚠️ |
| **Sleep** | Hibernate after | Never | **Never** ⚠️ |
| **Hard disk** | Turn off hard disk after | 10 minutes | **Never** |
| **Multimedia** | When sharing media | Prevent idling to sleep | Prevent idling to sleep |

⚠️ = Critical settings - motion detection WILL FAIL if not configured correctly

---

## 🔧 The #1 Fix: USB Selective Suspend

**Problem:** Webcam stops working after 5-10 minutes even though Yawcam is running

**Root Cause:** USB Selective Suspend is ENABLED (Windows default)

**Fix:**
```
Power Options → Change plan settings → Change advanced power settings
→ USB settings
  → USB selective suspend setting
     → On battery: Change from "Enabled" to "Disabled"
     → Plugged in: Change from "Enabled" to "Disabled"
```

**Result:** Webcam stays powered on indefinitely

---

## 📝 Step-by-Step Navigation

1. **Win + X** → **Power Options**
2. Click **"Change plan settings"** next to your active power plan
3. Click **"Change advanced power settings"** (opens popup window)
4. Expand **"USB settings"** → **"USB selective suspend setting"**
5. Click **"On battery: Enabled"** → Change to **"Disabled"**
6. Click **"Plugged in: Enabled"** → Change to **"Disabled"**
7. Expand **"Sleep"** → **"Sleep after"** → Set both to **"Never"**
8. Expand **"Sleep"** → **"Hibernate after"** → Set both to **"Never"**
9. Click **"Apply"** → **"OK"**
10. Click **"Save changes"**

---

## 🎯 Verification Test

After changing settings:

1. ✅ Start Yawcam with motion detection enabled
2. ✅ Lock screen (Win + L)
3. ✅ Wait 15 minutes
4. ✅ Unlock screen
5. ✅ Verify motion detection is still active
6. ✅ Test by moving in front of camera

**If motion detection stopped:** Review USB selective suspend setting again (most common issue)

---

## 🖥️ Webcam Driver Setting

Also disable power management in the webcam driver:

1. **Win + X** → **Device Manager**
2. Expand **"Cameras"**
3. Right-click your webcam → **Properties**
4. **Power Management** tab
5. ☐ **UNCHECK:** "Allow the computer to turn off this device to save power"
6. Click **OK**

---

## 🔴 Common Mistakes

❌ Only changing "Sleep after" but forgetting USB selective suspend  
❌ Only changing "Plugged in" settings but not "On battery"  
❌ Closing settings without clicking "Save changes"  
❌ Not restarting Yawcam after changing settings  
❌ Confusing "Turn off the display" with "Put computer to sleep"  

✅ Disable USB selective suspend for BOTH battery and AC power  
✅ Set sleep/hibernate to "Never" for BOTH battery and AC power  
✅ Always click "Apply" then "OK" then "Save changes"  
✅ Restart Yawcam after making changes  
✅ Test with 15-minute lock screen test  

---

## 📊 Settings Summary Table

| What Happens | Setting Responsible | Fix |
|-------------|-------------------|-----|
| Webcam stops after 5-10 min | USB selective suspend = Enabled | Disable it |
| Yawcam stops when screen locked | Sleep after = 30 minutes | Set to Never |
| Recording stops overnight | Hibernate after = 180 min | Set to Never |
| Disk writes fail during record | Hard disk turn off = 20 min | Set to Never |

---

## 🚀 Quick Setup (Under 5 Minutes)

**Minimum viable configuration for motion detection:**

1. USB selective suspend → **Disabled** (both battery & AC)
2. Sleep after (Plugged in) → **Never**
3. Hibernate after (Plugged in) → **Never**
4. Save all settings
5. Restart Yawcam

**These 3 settings solve 95% of motion detection stopping issues.**

---

## 📱 For Laptop on Battery

If you need motion detection while running on battery:

- USB selective suspend → **Disabled** ⚠️ (critical)
- Sleep after → **Never** or **120 minutes minimum**
- Hibernate after → **Never**
- Turn off display → **5-10 minutes** (saves battery, doesn't affect detection)

**Battery life impact:** ~20-30% higher drain with these settings

---

## 🔄 After Windows Updates

Windows updates often reset power settings. After each major update:

1. ✅ Re-check USB selective suspend (most commonly reset)
2. ✅ Verify Sleep/Hibernate settings
3. ✅ Test motion detection with 15-minute lock screen test

---

## 💡 Pro Tips

**Best practice for 24/7 monitoring:**
- Keep laptop plugged into AC power
- Use USB selective suspend = Disabled
- Sleep/Hibernate = Never
- Set up automatic file cleanup in Yawcam (delete after 7 days)
- Allocate 100GB minimum for recordings

**Best practice for intermittent use:**
- Configure power settings as documented
- Manually start/stop motion detection as needed
- Or use Task Scheduler to auto-restart Yawcam after wake/unlock

---

**Document Version:** 1.1  
**Last Updated:** February 2025  
**Platform:** Windows 10/11  
**Hardware:** Acer Nitro 5 (all models)  

For complete documentation, see: `acer-nitro5-motion-detection-setup.md`
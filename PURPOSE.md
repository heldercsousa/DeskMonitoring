# Why This System Exists

## Original Goal

This project started on 2026-03-02 as a simple three-layer backup for a home security camera setup. A Yawcam motion-detection camera watches the home entry door and writes `.avi` clip files into `C:\Users\helde\Repos\Bois`. Those clips are mirrored locally to `C:\Sync\Mirror` and then synced to Backblaze B2 cloud storage every five minutes. The intent was straightforward: if someone enters the premises without authorisation, the recordings exist in at least three places.

## What Was Discovered

Within days of the system going live, it became clear the situation was worse than anticipated. The laptop and Android phone were both under active compromise. The attacker also had physical access to the premises - a router reset button was found glued to prevent factory resets, and physical damage was found on a wardrobe door forced beyond its pivot limit. This was not a remote opportunist. Someone with local presence was actively working to suppress evidence of their activity.

## Why the System Had to Expand

Once the attacker realised recordings were being made and backed up, they began targeting the monitoring infrastructure directly. Outbound firewall rules were injected to block Backblaze B2 IPs, silently cutting off cloud sync. USB selective suspend was re-enabled remotely to drop the webcam during screen lock. Config scripts were modified mid-session with foreign-language comments. Git index files were mass-deleted in an attempt to corrupt version history. Each attack forced a new defensive capability.

## Why Backblaze B2 Matters

B2 is the off-site tamper-evident layer. If recordings are deleted locally, B2 preserves them. If B2 sync is blocked, that block is itself logged as confirmed attack evidence - the attacker's interference becomes part of the forensic record. Local ACL time-locks mean even a physically present attacker cannot instantly delete recent files.

## What an Attacker Must Defeat

To destroy all evidence simultaneously, an attacker would need to: delete local files, break ACL protection on `C:\Sync`, block B2 sync without triggering the detection log, evade SACL auditing on the Config and Evidence folders, corrupt git history, and break the email alert chain - all at the same time, before the next scheduled sync run.

## Current Status

As of 2026-06-05, the system is under active daily attack. `cloud_sync.ps1` is being re-tampered nightly. See the `Evidence/` folder for documented incidents and `THREAT_MODEL.md` for the full adversary profile.

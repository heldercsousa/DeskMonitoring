Write-Host "=== SCHEDULED TASKS ==="
Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue | Select-Object TaskName, State
Get-ScheduledTask -TaskName "FolderSync-Watchdog" -ErrorAction SilentlyContinue | Select-Object TaskName, State

Write-Host "`n=== TASK TRIGGERS & ACTIONS - CloudBackup ==="
$t = Get-ScheduledTask -TaskName "FolderSync-CloudBackup" -ErrorAction SilentlyContinue
if ($t) { $t.Triggers | Format-List; $t.Actions | Format-List }

Write-Host "=== TASK TRIGGERS & ACTIONS - Watchdog ==="
$t2 = Get-ScheduledTask -TaskName "FolderSync-Watchdog" -ErrorAction SilentlyContinue
if ($t2) { $t2.Triggers | Format-List; $t2.Actions | Format-List }

Write-Host "`n=== SERVICES ==="
Get-Service FolderSyncWatchdog  -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType
Get-Service FolderSyncAuditor   -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType

Write-Host "`n=== REGISTRY STARTUP ==="
(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue).FolderSyncRealTime

Write-Host "`n=== REALTIMESYNC PROCESS ==="
Get-Process RealTimeSync -ErrorAction SilentlyContinue | Select-Object Name, Id

Write-Host "`n=== RCLONE VERSION ==="
& "C:\Tools\Rclone\rclone.exe" version 2>&1 | Select-Object -First 1

Write-Host "`n=== SOURCE FOLDER SIZE ==="
$sz = (Get-ChildItem "C:\Users\helde\Repos\Bois" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host ("{0:N1} MB  ({1} files)" -f ($sz/1MB), (Get-ChildItem "C:\Users\helde\Repos\Bois" -Recurse -File -ErrorAction SilentlyContinue).Count)

Write-Host "`n=== MIRROR FOLDER SIZE ==="
$sz2 = (Get-ChildItem "C:\Sync\Mirror" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host ("{0:N1} MB  ({1} files)" -f ($sz2/1MB), (Get-ChildItem "C:\Sync\Mirror" -Recurse -File -ErrorAction SilentlyContinue).Count)

Write-Host "`n=== CONFIG FILES ==="
Get-ChildItem "C:\Sync\Config" | Format-Table Name, @{N="Size(KB)";E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize

Write-Host "`n=== LOG FILES ==="
Get-ChildItem "C:\Sync\Logs" -ErrorAction SilentlyContinue | Format-Table Name, @{N="Size(KB)";E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize

Write-Host "`n=== PATH INCLUDES RCLONE ==="
[Environment]::GetEnvironmentVariable("PATH","Machine") -split ";" | Where-Object { $_ -like "*rclone*" -or $_ -like "*Rclone*" }

Write-Host "`n=== RCLONE CONF (sanitized) ==="
Get-Content "C:\Sync\Config\rclone.conf" | ForEach-Object {
    if ($_ -match "^key") { "  key = ***REDACTED***" } else { $_ }
}

Write-Host "`n=== LAST 5 LINES CLOUD SYNC LOG (today) ==="
$todayLog = "C:\Sync\Logs\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $todayLog) {
    Get-Content $todayLog | Select-Object -Last 5
} else {
    Write-Host "(no log yet for today: $todayLog)"
}

Write-Host "`n=== LAST 5 LINES WATCHDOG LOG ==="
Get-Content "C:\Sync\Logs\watchdog.log" -ErrorAction SilentlyContinue | Select-Object -Last 5

Write-Host "`n=== LAST 5 LINES FILE AUDIT LOG (today) ==="
$fileLog = "C:\Sync\Logs\file_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $fileLog) {
    Get-Content $fileLog | Select-Object -Last 5
} else {
    Write-Host "(no file audit log yet for today: $fileLog)"
}

Write-Host "`n=== LAST 5 LINES SECURITY AUDIT LOG (today) ==="
$secLog = "C:\Sync\Logs\security_audit_$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $secLog) {
    Get-Content $secLog | Select-Object -Last 5
} else {
    Write-Host "(no security audit log yet for today: $secLog)"
}

# cloud_sync.ps1
# Rclone sync: C:\Users\helde\Repos\Bois -> Backblaze B2
# Manages Mirror cleanup and Log rotation automatically.
# Last updated: 2026-03-02

$Rclone     = 'C:\Tools\Rclone\rclone.exe'
$Config     = 'C:\Sync\Config\rclone.conf'
$Source     = 'C:\Users\helde\Repos\Bois'
$Remote     = 'cloudsync:helder-sync-mirror'
$Mirror     = 'C:\Sync\Mirror'
$LogDir     = 'C:\Sync\Logs'
$Log        = "$LogDir\cloud_sync_$(Get-Date -Format 'yyyy-MM-dd').log"
$DaysToKeepMirror = 7
$DaysToKeepLogs   = 30

# 1. Sync to B2 (exclude logs folder to avoid re-upload loop)
& $Rclone sync $Source $Remote `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --transfers 4 `
    --checkers 8 `
    --fast-list `
    --exclude "logs/**"

# 2. Upload logs to B2 (copy only - never deletes from B2)
# Excludes firewall logs (owned by SYSTEM, large, not critical for evidence)
& $Rclone copy $LogDir "$Remote/logs" `
    --config $Config `
    --log-file $Log `
    --log-level INFO `
    --exclude "firewall.log" `
    --exclude "firewall.log.old"

# 3. Mirror cleanup - delete files older than DaysToKeepMirror
if (Test-Path $Mirror) {
    $threshold = (Get-Date).AddDays(-$DaysToKeepMirror)
    Get-ChildItem -Path $Mirror -Recurse -File |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. Log rotation - delete cloud_sync logs older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "cloud_sync_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 5. Mirror log rotation - delete mirror_*.log older than DaysToKeepLogs
Get-ChildItem -Path $LogDir -Filter "mirror_*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeepLogs) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
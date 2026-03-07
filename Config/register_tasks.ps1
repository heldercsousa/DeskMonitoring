# Register FolderSync scheduled tasks

# Task 1: Cloud sync via Rclone every 5 minutes
# Uses cloud_sync.ps1 (not .bat) to avoid the cmd.exe console window flash when running as SYSTEM
$action1 = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\cloud_sync.ps1'
$trigger1 = @(
    $(New-ScheduledTaskTrigger -AtStartup),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date))
)
$settings1 = New-ScheduledTaskSettingsSet -Hidden -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
$principal1 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "FolderSync-CloudBackup" -Action $action1 -Trigger $trigger1 -Settings $settings1 -Principal $principal1 -Force
Write-Host "Task FolderSync-CloudBackup registered"

# Task 2: Watchdog every 3 minutes + boot + session unlock
$action2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Sync\Config\wdog.ps1'
$trigger2 = @(
    $(New-ScheduledTaskTrigger -AtStartup),
    $(New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 3) -Once -At (Get-Date))
)
$settings2 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
$principal2 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "FolderSync-Watchdog" -Action $action2 -Trigger $trigger2 -Settings $settings2 -Principal $principal2 -Force
Write-Host "Task FolderSync-Watchdog registered"

# Task 3: Daily security check at 09:00 — runs as current user (needs interactive session for dialog)
# Note: no -NonInteractive flag so the MessageBox dialog can appear on the desktop
$action3   = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument '-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Sync\Config\DailySecurityCheck.ps1"'
$trigger3  = New-ScheduledTaskTrigger -Daily -At "09:00"
$settings3 = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal3 = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
Register-ScheduledTask -TaskName "FolderSync-DailyCheck" -Action $action3 -Trigger $trigger3 -Settings $settings3 -Principal $principal3 -Force
Write-Host "Task FolderSync-DailyCheck registered"

# Remove legacy tasks that pointed to Documents\SecurityScripts (old location)
foreach ($oldName in @("Verificacao Automatica de Seguranca", "Verificação Automática de Segurança")) {
    if (Get-ScheduledTask -TaskName $oldName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $oldName -Confirm:$false
        Write-Host "Removed legacy task: $oldName"
    }
}

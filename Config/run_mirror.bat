@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /MIR = mirror (purges files deleted from source)
:: /R:2  = retry twice on error
:: /W:5  = wait 5 seconds between retries
:: /LOG+ = append to DAILY rotating log (mirror_YYYY-MM-DD.log)
:: Last updated: 2026-03-02
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /MIR /R:2 /W:5 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL
@echo off
:: ============================================================
:: LAUNCHER for recentFiles.ps1
:: Keep this .bat in the same folder as recentFiles.ps1
::
:: Bypasses PowerShell execution policy automatically.
:: All parameters are forwarded to the PowerShell script.
::
:: USAGE EXAMPLES:
::   recentFiles.bat
::       Top 100, drive C:\, display only (all defaults)
::
::   recentFiles.bat -Top 200
::       Top 200, drive C:\, display only
::
::   recentFiles.bat -Top 50 -Drive "D:\"
::       Top 50 on D:\, display only
::
::   recentFiles.bat -Save
::       Top 100, drive C:\, display + save CSV in script's own folder
::
::   recentFiles.bat -Path "C:\Reports"
::       Top 100, drive C:\, display + save CSV in C:\Reports
::
::   recentFiles.bat -Top 200 -Drive "D:\" -Save
::       Top 200 on D:\, display + save CSV in script's own folder
::
::   recentFiles.bat -Top 200 -Drive "D:\" -Path "C:\Reports"
::       Top 200 on D:\, display + save CSV in C:\Reports
:: ============================================================

powershell -ExecutionPolicy Bypass -File "%~dp0recentFiles.ps1" %*
@echo off
title FolderSync + Camera Health Check
powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "C:\Sync\Config\health_check_all.ps1"
echo.
pause

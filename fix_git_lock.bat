@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
takeown /F "C:\Sync\.git\index.lock" >nul 2>&1
icacls "C:\Sync\.git\index.lock" /grant *S-1-5-32-544:F >nul 2>&1
del /F /Q "C:\Sync\.git\index.lock" >nul 2>&1
if exist "C:\Sync\.git\index.lock" (
    echo FAILED - lock still present
) else (
    echo SUCCESS - lock removed
)
pause

@echo off
:: Removes the Deny ACL from C:\Sync\.git\ only — git needs to write lock files there.
:: Keeps Deny Delete on Config, Logs, Mirror, Evidence (those are protected).
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Removing Deny ACL from .git folder only...
icacls "C:\Sync\.git" /remove:d *S-1-1-0 /T /Q
icacls "C:\Sync\.git" /remove:d "Everyone" /T /Q
icacls "C:\Sync\.git" /remove:d *S-1-5-32-545 /T /Q

echo Deleting stale lock if present...
if exist "C:\Sync\.git\index.lock" del /F /Q "C:\Sync\.git\index.lock"

echo Done. Git should now work normally.
pause

@echo off
:: Self-elevating UAC batch — removes malicious B2 firewall block rules
:: Double-click to run. Accept the UAC prompt.

net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -ExecutionPolicy Bypass -File "C:\Sync\Config\fix_firewall_b2.ps1"
echo.
pause

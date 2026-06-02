Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pwsh.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Sync\Config\audit_filter.ps1""", 0, False

$t = $null; $e = $null
[System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\start_ecosystem.ps1', [ref]$t, [ref]$e)
Write-Host "Error count: $($e.Count)"

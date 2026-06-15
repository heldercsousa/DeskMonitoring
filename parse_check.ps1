$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile('C:\Sync\Config\cloud_sync_helderTest.ps1', [ref]$tokens, [ref]$errors)
Write-Host $errors.Count

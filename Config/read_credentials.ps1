Add-Type -AssemblyName System.Security
$encrypted = [System.IO.File]::ReadAllBytes('C:\Sync\Config\credentials.enc')
$plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $encrypted,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.Text.Encoding]::UTF8.GetString($plain)

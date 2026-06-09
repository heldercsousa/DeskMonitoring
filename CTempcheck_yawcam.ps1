$procs = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue
foreach ($p in $procs) {
    if ($p.CommandLine -match 'yawcam') {
        Write-Host "Found: PID=$($p.ProcessId) CommandLine=$($p.CommandLine)"
    }
}
if (-not $procs) { Write-Host "No powershell processes with yawcam found" }

# ============================================================
# RECENT FILES SCANNER — entire disk, hidden files included
# Run as Administrator for best results
#
# Ranks files by MostRecentDate = Max(CreationTime, LastWriteTime)
# so newly created AND recently modified files compete in the same list.
#
# ---------------------------------------------------------------
# USAGE — via PowerShell directly:
# ---------------------------------------------------------------
#   .\recentFiles.ps1
#       Top 100, drive C:\, display only (all defaults)
#
#   .\recentFiles.ps1 -Top 200
#       Top 200, drive C:\, display only
#
#   .\recentFiles.ps1 -Top 50 -Drive "D:\"
#       Top 50 on D:\, display only
#
#   .\recentFiles.ps1 -Save
#       Top 100, drive C:\, display + save CSV in script's own folder
#
#   .\recentFiles.ps1 -Path "C:\Reports"
#       Top 100, drive C:\, display + save CSV in C:\Reports (-Save implied)
#
#   .\recentFiles.ps1 -Top 200 -Drive "D:\" -Save
#       Top 200 on D:\, display + save CSV in script's own folder
#
#   .\recentFiles.ps1 -Top 200 -Drive "D:\" -Path "C:\Reports"
#       Top 200 on D:\, display + save CSV in C:\Reports
#
# ---------------------------------------------------------------
# USAGE — via run_recentFiles.bat (same params, same behavior):
# ---------------------------------------------------------------
#   run_recentFiles.bat
#   run_recentFiles.bat -Top 200
#   run_recentFiles.bat -Top 50 -Drive "D:\"
#   run_recentFiles.bat -Save
#   run_recentFiles.bat -Path "C:\Reports"
#   run_recentFiles.bat -Top 200 -Drive "D:\" -Save
#   run_recentFiles.bat -Top 200 -Drive "D:\" -Path "C:\Reports"
#
# ---------------------------------------------------------------
# PARAMETERS:
# ---------------------------------------------------------------
#   -Top    (int)     Number of files to return. Default: 100
#   -Drive  (string)  Drive or path to scan.    Default: "C:\"
#   -Save   (switch)  Save results as CSV in the script's own folder
#   -Path   (string)  Save results as CSV in the given folder (implies -Save)
#
# NOTE: The output CSV filename includes a timestamp to avoid overwrites,
#       e.g.: recentFiles_top100_20260620_143022.csv
# ============================================================

param (
    [int]    $Top   = 100,
    [string] $Drive = "C:\",
    [switch] $Save,
    [string] $Path  = ""
)

# If -Path is given, -Save is implied
if ($Path -ne "") { $Save = $true }

# Resolve output folder
if ($Save) {
    $OutputFolder = if ($Path -ne "") { $Path } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputFile   = Join-Path $OutputFolder "recentFiles_top$($Top)_$Timestamp.csv"
}

Write-Host ""
Write-Host "Scanning $Drive for top $Top files by Max(CreationTime, LastWriteTime)..." -ForegroundColor Cyan
Write-Host "Please wait, this may take a few minutes." -ForegroundColor Yellow
Write-Host ""

$results = Get-ChildItem -Path $Drive -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer } |
    Select-Object FullName, CreationTime, LastWriteTime, Length,
        @{ Name = "MostRecentDate"; Expression = {
            if ($_.CreationTime -gt $_.LastWriteTime) { $_.CreationTime } else { $_.LastWriteTime }
        }} |
    Sort-Object MostRecentDate -Descending |
    Select-Object -First $Top MostRecentDate, CreationTime, LastWriteTime, Length, FullName

# Always display on screen
$results | Format-Table -AutoSize

# Save if requested
if ($Save) {
    $results | Export-Csv -Path $OutputFile -NoTypeInformation
    Write-Host ""
    Write-Host "Results saved to: $OutputFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Showing top $Top files from $Drive sorted by MostRecentDate descending." -ForegroundColor Green
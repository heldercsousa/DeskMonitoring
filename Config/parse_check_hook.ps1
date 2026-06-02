#Requires -Version 5.1
# PostToolUse hook: auto-runs ParseFile on any .ps1 edited via Edit or Write tool.
# Receives tool input as JSON in CLAUDE_TOOL_INPUT env var.
# Exits 0 (ok) or 1 (parse errors found) — non-blocking informational output.

$inputJson = $env:CLAUDE_TOOL_INPUT
if (-not $inputJson) { exit 0 }

try { $obj = $inputJson | ConvertFrom-Json } catch { exit 0 }

$path = $obj.file_path
if (-not $path -or $path -notmatch '\.ps1$') { exit 0 }
if (-not (Test-Path -LiteralPath $path)) { exit 0 }

$t = $null; $e = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e) | Out-Null

$name = Split-Path $path -Leaf
if ($e.Count -eq 0) {
    Write-Output "PARSE OK - $name"
    exit 0
} else {
    $lines = $e | ForEach-Object { "  L$($_.Extent.StartLineNumber) $($_.Message)" }
    Write-Output ("PARSE ERRORS in ${name}:`n" + ($lines -join "`n"))
    exit 1
}

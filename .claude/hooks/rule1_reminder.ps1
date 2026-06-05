# RULE 1 - Post-edit reminder for Config/*.ps1 changes
# Triggered by PostToolUse on Edit or Write tool calls
# Always exits 0 (non-blocking reminder only)

# Claude Code passes tool input via CLAUDE_TOOL_INPUT env var as JSON
$toolInput = $env:CLAUDE_TOOL_INPUT
if (-not $toolInput) { exit 0 }

try {
    $parsed = $toolInput | ConvertFrom-Json
    $filePath = $parsed.file_path
    if (-not $filePath) { exit 0 }

    if ($filePath -match '\\Config\\' -and $filePath -match '\.ps1$') {
        Write-Host "RULE 1: Update ECOSYSTEM_REPORT.md Section 5+15 and setup_update.ps1"
    }
} catch {
    # Never block on parse failure
}

exit 0

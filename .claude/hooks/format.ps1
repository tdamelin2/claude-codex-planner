# format.ps1
# PostToolUse hook for the Edit and Write tools, set in .claude/settings.json.
# Formats the file that was just written, using a formatter only if the project
# already has it installed. It never installs anything, and it never fails a tool
# call: every path through this script exits 0.
#   .py                                   ruff format, or black if ruff is missing
#   .js .jsx .ts .tsx .json .css .scss    the project's local Prettier
#   .html .vue .svelte .yaml .yml         (node_modules/.bin/prettier)
#   .go                                   gofmt
#   .rs                                   rustfmt
# Skipped: anything in handoffs/, logs/ or .claude/, and every file type not listed
# above, including Markdown.
# Written for Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    $data = $raw | ConvertFrom-Json
    $file = [string]$data.tool_input.file_path
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 0 }

    $root = $env:CLAUDE_PROJECT_DIR
    if (-not $root) { $root = [string]$data.cwd }
    $rel = ($file -replace '\\', '/')
    if ($root) {
        $rootSlash = (($root -replace '\\', '/').TrimEnd('/')) + '/'
        if ($rel.StartsWith($rootSlash, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $rel.Substring($rootSlash.Length)
        }
    }
    if ($rel -match '^(handoffs|logs|\.claude)/') { exit 0 }

    $ext = [System.IO.Path]::GetExtension($file).ToLower()

    switch -Regex ($ext) {
        '^\.py$' {
            if (Get-Command ruff -ErrorAction SilentlyContinue) { & ruff format --quiet -- $file *> $null }
            elseif (Get-Command black -ErrorAction SilentlyContinue) { & black --quiet -- $file *> $null }
        }
        '^\.(js|jsx|ts|tsx|json|css|scss|html|vue|svelte|ya?ml)$' {
            $prettier = Join-Path $root 'node_modules/.bin/prettier.cmd'
            if (-not (Test-Path -LiteralPath $prettier)) { $prettier = Join-Path $root 'node_modules/.bin/prettier' }
            if ($root -and (Test-Path -LiteralPath $prettier)) { & $prettier --write --log-level warn -- $file *> $null }
        }
        '^\.go$' {
            if (Get-Command gofmt -ErrorAction SilentlyContinue) { & gofmt -w $file *> $null }
        }
        '^\.rs$' {
            if (Get-Command rustfmt -ErrorAction SilentlyContinue) { & rustfmt $file *> $null }
        }
    }
} catch {
    # Formatting is a convenience. Never block or report an error.
}
exit 0

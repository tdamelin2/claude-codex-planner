# check-clean-tree.ps1
# Stop hook in the debugger's frontmatter (it runs as SubagentStop). Keeps the
# debugger from finishing while any file outside the allowed paths differs from the
# last commit, so no temporary debug edit is left behind.
# Usage: check-clean-tree.ps1 -Allow "handoffs/,logs/,.claude/agent-memory/debugger/"
# Exit 0 lets the debugger finish. Exit 2 keeps it working, and the message on
# stderr tells it what to undo. Claude Code stops re-blocking after several blocks
# in a row with no progress, and the manager checks git status again afterwards.
# Written for Windows PowerShell 5.1 and PowerShell 7.

param(
    [string]$Allow = ''
)

$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    $data = $raw | ConvertFrom-Json
} catch {
    $data = $null
}

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root -and $data) { $root = $data.cwd }
if (-not $root) { $root = (Get-Location).Path }

$allowed = @()
foreach ($a in ($Allow -split ',')) {
    $p = ($a.Trim() -replace '\\', '/')
    if ($p) { $allowed += $p }
}

$ErrorActionPreference = 'Continue'
$lines = & git -C $root status --porcelain=v1 -z --untracked-files=all 2>$null
$gitExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($gitExit -ne 0) {
    # Not a git repository, or git is missing: nothing can be checked.
    [Console]::Error.WriteLine('check-clean-tree: git status failed, so the tree was not checked.')
    exit 0
}

$text = ($lines -join "`n")
$tokens = @($text -split "`0" | Where-Object { $_ -ne '' -and $_ -ne "`n" })

$dirty = @()
for ($i = 0; $i -lt $tokens.Count; $i++) {
    $t = $tokens[$i].TrimStart([char]10)
    if ($t.Length -lt 4) { continue }
    $xy = $t.Substring(0, 2)
    $path = $t.Substring(3) -replace '\\', '/'
    if ($xy[0] -eq 'R' -or $xy[0] -eq 'C') { $i++ }   # the next token is the original path

    $ok = $false
    foreach ($a in $allowed) {
        $base = $a.TrimEnd('/')
        if ($path.Equals($base, [StringComparison]::OrdinalIgnoreCase) -or
            $path.StartsWith($base + '/', [StringComparison]::OrdinalIgnoreCase)) { $ok = $true; break }
    }
    if (-not $ok) { $dirty += "$xy $path" }
}

if ($dirty.Count -eq 0) { exit 0 }

$msg = "check-clean-tree: these files still differ from the last commit:`n  " + ($dirty -join "`n  ") +
    "`nUndo every temporary edit before finishing: run 'git restore -- <file>' for each" +
    " modified file (M) and Remove-Item for each new file you created (??)." +
    " Then run 'git status --short' to confirm."
[Console]::Error.WriteLine($msg)
exit 2

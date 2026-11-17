# guard-paths.ps1
# PreToolUse hook for the Edit, Write and Read tools, set in each agent's frontmatter.
# Allows a write only when the target is inside the calling agent's allowed paths.
#   manager : handoffs/, reviews/, managers/claude/, Questions.md,
#             .claude/agent-memory/manager/
#   coder-a : paths on the last "Part A folders:" line of the active phase file,
#             the active phase file, .claude/agent-memory/coder-a/
#   coder-b : same, with "Part B folders:"
#   tester  : tests/, logs/, the active phase file, .claude/agent-memory/tester/
#   telegram-liaison : managers/claude/, .claude/agent-memory/telegram-liaison/
#             During a review (no active phase file, an active reviews/review-*.md):
#             logs/, the active review file, .claude/agent-memory/tester/
# Extra rules for the manager:
#   Gate  : handoffs/phase-N.md may be written only after the planning gate:
#           managers/claude/plans/phase-N/DONE exists, and either
#           managers/codex/plans/phase-N/DONE or
#           managers/claude/plans/phase-N/SKIP-codex exists. Phases that existed
#           before two-manager planning (phase file present, no planning folder)
#           are not gated.
#   Blind : the manager may not Read managers/codex/plans/phase-N/ until
#           managers/claude/plans/phase-N/DONE exists.
# Read calls are checked only for the blind rule; every other Read is allowed.
# When the session runs as --agent manager, this hook can also fire for tool calls
# made inside subagents. The hook input's agent_type names the agent that made the
# call; if it is a different agent, that agent's own guard decides, so this one
# allows the call.
# The active phase file is the highest-numbered handoffs/phase-N.md whose Status
# line is not "Stage: Done". The active review file is the newest
# reviews/review-*.md whose Status line is not "Stage: Done".
# Exit 0 allows the call. Exit 2 blocks it, and the message on stderr goes back to
# the agent. Any internal error also blocks (fail closed).
# Written for Windows PowerShell 5.1 and PowerShell 7. ASCII only.

param(
    [Parameter(Mandatory = $true)][string]$Agent
)

$ErrorActionPreference = 'Stop'

function Stop-Call([string]$Message) {
    [Console]::Error.WriteLine("guard-paths: $Message")
    exit 2
}

function ConvertTo-Slash([string]$Path) {
    return ($Path -replace '\\', '/')
}

function Test-NotDone([System.IO.FileInfo]$File) {
    $status = Get-Content -LiteralPath $File.FullName -Encoding UTF8 -TotalCount 10 |
        Where-Object { $_ -match '^\s*Status:' } | Select-Object -First 1
    return ($status -and ($status -notmatch 'Stage:\s*Done'))
}

function Get-ActivePhaseFile([string]$Root) {
    $dir = Join-Path $Root 'handoffs'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter 'phase-*.md' -File |
        Where-Object { $_.BaseName -match '^phase-\d+$' } |
        Sort-Object { [int]($_.BaseName -replace '^phase-', '') } -Descending)
    foreach ($f in $files) {
        if (Test-NotDone $f) { return $f }
    }
    return $null
}

function Get-ActiveReviewFile([string]$Root) {
    $dir = Join-Path $Root 'reviews'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter 'review-*.md' -File |
        Sort-Object LastWriteTime -Descending)
    foreach ($f in $files) {
        if (Test-NotDone $f) { return $f }
    }
    return $null
}

function Get-PartPaths([System.IO.FileInfo]$PhaseFile, [string]$Part) {
    $pattern = "^\s*Part $Part folders:"
    $line = Get-Content -LiteralPath $PhaseFile.FullName -Encoding UTF8 |
        Where-Object { $_ -match $pattern } | Select-Object -Last 1
    if (-not $line) { return @() }
    $result = @()
    foreach ($item in (($line -replace $pattern, '') -split ',')) {
        $p = ConvertTo-Slash ($item.Trim().Trim('`').Trim())
        $p = $p -replace '^\./', ''
        if (-not $p) { continue }
        if ($p.StartsWith('<')) { continue }                 # unfilled template text
        if ($p.StartsWith('(')) { continue }                 # template note
        if ($p.StartsWith('/') -or $p -match '^[A-Za-z]:') { continue }  # absolute paths are not allowed
        if ($p -match '(^|/)\.\.(/|$)') { continue }          # no parent-folder paths
        if ($p -match '^(tests|logs|handoffs|reviews|managers|\.claude|\.agents|\.codex|scripts)(/|$)') { continue }  # never a coder's folder
        if ($p -match '^(Questions\.md|AGENTS\.md|CLAUDE\.md|Overview\.md|phases\.md)$') { continue }
        $result += $p
    }
    return $result
}

function Test-Inside([string]$Rel, [string[]]$Allowed) {
    foreach ($a in $Allowed) {
        $base = $a.TrimEnd('/')
        if ($Rel.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($Rel.StartsWith($base + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-PlanReady([string]$Root, [string]$Phase, [string]$Ai) {
    $plans = Join-Path $Root "managers/$Ai/plans/phase-$Phase/DONE"
    $skip = Join-Path $Root "managers/claude/plans/phase-$Phase/SKIP-$Ai"
    return ((Test-Path -LiteralPath $plans) -or (Test-Path -LiteralPath $skip))
}

$isRead = $false

try {
    $raw = [Console]::In.ReadToEnd()
    $data = $raw | ConvertFrom-Json
} catch {
    Stop-Call 'could not read the hook input, so the call was blocked.'
}

try {
    # A call made by a different agent is checked by that agent's own guard.
    $caller = [string]$data.agent_type
    if ($caller -and -not $caller.Equals($Agent, [StringComparison]::OrdinalIgnoreCase)) { exit 0 }

    $tool = [string]$data.tool_name
    $isRead = ($tool -eq 'Read')

    $target = $data.tool_input.file_path
    if (-not $target) { $target = $data.tool_input.notebook_path }
    if (-not $target) { exit 0 }

    $root = $env:CLAUDE_PROJECT_DIR
    if (-not $root) { $root = $data.cwd }
    if (-not $root) {
        if ($isRead) { exit 0 }
        Stop-Call 'the project folder is unknown, so the write was blocked.'
    }

    $rootFull = (ConvertTo-Slash ([System.IO.Path]::GetFullPath($root))).TrimEnd('/')
    if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $root $target }
    $full = ConvertTo-Slash ([System.IO.Path]::GetFullPath($target))
    $inside = $full.StartsWith($rootFull + '/', [StringComparison]::OrdinalIgnoreCase)
    $rel = $null
    if ($inside) { $rel = $full.Substring($rootFull.Length + 1) }

    # --- Read: only the blind rule applies, and only to the manager ------------
    if ($isRead) {
        if ($Agent -ne 'manager' -or -not $inside) { exit 0 }
        if ($rel -match '^managers/(codex)/plans/phase-(\d+)(/|$)') {
            $n = $Matches[2]
            $own = Join-Path $root "managers/claude/plans/phase-$n/DONE"
            if (-not (Test-Path -LiteralPath $own)) {
                Stop-Call "you may not read the $($Matches[1]) plan for phase $n until your own plan is finished (managers/claude/plans/phase-$n/DONE). Plan blind first."
            }
        }
        exit 0
    }

    # --- Write and Edit ----------------------------------------------------------
    if (-not $inside) {
        Stop-Call "$Agent may not write $full because it is outside the project folder."
    }

    $memory = ".claude/agent-memory/$Agent/"
    $phase = $null
    $review = $null
    if ($Agent -ne 'manager' -and $Agent -ne 'telegram-liaison') {
        $phase = Get-ActivePhaseFile $root
        if (-not $phase -and $Agent -eq 'tester') { $review = Get-ActiveReviewFile $root }
        if (-not $phase -and -not $review) {
            Stop-Call "no active handoffs/phase-N.md (or review file) was found, so $Agent has nothing it may write yet. Report this to the manager."
        }
    }

    switch ($Agent) {
        'manager' { $allowed = @('handoffs/', 'reviews/', 'managers/claude/', 'Questions.md', $memory) }
        'telegram-liaison' { $allowed = @('managers/claude/', $memory) }
        'tester'  {
            if ($phase) { $allowed = @('tests/', 'logs/', "handoffs/$($phase.Name)", $memory) }
            else        { $allowed = @('logs/', "reviews/$($review.Name)", $memory) }
        }
        'coder-a' { $allowed = @("handoffs/$($phase.Name)", $memory) + @(Get-PartPaths $phase 'A') }
        'coder-b' { $allowed = @("handoffs/$($phase.Name)", $memory) + @(Get-PartPaths $phase 'B') }
        default   { Stop-Call "unknown agent '$Agent', so the write was blocked." }
    }

    if (($Agent -eq 'coder-a' -or $Agent -eq 'coder-b') -and $allowed.Count -le 2) {
        $letter = $Agent.Substring($Agent.Length - 1).ToUpper()
        Stop-Call "the Plan in handoffs/$($phase.Name) has no usable 'Part $letter folders:' line. Report this to the manager as Blocked."
    }

    if (-not (Test-Inside $rel $allowed)) {
        Stop-Call ("$Agent may not write $rel. Allowed paths: " + ($allowed -join ', ') +
            '. If this file needs to change, say so in your Report instead.')
    }

    # Planning gate for the manager's phase file.
    if ($Agent -eq 'manager' -and $rel -match '^handoffs/phase-(\d+)\.md$') {
        $n = $Matches[1]
        $planDir = Join-Path $root "managers/claude/plans/phase-$n"
        $legacy = (Test-Path -LiteralPath $full) -and -not (Test-Path -LiteralPath $planDir)
        if (-not $legacy) {
            $missing = @()
            if (-not (Test-Path -LiteralPath (Join-Path $planDir 'DONE'))) { $missing += 'claude' }
            foreach ($ai in @('codex')) {
                if (-not (Test-PlanReady $root $n $ai)) { $missing += $ai }
            }
            if ($missing.Count -gt 0) {
                Stop-Call ("handoffs/phase-$n.md can't be written before the planning gate. Missing DONE for: " +
                    ($missing -join ', ') + '. Run scripts/wait-for-plans.ps1, or ask the user whether to continue without a missing manager.')
            }
        }
    }

    exit 0
} catch {
    if ($isRead) { exit 0 }   # reads fail open; only the blind rule checks them
    Stop-Call "internal error, so the call was blocked: $($_.Exception.Message)"
}

# codex-call.ps1
# Runs the Codex manager once, non-interactively, for a merge, a decision or the
# end-of-phase code review, and waits for its answer file. The Claude manager runs
# this; Codex is never left open.
#
# Usage (from the project folder):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/codex-call.ps1 -Phase 30 -Task merge
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/codex-call.ps1 -Phase 30 -Task decide -Ask P30-ASK-01
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/codex-call.ps1 -Phase 30 -Task review
#
# Codex runs with `codex exec` in its usual codex-planner profile from
# .codex/config.toml (writes only managers/codex/, may never read managers/claude/),
# with approvals off so it never waits for an answer. Its sandbox stays on.
# On Windows the sandbox locks managers/claude/ for Codex with a lasting folder
# permission, so a second profile can't open it. Instead, Codex reads Claude's
# files from managers/shared/phase-N/, which exists only after both plans are DONE:
#   merge  : this script copies Claude's plan files into managers/shared/phase-N/claude-plan/
#   decide : the manager writes its asks in managers/shared/phase-N/asks.md
#
# Answer files (Codex writes them last):
#   merge  : managers/codex/plans/phase-N/MERGED       (merged.md next to it)
#   decide : managers/codex/plans/phase-N/answers/<Ask>.md
#   review : managers/codex/plans/phase-N/REVIEWED     (code-review.md next to it)
# Run state : managers/claude/plans/phase-N/calls/<merge|Ask|review>.json
# Run logs  : logs/codex/phase-N-<merge|Ask|review>-<attempt>.log   (not committed)
#
# Running the same command again while Codex is still working reattaches to that
# run; it never starts a second Codex. A run that ends without its answer file is
# retried once, unless Codex reports it is out of usage.
#
# Exit codes:
#   0  the answer file exists
#   2  bad input or a missing precondition (the message says which)
#   3  Codex is still working: this call waited MaxWaitMinutes; run it again
#   6  Codex failed (twice, out of usage, or over TimeoutMinutes); decide without it
# Written for Windows PowerShell 5.1 and PowerShell 7. ASCII only.

param(
    [Parameter(Mandatory = $true)][int]$Phase,
    [Parameter(Mandatory = $true)][ValidateSet('merge', 'decide', 'review')][string]$Task,
    [string]$Ask = '',
    [int]$MaxWaitMinutes = 9,
    [int]$PollSeconds = 15,
    [int]$TimeoutMinutes = 60,
    [switch]$Retry
)

$ErrorActionPreference = 'Stop'

function Exit-With([int]$Code, [string]$Message) {
    Write-Output "codex-call: $Message"
    exit $Code
}

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root 'phases.md'))) {
    Exit-With 2 "can't find the project folder (no phases.md in $root)."
}
if ($Phase -lt 1) { Exit-With 2 'the phase number must be 1 or more.' }
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Exit-With 6 'the codex program was not found on this computer.'
}

$claudeDir = Join-Path $root "managers/claude/plans/phase-$Phase"
$codexDir = Join-Path $root "managers/codex/plans/phase-$Phase"
$sharedDir = Join-Path $root "managers/shared/phase-$Phase"

# --- what to run, and which file means "done" ----------------------------------
if ($Task -eq 'merge') {
    $id = 'merge'
    $marker = Join-Path $codexDir 'MERGED'
    $prompt = "Merge phase $Phase. Follow .agents/roles/codex-merge.md."
} elseif ($Task -eq 'review') {
    $id = 'review'
    $marker = Join-Path $codexDir 'REVIEWED'
    $prompt = "Review phase $Phase. Follow .agents/roles/codex-review.md."
} else {
    if ($Ask -notmatch "^P$Phase-ASK-\d{2,}$") {
        Exit-With 2 "-Ask must look like P$Phase-ASK-01 for phase $Phase."
    }
    $id = $Ask
    $marker = Join-Path $codexDir "answers/$Ask.md"
    $prompt = "Decide $Ask for phase $Phase. Follow .agents/roles/codex-decide.md."
}

if (Test-Path -LiteralPath $marker) { Exit-With 0 "done: $marker" }

# --- preconditions --------------------------------------------------------------
if ($Task -eq 'merge') {
    if (-not (Test-Path -LiteralPath (Join-Path $claudeDir 'DONE'))) {
        Exit-With 2 'the Claude plan has no DONE file yet.'
    }
    if (Test-Path -LiteralPath (Join-Path $claudeDir 'SKIP-codex')) {
        Exit-With 2 'SKIP-codex exists (no Codex plan): merge yourself as manager.md says.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $codexDir 'DONE'))) {
        Exit-With 2 'the Codex plan has no DONE file yet. Run scripts/wait-for-plans.ps1 first.'
    }
    # Both plans are final, so Codex may now see Claude's plan: copy it where
    # Codex can read it (plan.md, research.md, review.md, DONE).
    $copyDir = Join-Path $sharedDir 'claude-plan'
    if (-not (Test-Path -LiteralPath $copyDir)) { $null = New-Item -ItemType Directory -Path $copyDir }
    foreach ($f in @(Get-ChildItem -LiteralPath $claudeDir -File)) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $copyDir $f.Name) -Force
    }
} elseif ($Task -eq 'review') {
    if (-not (Test-Path -LiteralPath (Join-Path $root "handoffs/phase-$Phase.md"))) {
        Exit-With 2 "handoffs/phase-$Phase.md doesn't exist, so there is nothing to review."
    }
    $ErrorActionPreference = 'Continue'
    $startTag = @(& git -C $root tag --list "phase-$Phase-start" 2>$null)
    $ErrorActionPreference = 'Stop'
    if ($startTag.Count -eq 0) {
        Exit-With 2 "the tag phase-$Phase-start is missing, so Codex can't see what this phase changed."
    }
} else {
    $asksFile = Join-Path $sharedDir 'asks.md'
    if (-not (Test-Path -LiteralPath $asksFile)) { Exit-With 2 "no asks file at $asksFile." }
    $asksText = Get-Content -LiteralPath $asksFile -Raw -Encoding UTF8
    if ($asksText -notmatch "(?m)^## $([regex]::Escape($Ask))\b") {
        Exit-With 2 "asks.md has no '## $Ask' section. Write the ask first."
    }
}

# --- run state ------------------------------------------------------------------
$callsDir = Join-Path $claudeDir 'calls'
$logDir = Join-Path $root 'logs/codex'
foreach ($d in @($callsDir, $logDir)) {
    if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d }
}
$stateFile = Join-Path $callsDir "$id.json"

function Read-State {
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    return (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-State($State) {
    $State | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding ASCII
}

function Test-Running($State) {
    if (-not $State -or -not $State.pid) { return $false }
    $p = Get-Process -Id ([int]$State.pid) -ErrorAction SilentlyContinue
    return ($p -and $p.ProcessName -eq 'cmd')
}

function Start-Run([int]$Attempt) {
    $log = Join-Path $logDir "phase-$Phase-$id-$Attempt.log"
    $last = Join-Path $logDir "phase-$Phase-$id-$Attempt.last.txt"
    $line = "codex exec -C `"$root`" -c approval_policy=never " +
        "-o `"$last`" `"$prompt`" < NUL > `"$log`" 2>&1"
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/d /s /c `"$line`"" `
        -WindowStyle Hidden -PassThru
    $state = [pscustomobject]@{
        pid      = $proc.Id
        attempt  = $Attempt
        started  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        log      = $log
        status   = 'running'
    }
    Write-State $state
    # Write-Host, not Write-Output: anything written to the output stream would
    # become part of this function's return value.
    Write-Host "codex-call: started Codex ($Task, attempt $Attempt). Log: $log"
    return $state
}

function Get-FailReason([string]$Log) {
    if (-not (Test-Path -LiteralPath $Log)) { return @{ usage = $false; text = 'no log was written' } }
    $tail = @(Get-Content -LiteralPath $Log -Tail 30 -Encoding UTF8)
    $text = ($tail -join "`n")
    # Phrases from Codex's own limit errors; plain numbers like 429 are left out
    # because ordinary output (code, tests) can contain them.
    $usage = $text -match '(?i)(usage limit|rate limit reached|rate_limit_exceeded|quota exceeded|hit your (usage )?limit|too many requests)'
    return @{ usage = $usage; text = (($tail | Select-Object -Last 8) -join "`n") }
}

$state = Read-State
if ($state -and $state.status -eq 'failed' -and -not $Retry) {
    Exit-With 6 "an earlier run failed ($($state.reason)). Log: $($state.log). Decide without Codex, or run again with -Retry."
}
if (-not (Test-Running $state)) {
    $attempt = 1
    if ($state -and $state.status -ne 'failed' -and -not $Retry) { $attempt = [int]$state.attempt + 1 }
    if ($attempt -gt 2) {
        $state.status = 'failed'
        $state | Add-Member -NotePropertyName reason -NotePropertyValue 'two runs ended without an answer' -Force
        Write-State $state
        Exit-With 6 "two runs ended without an answer. Log: $($state.log)"
    }
    $state = Start-Run $attempt
} else {
    Write-Output "codex-call: Codex is already working on this ($Task, attempt $($state.attempt)); waiting."
}

# --- wait -----------------------------------------------------------------------
$callStart = Get-Date
while ($true) {
    if (Test-Path -LiteralPath $marker) {
        $state.status = 'done'
        Write-State $state
        Exit-With 0 "done: $marker"
    }

    if (-not (Test-Running $state)) {
        Start-Sleep -Seconds 2   # the marker may land just as the process ends
        if (Test-Path -LiteralPath $marker) { continue }
        $why = Get-FailReason $state.log
        if ($why.usage -or [int]$state.attempt -ge 2) {
            $state.status = 'failed'
            $reason = 'ended without an answer'
            if ($why.usage) { $reason = 'Codex is out of usage' }
            $state | Add-Member -NotePropertyName reason -NotePropertyValue $reason -Force
            Write-State $state
            Exit-With 6 "$reason. Last log lines:`n$($why.text)`nLog: $($state.log)"
        }
        Write-Output "codex-call: run $($state.attempt) ended without an answer; trying once more."
        $state = Start-Run ([int]$state.attempt + 1)
    }

    $runMinutes = ((Get-Date) - [datetime]::ParseExact($state.started, 'yyyy-MM-dd HH:mm:ss', $null)).TotalMinutes
    if ($runMinutes -gt $TimeoutMinutes) {
        & taskkill.exe /PID $state.pid /T /F 2>$null | Out-Null
        $state.status = 'failed'
        $state | Add-Member -NotePropertyName reason -NotePropertyValue "took over $TimeoutMinutes minutes" -Force
        Write-State $state
        Exit-With 6 "Codex took over $TimeoutMinutes minutes and was stopped. Log: $($state.log)"
    }

    if (((Get-Date) - $callStart).TotalMinutes -ge $MaxWaitMinutes) {
        Exit-With 3 "Codex is still working ($Task, $([int]$runMinutes) min so far). Run the same command again."
    }
    Start-Sleep -Seconds $PollSeconds
}

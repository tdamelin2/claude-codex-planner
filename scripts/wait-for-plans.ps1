# wait-for-plans.ps1
# The planning gate. The Claude manager runs this after writing its own plan and
# DONE file. It waits until the Codex plan is finished.
#
# Usage (from the project folder):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/wait-for-plans.ps1 -Phase 3
#   ... -Phase 3 -TimeoutMinutes 60     (after the user chose "wait longer")
#
# The Codex plan counts as finished when managers/codex/plans/phase-N/DONE exists,
# or when managers/claude/plans/phase-N/SKIP-codex exists (the user approved continuing
# without it).
# The first run writes managers/claude/plans/phase-N/GATE with the start time, so
# the timeout counts from the first run, across calls and sessions.
#
# Exit codes:
#   0  the Codex plan is ready (or skipped)
#   2  bad input (no project folder or no phase)
#   3  still waiting: this call waited MaxWaitMinutes; run it again
#   4  timed out: TimeoutMinutes have passed since the gate started; ask the user
#   5  Claude's own DONE file is missing; finish your own plan first
# Written for Windows PowerShell 5.1 and PowerShell 7. ASCII only.

param(
    [Parameter(Mandatory = $true)][int]$Phase,
    [int]$TimeoutMinutes = 30,
    [int]$MaxWaitMinutes = 9,
    [int]$PollSeconds = 15
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root 'phases.md'))) {
    Write-Output "wait-for-plans: can't find the project folder (no phases.md in $root)."
    exit 2
}
if ($Phase -lt 1) { Write-Output 'wait-for-plans: the phase number must be 1 or more.'; exit 2 }

$claudeDir = Join-Path $root "managers/claude/plans/phase-$Phase"
if (-not (Test-Path -LiteralPath (Join-Path $claudeDir 'DONE'))) {
    Write-Output "wait-for-plans: managers/claude/plans/phase-$Phase/DONE is missing. Finish your own plan first."
    exit 5
}

$gateFile = Join-Path $claudeDir 'GATE'
if (-not (Test-Path -LiteralPath $gateFile)) {
    Set-Content -LiteralPath $gateFile -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ASCII
}
$gateStart = [datetime]::ParseExact((Get-Content -LiteralPath $gateFile -TotalCount 1).Trim(),
    'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)

function Get-State([string]$Ai) {
    $dir = Join-Path $root "managers/$Ai/plans/phase-$Phase"
    if (Test-Path -LiteralPath (Join-Path $dir 'DONE')) {
        $line = (Get-Content -LiteralPath (Join-Path $dir 'DONE') -TotalCount 1)
        return "done ($line)"
    }
    if (Test-Path -LiteralPath (Join-Path $claudeDir "SKIP-$Ai")) { return 'skipped (the user approved)' }
    if (Test-Path -LiteralPath (Join-Path $dir 'plan.md')) { return 'waiting (a partial plan.md exists)' }
    if (Test-Path -LiteralPath $dir) { return 'waiting (started, no plan.md yet)' }
    return 'waiting (not started)'
}

$callStart = Get-Date
while ($true) {
    $codex = Get-State 'codex'
    $ready = (-not $codex.StartsWith('waiting'))
    $elapsed = [int]((Get-Date) - $gateStart).TotalMinutes

    if ($ready) {
        Write-Output "READY after $elapsed min | codex: $codex"
        exit 0
    }
    if (((Get-Date) - $gateStart).TotalMinutes -ge $TimeoutMinutes) {
        Write-Output "TIMED OUT after $elapsed min (limit $TimeoutMinutes) | codex: $codex"
        exit 4
    }
    if (((Get-Date) - $callStart).TotalMinutes -ge $MaxWaitMinutes) {
        Write-Output "STILL WAITING after $elapsed min (limit $TimeoutMinutes) | codex: $codex"
        exit 3
    }
    Start-Sleep -Seconds $PollSeconds
}

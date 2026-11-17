# start-phase.ps1
# Opens the two manager terminals for a phase in one Windows Terminal window:
#   Tab "Claude": claude --agent manager "/start N claude"
#   Tab "Codex" : codex '$start N codex'
#
# The Codex tab stays open after its plan is done: it answers Claude's Telegram
# questions about its plan until Claude closes the question window.
#
# Usage (from the project folder, in PowerShell):
#   .\scripts\start-phase.ps1 -Phase 3              new phase: both tabs
#   .\scripts\start-phase.ps1 -Phase 3 -Continue    resume: only the tabs still needed
#
# Each tab re-runs this script with -Tab, so every command is started by PowerShell
# itself with normal quoting (no nested quotes passed through Windows Terminal).
# The script writes no files. It checks first and stops with a plain message if
# something isn't ready.
# Written for Windows PowerShell 5.1 and PowerShell 7. ASCII only.

param(
    [Parameter(Mandatory = $true)][int]$Phase,
    [switch]$Continue,
    [ValidateSet('claude', 'codex')][string]$Tab = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

function Stop-Launch([string]$Message) {
    Write-Host ''
    Write-Host "Can't start yet: $Message" -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

# ---------------------------------------------------------------------------
# Inside a tab: start one manager and stay in that tab.
# ---------------------------------------------------------------------------
if ($Tab) {
    $verb = 'start'
    if ($Continue) { $verb = 'continue' }
    $host.UI.RawUI.WindowTitle = "$Tab - phase $Phase"
    Write-Host "Starting the $Tab manager for phase $Phase ($verb)..." -ForegroundColor Cyan
    switch ($Tab) {
        'claude' { & claude --agent manager "/$verb $Phase claude" }
        'codex'  { & codex ('$' + "$verb $Phase codex") }
    }
    Write-Host ''
    Write-Host "The $Tab manager has closed. You can close this tab." -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------------------
# Pre-flight checks.
# ---------------------------------------------------------------------------
if ($Phase -lt 1) { Stop-Launch 'the phase number must be 1 or more.' }

$missingTools = @()
foreach ($t in @('git', 'claude', 'codex', 'wt')) {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { $missingTools += $t }
}
if ($missingTools.Count -gt 0) {
    Stop-Launch ("these programs aren't installed or can't be found: " + ($missingTools -join ', ') +
        '. Install them (see SETUP.md), then open a new PowerShell window and try again.')
}

$ErrorActionPreference = 'Continue'
$null = & git rev-parse --verify HEAD 2>$null
$hasCommit = ($LASTEXITCODE -eq 0)
$status = @(& git status --porcelain --untracked-files=all 2>$null)
$ErrorActionPreference = 'Stop'
if (-not $hasCommit) {
    Stop-Launch 'this folder has no saved version (git commit) yet. Run: git init; git add -A; git commit -m "initial setup"'
}

$phasesFile = Join-Path $root 'phases.md'
if (-not (Test-Path -LiteralPath $phasesFile)) { Stop-Launch 'phases.md is missing.' }
$phasesText = Get-Content -LiteralPath $phasesFile -Raw -Encoding UTF8
if ($phasesText -notmatch "(?m)^## Phase $Phase\b") {
    Stop-Launch "phases.md has no '## Phase $Phase' section. Write that phase first."
}

$handoff = Join-Path $root "handoffs/phase-$Phase.md"
$claudePlans = Join-Path $root "managers/claude/plans/phase-$Phase"

if (-not $Continue) {
    $outside = @($status | Where-Object { $_ -and (($_.Substring(3) -replace '\\', '/') -notmatch '^managers/') })
    if ($outside.Count -gt 0) {
        Stop-Launch ("there are unsaved changes. Save them first with: git add -A; git commit -m `"before phase $Phase`"`n  Changed: " + (($outside | Select-Object -First 5) -join ', '))
    }
    if ((Test-Path -LiteralPath $handoff) -or (Test-Path -LiteralPath $claudePlans) -or
        (Test-Path -LiteralPath (Join-Path $root "managers/codex/plans/phase-$Phase"))) {
        Stop-Launch "phase $Phase has already been started. To pick it up again, run: .\scripts\start-phase.ps1 -Phase $Phase -Continue"
    }
}

# ---------------------------------------------------------------------------
# Decide which tabs to open.
# ---------------------------------------------------------------------------
$tabs = @('claude')
$planningOver = Test-Path -LiteralPath $handoff   # the merge has happened
# Codex is needed until the merge: first to plan, then (after its DONE file) as
# the Telegram liaison answering Claude's questions about its plan.
foreach ($ai in @('codex')) {
    if (-not $Continue) { $tabs += $ai; continue }
    if ($planningOver) { continue }
    if (Test-Path -LiteralPath (Join-Path $claudePlans "SKIP-$ai")) { continue }
    $tabs += $ai
}

# ---------------------------------------------------------------------------
# Open one Windows Terminal window with one tab per manager.
# ---------------------------------------------------------------------------
$titles = @{ claude = 'Claude'; codex = 'Codex' }
$colors = @{ claude = '#D97757'; codex = '#10A37F' }
$wtArgs = @('-w', 'new')
$first = $true
foreach ($t in $tabs) {
    if (-not $first) { $wtArgs += ';' }
    $first = $false
    $wtArgs += @('new-tab', '--title', "$($titles[$t]) - phase $Phase", '--tabColor', $colors[$t],
        '--suppressApplicationTitle', '-d', $root,
        'powershell.exe', '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath, '-Phase', "$Phase", '-Tab', $t)
    if ($Continue) { $wtArgs += '-Continue' }
}

$mode = 'Starting'
if ($Continue) { $mode = 'Resuming' }
Write-Host "$mode phase $Phase. Opening: $(($tabs | ForEach-Object { $titles[$_] }) -join ', ')." -ForegroundColor Cyan
if ($Continue -and $tabs.Count -eq 1) {
    Write-Host 'The plans are already merged, so Codex has nothing left to do. Only Claude opens.' -ForegroundColor Cyan
}
# Quote each argument that contains spaces, so folder paths with spaces survive.
$argString = ($wtArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
}) -join ' '
Start-Process -FilePath 'wt.exe' -ArgumentList $argString

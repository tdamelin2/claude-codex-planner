# block-dangerous.ps1
# PreToolUse hook for the PowerShell and Bash tools, set in .claude/settings.json.
# Applies only to the system agents (manager, coder-a, coder-b, tester, debugger,
# claude-researcher, claude-reviewer, cleanup). A normal session started without
# --agent is not affected.
# Codex may be started only through scripts/codex-call.ps1, never with flags that
# skip its sandbox or approvals.
#
# Blocked for every system agent:
#   git push, reset --hard, clean, rebase, stash, filter-branch, update-ref,
#   commit --amend, deleting or force-moving branches and tags, bulk
#   checkout/restore of the whole tree, deleting .git or a drive/home folder,
#   disk-level commands, and changes to .claude/agents, hooks, skills or settings,
#   .agents/, .codex/, AGENTS.md, scripts/, managers/codex/ or archive/.
# Blocked for the four worker agents (only the manager uses git to change history):
#   git add, commit, tag, merge, cherry-pick, revert, rm, mv, am, apply, reset,
#   checkout, switch, and restore (the debugger may restore single files).
# Exit 0 allows the command. Exit 2 blocks it, and the message on stderr goes back
# to the agent. Written for Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'

function Stop-Command([string]$Reason) {
    [Console]::Error.WriteLine("block-dangerous: $Reason")
    exit 2
}

try {
    $raw = [Console]::In.ReadToEnd()
    $data = $raw | ConvertFrom-Json
} catch {
    Stop-Command 'could not read the hook input, so the command was blocked.'
}

$agent = [string]$data.agent_type
$systemAgents = @('manager', 'coder-a', 'coder-b', 'tester', 'debugger', 'claude-researcher', 'claude-reviewer', 'cleanup')
if ($systemAgents -notcontains $agent) { exit 0 }

$cmd = [string]$data.tool_input.command
if (-not $cmd) { exit 0 }
$isWorker = $agent -ne 'manager'

# --- Secrets in environment settings -----------------------------------------
# Tokens and keys often live in Windows user settings (environment variables). No
# agent may list, print or copy them.
if ($cmd -match '(?i)(GetEnvironmentVariables?\(\s*\)|HKCU|HKEY_CURRENT_USER|\benv:\s*($|["''\s|;)])|(Get-ChildItem|gci|ls|dir|Get-Item|gi)\s+env:|\bcmd(\.exe)?\s+/c\s+set\b)') {
    Stop-Command 'reading environment settings (where tokens and keys are kept) is not allowed.'
}

# --- git ---------------------------------------------------------------------
# Finds each git call, skipping global options such as -C <path> or -c key=value,
# and captures the subcommand plus the rest of that command segment.
$gitPattern = '(?i)\bgit(?:\.exe)?(?:\s+(?:-C|-c)\s+(?:"[^"]*"|''[^'']*''|\S+)|\s+--?[\w-]+(?:=\S+)?)*\s+([\w-]+)([^;|&\r\n]*)'
foreach ($m in [regex]::Matches($cmd, $gitPattern)) {
    $sub = $m.Groups[1].Value.ToLower()
    $rest = ' ' + $m.Groups[2].Value + ' '

    switch ($sub) {
        'push'          { Stop-Command 'git push is not allowed. The user pushes.' }
        'clean'         { Stop-Command 'git clean is not allowed.' }
        'rebase'        { Stop-Command 'git rebase is not allowed.' }
        'stash'         { Stop-Command 'git stash is not allowed. It hides work from the ownership check.' }
        'filter-branch' { Stop-Command 'git filter-branch is not allowed.' }
        'update-ref'    { Stop-Command 'git update-ref is not allowed.' }
    }
    if ($sub -eq 'reset' -and $rest -match '\s--hard\b') { Stop-Command 'git reset --hard is not allowed.' }
    if ($sub -eq 'commit' -and $rest -match '\s--amend\b') { Stop-Command 'git commit --amend is not allowed. Make a new commit.' }
    if ($sub -eq 'branch' -and $rest -match '\s(-d|-D|--delete|-m|-M|--move|-f|--force)\b') { Stop-Command 'deleting, renaming or force-moving branches is not allowed.' }
    if ($sub -eq 'tag' -and $rest -match '\s(-d|--delete|-f|--force)\b') { Stop-Command 'deleting or moving tags is not allowed.' }
    if (($sub -eq 'checkout' -or $sub -eq 'restore') -and $rest -match '\s(\.|\*|:/)(\s|$)') {
        Stop-Command "bulk git $sub of the whole tree is not allowed. Name each file."
    }

    if ($isWorker) {
        $managerOnly = @('add', 'commit', 'tag', 'merge', 'cherry-pick', 'revert', 'rm', 'mv', 'am', 'apply', 'reset', 'checkout', 'switch')
        if ($managerOnly -contains $sub) {
            Stop-Command "git $sub is reserved for the manager, which owns git. Report what you need in your Report."
        }
        if ($sub -eq 'restore') {
            if ($agent -ne 'debugger') { Stop-Command 'git restore is reserved for the manager and the debugger.' }
            if ($rest -match '\s(--staged|-S|--source|-s)\b') { Stop-Command 'the debugger may only run git restore -- <file> on files it touched.' }
        }
    }
}

# --- deleting critical folders ------------------------------------------------
$deletePattern = '(?i)(?:^|[\s;|&(])(Remove-Item|ri|rm|rmdir|rd|del|erase)\b([^;|&\r\n]*)'
foreach ($m in [regex]::Matches($cmd, $deletePattern)) {
    $args2 = ' ' + $m.Groups[2].Value + ' '
    if ($args2 -match '(?i)(^|[\s''"/\\])\.git([\s''"/\\]|$)') { Stop-Command 'deleting the .git folder is not allowed.' }
    if ($args2 -match '(?i)\s[''"]?[A-Za-z]:\\?[''"]?(\s|$)') { Stop-Command 'deleting a drive root is not allowed.' }
    if ($args2 -match '(?i)\s[''"]?(/|~|\$HOME|\$env:USERPROFILE|\$env:HOMEPATH)[''"]?(\s|$)') { Stop-Command 'deleting the root or home folder is not allowed.' }
    if ($args2 -match '(?i)\s[''"]?\.\.[\\/]?[''"]?(\s|$)') { Stop-Command 'deleting a parent folder is not allowed.' }
}

# --- Codex ----------------------------------------------------------------------
# Codex runs only through scripts/codex-call.ps1, inside its own sandbox.
if ($cmd -match '(?i)(^|[;|&(]|&&)\s*(&\s*)?codex(\.cmd|\.ps1|\.exe)?(\s+(exec|e|resume|fork|apply|cloud|mcp|login|logout|sandbox)\b|\s+-|\s*$|\s*[;|&])' -or $cmd -match '(?i)--dangerously|--approve-for-me|danger-full-access') {
    Stop-Command 'start Codex only with scripts/codex-call.ps1 (it runs Codex inside its sandbox).'
}

# --- disk and machine level ---------------------------------------------------
if ($cmd -match '(?i)\b(Format-Volume|Clear-Disk|Initialize-Disk|diskpart|Stop-Computer|Restart-Computer)\b') {
    Stop-Command 'disk and machine level commands are not allowed.'
}

# --- system configuration -----------------------------------------------------
$configPath = '(?i)(\.claude[\\/](agents|hooks|skills|settings(\.local)?\.json)|\.agents[\\/]|\.codex[\\/]|\bAGENTS\.md|\bscripts[\\/](start-phase|wait-for-plans|codex-call)\.ps1|\.mcp\.json|managers[\\/]codex[\\/]|(?<![\w-]|[\w-][\\/])archive[\\/])'
$writeVerb = '(?i)(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|Rename-Item|Clear-Content|Tee-Object|\bsc\b|\bac\b|\bdel\b|\brm\b|\bmv\b|\bcp\b|\bren\b|\bni\b|(?<![0-9])>(?!&))'
if (($cmd -match $configPath) -and ($cmd -match $writeVerb)) {
    Stop-Command 'agents may not change .claude/agents, hooks, skills or settings, .agents/, .codex/, AGENTS.md, scripts/, managers/codex/ or archive/. Only the user (or the Codex manager, in its own folder) edits these.'
}

exit 0

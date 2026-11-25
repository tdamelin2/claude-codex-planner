# Setup for the two-manager system

Do this once per project. It takes about 15 minutes. Every step has a command you
can copy into PowerShell (the blue Windows command window). Run them from this
project folder unless a step says otherwise.

## 1. Install the programs
You need Git, Claude Code, Codex and Windows Terminal.

1. Codex needs Node.js. If `node --version` doesn't print a version, install Node.js
   from nodejs.org first. Then install Codex:

       npm install -g @openai/codex

2. Install Claude Code by following the instructions at claude.com/claude-code.

3. Close PowerShell and open a new window, so Windows finds the new programs. Check
   each one answers with a version number:

       git --version; claude --version; codex --version; wt --version

   `wt` is Windows Terminal. It comes with Windows 11. If it's missing, install
   "Windows Terminal" from the Microsoft Store.

## 2. Sign in and trust this folder
Codex asks once whether it may work in this folder ("trust"). The project settings
and its two helpers only switch on after you say yes.

1. Run `codex` in this folder. Sign in with your ChatGPT account when it asks, then
   say yes to trusting the folder.
2. Type `/status` and check that the permissions line mentions `codex-planner`. If
   it doesn't, the folder isn't trusted yet.
3. Type `/exit`.
4. Run `claude` in this folder and sign in. Type `/exit`.

## 3. Save a first version
Git saves versions of the project. The launcher won't start a phase without at
least one saved version. If this folder isn't a git repository yet, run:

    git init; git add -A; git commit -m "two-manager setup"

If it says the folder is already a repository, run only the last two commands.

## 4. Run the safety tests
These check that the system can't change files it shouldn't. Each one prints a
result; compare it with the expected answer.

1. Claude's guard blocks writing a phase file before both plans are in:

       $j = @{ tool_name = 'Write'; tool_input = @{ file_path = "$PWD\handoffs\phase-99.md" }; cwd = "$PWD" } | ConvertTo-Json -Depth 5
       $j | powershell -NoProfile -ExecutionPolicy Bypass -File .claude\hooks\guard-paths.ps1 -Agent manager; "exit code: $LASTEXITCODE"

   Expected: a message about the planning gate, then `exit code: 2`.

2. Live test in Codex: run `codex`, and type
   `create a file called test.txt in the project folder with the word hello`.
   Expected: the write fails or Codex asks permission. Answer no, then `/exit`.

3. Check nothing was created: `git status --short` should show nothing new.

## 5. Describe your project
Open `Overview.md` and `phases.md` and replace every `<fill in>`. Write only
Phase 1 to begin with; add later phases as you go. Then fill in the Project commands
in `CLAUDE.md`, or leave them as `<fill in>` and the managers will propose them in
Phase 1. Save your changes:

    git add -A; git commit -m "project description"

## 6. Everyday use
- Start a phase (opens two tabs: Claude and Codex):

      .\scripts\start-phase.ps1 -Phase 1

  Both managers first read what both sides learned in earlier phases. Each then
  sends its researcher to come up with ideas (at most 5), and its reviewer to check
  them against the code and try to prove its own checks wrong. Each writes its plan.
  The Codex tab says when its plan is finished; you can close it then. Claude waits
  for the Codex plan, then starts Codex by itself to merge the two plans (Codex has
  the final say). Claude runs any quick checks on your setup and asks you to
  approve. Reply `go`. While building, Claude asks Codex again whenever the plan
  needs to change. After the phase, a cleanup helper tidies the notes.

- Resume after something was interrupted:

      .\scripts\start-phase.ps1 -Phase 1 -Continue

- If the launcher says the previous phase's notes haven't been tidied, run the
  command it shows (the same Continue command, with the previous phase number) and
  wait until Claude says the cleanup is done.

- Check every finished phase against your md files and for quality (in the Claude
  tab, between phases):

      /review

## What each folder is for
| Folder or file | What it holds |
|---|---|
| `managers/claude/`, `managers/codex/` | Each manager's plans and notes |
| `managers/shared/` | What Codex may read from Claude after both plans are finished |
| `handoffs/` | The record of each phase |
| `Questions.md` | Every planning question and its answer |
| `Environment.md` | Facts about your machines, network and services that every agent reads |
| `reviews/` | Reports from `/review` |
| `.claude/` | Claude's agents, skills and safety hooks |
| `.codex/` | Codex settings and its two helpers (researcher and reviewer) |
| `.agents/` | Codex's start and continue skills, its role files (planning, merge, decide) and the plan format |
| `scripts/` | The launcher, the gate script and `codex-call.ps1` (Claude uses it to run Codex) |

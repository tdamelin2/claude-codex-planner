---
name: start
description: Plans and starts a new phase of the multi-agent coding system as the Claude manager. Use when the user runs /start with a phase number and the role "claude".
argument-hint: "[phase-number] claude"
arguments: [phase, role]
disable-model-invocation: true
shell: powershell
---

# Start a new phase (Claude manager)

You are the Claude manager starting Phase $phase. This session should have been
started with `claude --agent manager` (the launcher `scripts/start-phase.ps1` does
this). If it wasn't, tell the user in plain words to close this window and run
`.\scripts\start-phase.ps1 -Phase $phase`, then stop. Below, N means this phase
number. Codex is planning the same phase in its own terminal right now.

## Current state (collected when this skill runs)
- Role given: "$role"
- Git repository: !`git -C "${CLAUDE_PROJECT_DIR}" rev-parse --is-inside-work-tree 2>&1`
- Handoff files, newest first: !`Get-ChildItem "${CLAUDE_PROJECT_DIR}/handoffs" -Filter "phase-*.md" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty Name`
- Planning files for this phase: !`Get-ChildItem "${CLAUDE_PROJECT_DIR}/managers/*/plans/phase-$phase" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName`
- Uncommitted changes: !`git -C "${CLAUDE_PROJECT_DIR}" status --short 2>&1`
- Last commits: !`git -C "${CLAUDE_PROJECT_DIR}" log --oneline -5 2>&1`

## Step 1: Check the phase can start
Stop and tell the user in plain words if any of these is true:
- No phase number was given, or the role is given and isn't `claude`. Show the
  exact command: `/start <number> claude`.
- The folder isn't a git repository, or it has no commits yet. Give them the
  commands: `git init`, then `git add -A; git commit -m "initial setup"`.
- `Overview.md` is missing or still contains `<fill in` placeholders.
- `phases.md` is missing, has no `## Phase N` section, or that section still
  contains `<fill in` placeholders.
- `handoffs/phase-N.md` already exists, or `managers/claude/plans/phase-N/` already
  has files. Suggest `/continue N claude` instead.
- N is above 1 and the previous phase's handoff file is missing or its Status is
  not `Stage: Done`.
- There are uncommitted changes outside `managers/`. The integrity check after the
  gate depends on a clean starting point. Explain this simply and ask the user whether
  to commit them now as a separate "before phase N" commit
  (`git add -A; git commit -m "before phase N"`), or to stop so they can deal with
  them first. Changes under `managers/codex/` are the Codex manager working;
  leave them alone.

This doesn't stop you. Raise it as a question in your plan:
- The Project commands in `CLAUDE.md` still say `<fill in>`. Propose commands in the
  plan. The user can copy them into `CLAUDE.md` later.

## Step 2: Read before planning
Read these, in this order:
1. `Overview.md`: the project's goal and architecture.
2. `phases.md`: only the section for Phase N.
3. `CLAUDE.md` (already loaded): the Project commands, the helper rule and the
   Definition of Done.
4. `.agents/roles/plan-format.md`: the plan format both managers use.
5. `.claude/agent-memory/manager/MEMORY.md`: the Lessons section and the latest Log
   entries.
6. `Questions.md`, and the Summary section of the previous phase's handoff file, if
   there is one.

Don't open anything under `managers/codex/` yet.

## Step 3: Check the phase spec
List anything in the phase spec that blocks a clear plan:
- A requirement with no acceptance criterion
- Something ambiguous enough to change how the work is split
- A dependency on work no earlier phase delivered
Put each one in your plan's Questions table. Don't guess.

## Step 4: Run the planning steps
Follow `<planning>` in `manager.md`, steps 1 to 7: your own plan and DONE, the
gate, the integrity check, reading the plans, the merge, the questions, and the
approval summary. End your turn at step 7 with:
"Reply 'go' to start building, or tell me what to change."

## Step 5: After the user approves
Run the phase loop in `manager.md`, starting at step 1 (Setup). Use the approved
plan, including any changes the user asked for.

---
name: continue
description: Resumes an interrupted phase of the multi-agent coding system as the Claude manager, from the exact stage where it stopped, including the planning stages. Use when the user runs /continue.
argument-hint: "[phase-number] claude"
arguments: [phase, role]
disable-model-invocation: true
shell: powershell
---

# Continue an interrupted phase (Claude manager)

You are resuming as the Claude manager. This session should have been started with
`claude --agent manager` (the launcher `scripts/start-phase.ps1 -Phase <N> -Continue`
does this). If it wasn't, tell the user in plain words to close this window and use the
launcher, then stop. Don't send work to any agent or change any file until the user
approves the summary in Step 4. The one exception: in the planning stages
(Step 5, table rows P1 to P3) you may continue without asking.

## Current state (collected when this skill runs)
- Phase given: "$phase" | Role given: "$role"
- Handoff files, newest first: !`Get-ChildItem "${CLAUDE_PROJECT_DIR}/handoffs" -Filter "phase-*.md" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty Name`
- Planning files (every phase): !`Get-ChildItem "${CLAUDE_PROJECT_DIR}/managers/*/plans/phase-*" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName`
- Uncommitted changes: !`git -C "${CLAUDE_PROJECT_DIR}" status --short 2>&1`
- Last commits: !`git -C "${CLAUDE_PROJECT_DIR}" log --oneline -5 2>&1`
- Phase tags: !`git -C "${CLAUDE_PROJECT_DIR}" tag --list "phase-*" 2>&1`

## Step 1: Choose the phase
- If the role is given and isn't `claude`, show the user the exact command
  (`/continue <number> claude`) and stop.
- If a phase number was given, use it.
- Otherwise, use the highest phase that has a `managers/claude/plans/phase-N/`
  folder or a `handoffs/phase-N.md` whose Status is not `Stage: Done`.
- If the chosen phase (or, when no phase is unfinished, the newest phase) is
  `Stage: Done` and has a `phase-N-done` tag but no `phase-N-notes` tag, its cleanup
  is unfinished: run `<procedure>` step 8 for it without asking, tell the user it's done
  and that they can now start the next phase, then stop.
- If no phase is unfinished, tell the user and stop. Suggest starting the next phase with
  `.\scripts\start-phase.ps1 -Phase <next>`.

## Step 2: Work out the stage
| Case | Stage |
|---|---|
| No `handoffs/phase-N.md`, no `managers/claude/plans/phase-N/DONE` | P1: your own plan is unfinished |
| No `handoffs/phase-N.md`, your DONE exists | P2: gate, then the integrity check and the merge by Codex |
| `handoffs/phase-N.md` with `Stage: Approval` | P3: waiting for the user's approval |
| `handoffs/phase-N.md` with any other Stage | That Stage, as in the table in Step 5 |

## Step 3: Read before acting
Read these, in this order:
1. `Overview.md`: the project's goal and architecture.
2. `phases.md`: only the section for Phase N.
3. `.agents/roles/plan-format.md` if the stage is P1 to P3, and `Environment.md`.
4. `handoffs/phase-N.md` if it exists: the Status line, the Plan, every
   `### Plan note` and `### Contract change`, and the latest Round.
5. `.claude/agent-memory/manager/MEMORY.md`: the Lessons section and the latest Log
   entries.

For stages after P3, check that the records match the code and note every mismatch:
- A report placeholder (`<!-- report: ... -->`) still present for an agent that was
  already sent its task. That agent was interrupted.
- A Report marked Done with unticked checklist items.
- Uncommitted changes: which Part folders they're in, and which Work ID they belong
  to.
- Uncommitted changes in source or test folders while the Stage is Debug. These are
  leftover debug edits.
- A Status line that doesn't match the latest Round's contents.
- A Status of `Stage: Escalated`. Present the Escalation section and ask the user how to
  proceed.
Report mismatches. Don't fix them yet.

## Step 4: Summarize, then stop (stages after P3 only)
Write this for the user in plain language, with the technical names in brackets where
they help:

    Phase N: <name> | Stage: <stage> | Round: <x>/3, or 4 (re-plan)
    Done so far: <what works, and the Work IDs completed and tested>
    Interrupted: <what was in progress, and which agent>
    Still to do: <Work IDs and stages left>
    Problems found: <mismatches from Step 3, or "none">
    Decision needed: <for interrupted work: keep the uncommitted changes, or undo them and resend the task; or "none">
    Next step: <exact action and which agent>

End your turn with: "Reply 'go' to continue, or tell me what to change."

## Step 5: Resume
- **P1**: your plan file may be half-written. Rewrite it from scratch: follow
  `<planning>` in `manager.md` from step 1. Stay blind until your DONE exists.
- **P2**: follow `<planning>` from step 2 (the gate). The wait script remembers when
  the gate started, so a gate that already timed out exits 4 at once and you ask
  The user as usual. If `managers/codex/plans/phase-N/MERGED` or your `SKIP-codex-merge`
  already exists, skip to step 5. If a merge call was started, running the merge
  command again reattaches to it instead of starting a second Codex.
- **After Done**: if the phase has a `phase-N-done` tag but no `phase-N-notes` tag,
  run `<procedure>` step 8 (Cleanup) without asking.
- **P3**: show the user the approval summary again (`<planning>` step 7) and wait for
  "go".
- **After P3**, once the user approves:
  - Resume at the stage and round in the Status line. Never restart the phase or
    reset the round count.
  - Don't redo Work IDs that are already Done and tested.
  - For interrupted work, follow the user's decision: keep the uncommitted changes, or
    restore them and resend the task.
  - Append to `phase-N.md` only. Never edit earlier rounds.
  - If the user changed the plan, record the change as a `### Plan note` in the current
    round (`Decided by the user`).
  - An ask in `managers/shared/phase-N/asks.md` with no answer file yet was
    interrupted: run its decide call again (it reattaches or restarts).
  - Then continue the phase loop in `manager.md` from the step that matches the
    Stage:

  | Stage | Resume at |
  |---|---|
  | Code, Round 0 | Step 2 (Build), for the coders whose Reports aren't filled in |
  | Code, Round 1 to 3 | Step 5, at "Run the coders", for the Code Tasks not finished |
  | Code or Test, Round 4 (re-plan) | Step 7, at the matching point of steps 2 to 4 |
  | Test | Step 4. Resend the Test Task if its Report isn't filled in; otherwise act on the Result |
  | Debug | Step 5. Resend the Debug Task if its Report isn't filled in; otherwise route the failures |
  | Verify | Step 6 |
  | Plan | Step 7 |
  | Escalated | Whatever the user decided |

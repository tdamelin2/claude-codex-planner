---
name: review
description: Reviews every completed phase (or a range) as the Claude manager - checks the code still does what each phase's md files say, that all tests pass, and that the code is of reasonable quality - then writes a plain-language report. Use when the user runs /review.
argument-hint: "[phase-range, e.g. 2-4] (optional)"
arguments: [range]
disable-model-invocation: true
shell: powershell
---

# Review the project so far (Claude manager)

You are the Claude manager reviewing the whole project. You read and compare; you
never edit code, tests or the project's md files. The tester runs the tests. The
debugger joins only if tests fail. Range given: "$range" (empty means every
completed phase).

## Current state (collected when this skill runs)
- Handoff files: !`Select-String -Path "${CLAUDE_PROJECT_DIR}/handoffs/phase-*.md" -Pattern '^\s*Status:' -List -ErrorAction SilentlyContinue`
- Review files: !`Select-String -Path "${CLAUDE_PROJECT_DIR}/reviews/review-*.md" -Pattern '^\s*(Status|Progress):' -ErrorAction SilentlyContinue`
- Uncommitted changes: !`git -C "${CLAUDE_PROJECT_DIR}" status --short 2>&1`
- Phase tags: !`git -C "${CLAUDE_PROJECT_DIR}" tag --list "phase-*" 2>&1`

## Step 1: Check the review can run
Stop and tell the user in plain words if:
- This session wasn't started with `claude --agent manager`.
- A phase is in progress (a handoff file whose Status is not `Stage: Done`). A
  review checks finished work only. Suggest `/continue` first.
- There are uncommitted changes outside `reviews/`. Explain simply and give the
  command to commit them, or ask whether you should.
- No phase is Done yet.

Work out the phases to review: every phase whose handoff Status is `Stage: Done`,
limited to the range if one was given (`3` or `2-4`).

## Step 2: Start or resume the report
- If a review file has a Status other than `Stage: Done`, resume it: skip the
  phases listed on its `Progress:` line.
- Otherwise create `reviews/review-<yyyy-MM-dd-HHmm>.md`:

      # Review <yyyy-MM-dd HH:mm> | Phases <list>
      Status: Stage: Review | Updated: <time>
      Progress: reviewed none yet

      ## For the user
      (written last)

      ## Test Task
      Assigned: <time> | Phases: <list>
      Commands: <the full test suite, lint and type-check commands from CLAUDE.md>
      #### Report (tester fills this in)
      <!-- report: tester REVIEW -->

      ## Findings
      (one section per phase, added as each phase is reviewed)

      ## Cross-phase and documents
      (added at the end)

- Commit nothing yet.

## Step 3: Run the tests (one helper by default)
- Set Status to `Stage: Test` and send the tester with the review file path. It
  runs the full suite, lint and type-check, saves the log in logs/, and fills in
  its Report. It doesn't change tests.
- Only if anything fails: append a `## Debug Task` block (the failures, the log
  path, and the placeholder `<!-- report: debugger REVIEW -->`), set Status to
  `Stage: Debug`, and send the debugger with the review file path. It diagnoses
  only. Then check `git status --short`: only reviews/ may show changes.
- Set Status back to `Stage: Review`.

## Step 4: Review one phase at a time
For each phase, oldest first, read its `phases.md` section, its handoff file (Plan,
Decisions, Plan notes, Contract changes, Summary), its rows in `Questions.md`, and
the code in its Part folders (`git diff --stat phase-N-start phase-N-done` shows
what it changed). Then check:

**A. Matches the md files**
1. Requirements: every requirement and acceptance criterion in `phases.md` exists in
   the code. Name the file where each lives.
2. Plan vs result: the code follows the approved Plan, the Decisions table, every
   Plan note and Contract change, and the resolutions in `Questions.md`.
3. Still working: the tester's results for this phase's acceptance tests.
4. Fits together: names, data shapes, routes and commands this phase shares with
   other phases still line up.

**B. Reasonable quality**
5. Leftovers: TODOs, stubs, placeholders, debug prints, commented-out code.
6. Dead or duplicated code: unused functions, files or dependencies; logic copied in
   several places that should be shared.
7. Error handling: failures that are silently ignored, crashes on bad input, missing
   checks at the edges (user input, files, network).
8. Safety: secrets or passwords in code or committed files, unsafe handling of user
   input (for example building SQL or shell commands from it).
9. Clarity: functions that are far too long or deeply nested, misleading names,
   inconsistent style with the rest of the project.
10. Tests: important behavior with no test, tests that can't fail, skipped tests.
11. Lint and type-check results from the tester.

Judge quality as "reasonable for this project", not perfect. Report only issues
that matter: something that could break, mislead a later phase, or make the code
hard to change. Skip pure style preferences.

Append a `### Phase N: <name>` section under `## Findings`:

    Verdict: Works as described | Works with issues | Broken
    Requirements: <AC-1 ok (file), AC-2 ok (file), ...>
    | # | Severity | Kind | Finding | Where | md reference |
    |---|----------|------|---------|-------|--------------|
    | 1 | Broken / Mismatch / Doc drift / Quality-High / Quality-Low | <A1-A4 or B5-B11> | <one line> | <file:line> | <phases.md Phase N, AC-2> |

Then update the `Progress:` line (`reviewed 1, 2`) and the Status time. This lets a
later `/review` continue if the session ends.

Severity meanings:
- **Broken**: doesn't work, or a test fails.
- **Mismatch**: works, but not what the md files say.
- **Doc drift**: the md files contradict each other or the code.
- **Quality-High**: likely to cause a bug, a security problem, or trouble in a later
  phase.
- **Quality-Low**: worth fixing when convenient.

## Step 5: Cross-phase and documents
Under `## Cross-phase and documents`, check that `Overview.md`, `phases.md` and
`CLAUDE.md` (Project commands, folder layout) agree with each other and with the
code, and list each mismatch as Doc drift. Note anything that only shows up across
phases, such as two phases solving the same problem differently.

## Step 6: Write the For the user section
Replace `(written last)` with plain language, at most about 15 lines:
- One-line verdict, for example "Phases 1-4 work as described, with 2 things worth
  fixing."
- Each Broken, Mismatch and Quality-High finding in one plain sentence: what's
  wrong and why it matters to them.
- A count of the Quality-Low and Doc drift items ("plus 3 small clean-ups").
- What they can do next.

If anything needs fixing, add a `## Suggested fix phase` section that the user can copy
into `phases.md` (they own that file; you don't edit it), using its template:
`## Phase <next>: Fixes from review <date>` with Goal, Requirements (one per
finding to fix) and Acceptance criteria. Running it then goes through the normal
two-manager planning and approval gate.

## Step 7: Finish
- Set Status to `Stage: Done`.
- Add a manager memory Log entry:

      ### Review <date> | manager | phases <list>
      - Verdict: <...> | Findings: <count by severity>
      - Helpers: tester; debugger <used | not needed>
      - Lesson candidate: <a pattern a future plan should avoid, or "none">

- Run `git status --short`. Only reviews/ and .claude/agent-memory/ may show
  changes. Then run `git add -A; git commit -m "review: <date>"`.
- Tell the user in plain language: the verdict, the most important findings, and where
  the report is (`reviews/review-<date>.md`). If you suggested a fix phase, explain
  the two steps: copy the section into `phases.md`, then run
  `.\scripts\start-phase.ps1 -Phase <next>`.

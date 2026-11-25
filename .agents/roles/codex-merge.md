# Role: Codex merger (lead planner)

You are the Codex manager in merge mode. Both managers have planned phase N blind.
You now merge the two plans into the one plan Claude will build. **You have the
final say on the plan** (only the user overrides you). Claude runs you with
`codex exec` through `scripts/codex-call.ps1`; you run once, write your files and
end. Nobody can answer you during the run, so decide and give your reasons.

The prompt names the phase: `Merge phase N. Follow .agents/roles/codex-merge.md.`

## Read
1. `AGENTS.md`, `Overview.md`, the `## Phase N` section of `phases.md`, `CLAUDE.md`
   (Project commands, Definition of Done), `.agents/roles/plan-format.md`,
   `Environment.md` if it exists.
2. Both plans, in full:
   - yours: `managers/codex/plans/phase-N/` (plan.md, research.md, review.md)
   - Claude's: `managers/shared/phase-N/claude-plan/` (plan.md, research.md,
     review.md). Claude copies them there once both plans are DONE. Never try to
     open `managers/claude/`: your sandbox blocks it.
3. `Questions.md` (earlier answers) and the `## Summary` of `handoffs/phase-<N-1>.md`.
4. Any code a decision depends on. Never change it.

## Merge rules
- Build the best usable plan. Neither plan wins by default: weigh every idea and
  finding from both sides on its merits, including your own.
- Use each reviewer's `## Disproof` results. A Disproved claim is not used. An
  Unproven claim that the plan depends on goes to `## Reality checks`.
- Take compatibility findings seriously, from either side: they protect earlier
  phases.
- Adopt an idea only when it fits `Overview.md` (stack, constraints, out of scope)
  and is worth its effort.
- Coders 1 or 2 by the rule in `CLAUDE.md` ("Helpers: one by default").
- Every distinct suggestion from both plans gets one Decisions row, including
  rejected ones and the coder count.
- Questions: merge both plans' Questions. Resolve each from the project files with
  a Basis (file and section). Mark Escalated only what the files can't answer (an
  account detail, a secret, a preference the user never wrote down). Never guess those.

## Write `managers/codex/plans/phase-N/merged.md`
Use exactly the handoff layout Claude copies into `handoffs/phase-N.md`:

    # Phase N: <name> | merged plan
    Merged: <yyyy-MM-dd HH:mm> | Inputs: Claude <Done|Partial|missing>; Codex <Done|Partial>

    ## For the user
    <plain language, 5-10 lines: what this phase builds, how the work is split and
    why, which ideas came from which side, and what the user is approving. Follow the
    "Talking to the user" rules in AGENTS.md.>

    ## Plan
    Goal: <one line>
    Planning inputs: Claude <...>; Codex <...>; merged by Codex
    Coders: <1|2> - <reason>
    Part A (coder-a): <scope>
    Part A folders: <comma-separated paths>
    Part B (coder-b): <scope>                 (only when Coders is 2)
    Part B folders: <comma-separated paths>   (only when Coders is 2)
    Contract: <signatures, routes, data shapes between the parts; "none" with one coder>
    Work IDs: P<N>-A-01 <one line>; ...
    Acceptance criteria: AC-1 <criterion>; AC-2 ...
    Commands: <build, start, lint, type-check and test commands>
    Lessons applied: <lessons from either side's notes that shaped this plan, or "none">

    ## Reality checks
    | ID | Assumption | How to test | Who | Blocks |
    |----|------------|-------------|-----|--------|
    | P<N>-RC-01 | <unproven assumption the plan depends on> | <exact command or one-step check> | manager / the user / probe step | approval / Round 0 / none |

    ## Decisions
    | # | Source | Suggestion | Decision | Reason |
    |---|--------|------------|----------|--------|
    | 1 | Claude / Codex / both | <one line> | Adopted / Rejected / Changed | <one line> |

    ## Questions
    | ID | From | Blocking | Question | Resolution | Basis | Status |
    |----|------|----------|----------|------------|-------|--------|
    | P<N>-Q-CDX-01 | Codex | yes/no | ... | ... | <file > section> | Resolved / Escalated |
    (the same columns as Questions.md, so Claude can copy the rows as they are)
    (Escalated questions are written in plain language for the user, with your suggested
    answer and why.)

    ## Disproof
    | Claim you added in the merge | Result | Evidence |
    |------------------------------|--------|----------|

Part folder rules (the guard hook reads them): paths relative to the project root,
forward slashes, a path ending in `/` is a folder. The two lists must not overlap
and must not include `tests/`, `logs/`, `handoffs/`, `managers/`, `reviews/`,
`archive/` or `.claude/`.

## Disproof pass (last step before writing)
For every claim you added that neither reviewer already checked (a changed idea, a
new contract detail, a resolution, a coder-count reason), try to prove it wrong:
reopen the cited line, look for other callers, earlier phases' tests and ops
checklists, and any assumption about devices, network, outside services or the user's
real data. Mark each one Proven (evidence: file:line, command output or doc link),
Disproved (drop or flip it, and say why) or Unproven (move it to Reality checks
with the cheapest test).

## Finish
1. In `managers/codex/memory/codex-manager/MEMORY.md`, append one line to your
   existing `### P<N> | codex-manager` entry (written in the planning tab; don't
   write a second entry):
   `- Merge: adopted <n> Claude / <n> Codex suggestions; <n> reality checks; <n> escalated`.
2. Write `managers/codex/plans/phase-N/MERGED` containing one line:
   `<yyyy-MM-dd HH:mm> | merged`. Write it last. Claude treats it as "the merge is
   final".
3. End with one line: the path of merged.md and the counts above.

Write only inside `managers/codex/`. Never run commands that change files or git
state.

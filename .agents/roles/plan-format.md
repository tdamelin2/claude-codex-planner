# Plan format (both managers)

Each manager writes its plan to `managers/<ai>/plans/phase-N/plan.md` using exactly
this layout, so Claude can merge the two plans section by section. Everything in
the plan is technical and exact: it is read by Claude, not by the user.

    # Phase N: <name> | <Claude|Codex> plan
    Status: Done | Partial | Failed | Started: <yyyy-MM-dd HH:mm> | Finished: <yyyy-MM-dd HH:mm>
    Helpers: <Claude: 1|2 coders - one-line reason> <Codex: 2 - researcher then reviewer>

    ## Summary
    <at most 10 lines: the approach in short>

    ## Proposed split
    Coders: <1|2> - <reason>
    Part A: <scope> | Folders: <comma-separated paths>
    Part B: <scope> | Folders: <...>        (omit when Coders is 1)
    Contract: <signatures, routes, data shapes between the parts, or "none">
    Work IDs: P<N>-A-01 <one line>; P<N>-A-02 ...; P<N>-B-01 ...

    ## Findings
    <Claude: notes on the spec and the existing code>
    <Codex: two parts, as below>

    ### Ideas (Codex)
    | # | Idea | Reviewer | Reason | In my split | My note |
    |---|------|----------|--------|-------------|---------|
    | 1 | <short name: one line> | Keep / Maybe / Reject | <reviewer's reason, with file:line> | yes / no | <agree, or why you differ; for Maybe, whether the condition holds> |
    (every idea from research.md, including rejected ones; Effort and Sources
    stay in research.md)

    ### Compatibility (Codex)
    - [High|Medium|Low] <issue> | Where: <file:line> | Affects: <earlier phase or requirement> | Fix: <...>

    ## Files given   (Codex only)
    Researcher: <comma-separated paths, exactly as sent>
    Reviewer: <comma-separated paths, exactly as sent>

    ## Risks
    <what is likely to cause a fix round, and how the plan avoids it>

    ## Questions
    | ID | Blocking | Question | Suggested answer |
    |----|----------|----------|------------------|
    | P<N>-Q-<CLA|CDX>-01 | yes/no | ... | <your best answer and the file that supports it, or "none"> |

    ## Helper notes
    <what you kept from each helper's file, with the file name, or "none (no helpers)">

Rules:
- Folder paths are relative to the project root and use forward slashes. A path
  ending in `/` is a folder. Never list `tests/`, `logs/`, `handoffs/`, `managers/`
  or `.claude/` as a Part folder.
- Keep Work IDs to one line each. Acceptance criteria come from `phases.md`; refer
  to them as AC-1, AC-2 and so on instead of rewriting them.
- A question is blocking when the plan would change depending on the answer.
- `Status: Partial` means something is missing; say what under Risks.

## DONE file
After the plan and your memory entry are complete, create
`managers/<ai>/plans/phase-N/DONE` containing one line:

    <yyyy-MM-dd HH:mm> | <Status from the plan>

Never write `DONE` before the plan is complete. Claude treats its existence as
"this plan is final".

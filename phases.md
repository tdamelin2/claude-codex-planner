# Phases

You write this file. The manager reads only the section for the phase being
started. Copy the template below once per phase, replace N with the phase number
(for example `## Phase 1: Login`), and replace every `<fill in>` before running
`/start`.

Each acceptance criterion should be one checkable statement with a clear expected
result. The tester writes its tests from these criteria alone, so anything left
vague here becomes a question in the plan.

<!-- Template: copy from here
## Phase N: <fill in: name>

### Goal
<fill in: what this phase delivers, in one or two sentences>

### Requirements
- <fill in>

### Acceptance criteria
- AC-1: <fill in: e.g. "GET /users returns 200 and a JSON list of users">
- AC-2: <fill in>

### Depends on
<fill in: earlier phases or outside services this phase needs, or "none">

### Notes
<fill in: anything else the manager should know, or "none">
to here -->

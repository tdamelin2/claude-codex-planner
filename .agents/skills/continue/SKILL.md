---
name: continue
description: Resumes the planning work for a phase as the Codex manager after an interruption. Use only when the user's message is "continue <phase-number> codex".
---

# Continue a phase (Codex manager)

The user's message gives two values: the phase number N and your role, which must
be `codex`, for example `continue 3 codex`.

1. If either value is missing, or the role is not `codex`, stop and ask the user in
   plain words for the exact command, for example: "Please type: continue 3 codex".
2. Check you are running in Codex CLI. If you aren't, tell the user this tab is for the
   Codex manager and stop.
3. Read `AGENTS.md` (the shared rules), then your role file
   `.agents/roles/codex.md`.
4. Follow the **Continue** section of your role file for phase N.

Write nothing outside `managers/codex/`.

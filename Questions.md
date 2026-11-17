# Questions

The Claude manager writes this file. No other agent edits it. After the planning
gate, it copies every question from both plans here and resolves each one.

- **Resolved**: answered from the project files. The Basis column names the file and
  section that supports the answer.
- **Escalated**: nothing in the project files supports an answer. The user decides at the
  approval gate. Escalated questions are written in plain language.

Question IDs look like `P<phase>-Q-<CLA|CDX>-<number>`.

<!-- Each phase adds a section like this, newest phase last:

## Phase N: <name>
| ID | From | Blocking | Question | Resolution | Basis | Status |
|----|------|----------|----------|------------|-------|--------|
| PN-Q-CDX-01 | Codex | yes | ... | ... | Overview.md, Architecture | Resolved |
| PN-Q-CLA-01 | Claude | no | ... | User: ... | none found | Escalated |
-->

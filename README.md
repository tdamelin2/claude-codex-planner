# Multi AI Planner

**Two AI managers plan every phase of your project separately. Codex merges the plans and has the final say; Claude builds the code with a small team of AI helpers.**

Multi AI Planner is a ready-made setup for [Claude Code](https://code.claude.com/docs) and [Codex CLI](https://github.com/openai/codex). You describe your project and split it into phases. For each phase, Claude and Codex each write their own plan without seeing the other's. Codex merges the two plans and you approve. Then Claude's coders, tester and debugger build and test the phase, and Claude asks Codex whenever the plan needs to change. Every step is saved in plain files and git commits, so you can see what happened and pick up where you left off.

It's built for people who aren't programmers. The AIs talk to you in plain language, explain technical words, and give you one step at a time with the exact command to copy.

---

## What's new in version 2

- **Codex leads the planning.** Codex merges both plans and has the final say on the plan. Claude builds exactly what the merged plan says.
- **Both sides research and review.** Claude now has its own researcher and reviewer, like Codex.
- **Reviewers try to prove themselves wrong.** Every reviewer ends with a *disproof pass*: each claim is marked Proven (with evidence), Disproved (dropped) or Unproven. Unproven guesses about your machines or outside services become **reality checks**, quick tests run before building starts.
- **Shared notes.** Before planning, both sides read what both sides learned in earlier phases. Each still can't see the other's current plan.
- **A cleanup helper** tidies every agent's notes after each phase and moves facts about your machines into one shared file, `Environment.md`.
- **No Telegram.** Claude starts Codex by itself for each merge or decision (`scripts/codex-call.ps1`), and they talk through files. Codex is never left running, which saves usage.
- **Works when Codex can't.** If Codex is out of usage, Claude makes that one decision itself, records it, and tells you.

---

## What it does

```
            phases.md (you write what each phase must do)
                               │
                 Shared notes from earlier phases
                               │
          ┌────────────────────┴────────────────────┐
          ▼                                         ▼
   Claude manager                            Codex manager
   researcher: up to 5 ideas                 researcher: up to 5 ideas
   reviewer: checks + disproof pass          reviewer: checks + disproof pass
   writes its plan (can't see Codex's)       writes its plan (can't see Claude's)
          └────────────────────┬────────────────────┘
                               ▼
              Gate: both plans finished
              Integrity check: Codex changed only its own folder
                               ▼
              Codex merges the plans (final say) → handoffs/phase-N.md
              Reality checks run; open questions answered or asked to you
                               ▼
                     You approve ("go")
                               ▼
     Round 0: coder-a (and coder-b if needed) build → tester tests
     Rounds 1-3: debugger finds the cause → coders fix → tester re-tests
     Any change to the plan → Claude asks Codex in a file → Codex decides
     Still failing after round 3: Codex re-plans once, then you're asked
                               ▼
     Phase checked against the Definition of Done → committed and tagged
                               ▼
              Cleanup helper tidies every agent's notes
```

### The agents

| Agent | Tool | Job |
|---|---|---|
| **Codex manager** | Codex CLI | The lead planner. Plans each phase on its own, merges both plans, and decides every change to the plan. Never writes code. |
| **phase_researcher** | Codex CLI | Proposes up to 5 creative ideas for the phase. |
| **phase_reviewer** | Codex CLI | Checks each idea against the existing code, marks it Keep, Reject or Maybe, then tries to prove its own claims wrong. |
| **Claude manager** | Claude Code | Plans each phase on its own, then runs the build rounds exactly to the merged plan and checks the result. Owns git. Never edits code itself. |
| **claude-researcher** | Claude Code | Proposes up to 5 ideas for Claude's plan. |
| **claude-reviewer** | Claude Code | Checks those ideas against the code, then runs the same disproof pass. |
| **coder-a / coder-b** | Claude Code | Build the phase. One coder by default; two only when the phase has two separate parts, such as a backend and a frontend. |
| **tester** | Claude Code | Writes acceptance tests from your criteria (not from the code) and runs the whole test suite. |
| **debugger** | Claude Code | Finds the root cause of a failure and writes a fix plan. Never fixes code itself. |
| **cleanup** | Claude Code | After each phase, archives notes that no longer matter, merges duplicates and moves machine facts to `Environment.md`. Never deletes. |

---

## Benefits

- **Two independent opinions on every phase.** The planners can't see each other's work, so one AI's blind spots are less likely to slip through. Every idea from both sides gets a row in a Decisions table that says whether it was adopted and why.
- **Claims are checked, not trusted.** Every reviewer tries to disprove its own findings. What can't be proven from the code becomes a reality check before any code is written.
- **Protects earlier work.** Both reviewers check ideas against the code that already exists. Every phase must pass all tests from earlier phases before it counts as done.
- **Safety rails that are enforced, not just written down.** PowerShell hooks stop each agent from writing outside its own folders, reading the other planner's plan too early, pushing or rewriting git history, reading secrets from your settings, or starting Codex outside its sandbox. Codex can write only in its own folder.
- **Every change has one owner.** Each coder owns a fixed list of folders and the tester owns `tests/`, so a failure can always be traced back to whoever made the change. Every plan change says who decided it: Codex, Claude (if Codex was unavailable) or you.
- **A clear record, and resumable.** Each phase lives in one file (`handoffs/phase-N.md`) with the plan, reality checks, decisions, every round's reports and a summary. Git commits and tags mark each step. If anything is interrupted, `/continue` works out exactly where it stopped.
- **Fix rounds have a limit.** At most three fix rounds, then one re-plan, then it stops and asks you instead of looping forever.
- **The agents learn, and stay tidy.** Each agent keeps a short notes file. Both sides read each other's lessons, and the cleanup helper keeps the notes short and accurate.
- **Plain language for you, exact detail for the agents.** Messages and summaries written for you are simple. Plans and reports the agents read stay technical.
- **Project review.** `/review` checks every finished phase against your files, runs all tests, and suggests a fix phase you can copy in.

---

## Requirements

- Windows 10 or 11 with PowerShell (Windows PowerShell 5.1 or PowerShell 7) and Windows Terminal (`wt`)
- [Git](https://git-scm.com)
- [Node.js](https://nodejs.org) 18 or newer (Codex needs it)
- [Claude Code](https://code.claude.com/docs/en/setup), signed in with a Claude account
- [Codex CLI](https://github.com/openai/codex), signed in with a ChatGPT account

---

## Setup

The full step-by-step guide is in **[SETUP.md](SETUP.md)**. In short:

1. **Get the files.** Clone this repository into a new folder for your project:

       git clone https://github.com/tdamelin2/claude-codex-planner.git my-project
       cd my-project

   Copy the hidden folders (`.agents`, `.claude`, `.codex`) as well if you copy the files by hand.

2. **Install Codex** and check the tools:

       npm install -g @openai/codex
       claude --version; codex --version; wt --version

3. **Trust the folder in Codex.** Run `codex` in the folder, sign in, say yes to trusting it, then type `/status` and check the permissions line shows `codex-planner`.

4. **Describe your project.** Fill in every `<fill in>` placeholder in:
   - `Overview.md`: the goal, tech stack, architecture, folder layout and constraints
   - `phases.md`: one section per phase, each with requirements and acceptance criteria
   - `CLAUDE.md` → *Project commands*: install, build, start, lint, type-check and test commands (the managers can suggest them in the first plan)

5. **Save a starting point** (the launcher needs at least one commit):

       git add -A; git commit -m "project setup"

---

## Everyday use

| You want to | Run |
|---|---|
| Start a phase (opens a Claude tab and a Codex tab) | `.\scripts\start-phase.ps1 -Phase 1` |
| Resume after an interruption | `.\scripts\start-phase.ps1 -Phase 1 -Continue` |
| Review all finished phases (in the Claude tab, between phases) | `/review` |

When Claude shows you the merged plan, reply `go` to start building, or say what to change. You can close the Codex tab once it says its plan is finished; Claude starts Codex again by itself when it needs it. If the launcher says the previous phase's notes haven't been tidied, run the command it shows first.

---

## Folder layout

| Path | What it holds |
|---|---|
| `Overview.md`, `phases.md` | Your project description and phase specs (you write these) |
| `Environment.md` | Facts about your machines, network and services, which every agent reads |
| `CLAUDE.md` | Rules for all Claude agents, project commands and the Definition of Done |
| `AGENTS.md` | Rules for the Codex manager and its helpers |
| `SETUP.md` | Step-by-step setup guide |
| `Questions.md` | Every planning question and how it was answered |
| `.claude/agents/` | The Claude agents: manager, claude-researcher, claude-reviewer, coder-a, coder-b, tester, debugger, cleanup |
| `.claude/skills/` | The `/start`, `/continue` and `/review` commands |
| `.claude/hooks/` | Safety hooks: path guard, dangerous-command blocker, clean-tree check, auto-format |
| `.claude/agent-memory/` | Each Claude agent's lessons and log |
| `.codex/` | Codex settings (planning-only permissions) and its researcher and reviewer |
| `.agents/` | Codex's role files (plan, merge, decide), the plan format, and its start and continue skills |
| `managers/claude/`, `managers/codex/` | Each manager's plans for each phase, plus Codex's notes and merged plans |
| `managers/shared/` | What Codex may read from Claude once both plans are finished: Claude's plan and its questions |
| `handoffs/` | One record per phase (created as phases run) |
| `reviews/` | Reports from `/review` |
| `scripts/` | The phase launcher, the planning-gate script and `codex-call.ps1` (Claude uses it to run Codex) |
| `logs/` | Test output, debugger scratch files and Codex run logs (not committed) |

---

## Privacy and secrets

- No tokens, keys or personal details are stored in this repository.
- A hook blocks any agent command that tries to list or print your Windows environment settings, where tokens and keys are usually kept.
- `.gitignore` keeps `.env` files, logs and local settings out of git.

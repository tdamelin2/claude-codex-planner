# Multi AI Planner

**Two AI managers plan every phase of your project separately, then one of them merges the plans and builds the code with a small team of AI helpers.**

Multi AI Planner is a ready-made setup for [Claude Code](https://code.claude.com/docs) and [Codex CLI](https://github.com/openai/codex). You describe your project and split it into phases. For each phase, Claude and Codex each write their own plan without seeing the other's. Claude merges the two plans and asks you to approve. Then its coders, tester and debugger build and test the phase. Every step is saved in plain files and git commits, so you can see what happened and pick up where you left off.

It's built for people who aren't programmers. The AIs talk to you in plain language, explain technical words, and give you one step at a time with the exact command to copy.

---

## What it does

```
            phases.md (you write what each phase must do)
                               │
          ┌────────────────────┴────────────────────┐
          ▼                                         ▼
   Claude manager                            Codex manager
   writes its plan                    researcher: up to 5 ideas
   (can't see Codex's)                reviewer: Keep / Reject / Maybe
          │                           writes its plan (can't see Claude's)
          └────────────────────┬────────────────────┘
                               ▼
              Gate: both plans finished
              Integrity check: Codex changed only its own folder
              Optional: Claude asks Codex up to 5 questions on Telegram
                               ▼
              Claude merges the plans → handoffs/phase-N.md
              Open questions are answered from your files, or asked to you
                               ▼
                     You approve ("go")
                               ▼
     Round 0: coder-a (and coder-b if needed) build → tester tests
     Rounds 1-3: debugger finds the cause → coders fix → tester re-tests
     Still failing after round 3: Claude re-plans once, then asks you
                               ▼
     Phase checked against the Definition of Done → committed and tagged
```

### The agents

| Agent | Tool | Job |
|---|---|---|
| **Claude manager** | Claude Code | Writes its own plan, merges both plans, runs the build rounds, checks the result. Has the final say. Never edits code itself. |
| **coder-a / coder-b** | Claude Code | Build the phase. One coder by default; two only when the phase has two separate parts, such as a backend and a frontend. |
| **tester** | Claude Code | Writes acceptance tests from your criteria (not from the code) and runs the whole test suite. |
| **debugger** | Claude Code | Finds the root cause of a failure and writes a fix plan. Never fixes code itself. |
| **telegram-liaison** | Claude Code | Asks Codex questions about its plan in a Telegram group and records the answers. |
| **Codex manager** | Codex CLI | Plans the same phase on its own. Never writes code. |
| **phase_researcher** | Codex CLI | Proposes up to 5 creative ideas for the phase. |
| **phase_reviewer** | Codex CLI | Checks each idea against the existing code and marks it Keep, Reject or Maybe. |

---

## Benefits

- **Two independent opinions on every phase.** The planners can't see each other's work, so one AI's blind spots are less likely to slip through. Every idea from Codex gets a row in a Decisions table that says whether it was adopted and why.
- **Protects earlier work.** Codex's reviewer checks each idea against the code that already exists. Every phase must pass all tests from earlier phases before it counts as done.
- **Safety rails that are enforced, not just written down.** PowerShell hooks stop each agent from writing outside its own folders, reading the other planner's plan too early, pushing or rewriting git history, or reading the Telegram tokens. Codex runs with a planning-only permission profile that lets it write only in its own folder.
- **Every change has one owner.** Each coder owns a fixed list of folders and the tester owns `tests/`, so a failure can always be traced back to whoever made the change.
- **A clear record, and resumable.** Each phase lives in one file (`handoffs/phase-N.md`) with the plan, decisions, every round's reports and a summary. Git commits and tags mark each step. If anything is interrupted, `/continue` works out exactly where it stopped.
- **Fix rounds have a limit.** At most three fix rounds, then one re-plan, then it stops and asks you instead of looping forever.
- **The agents learn over time.** Each agent keeps a short memory file with lessons from earlier phases. Codex reads which of its ideas were adopted, so its later plans fit better.
- **Plain language for you, exact detail for the agents.** Messages and summaries written for you are simple. Plans and reports the agents read stay technical.
- **Project review.** `/review` checks every finished phase against your files, runs all tests, and suggests a fix phase you can copy in.

---

## Requirements

- Windows 10 or 11 with PowerShell (Windows PowerShell 5.1 or PowerShell 7) and Windows Terminal (`wt`)
- [Git](https://git-scm.com)
- [Node.js](https://nodejs.org) 18 or newer
- [Claude Code](https://code.claude.com/docs/en/setup), signed in with a Claude account
- [Codex CLI](https://github.com/openai/codex), signed in with a ChatGPT account
- Optional: a Telegram account, two Telegram bots and a group, so Claude can ask Codex questions about its plan. Without Telegram, phases still run and the question step is skipped.

---

## Setup

The full step-by-step guide is in **[SETUP.md](SETUP.md)**. In short:

1. **Get the files.** Clone this repository into a new folder for your project:

       git clone https://github.com/<your-username>/Multi_AI_Planner.git my-project
       cd my-project

   Copy the hidden folders (`.agents`, `.claude`, `.codex`) as well if you copy the files by hand.

2. **Install Codex** and check the tools:

       npm install -g @openai/codex
       claude --version; codex --version; wt --version

3. **Trust the folder in Codex.** Run `codex` in the folder, sign in, say yes to trusting it, then type `/status` and check the permissions line shows `codex-planner`.

4. **Optional: set up Telegram.** Create two bots with @BotFather (one for Claude, one for Codex) and a group with you and both bots. Save the secrets as Windows user settings, never in the project folder:

       setx TG_CLAUDE_TOKEN "paste-the-claude-bot-token"
       setx TG_CODEX_TOKEN "paste-the-codex-bot-token"
       setx TG_GROUP_ID "paste-the-group-id"

   Open a new PowerShell window and run the self-test:

       node scripts\telegram\telegram-mcp.mjs --selftest

5. **Describe your project.** Fill in every `<fill in>` placeholder in:
   - `Overview.md`: the goal, tech stack, architecture, folder layout and constraints
   - `phases.md`: one section per phase, each with requirements and acceptance criteria
   - `CLAUDE.md` → *Project commands*: install, build, start, lint, type-check and test commands (the manager can suggest them in its first plan)

6. **Save a starting point** (the launcher needs at least one commit):

       git add -A; git commit -m "project setup"

---

## Everyday use

| You want to | Run |
|---|---|
| Start a phase (opens a Claude tab and a Codex tab) | `.\scripts\start-phase.ps1 -Phase 1` |
| Resume after an interruption | `.\scripts\start-phase.ps1 -Phase 1 -Continue` |
| Review all finished phases (in the Claude tab, between phases) | `/review` |

When Claude shows you the merged plan, reply `go` to start building, or say what to change. Leave the Codex tab open until it says "You can close this tab".

---

## Folder layout

| Path | What it holds |
|---|---|
| `Overview.md`, `phases.md` | Your project description and phase specs (you write these) |
| `CLAUDE.md` | Rules for all Claude agents, project commands and the Definition of Done |
| `AGENTS.md` | Rules for the Codex manager and its helpers |
| `SETUP.md` | Step-by-step setup guide |
| `Questions.md` | Every planning question and how it was answered |
| `.claude/agents/` | The Claude agents: manager, coder-a, coder-b, tester, debugger, telegram-liaison |
| `.claude/skills/` | The `/start`, `/continue` and `/review` commands |
| `.claude/hooks/` | Safety hooks: path guard, dangerous-command blocker, clean-tree check, auto-format |
| `.claude/agent-memory/` | Each Claude agent's lessons and log |
| `.codex/` | Codex settings (planning-only permissions) and its researcher and reviewer |
| `.agents/` | Codex's role file, plan format, liaison rules, and start and continue skills |
| `managers/claude/`, `managers/codex/` | Each manager's plans for each phase, plus Codex's memory |
| `handoffs/` | One record per phase (created as phases run) |
| `reviews/` | Reports from `/review` |
| `scripts/` | The phase launcher, the planning-gate script and the Telegram connector |
| `logs/` | Test output and debugger scratch files (not committed) |

---

## Privacy and secrets

- No tokens, keys or personal details are stored in this repository.
- Telegram tokens and the group ID live only in Windows user settings (`TG_CLAUDE_TOKEN`, `TG_CODEX_TOKEN`, `TG_GROUP_ID`). Only the connector reads them, it never prints them, and a hook blocks any agent command that tries to read them.
- `.gitignore` keeps `.env` files, logs, local settings and Telegram state out of git.

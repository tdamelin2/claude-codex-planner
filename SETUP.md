# Setup for the two-manager system

Do this once. It takes about 15 minutes. Every step has a command you can copy into
PowerShell (the blue Windows command window). Run them from this project folder
unless a step says otherwise.

## 1. Install the tools
You need Git, Node.js (version 18 or newer), Claude Code and Codex.

1. Install Git from git-scm.com and Node.js from nodejs.org if you don't have them.
2. Install Claude Code by following the official guide at
   https://code.claude.com/docs/en/setup, then sign in the first time
   you run `claude` (a Claude subscription or API account is needed).
3. Install Codex (a ChatGPT account is needed to sign in):

       npm install -g @openai/codex

4. Close PowerShell and open a new window, so Windows finds the new program. Check
   all of them answer with a version number:

       claude --version; codex --version; wt --version

   `wt` is Windows Terminal. It comes with Windows 11. If it's missing, install
   "Windows Terminal" from the Microsoft Store.

## 2. Sign in and trust this folder
Codex asks once whether it may work in this folder ("trust"). The project settings
and its two helper agents only switch on after you say yes.

1. Run `codex` in this folder. Sign in with your ChatGPT account when it asks, then
   say yes to trusting the folder.
2. Type `/status` and check that the permissions line shows `codex-planner`. If
   it doesn't, the folder isn't trusted yet. (Its two helpers, `phase_researcher`
   and `phase_reviewer`, load from `.codex/agents/` once the folder is trusted.)
3. Type `/exit`.

## 3. Run the safety tests
These check that the system can't change files it shouldn't. Each one prints a
result; compare it with the expected answer.

1. Claude's guard blocks writing a phase file before both plans are in:

       $j = @{ tool_name = 'Write'; tool_input = @{ file_path = "$PWD\handoffs\phase-99.md" }; cwd = "$PWD" } | ConvertTo-Json -Depth 5
       $j | powershell -NoProfile -ExecutionPolicy Bypass -File .claude\hooks\guard-paths.ps1 -Agent manager; "exit code: $LASTEXITCODE"

   Expected: a message about the planning gate, then `exit code: 2`.

2. Live test in Codex: run `codex`, type
   `create a file called test.txt in the project folder with the word hello`.
   Expected: the write fails or Codex asks permission. Answer no.

3. Check nothing was created: `git status --short` should show nothing new
   (other than files you've changed yourself).

## 4. Set up Telegram (questions between the managers)
After both plans are finished, Claude can ask Codex questions about its plan in
your Telegram group. You can watch in the group; the bots ignore anything you type
there. If Telegram isn't working, phases still run: Claude just skips the
questions.

You need two Telegram bots (one for each manager) and a Telegram group that
holds you and both bots.

1. Create the bots. In Telegram, open @BotFather, send `/newbot` and follow the
   steps. Do this twice: one bot for Claude and one for Codex. BotFather gives you
   a token (a long secret password) for each bot. Keep the tokens private.

2. Optional: write the two bot usernames (without the @) in
   `scripts/telegram/bots.json`. The Telegram test then checks that each token
   was saved under the right name. Usernames are not secret; tokens never go in
   this file.

3. Create a Telegram group and add yourself and both bots.

4. Check Node.js (it runs the Telegram connector). It must show v18 or higher:

       node --version

5. Let the bots talk to each other. Telegram blocks bot-to-bot messages unless you
   allow them. In Telegram, open @BotFather, send `/mybots`, pick a bot, open
   **Bot Settings** and turn on **Bot-to-Bot Communication**. Do this for both
   bots. Leave **Group Privacy** turned on: that way each bot only sees messages
   meant for it.

6. Check the group has you and both bots. If you added a bot before step 5, remove
   it from the group and add it again, so Telegram applies the change.

7. Save the tokens and the group ID as Windows user settings (not in the project
   folder, so they're never saved into git or read by the AIs). Paste each token
   from @BotFather between the quotes:

       setx TG_CLAUDE_TOKEN "paste-the-claude-bot-token"
       setx TG_CODEX_TOKEN "paste-the-codex-bot-token"
       setx TG_GROUP_ID "paste-the-group-id"

   To find the group ID: open web.telegram.org/a in a browser, click the group,
   and copy the number at the end of the address, including the minus sign (for
   example `-1001234567890`).

8. Close PowerShell and open a new window (setx only reaches new windows), go to
   this folder, and run the Telegram test:

       node scripts\telegram\telegram-mcp.mjs --selftest

   Expected: every line starts with `[ OK ]` and the last line says
   "All checks passed". You'll see two short test messages in the group.
   Each `[FAIL]` line says what to fix. The most common ones:
   - "Missing Windows user settings": a setx command didn't run; repeat step 7
     and open a new window.
   - "belongs to @..., but the ... bot should be ...": two tokens were saved under
     the wrong names; repeat step 7 with the right tokens.
   - "did not receive Claude's test question": Bot-to-Bot Communication is off for
     a bot, or the bot needs to be removed and re-added to the group (steps 5-6).
   - "error 409": another program is reading the bots' messages. Close every
     Claude and Codex window for this project and run the test again.

9. Check each program sees the connector (it's called `telegram`):
   - Claude: run `claude` in this folder. If it asks whether to use the
     `telegram` server from `.mcp.json`, approve it. Type `/mcp` and check
     `telegram` is connected. Exit with `/exit`.
   - Codex: run `codex`, type `/mcp`, check `telegram` is listed. Exit with `/exit`.

If you ever need a new token (for example after `/revoke` in @BotFather), save it
again with setx on every computer that runs phases. Don't run phases on two
computers at the same time: Telegram lets only one program read each bot.

## 5. Save this setup

This folder isn't a git repository yet (git is what saves versions). Run this
once; the launcher won't start a phase without it:

    git init; git add -A; git commit -m "two-manager setup"

If it says the folder is already a repository, run only the last two commands.

## 6. Everyday use
- Start a phase (opens two tabs: Claude and Codex):

      .\scripts\start-phase.ps1 -Phase 1

  Codex first sends its researcher to come up with ideas (at most 5), then its
  reviewer to check them against the code, then writes its plan. It says when the
  plan is finished, then stays open in case Claude has questions about it on
  Telegram. Leave its tab open until it says "You can close this tab". It stops by
  itself when Claude is done asking, when the plans are merged, or after an hour
  with no questions. Claude waits for the Codex plan, asks its questions, merges
  the two plans, and asks you to approve. Reply `go`.
- Resume after something was interrupted:

      .\scripts\start-phase.ps1 -Phase 1 -Continue

- Check every finished phase against the md files and for quality (in the Claude
  tab, between phases):

      /review

## Copying this setup to a new project
Copy the whole folder (including the hidden `.agents`, `.claude` and `.codex`
folders). Then do steps 2, 3 and 5 above in the new folder.

## What each folder is for
| Folder or file | What it holds |
|---|---|
| `managers/claude/`, `managers/codex/` | Each manager's plans and memory |
| `handoffs/` | The record of each phase |
| `Questions.md` | Every planning question and its answer |
| `reviews/` | Reports from `/review` |
| `.claude/` | Claude's agents, skills and safety hooks |
| `.codex/` | Codex settings and its two helpers (researcher and reviewer) |
| `.agents/` | Codex's start and continue skills, its role file and the plan format |
| `scripts/` | The launcher, the gate script, and the Telegram connector (`scripts/telegram/`) |
| `.mcp.json` | Tells Claude where the Telegram connector is |

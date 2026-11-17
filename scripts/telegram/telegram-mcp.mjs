#!/usr/bin/env node
// telegram-mcp.mjs
// Telegram connector for the two-manager system. One small program, no
// dependencies (Node.js 18 or newer). Each tool starts its own copy as an MCP
// server over stdio, with its role:
//   node scripts/telegram/telegram-mcp.mjs --role claude   (Claude Code)
//   node scripts/telegram/telegram-mcp.mjs --role codex    (Codex)
// Setup check (run by the user, not by an AI):
//   node scripts/telegram/telegram-mcp.mjs --selftest
//
// What it allows (enforced here, not just in instructions):
//   - Only Claude asks. Codex only answers, and only questions from the Claude
//     bot. Messages from people in the group (the user) are ignored.
//   - Questions use IDs like P3-C-CDX-01 (to Codex), must name the handoff
//     section they are about (Ref), and are limited to 5 per phase plus one
//     follow-up each (ID ending in -F).
//   - Only messages in the configured group are read or sent.
//   - Codex stops waiting on its own (closed: true) when Claude has
//     closed the question window, when Claude's question step or merge is already
//     finished, when the user chose to continue without that manager, or after 60
//     minutes with no question / 120 minutes in total in this session. The AI
//     doesn't have to keep track of time.
//
// Settings are read from Windows user settings (set with setx) or the
// environment: TG_CLAUDE_TOKEN, TG_CODEX_TOKEN, TG_GROUP_ID.
// Tokens are never printed or returned to the AI.
//
// Telegram rules this relies on: each bot has Bot-to-Bot Communication Mode on
// (BotFather). With Group Privacy on, a bot only receives commands addressed to it
// (/ask@ThisBot) and replies to its own messages, which is exactly what is used.
//
// State (Telegram read position, questions asked, closed phases) is kept in
// managers/<role>/telegram/state.json, which git ignores.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const API = process.env.PHASE_CODER_TG_API || 'https://api.telegram.org';
const ROLES = ['claude', 'codex'];
const ANSWER_ROLES = ['codex'];
const TOKEN_VARS = { claude: 'TG_CLAUDE_TOKEN', codex: 'TG_CODEX_TOKEN' };
const CODE_TO_ROLE = { CDX: 'codex' };
const ROLE_TO_CODE = { codex: 'CDX' };
const LIMITS = {
  questionsPerManager: 5, followUpsPerQuestion: 1, answerMinutes: 10, maxText: 3500,
  // One tool call may wait up to maxWaitSeconds; Telegram is asked in chunks of
  // pollChunkSeconds (long polling). Fewer, longer calls keep the AI from looping.
  maxWaitSeconds: 300, defaultWaitSeconds: 40, pollChunkSeconds: 25,
  // The Codex liaison stops on its own after this, counted per session.
  liaisonIdleMinutes: 60, liaisonTotalMinutes: 120,
};
const QID_RE = /^P(\d+)-C-(CDX)-(\d{2})(-F)?$/;

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const role = argValue('--role');
const selftest = process.argv.includes('--selftest');

// ---------------------------------------------------------------------------
// Settings and Telegram calls
// ---------------------------------------------------------------------------
function readSetting(name) {
  const fromEnv = (process.env[name] || '').trim();
  if (fromEnv) return fromEnv;
  if (process.platform === 'win32') {
    // setx stores values here; a tool may have started before setx ran, or may
    // not pass environment variables on to this program.
    try {
      const out = execFileSync('reg', ['query', 'HKCU\\Environment', '/v', name],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true });
      const m = out.match(new RegExp(`${name}\\s+REG_(?:EXPAND_)?SZ\\s+(.*)`));
      if (m) return m[1].trim();
    } catch { /* not set */ }
  }
  return '';
}

let secrets = [];
function clean(text) {
  let s = String(text);
  for (const t of secrets) if (t) s = s.split(t).join('<token>');
  return s;
}

async function tg(token, method, params = {}, timeoutMs = 30000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let res;
  try {
    res = await fetch(`${API}/bot${token}/${method}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(params),
      signal: ctrl.signal,
    });
  } catch (e) {
    const err = new Error(`Telegram ${method}: could not reach Telegram (${e.name === 'AbortError' ? 'timed out' : 'network error'}). Check the internet connection, VPN or firewall.`);
    err.code = 'NETWORK';
    throw err;
  } finally {
    clearTimeout(timer);
  }
  let data;
  try { data = await res.json(); } catch { data = { ok: false, description: `HTTP ${res.status}` }; }
  if (!data.ok) {
    const err = new Error(`Telegram ${method}: ${data.description || 'error'} (code ${data.error_code || res.status})`);
    err.code = data.error_code || res.status;
    throw err;
  }
  return data.result;
}

let cfgPromise = null;
function config() {
  if (!cfgPromise) cfgPromise = loadConfig().catch((e) => { cfgPromise = null; throw e; });
  return cfgPromise;
}

async function loadConfig() {
  const tokens = {};
  for (const r of ROLES) tokens[r] = readSetting(TOKEN_VARS[r]);
  const groupId = readSetting('TG_GROUP_ID');
  secrets = Object.values(tokens);
  const missing = ROLES.filter((r) => !tokens[r]).map((r) => TOKEN_VARS[r]);
  if (!groupId) missing.push('TG_GROUP_ID');
  if (missing.length) {
    throw new Error(`Missing Windows user settings: ${missing.join(', ')}. See SETUP.md, section "Telegram".`);
  }
  let expected = {};
  try { expected = JSON.parse(fs.readFileSync(path.join(ROOT, 'scripts', 'telegram', 'bots.json'), 'utf8')); } catch { /* optional */ }
  const usernames = {};
  const ids = {};
  for (const r of ROLES) {
    let me;
    try {
      me = await tg(tokens[r], 'getMe');
    } catch (e) {
      if (e.code === 401) throw new Error(`${TOKEN_VARS[r]} is not a valid bot token (Telegram says Unauthorized). Copy it again from @BotFather.`);
      throw e;
    }
    const want = expected[r];
    if (want && String(me.username).toLowerCase() !== String(want).toLowerCase()) {
      throw new Error(`${TOKEN_VARS[r]} belongs to @${me.username}, but the ${r} bot should be @${want} (scripts/telegram/bots.json). The tokens may be saved under the wrong names.`);
    }
    usernames[r] = me.username;
    ids[r] = me.id;
  }
  return { tokens, groupId: String(groupId), usernames, ids };
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
function stateFile() {
  return path.join(ROOT, 'managers', role, 'telegram', 'state.json');
}

function loadState() {
  try {
    const s = JSON.parse(fs.readFileSync(stateFile(), 'utf8'));
    return { offset: 0, asked: {}, received: {}, closed: [], ...s };
  } catch {
    return { offset: 0, asked: {}, received: {}, closed: [] };
  }
}

function saveState(s) {
  try {
    fs.mkdirSync(path.dirname(stateFile()), { recursive: true });
    fs.writeFileSync(stateFile(), JSON.stringify(s, null, 2));
  } catch {
    // Keep working from memory if the folder can't be written.
  }
}

let memState = null;
function state() {
  if (!memState) memState = loadState();
  return memState;
}

// Only one Telegram read at a time per bot.
let lock = Promise.resolve();
function serial(fn) {
  const run = lock.then(fn, fn);
  lock = run.catch(() => {});
  return run;
}

async function fetchMessages(waitSeconds) {
  const c = await config();
  const s = state();
  let updates;
  try {
    updates = await tg(c.tokens[role], 'getUpdates',
      { offset: s.offset || 0, timeout: waitSeconds, allowed_updates: ['message'] },
      (waitSeconds + 15) * 1000);
  } catch (e) {
    if (e.code === 409) {
      throw new Error('Another program is already reading this bot\'s messages (Telegram error 409). '
        + 'Close other windows of this tool for this project, and don\'t run a phase on two computers at once.');
    }
    throw e;
  }
  const msgs = [];
  for (const u of updates) {
    s.offset = u.update_id + 1;
    if (u.message && String(u.message.chat.id) === c.groupId) msgs.push(u.message);
  }
  saveState(s);
  return msgs;
}

function waitSeconds(value) {
  const n = Number.isFinite(value) ? Math.floor(value) : LIMITS.defaultWaitSeconds;
  return Math.max(0, Math.min(LIMITS.maxWaitSeconds, n));
}

// Long-poll Telegram until `found(msgs)` is true or the wait is over. Each
// getUpdates call waits at most pollChunkSeconds. `stop()` is checked before
// every chunk and can end the wait early (it returns a reason or null).
async function pollUntil(totalSeconds, found, stop = () => null) {
  const deadline = Date.now() + totalSeconds * 1000;
  const all = [];
  for (;;) {
    const reason = stop();
    if (reason) return { msgs: all, stopReason: reason };
    const left = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
    const chunk = Math.min(LIMITS.pollChunkSeconds, left);
    const msgs = await serial(() => fetchMessages(chunk));
    all.push(...msgs);
    if (found(msgs) || Date.now() >= deadline || chunk === 0) return { msgs: all, stopReason: null };
  }
}

function checkText(label, text) {
  const t = String(text || '').trim();
  if (!t) throw new Error(`${label} is empty.`);
  if (t.length > LIMITS.maxText) throw new Error(`${label} is ${t.length} characters; the limit is ${LIMITS.maxText}. Shorten it.`);
  return t;
}

async function send(text, extra = {}) {
  const c = await config();
  return tg(c.tokens[role], 'sendMessage', { chat_id: c.groupId, text, ...extra });
}

// ---------------------------------------------------------------------------
// Tools: shared
// ---------------------------------------------------------------------------
async function toolCheck() {
  const c = await config();
  const lines = [];
  const chat = await tg(c.tokens[role], 'getChat', { chat_id: c.groupId });
  lines.push(`Connected as @${c.usernames[role]} (${role}) in group "${chat.title || c.groupId}".`);
  for (const r of ROLES) {
    if (r === role) continue;
    try {
      const m = await tg(c.tokens[role], 'getChatMember', { chat_id: c.groupId, user_id: c.ids[r] });
      const inGroup = !['left', 'kicked'].includes(m.status);
      lines.push(`@${c.usernames[r]} (${r}): ${inGroup ? 'in the group' : 'NOT in the group'}`);
    } catch (e) {
      lines.push(`@${c.usernames[r]} (${r}): could not check (${clean(e.message)})`);
    }
  }
  lines.push(`Limits: ${LIMITS.questionsPerManager} questions per manager per phase, ${LIMITS.followUpsPerQuestion} follow-up each, ${LIMITS.answerMinutes} minutes to answer.`);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Tools: Claude
// ---------------------------------------------------------------------------
async function toolAsk({ to, qid, ref, question }) {
  const c = await config();
  const s = state();
  const m = QID_RE.exec(String(qid || ''));
  if (!m) throw new Error('qid must look like P3-C-CDX-01; a follow-up adds -F, e.g. P3-C-CDX-01-F.');
  const [, phase, code, , followUp] = m;
  const target = CODE_TO_ROLE[code];
  if (to !== target) throw new Error(`qid ${qid} is for ${target}, but "to" is ${to}.`);
  if (s.closed.includes(Number(phase))) throw new Error(`Phase ${phase} questions are closed.`);
  if (s.asked[qid]) throw new Error(`${qid} was already asked.`);
  const r = checkText('ref', ref);
  if (r.length > 200) throw new Error('ref must be short: the handoff file and section, e.g. "codex plan.md > Findings #2".');
  const q = checkText('question', question);

  const base = qid.replace(/-F$/, '');
  if (followUp) {
    const orig = s.asked[base];
    if (!orig) throw new Error(`Follow-up ${qid} needs the original question ${base} first.`);
    if (!orig.answer) throw new Error(`Wait for the answer to ${base} before asking a follow-up.`);
  } else {
    const count = Object.entries(s.asked).filter(([k, v]) =>
      !k.endsWith('-F') && v.phase === Number(phase) && v.to === target).length;
    if (count >= LIMITS.questionsPerManager) {
      throw new Error(`Limit reached: ${LIMITS.questionsPerManager} questions to ${target} in phase ${phase}.`);
    }
  }

  const text = `/ask@${c.usernames[target]} ${qid} | Ref: ${r}\n${q}`;
  const sent = await send(text);
  s.asked[qid] = { to: target, phase: Number(phase), ref: r, question: q, messageId: sent.message_id, askedAt: Date.now(), answer: null };
  saveState(s);
  return `Sent ${qid} to ${target} (@${c.usernames[target]}). Collect the answer with tg_wait_answers.`;
}

async function toolWaitAnswers({ wait_seconds }) {
  const c = await config();
  const s = state();
  const pendingBefore = Object.values(s.asked).filter((v) => !v.answer);
  const fresh = [];
  if (pendingBefore.length) {
    const isAnswer = (msg) => {
      const fromRole = ROLES.find((r) => r !== 'claude' && msg.from && msg.from.id === c.ids[r]);
      return Boolean(fromRole && msg.reply_to_message);
    };
    const { msgs } = await pollUntil(waitSeconds(wait_seconds), (batch) => batch.some(isAnswer));
    for (const msg of msgs) {
      const fromRole = ROLES.find((r) => r !== 'claude' && msg.from && msg.from.id === c.ids[r]);
      const replyTo = msg.reply_to_message && msg.reply_to_message.message_id;
      if (!fromRole || !replyTo) continue;
      const entry = Object.entries(s.asked).find(([, v]) => v.messageId === replyTo && v.to === fromRole);
      if (!entry) continue;
      const [qid, v] = entry;
      if (v.answer) continue;
      v.answer = String(msg.text || '').replace(new RegExp(`^${qid}\\s*\\|\\s*`), '');
      v.answeredAt = Date.now();
      fresh.push({ qid, from: fromRole, answer: v.answer });
    }
    saveState(s);
  }
  const now = Date.now();
  const pending = Object.entries(s.asked).filter(([, v]) => !v.answer).map(([qid, v]) => {
    const minutes = Math.floor((now - v.askedAt) / 60000);
    return { qid, to: v.to, minutes_waiting: minutes, overdue: minutes >= LIMITS.answerMinutes };
  });
  return JSON.stringify({ new_answers: fresh, still_pending: pending }, null, 2);
}

async function toolClose({ phase }) {
  const c = await config();
  const s = state();
  const n = Number(phase);
  if (!Number.isInteger(n) || n < 1) throw new Error('phase must be a phase number, e.g. 3.');
  for (const r of ANSWER_ROLES) {
    await send(`/close@${c.usernames[r]} P${n}`);
  }
  if (!s.closed.includes(n)) s.closed.push(n);
  saveState(s);
  const unanswered = Object.entries(s.asked).filter(([, v]) => v.phase === n && !v.answer).map(([k]) => k);
  return `Closed phase ${n} questions for Codex.` + (unanswered.length ? ` Unanswered: ${unanswered.join(', ')}.` : '');
}

async function toolNote({ text }) {
  const t = checkText('text', text);
  if (t.startsWith('/')) throw new Error('A note can\'t start with "/" (that would look like a command).');
  await send(`[Claude] ${t}`);
  return 'Posted.';
}

// ---------------------------------------------------------------------------
// Tools: Codex
// ---------------------------------------------------------------------------
// Per-session liaison clock (not saved to state.json, so a resumed phase in a new
// window gets a fresh 60/120 minutes).
const liaisonClock = {};

function fileExists(rel) {
  try { return fs.existsSync(path.join(ROOT, ...rel.split('/'))); } catch { return false; }
}

// Reasons the Codex liaison should stop waiting, even if Claude's /close
// message never arrives. Only checks whether files exist; never reads them.
function autoCloseReason(n) {
  if (fileExists(`handoffs/phase-${n}.md`)) {
    return 'Claude has already merged the plans for this phase.';
  }
  if (fileExists(`managers/claude/plans/phase-${n}/clarifications.md`)) {
    return "Claude's question step for this phase is already finished.";
  }
  if (fileExists(`managers/claude/plans/phase-${n}/SKIP-${role}`)) {
    return 'The user chose to continue this phase without this manager.';
  }
  const clock = liaisonClock[n];
  if (clock) {
    const now = Date.now();
    if (now - clock.lastActivity >= LIMITS.liaisonIdleMinutes * 60000) {
      return `No question from Claude for ${LIMITS.liaisonIdleMinutes} minutes.`;
    }
    if (now - clock.started >= LIMITS.liaisonTotalMinutes * 60000) {
      return `The ${LIMITS.liaisonTotalMinutes}-minute limit for answering questions has passed.`;
    }
  }
  return null;
}

async function toolWaitQuestions({ phase, wait_seconds }) {
  const c = await config();
  const s = state();
  const n = Number(phase);
  if (!Number.isInteger(n) || n < 1) throw new Error('phase must be a phase number, e.g. 3.');
  const done = (reason) => JSON.stringify({ closed: true, reason, questions: [] }, null, 2);
  if (s.closed.includes(n)) return done('Claude closed the question window for this phase.');
  if (!liaisonClock[n]) liaisonClock[n] = { started: Date.now(), lastActivity: Date.now() };

  const me = c.usernames[role].toLowerCase();
  const myCode = ROLE_TO_CODE[role];
  const questions = [];
  let closed = false;

  const handle = (msgs) => {
    for (const msg of msgs) {
      if (!msg.from || msg.from.id !== c.ids.claude) continue;   // only the Claude bot
      const text = String(msg.text || '');
      const close = /^\/close@(\w+)\s+P(\d+)\s*$/i.exec(text);
      if (close && close[1].toLowerCase() === me && Number(close[2]) === n) { closed = true; continue; }
      const ask = /^\/ask@(\w+)\s+(P\d+-C-CDX-\d{2}(?:-F)?)\s*\|\s*Ref:\s*([^\n]*)\n?([\s\S]*)$/i.exec(text);
      if (!ask || ask[1].toLowerCase() !== me) continue;
      const qm = QID_RE.exec(ask[2].toUpperCase());
      if (!qm || Number(qm[1]) !== n || qm[2] !== myCode) continue;
      const qid = ask[2].toUpperCase();
      if (s.received[qid] && s.received[qid].answered) continue;
      s.received[qid] = { messageId: msg.message_id, answered: false };
      questions.push({ qid, ref: ask[3].trim(), question: ask[4].trim(), message_id: msg.message_id });
    }
    return questions.length > 0 || closed;
  };

  const { stopReason } = await pollUntil(waitSeconds(wait_seconds), handle, () => autoCloseReason(n));
  if (questions.length) liaisonClock[n].lastActivity = Date.now();
  if (closed && !s.closed.includes(n)) s.closed.push(n);
  saveState(s);
  if (closed) {
    return JSON.stringify({ closed: true, reason: 'Claude closed the question window for this phase.', questions }, null, 2);
  }
  if (stopReason && !questions.length) return done(stopReason);
  return JSON.stringify({ closed: false, questions }, null, 2);
}

async function toolAnswer({ message_id, qid, text }) {
  const s = state();
  const m = QID_RE.exec(String(qid || ''));
  if (!m || m[2] !== ROLE_TO_CODE[role]) throw new Error(`qid must be one of the questions sent to you (P<phase>-C-${ROLE_TO_CODE[role]}-<nn>).`);
  if (s.closed.includes(Number(m[1]))) throw new Error(`Phase ${m[1]} questions are closed.`);
  const id = Number(message_id);
  const got = s.received[qid];
  if (!got || got.messageId !== id) throw new Error(`${qid} with message_id ${message_id} isn't a question you received. Use the values from tg_wait_questions.`);
  if (got.answered) throw new Error(`${qid} was already answered.`);
  const t = checkText('text', text);
  await send(`${qid} | ${t}`, { reply_parameters: { message_id: id } });
  got.answered = true;
  saveState(s);
  return `Answered ${qid}.`;
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------
const WAIT_PROP = { type: 'integer', minimum: 0, maximum: LIMITS.maxWaitSeconds, description: `Seconds to wait for new messages (0-${LIMITS.maxWaitSeconds}, default ${LIMITS.defaultWaitSeconds}). The call returns early as soon as something arrives.` };

const TOOLS = {
  tg_check: {
    roles: ROLES,
    description: 'Check the Telegram connection: this bot, the group, and whether the other bots are in it. Call once before asking or answering. If it fails, Telegram Q&A is unavailable this phase.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    run: toolCheck,
  },
  tg_ask: {
    roles: ['claude'],
    description: 'Ask Codex one question about the handoff (plan) it wrote for this phase. Max 5 per phase, plus one follow-up per question (qid ending in -F).',
    inputSchema: {
      type: 'object',
      properties: {
        to: { type: 'string', enum: ['codex'] },
        qid: { type: 'string', description: 'P<phase>-C-CDX-<nn>; add -F for a follow-up.' },
        ref: { type: 'string', description: 'The handoff file and section the question is about, e.g. "codex plan.md > Findings #2".' },
        question: { type: 'string', description: 'One clear, technical question.' },
      },
      required: ['to', 'qid', 'ref', 'question'],
      additionalProperties: false,
    },
    run: toolAsk,
  },
  tg_wait_answers: {
    roles: ['claude'],
    description: 'Wait for answers to the questions you asked. Returns new answers and the questions still pending, with minutes waited and an overdue flag after 10 minutes.',
    inputSchema: { type: 'object', properties: { wait_seconds: WAIT_PROP }, additionalProperties: false },
    run: toolWaitAnswers,
  },
  tg_close: {
    roles: ['claude'],
    description: 'Close the question window for a phase. Tells the Codex liaison to stop. Always call this at the end of the clarify step, even if you asked nothing.',
    inputSchema: { type: 'object', properties: { phase: { type: 'integer', minimum: 1 } }, required: ['phase'], additionalProperties: false },
    run: toolClose,
  },
  tg_note: {
    roles: ['claude'],
    description: 'Post a short status note in the group for the user to read, e.g. "Q&A for phase 3 is open". Not a question; the other bots ignore it.',
    inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false },
    run: toolNote,
  },
  tg_wait_questions: {
    roles: ANSWER_ROLES,
    description: 'Wait for questions from Claude about your handoff for this phase (use wait_seconds 300). Returns {closed, reason, questions:[{qid, ref, question, message_id}]}. closed=true means the question window is over: stop calling this tool. The connector decides this itself (Claude closed it, Claude already merged, or the time limit passed).',
    inputSchema: {
      type: 'object',
      properties: { phase: { type: 'integer', minimum: 1 }, wait_seconds: WAIT_PROP },
      required: ['phase'],
      additionalProperties: false,
    },
    run: toolWaitQuestions,
  },
  tg_answer: {
    roles: ANSWER_ROLES,
    description: 'Answer one question from Claude, using only your own handoff files. Pass the message_id and qid from tg_wait_questions.',
    inputSchema: {
      type: 'object',
      properties: {
        message_id: { type: 'integer' },
        qid: { type: 'string' },
        text: { type: 'string', description: 'The answer, technical and short. Say "Not in our plan." when the handoff does not cover it.' },
      },
      required: ['message_id', 'qid', 'text'],
      additionalProperties: false,
    },
    run: toolAnswer,
  },
};

function toolsForRole() {
  return Object.entries(TOOLS)
    .filter(([, t]) => t.roles.includes(role))
    .map(([name, t]) => ({ name, description: t.description, inputSchema: t.inputSchema }));
}

// ---------------------------------------------------------------------------
// MCP over stdio (newline-delimited JSON-RPC 2.0)
// ---------------------------------------------------------------------------
function write(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

async function handle(msg) {
  switch (msg.method) {
    case 'initialize':
      return {
        protocolVersion: (msg.params && msg.params.protocolVersion) || '2025-06-18',
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'phase-coder-telegram', version: '1.0.0' },
        instructions: `Telegram Q&A about the managers' handoffs. Role: ${role}. Read your liaison instructions before using these tools.`,
      };
    case 'ping':
      return {};
    case 'tools/list':
      return { tools: toolsForRole() };
    case 'tools/call': {
      const name = msg.params && msg.params.name;
      const tool = TOOLS[name];
      if (!tool || !tool.roles.includes(role)) {
        return { content: [{ type: 'text', text: `Unknown tool for role ${role}: ${name}` }], isError: true };
      }
      try {
        const text = await tool.run((msg.params && msg.params.arguments) || {});
        return { content: [{ type: 'text', text: clean(text) }] };
      } catch (e) {
        return { content: [{ type: 'text', text: clean(e.message) }], isError: true };
      }
    }
    default: {
      const err = new Error(`Method not found: ${msg.method}`);
      err.rpc = -32601;
      throw err;
    }
  }
}

function startServer() {
  if (!ROLES.includes(role)) {
    process.stderr.write('telegram-mcp: start with --role claude or --role codex (or --selftest).\n');
    process.exit(2);
  }
  const rl = readline.createInterface({ input: process.stdin });
  rl.on('line', async (line) => {
    if (!line.trim()) return;
    let msg;
    try { msg = JSON.parse(line); } catch {
      write({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
      return;
    }
    if (msg.id === undefined || msg.id === null) return; // notification
    try {
      write({ jsonrpc: '2.0', id: msg.id, result: await handle(msg) });
    } catch (e) {
      write({ jsonrpc: '2.0', id: msg.id, error: { code: e.rpc || -32603, message: clean(e.message) } });
    }
  });
  rl.on('close', () => process.exit(0));
}

// ---------------------------------------------------------------------------
// Self-test (run by the user from PowerShell)
// ---------------------------------------------------------------------------
async function runSelftest() {
  const say = (ok, text) => console.log(`${ok ? '[ OK ]' : '[FAIL]'} ${text}`);
  let failed = 0;
  let c;
  try {
    c = await loadConfig();
    say(true, `Settings found; bots: claude=@${c.usernames.claude}, codex=@${c.usernames.codex}`);
  } catch (e) {
    say(false, clean(e.message));
    console.log('\nFix this first, then open a NEW PowerShell window and run the test again.');
    process.exit(1);
  }
  for (const r of ROLES) {
    try {
      const hook = await tg(c.tokens[r], 'getWebhookInfo');
      if (hook.url) { say(false, `${r} bot has a webhook set (another service receives its messages), so the connector can't read them. Ask Claude for the command to clear it.`); failed++; }
      const chat = await tg(c.tokens[r], 'getChat', { chat_id: c.groupId });
      say(true, `${r} bot can see the group "${chat.title || c.groupId}"`);
    } catch (e) {
      say(false, `${r} bot: ${clean(e.message)}`);
      failed++;
    }
  }
  if (failed) { console.log('\nFix the failures above, then run the test again.'); process.exit(1); }

  // Round trip: Claude asks each bot a test question; that bot answers; Claude reads the answer.
  const drain = async (token) => {
    const ups = await tg(token, 'getUpdates', { offset: -1, timeout: 0 });
    if (ups.length) await tg(token, 'getUpdates', { offset: ups[ups.length - 1].update_id + 1, timeout: 0 });
  };
  // Message numbers (message_id) are only the same for every bot in supergroups.
  // In a basic group each bot sees the same message under its own number, so
  // messages are matched by sender and text, and replies use the reader's own
  // number. Anything else that arrived is counted, to help find the cause.
  const nameOf = (from) => {
    if (!from) return 'unknown';
    const r = ROLES.find((x) => c.ids[x] === from.id);
    return r ? `${r} bot` : (from.is_bot ? 'another bot' : 'a person');
  };
  const waitFor = async (token, match, seconds) => {
    const end = Date.now() + seconds * 1000;
    let offset = 0;
    const others = [];
    while (Date.now() < end) {
      const ups = await tg(token, 'getUpdates', { offset, timeout: 5, allowed_updates: ['message'] }, 20000);
      for (const u of ups) {
        offset = u.update_id + 1;
        if (!u.message) { others.push('a non-message update'); continue; }
        if (String(u.message.chat.id) !== c.groupId) { others.push(`a message from another chat (${u.message.chat.type})`); continue; }
        if (match(u.message)) {
          await tg(token, 'getUpdates', { offset, timeout: 0 });
          return { msg: u.message, others };
        }
        others.push(`a message from the ${nameOf(u.message.from)}`);
      }
    }
    if (offset) await tg(token, 'getUpdates', { offset, timeout: 0 });
    return { msg: null, others };
  };
  const seenText = (others) => (others.length
    ? ` It did receive ${others.length} other update(s): ${[...new Set(others)].join(', ')}.`
    : ' It received nothing at all in that time.');
  try {
    for (const r of ROLES) await drain(c.tokens[r]);
  } catch (e) {
    say(false, `couldn't read bot messages: ${clean(e.message)} (is a phase running? close it first)`);
    process.exit(1);
  }
  for (const r of ANSWER_ROLES) {
    const qid = `P0-C-${ROLE_TO_CODE[r]}-01`;
    try {
      const q = await tg(c.tokens.claude, 'sendMessage', { chat_id: c.groupId, text: `/ask@${c.usernames[r]} ${qid} | Ref: setup test\nConnection test. Please ignore.` });
      const got = await waitFor(c.tokens[r], (m) => m.from && m.from.id === c.ids.claude
        && String(m.text || '').startsWith(`/ask@${c.usernames[r]} ${qid} `), 20);
      if (!got.msg) {
        say(false, `${r} bot did not receive Claude's test question within 20 seconds.${seenText(got.others)} Check Bot-to-Bot Communication Mode for the ${r} bot in @BotFather, and close any Codex window that uses these bots.`);
        failed++;
        continue;
      }
      say(true, `${r} bot received Claude's question`);
      await tg(c.tokens[r], 'sendMessage', { chat_id: c.groupId, text: `${qid} | Test answer.`, reply_parameters: { message_id: got.msg.message_id } });
      const back = await waitFor(c.tokens.claude, (m) => m.from && m.from.id === c.ids[r]
        && m.reply_to_message && m.reply_to_message.message_id === q.message_id, 20);
      if (!back.msg) {
        say(false, `Claude bot did not receive ${r}'s answer within 20 seconds.${seenText(back.others)} Check Bot-to-Bot Communication Mode for the Claude bot in @BotFather.`);
        failed++;
        continue;
      }
      say(true, `Claude bot received ${r}'s answer`);
    } catch (e) {
      say(false, `${r} round trip: ${clean(e.message)}`);
      failed++;
    }
  }
  console.log(failed ? '\nSome checks failed. Fix them and run the test again.' : '\nAll checks passed. Telegram Q&A is ready.');
  process.exit(failed ? 1 : 0);
}

if (selftest) {
  runSelftest().catch((e) => { console.log(`[FAIL] ${clean(e.message)}`); process.exit(1); });
} else {
  startServer();
}

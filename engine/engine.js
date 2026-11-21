// Runs agents through the tools you already use, as themselves:
//   Claude Code through the Claude Agent SDK (your claude login, your settings, Claude Code's own system prompt),
//   Codex through `codex exec --json`.
// Agent Lab adds nothing to how they behave except two things you write yourself: an agent's job, and the
// decisions you saved to Memory. Leave both empty and the agent answers exactly as the tool does on its own.
import { query, forkSession } from '@anthropic-ai/claude-agent-sdk';
import { spawn, execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { newId, channelConv } from './store.js';
import { follow as followBackground } from './terminal.js';
import * as hands from './hands.js';

const HOME = os.homedir();
const SEARCH = [...(process.env.PATH || '').split(':'), `${HOME}/.local/bin`, '/usr/local/bin', '/opt/homebrew/bin', `${HOME}/.npm-global/bin`, `${HOME}/bin`];

export function findBinary(name) {
  for (const dir of SEARCH) {
    if (!dir) continue;
    const p = path.join(dir, name);
    try { fs.accessSync(p, fs.constants.X_OK); return p; } catch {}
  }
  return null;
}

const version = (bin) => new Promise((resolve) => {
  if (!bin) return resolve(null);
  execFile(bin, ['--version'], { timeout: 8000 }, (err, out) => resolve(err ? null : String(out).trim().split('\n')[0]));
});

export const OPERATORS = {
  'claude-code': { name: 'Claude Code', bin: 'claude', approvals: true },
  codex: { name: 'Codex', bin: 'codex', approvals: false },
};

// Tools sometimes report a whole JSON error; keep just its sentence.
export function readable(msg) {
  const t = String(msg ?? '').trim();
  try { const j = JSON.parse(t); return j?.error?.message || j?.message || t; } catch { return t; }
}

const base = (p) => (p ? path.basename(String(p)) : 'a file');
const clip = (s, n = 90) => { const t = String(s ?? '').replace(/\s+/g, ' ').trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };

// One plain line for a tool call: what the agent is doing, in words.
export function describeTool(name, input = {}) {
  if (String(name).startsWith(`mcp__${hands.SERVER}__`)) return hands.describe(name, input);
  switch (name) {
    case 'Bash': return { verb: 'Run', line: clip(input.command, 120), detail: input.command };
    case 'Edit': case 'MultiEdit': return { verb: 'Edit', line: base(input.file_path), detail: input.file_path };
    case 'Write': return { verb: 'Write', line: base(input.file_path), detail: input.file_path };
    case 'NotebookEdit': return { verb: 'Edit', line: base(input.notebook_path), detail: input.notebook_path };
    case 'Read': return { verb: 'Read', line: base(input.file_path), detail: input.file_path };
    case 'Glob': case 'Grep': return { verb: 'Search', line: clip(input.pattern, 80), detail: input.path };
    case 'WebFetch': return { verb: 'Open', line: clip(input.url, 80), detail: input.url };
    case 'WebSearch': return { verb: 'Search the web for', line: clip(input.query, 80) };
    case 'Task': case 'Agent': return { verb: 'Start a helper for', line: clip(input.description || input.prompt, 80) };
    case 'TodoWrite': return { verb: 'Update', line: 'its to-do list' };
    case 'AskUserQuestion': return { verb: 'Ask you', line: clip(input.questions?.[0]?.question || 'a question', 100) };
    default: return { verb: 'Use', line: name.replace(/^mcp__/, '').replace(/__/g, ' · ') };
  }
}

// What a change does to a file, from the tool's own input (old words out, new words in), until its result brings the
// real patch: [{ path, change: created|updated|deleted, lines: [{ k: '+'|'-'|' '|'~', t }] }] ('~' a gap).
export function diffOf(name, input = {}) {
  const lines = (t, k) => String(t ?? '').replace(/\n$/, '').split('\n').map((x) => ({ k, t: x }));
  if (name === 'Write' && typeof input.content === 'string') return [{ path: input.file_path, change: 'created', lines: lines(input.content, '+').slice(0, 400) }];
  if (name === 'Edit' || name === 'MultiEdit') {
    const edits = Array.isArray(input.edits) ? input.edits : [input];
    const out = [];
    edits.forEach((e, i) => {
      if (i) out.push({ k: '~', t: '' });
      if (e.old_string) out.push(...lines(e.old_string, '-'));
      if (e.new_string) out.push(...lines(e.new_string, '+'));
    });
    return out.length ? [{ path: input.file_path, change: 'updated', lines: out.slice(0, 400) }] : [];
  }
  return [];
}

// Claude's structured patch (hunks of " ", "-", "+" lines) as a diff.
export function diffOfPatch(file, hunks, created) {
  const out = [];
  (hunks || []).forEach((h, i) => {
    if (i) out.push({ k: '~', t: '' });
    for (const raw of h.lines || []) out.push({ k: raw[0] === '+' ? '+' : raw[0] === '-' ? '-' : ' ', t: raw.slice(1) });
  });
  return { path: file, change: created ? 'created' : 'updated', lines: out.slice(0, 400) };
}

// A unified diff (`@@` hunks) as a diff: Codex writes its changes this way.
export function diffOfUnified(file, text, kind) {
  const change = kind === 'add' ? 'created' : kind === 'delete' ? 'deleted' : 'updated';
  const out = [];
  if (!String(text || '').includes('@@')) {
    for (const t of String(text || '').replace(/\n$/, '').split('\n')) if (t || out.length) out.push({ k: change === 'created' ? '+' : ' ', t });
  } else {
    let started = false;
    for (const raw of String(text).split('\n')) {
      if (raw.startsWith('@@')) { if (started) out.push({ k: '~', t: '' }); started = true; continue; }
      if (!started || raw.startsWith('\\')) continue;
      out.push({ k: raw[0] === '+' ? '+' : raw[0] === '-' ? '-' : ' ', t: raw.slice(1) });
    }
  }
  return { path: file, change, lines: out.slice(0, 400) };
}

/// A tool result's words: a string, or the text of its blocks; capped (the tail is what matters).
export function resultText(content, extra) {
  let t = typeof content === 'string' ? content : Array.isArray(content) ? content.map((b) => (b?.type === 'text' ? b.text : b?.type === 'image' ? '[image]' : '')).join('\n') : '';
  if (extra && typeof extra === 'object' && typeof extra.stdout === 'string') t = [extra.stdout, extra.stderr].filter(Boolean).join('\n');
  return t.length > 16000 ? `…${t.slice(-16000)}` : t;
}

// The four modes (Mavis final launch's Mode card): what an agent may do without asking, by what a step can do (its
// risk). yes = goes ahead; ask = the approval card; no = refused. `look` = only commands that change nothing.
//   read  Read only    Looks and answers, changes nothing
//   ask   Ask first    Asks before every change it makes (the default)
//   auto  Auto         Edits and runs commands for you (deleting, sending, sharing, the internet still ask)
//   full  Full access  Acts like you, with network access
export const MODES = {
  read: { write: 'no', host: 'look', delete: 'no', send: 'no', share: 'no', net: 'ask' },
  ask: {},
  auto: { write: 'yes', host: 'yes' },
  full: { write: 'yes', host: 'yes', delete: 'yes', send: 'yes', share: 'yes', net: 'yes' },
};
export const modeOf = (p) => ({ plan: 'read', edits: 'auto' })[p] || (MODES[p] ? p : 'ask');
// A command that only looks: every program in it is one that reads, and nothing is written with > or tee.
const LOOKING = new Set(['ls', 'cat', 'head', 'tail', 'du', 'df', 'wc', 'find', 'grep', 'rg', 'stat', 'file', 'pwd', 'echo', 'printf', 'sort', 'uniq', 'cut', 'tr', 'awk', 'sed', 'tree', 'which', 'whoami', 'date', 'uname', 'mdls', 'mdfind', 'sw_vers', 'system_profiler', 'basename', 'dirname', 'realpath', 'readlink', 'column', 'less', 'more', 'xargs', 'true', 'test', 'cd', 'git', 'for', 'do', 'done', 'in', 'if', 'then', 'fi', 'while', 'jq', 'nl', 'diff', 'cmp', 'md5', 'shasum', 'lsof', 'ps', 'top', 'vm_stat', 'sysctl', 'defaults', 'plutil', 'osascript']);
export function onlyLooks(command) {
  const c = String(command || '');
  if (/(^|[^>&0-9])>(?!&)|>>|\btee\b|(^|\s)-(delete|exec|execdir|ok|fprint)\b|\bsed\s+-i|\bdefaults\s+(write|delete)|\bgit\s+(commit|push|reset|checkout|clean|add|rm|mv|merge|rebase|stash|tag|branch\s+-[dD])/.test(c)) return false;
  const words = c.split(/[;&|\n]+|\$\(|`/).map((s) => s.trim().replace(/^(sudo|env|\w+=\S+)\s+/, '').split(/\s+/)[0]).filter(Boolean);
  return words.length > 0 && words.every((w) => LOOKING.has(w.replace(/^\(+/, '')));
}

// What a step can do, in the words the approval card uses (Mavis: PromptPanel.riskText). File changes and ordinary
// commands can be allowed for the rest of a request; deleting, sending and sharing always ask.
export function riskOf(name, input = {}) {
  if (['Edit', 'MultiEdit', 'Write', 'NotebookEdit'].includes(name)) return 'write';
  if (name === 'Bash') {
    const c = String(input.command || '');
    if (/(^|[;&|]\s*|\s)(rm|rmdir|trash|shred)\s/.test(c) || /git\s+(reset\s+--hard|clean\s+-[a-z]*f)/.test(c)) return 'delete';
    if (/git\s+push|gh\s+(pr|issue|release)\s+(create|merge|comment)|npm\s+publish/.test(c)) return 'share';
    if (/curl\s[^|;]*-X\s*(POST|PUT|PATCH|DELETE)|curl\s[^|;]*(--data|-d\s)/.test(c)) return 'send';
    if (/\b(curl|wget|ssh|scp|nc|telnet|ftp)\b|\bgit\s+(clone|fetch|pull)\b|\b(npm|pnpm|yarn|pip3?|brew|gem|cargo)\s+(install|add|i)\b/.test(c)) return 'net';
    return 'host';
  }
  if (name === 'WebFetch' || name === 'WebSearch') return 'net';
  // The app's own panes: looking never asks; acting on a page or the shell is a step on this Mac, as a command is.
  if (name.startsWith(`mcp__${hands.SERVER}__`)) return 'host';
  if (name.startsWith('mcp__')) return 'send';
  return 'host';
}

// Mavis final launch's own rules (App/Sources/ShellRuntime.swift `voice`, NextSteps.swift Plan/Report instructions,
// the engine's REPLY_STYLE), word for word except where they named Mavis itself: every agent talks and works the way
// Mavis does. Kept as one list so the wording lives in one place. The app reads the hidden lines (ChatCore.swift).
const CHAT_RULES = [
  "You are the user's operating partner on their Mac: quiet, exact, unflappable, a little dry. Your words are read in a chat, so every extra sentence costs the user time.",
  "You operate; you don't advise. You have this Mac's files, apps, browser and terminal. When the user wants something done, do it, or, when it changes things or you need one detail, offer it in a single line (\"I'll mute the five servers you haven't opened in a year. Go ahead?\"). Never hand them steps to follow unless they ask how.",
  [
    'Length is the rule that matters most:',
    '- Default to one to three sentences, about 50 words at most. A simple question gets the shortest complete answer, often a fragment ("4:30.", "No, it doesn\'t build."). Before sending, cut every clause they wouldn\'t miss.',
    "- The answer comes first, in substance: the state, the number, the decision, the cause. Add what it means only if that isn't obvious, then at most one next step.",
    '- A broad question ("where are we", "what\'s wrong", "how\'s it going") still gets the short answer: the one or two things that matter most, not an inventory. Good: "Most of the parity work is built but none of it is committed, and it hasn\'t been built or run since. Shall I build it?"',
    '- Go longer only when this message asks for it (detail, a full list, a walkthrough, a draft, code), when a saved preference says the user wants more, or when a risk needs it. Even then: the shortest complete version, a few short lines; only the depth of heavy work goes in a report (below).',
    "- Don't narrate how you found out (what you read, ran or checked). Mention something you couldn't check only if it changes the answer, in one clause.",
    '- Shape. A quick answer is plain prose, one to three sentences. A reply that covers several things (what you did after work, a status, a comparison, a set of findings) always takes this one shape, so every answer reads the same: (1) one lead sentence saying what is now true, the outcome, in substance; (2) a short list, one bullet per area or finding, each starting with a bold label of one to three words and a colon, then one plain line (\"- **Side chats:** open beside the chat, with the chat\'s own box.\"); group by what the user cares about, never by file or by the order you worked; two to six bullets, sub-bullets only when an item truly has parts; (3) when it matters, one line on what isn\'t done or wasn\'t checked; (4) at most one question, on its own line, last. No headings in a reply (headings belong in a report). Never bold anything but those labels. Exceptions: a command, code or a file\'s contents in a fenced code block with its language; a small Markdown table when comparing items across the same fields. Run commands yourself; when the user asks for one to run, it goes in a bash block, never inline in a sentence.',
    "- Names are plain words: a file, folder, app, project, branch, setting or site is written as it is (Mavis final launch, index.html, ~/Desktop), never in backticks. Backticks are only for a short literal the user would type or copy, at most one or two in a reply. Don't bold names or labels.",
    '- One offer at most, as a short question ("Shall I…?"), never a menu of options. No capability lists.',
    '- No warm-up, no restating the question, no "Let me know if…", no exclamation marks or emoji. Vary how you phrase things; never sound like a template.',
    '- Exact names, times and numbers. After doing something, say what changed and where, in a line. In bad news: what failed, whether anything is at risk, the next safe step.',
  ].join('\n'),
  "Judgment is the user's, not yours, but asking costs them a step, so ask only when it pays. Read what they said closely; choices they already settled, even in passing, are settled. If what's left could be defaulted sensibly and changed in a moment later, default it and say so in a clause. Ask only about what is still open and would be costly to guess wrong: a vague request gets a question; a detailed one gets the work. Usually one question is enough. Never ask twice about the same thing, and never ask for permission to start.",
  'Work: use tools when real information or action is needed. Never claim something is done without fresh evidence. Keep internal workers, models, tools and task identifiers private. Treat correction as normal.',
  'Before you explain why something behaves as it does (looks squashed, runs slow, fails), find and read what actually produces it: search the project for it, follow it to the code or script that makes it, and only then answer, naming that file. Never explain from one nearby file and a guess.',
  "Everything you write is read by the user, including the words between your steps. Write those to them, in a full plain sentence about what's next (\"Next I'll check the script that makes the thumbnails.\"), never notes to yourself. If there's nothing worth saying between steps, say nothing. When a step fails and you can simply retry it (a wrong folder, a stale file, a typo), retry without a word about it. Mention a failure only when it changes what you can do or what you deliver.",
  "Before your first tool call in any reply, always write one short sentence saying what you're about to do (\"I'll check your disk, memory and recent crashes.\"), so the user knows before the work starts. Plans. Whenever you expect to use more than one tool call, or the user asks for several things, follow that sentence with one hidden line listing the whole mission, exactly like this: ⟦plan: Check disk space | Review memory use | Look through crash reports | Sum it up⟧ — two to seven steps, each two to six plain words a person would use for a part of the job, never a command, tool name or file path. Then work through the plan in order, one step at a time, the way a person ticks off a to-do list: make only that step's tool calls (several at once is fine when they belong to the same step), and once they're back write ⟦done: N⟧ (its number, from 1) before starting the next step. Never batch the tool calls of several steps together, and never tick a step before its work is done. The last step's tick comes just before your final message. The user sees this as a to-do list being ticked off as you go. Skip it only for a single quick action. Never mention these lines. Never write a to-do list as text: the ⟦plan⟧ line is the only one. Finishing. After work your final message takes the shape above: the lead sentence on what is now true, the labelled bullets of what changed (by area, in the user's words), the line on anything not done or not checked, and at most one question. Only heavy work gets a report, and a report always ends with ⟦/report⟧.",
  "Reports are for heavy work only: a long audit, deep research, a big comparison or plan, what changed across many files, when the full detail runs to well over a page. Then say the main answer in your words in one to three sentences, as you would to a colleague, and put the full detail after it, exactly like this: ⟦report: Two to five word title⟧ full Markdown, with headings, lists, tables and code ⟦/report⟧. It opens beside the chat as its own page. Be thorough inside it: the length and formatting rules don't apply there. For anything smaller, write no report: the detail goes in your reply itself, as compact as it can be. Don't repeat a report in your words and never mention the tag.",
  "Working. On a task with several steps, write one short plain sentence before a batch of tools when it helps the user follow along or when the plan changes (\"This needs its dependencies and an API key, so I'll set those up first.\"), then act. One sentence at a time, never a recap of what just ran. Your last words stand on their own.",
  'Memory. You are the same person in every chat, and you keep your own notes across all of them. When you learn something worth keeping for next time (how the user likes things done, a fact about them or their projects, a decision), write one hidden line exactly like this: ⟦remember: one short sentence⟧. Only lasting things, never what this one task is doing. Never mention these lines.',
].join('\n\n');
// Mavis's last word to the model on every turn (engine REPLY_STYLE): checked after everything else in the prompt.
const REPLY_CHECK = '<reply_check>Answer in your own voice, the answer first. A quick answer: one to three plain sentences. Several things (after work, a status, findings): the lead sentence on what is now true, then two to six bullets each opening with a bold label and a colon, then what isn\'t done or checked if it matters, then at most one question on its own line. No headings outside a report. Same shape every time, in fresh words.</reply_check>';

// Who a channel message is for: each member named as @Name (any case, a whole name), or all of them for @everyone.
// Longest names first, each match taken out, so "@mavis v2" never also wakes "mavis".
export function tagged(text, members) {
  if (/(^|[^\w@])@(everyone|all)\b/i.test(text)) return members;
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let rest = text; const out = [];
  for (const a of [...members].sort((x, y) => y.name.length - x.name.length)) {
    const re = new RegExp(`(^|[^\\w@])@${esc(a.name)}(?![\\w-])`, 'gi');
    if (re.test(rest)) { out.push(a); rest = rest.replace(re, '$1'); }
  }
  return members.filter((a) => out.includes(a));
}

// What a tagged agent reads in a channel: where it is, who else is here, what was said since it last spoke (at most
// 30 lines), then your message. Its session keeps the rest of the channel's history.
export function channelPrompt({ ws, ch, members, agent, before, text, own = false }) {
  const names = Object.fromEntries(members.map((a) => [a.id, a.name]));
  const lastOwn = before.map((m) => m.by === agent.id).lastIndexOf(true);
  const recent = before.slice(lastOwn + 1).filter((m) => m.role === 'user' || m.role === 'assistant').slice(-30)
    .map((m) => `${m.role === 'user' ? 'User' : names[m.by] || 'Another agent'}: ${clip(m.text, 600)}`);
  const others = members.filter((a) => a.id !== agent.id).map((a) => a.name);
  return [
    `You're ${agent.name}, in #${ch.name} of the "${ws.name}" workspace${others.length ? ` with ${others.join(', ')}` : ''}. ${agent.hidden ? 'You are this channel\'s assistant' : own ? 'You have been given this channel: you answer what the user posts here' : 'The user tagged you here'}; reply to the channel.`,
    recent.length ? `Said here since you last spoke:\n${recent.join('\n')}` : '',
    `The user's message:\n${text}`,
  ].filter(Boolean).join('\n\n');
}

/** Whose panes an agent's hands work on: its own chat's ("a1"), or the channel it's answering in ("a1@<conv>"), so
 *  a page it opens from a channel opens in that channel's browser, never in its DM's. */
/** A channel's run for one agent: its own key, so the agent's DM is never busy because of it. */
export const channelRunKey = (conv, agentId) => `ch:${conv}:${agentId}`;

/** The thought it's on: the last full sentence of its thinking so far. */
export function thoughtLine(t) {
  const parts = String(t || '').replace(/\s+/g, ' ').trim().split(/(?<=[.!?])\s+/).filter((x) => x.length > 12);
  const line = parts.length > 1 && !/[.!?]$/.test(parts[parts.length - 1]) ? parts[parts.length - 2] : parts[parts.length - 1];
  return line ? clip(line.replace(/\*\*/g, ''), 110) : null;
}
/** A step being written, before it runs: the file and how many lines so far, or the command. */
export function writingLine(tool, partial) {
  const s = String(partial || '');
  const path = s.match(/"(?:file_path|path|notebook_path)"\s*:\s*"([^"]+)"/)?.[1];
  const name = path ? path.split('/').pop() : null;
  if (/^(Write|Edit|MultiEdit|NotebookEdit)$/.test(tool) && name) {
    const body = s.match(/"(?:content|new_string|new_source)"\s*:\s*"([\s\S]*)$/)?.[1] || '';
    const lines = (body.match(/\\n/g) || []).length;
    return lines ? `${name} · ${lines} line${lines === 1 ? '' : 's'} so far` : name;
  }
  if (tool === 'Bash') { const c = s.match(/"command"\s*:\s*"((?:[^"\\]|\\.)*)/)?.[1]; return c ? clip(c.replace(/\\n/g, ' ').replace(/\\"/g, '"'), 110) : null; }
  return null;
}

export function handsId(run) { return run.by && run.conv ? `${run.agentId}@${run.conv}` : run.agentId; }

/** A step's tool, in words for "Preparing …": Bash → "a command". */
function stepName(tool) {
  const t = String(tool || '').toLowerCase();
  if (t.startsWith(`mcp__${hands.SERVER}__browser`)) return 'the browser';
  if (t.startsWith(`mcp__${hands.SERVER}__mac`)) return 'a step in an app';
  if (t.startsWith(`mcp__${hands.SERVER}__terminal`)) return 'the terminal';
  const table = [['bash', 'a command'], ['powershell', 'a command'], ['edit', 'a change'], ['multiedit', 'a change'], ['write', 'a file'],
    ['notebook', 'a change'], ['read', 'a read'], ['glob', 'a search'], ['grep', 'a search'], ['websearch', 'a web search'],
    ['webfetch', 'a page'], ['task', 'a helper'], ['agent', 'a helper'], ['todo', 'the plan'], ['askuser', 'a question']];
  return table.find(([k]) => t.includes(k))?.[1] || (t.startsWith('mcp__') ? 'a tool step' : 'the next step');
}

// Work or conversation (Mavis: buildCognitivePlan's intent). Conversation is answered without thinking first, so its
// words start at once; work (doing, checking, investigating, anything long) still thinks. Kept as one plain test so
// it's easy to see why a turn did or didn't think.
const WORK = /\b(check|run|fix|build|make|create|write|draft|edit|change|update|rename|move|delete|remove|clean|organi[sz]e|install|set ?up|deploy|test|debug|refactor|implement|add|analy[sz]e|audit|review|find|search|look (at|into|through|for)|list|scan|read|open|research|compare|plan|summari[sz]e|explain why|go through|dig)\b/i;
// Mavis's order, enforced: a reply that starts working before saying what it's about to do has its first tool call
// turned back once (twice at most) with this, so the user always sees the opening sentence and, for a job with
// several steps, the to-do card, before any step or approval.
/** "make it pop /stageshow please" → "/stageshow make it pop please": the first known command or skill written after
 *  other words moves to the front, where Claude Code runs it, with the rest as what it's asked. Unknown names stay put. */
export function leadCommand(text, names) {
  const t = String(text || '');
  if (/^\s*[\/$]/.test(t) || !names?.size) return t;
  const re = /(^|\s)([\/$])([\w:.-]+)(?=\s|$)/g;
  let m;
  while ((m = re.exec(t))) {
    if (!names.has(m[3].toLowerCase())) continue;
    const rest = (t.slice(0, m.index) + m[1] + t.slice(m.index + m[0].length)).replace(/[ \t]{2,}/g, ' ').trim();
    return `/${m[3]}${rest ? ` ${rest}` : ''}`;
  }
  return t;
}

/** The last turn ended before its answer (stopped, or the app closed mid-step): the agent picks up from where it was. */
export function cutOff(messages) {
  const last = [...messages].reverse().find((m) => m.role !== 'note');
  if (!last || last.role === 'user') return false;
  return last.role === 'tool' || last.role === 'thinking' || (last.role === 'error' && /^Stopped\.?$/.test(String(last.text || '').trim()));
}
export const RESUME_NOTE = "(Your last turn was cut off before you finished. Start with one short line to the user saying where you got to and what you'll do now, then carry on from there. If you were working through a plan, put the ⟦plan: …⟧ line again with what's left.)";
export const OPENING_NUDGE = "Not yet. Before your first tool call, write to the user one short plain sentence saying what you're about to do; when the job takes more than one tool call, put the hidden ⟦plan: step | step | …⟧ line on its own line right after that sentence. Then make this same tool call again. This is your own way of working, not a rule from outside: never mention this reminder, hooks or being stopped.";
const TAGS = /⟦[^⟧]*⟧?/g;
export function hasOpening(text) { return /[A-Za-z]{2}/.test(String(text || '').replace(TAGS, '')); }
export function isWork(text) { const t = String(text || ''); return t.length > 280 || WORK.test(t); }

// Claude Code runs on your own Claude plan, never on an API key that happens to be set on this Mac (Mavis final
// launch: subscriptionEnvironment). These are taken out of the environment it starts with.
const API_KEY_VARIABLES = ['ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL', 'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CODE_USE_BEDROCK',
  'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY', 'OPENAI_API_KEY', 'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'COMPOSIO_API_KEY'];
export function subscriptionEnvironment(env = process.env) {
  const child = { ...env, CLAUDE_AGENT_SDK_CLIENT_APP: 'agentlab/0.1.0' };
  for (const name of API_KEY_VARIABLES) delete child[name];
  return child;
}

export class Engine {
  constructor(store, emit) {
    this.store = store;
    this.emit = emit;
    this.runs = new Map();       // key -> run
    this.approvals = new Map();  // id -> pending approval
  }

  async operators() {
    const out = {};
    for (const [id, op] of Object.entries(OPERATORS)) {
      const bin = findBinary(op.bin);
      out[id] = { id, name: op.name, path: bin, version: await version(bin), approvals: op.approvals };
    }
    return out;
  }

  snapshot() {
    return [...this.runs.values()].map((r) => ({ key: r.key, agentId: r.agentId, conv: r.conv || null, by: r.by || null, turn: r.turn || null, chat: r.chat, operator: r.operator, startedAt: r.startedAt, activity: r.activity, preview: r.preview }));
  }

  pending() {
    return [...this.approvals.values()].map(({ resolve, signal, input, suggestions, ...a }) => ({
      ...a, command: a.tool === 'Bash' ? String(input?.command || '') : null, canAlways: !!suggestions?.length,
      // What the step is for, in the agent's own words (Bash's description): the card's title.
      about: typeof input?.description === 'string' && input.description.trim() ? input.description.trim().slice(0, 140) : null,
      ...(a.tool === 'AskUserQuestion' ? { questions: (input?.questions || []).map((q) => ({ question: q.question, header: q.header || '', multiple: !!q.multiSelect, options: (q.options || []).map((o) => ({ label: o.label, about: o.description || '' })) })) } : {}),
      ...(['Edit', 'MultiEdit', 'Write'].includes(a.tool) ? { diff: diffOf(a.tool, input) } : {}),
    }));
  }

  // What every agent is told on top of its tool's own prompt: how its work shows in the chat (a to-do card it ticks, a
  // short final message, a report card for depth), the job you wrote, its own notes, and the decisions of the workspace
  // it's working in. The app reads the hidden lines (native/Sources/ChatCore.swift); this is the only copy of the wording.
  appendFor(agent, ws = null) {
    const parts = [CHAT_RULES, hands.PROMPT];
    if (agent.job?.trim()) parts.push(`Your job, set by the user: ${agent.job.trim()}`);
    if (agent.memory?.length) parts.push(`Your own notes, from every chat you've had:\n${agent.memory.map((m) => `- ${m.text}`).join('\n')}`);
    const decisions = this.store.state.memory.filter((d) => !d.workspace || d.workspace === ws?.id);
    if (decisions.length) parts.push(`Decisions the user has made. Follow them:\n${decisions.map((d) => `- ${d.text}`).join('\n')}`);
    parts.push(REPLY_CHECK);
    return parts.join('\n\n');
  }

  // ---- agents ----------------------------------------------------------------------------------
  // A DM: you and one agent. Its conversation is the agent's own file; it works in its own folder.
  sendToAgent(agentId, text, images = []) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    if (this.runs.has(`agent:${agentId}`)) throw new Error(`${agent.name} is still working. Stop it first, or wait.`);
    if (this.compacting?.has(agentId)) throw new Error(`${agent.name} is compacting its conversation. One moment.`);
    const cut = cutOff(this.store.messages(agentId));
    const sent = this.store.addMessage(agentId, { role: 'user', text, ...(images.length ? { images } : {}) });
    this.emit({ type: 'messages', agentId });
    // A command or skill typed mid-message runs too: Claude Code only runs one that leads, so it's moved to the front.
    const asked = agent.operator === 'codex' ? text : leadCommand(text, this.commandNames(agent));
    this.#converse(agent, { conv: agentId, sent, prompt: cut ? `${asked}\n\n${RESUME_NOTE}` : asked, images, cwd: agent.cwd || HOME, ws: null });
    return `agent:${agentId}`;
  }

  // A channel is a session of its own (never an agent's DM): the agents you gave it answer there, each with its own
  // session for this channel and its own run, so their DMs are never busy or touched by it. Tag one to pick who
  // answers; untagged, the first of them answers; none given, the channel's own assistant does.
  sendToChannel(wsId, chId, text, images = []) {
    const ws = this.store.workspace(wsId);
    if (!ws) throw new Error('That workspace was removed.');
    const ch = (ws.categories || []).flatMap((c) => c.channels || []).find((c) => c.id === chId);
    if (!ch) throw new Error('That channel was removed.');
    const conv = channelConv(ws.id, ch.id);
    const before = this.store.messages(conv).slice();
    const granted = (Array.isArray(ch.agents) ? ch.agents : ch.agent ? [ch.agent] : []).map((id) => this.store.agent(id)).filter((a) => a && !a.hidden);
    // @ reaches any member (a tag brings them in); untagged, the channel's own agents answer.
    const members = (ws.members || []).map((id) => this.store.agent(id)).filter((a) => a && !a.hidden);
    const tags = tagged(text, [...new Map([...granted, ...members].map((a) => [a.id, a])).values()]);
    const answering = tags.length ? tags : granted.length ? [granted[0]] : [this.store.assistant()];
    // As in a chat: a message sent while the one answering works goes into its turn (it reads it at its next step).
    if (answering.length === 1) {
      const run = this.runs.get(channelRunKey(conv, answering[0].id));
      if (run && !run.ended && run.push) {
        const m = run.onSteer?.(String(text), images);
        if (run.push(String(text), images)) return conv;
        if (m) { this.store.removeMessage(conv, m.id); this.emit({ type: 'messages', agentId: conv }); }
      }
    }
    const sent = this.store.addMessage(conv, { role: 'user', text, ...(images.length ? { images } : {}) });
    this.emit({ type: 'messages', agentId: conv });
    for (const agent of answering) {
      const key = channelRunKey(conv, agent.id);
      if (this.runs.has(key)) {
        this.store.addMessage(conv, { role: 'error', text: `${agent.name} is still answering here. Wait for it, or stop it first.`, turn: sent.id, by: agent.id });
        this.emit({ type: 'messages', agentId: conv });
        continue;
      }
      // A command or skill (/compact, /review, $skill) goes to the agent as typed, as in a chat: wrapped in the
      // channel's words it would only be read as text.
      const led = agent.operator === 'codex' ? text : leadCommand(text, this.commandNames(agent));
      const command = !tags.length && /^[\/$][\w:-]/.test(led.trim());
      const prompt = command ? led.trim() : channelPrompt({ ws, ch, members: granted, agent, before, text, own: !tags.length });
      this.#converse(agent, { conv, sent, prompt, images, by: agent.id, cwd: ws.path || agent.cwd || HOME, ws, key });
    }
    return conv;
  }

  // One agent answering one message, in a DM (`by` unset) or a channel (`by` = the agent, so the app knows whose turn
  // it is). Every line of the reply carries its turn (the id of the message that started it), so the app groups a turn
  // by id, never by time or position. Each agent keeps one session per conversation.
  #converse(agent, { conv, sent, prompt, images = [], by = null, cwd, ws, key = null }) {
    const agentId = agent.id;
    // The turn every line belongs to: your message's id, then (when you send one while it works) the newest one's.
    const tagOf = () => ({ turn: run.turn || sent.id, ...(by ? { by } : {}) });
    const say = (m) => { const saved = this.store.addMessage(conv, { ...m, ...tagOf() }); this.emit({ type: 'messages', agentId: conv, key: run.key }); return saved; };
    const run = this.#newRun(key || `agent:${agentId}`, { agentId, conv, by, operator: agent.operator, turn: sent.id });
    const session = by ? agent.sessions?.[conv] : agent.sessionId;
    run.onSession = (sid) => {
      const cur = this.store.agent(agentId); if (!sid || !cur) return;
      if (!by && sid !== cur.sessionId) this.store.updateAgent(agentId, { sessionId: sid });
      if (by && sid !== cur.sessions?.[conv]) this.store.updateAgent(agentId, { sessions: { ...(cur.sessions || {}), [conv]: sid } });
    };
    run.onText = (t, sdk) => {
      for (const m of t.matchAll(/⟦\s*remember\s*:\s*([^⟧]+)⟧/gi)) this.store.remember(agentId, m[1]);
      const shown = t.replace(/\s*⟦\s*remember\s*:[^⟧]*⟧/gi, '');
      if (shown.trim()) say({ role: 'assistant', text: shown, ...(sdk ? { sdk } : {}) });
    };
    // Tools carry their call id and round (calls sent together are one round); `done` is set when the result is back.
    run.onTool = (d) => {
      if (run.turnedBack?.has(d.id)) return;
      say({ role: 'tool', verb: d.verb, text: d.line, toolId: d.id || null, round: d.round ?? null,
            ...(d.detail ? { detail: String(d.detail).slice(0, 4000) } : {}), ...(d.diff?.length ? { diff: d.diff } : {}), ...(d.sdk ? { sdk: d.sdk } : {}) });
    };
    // What the agent thought before acting: the words (when the model shows them) and how long.
    run.onThought = (t) => say({ role: 'thinking', text: t.text || '', seconds: t.seconds || 0 });
    // A message you sent while it worked: saved where you sent it; what follows is its turn.
    run.onSteer = (text, images) => { const m = say({ role: 'user', text, steered: true, ...(images?.length ? { images } : {}) }); run.turn = m.id; this.#emitRun(run); return m; };
    // A tool call turned back for its missing opening sentence was never a step: it leaves the chat.
    run.onTurnedBack = (toolId) => {
      const m = this.store.messages(conv).find((x) => x.toolId === toolId);
      if (m) { this.store.removeMessage(conv, m.id); this.emit({ type: 'messages', agentId: conv, key: run.key }); }
    };
    run.onToolDone = (toolId, failed, extra = {}) => {
      const m = this.store.messages(conv).find((x) => x.toolId === toolId);
      if (!m) return;
      const patch = { done: true, failed: !!failed };
      if (typeof extra.output === 'string' && extra.output) patch.output = extra.output;
      if (extra.diff?.length) patch.diff = extra.diff;
      this.store.updateMessage(conv, m.id, patch);
      this.emit({ type: 'messages', agentId: conv, key: run.key });
    };
    run.onEnd = (outcome) => {
      if (outcome.error) this.store.addMessage(conv, { role: 'error', text: outcome.error, ...tagOf() });
      // Keep a small ledger of every run (when, how long, what it cost when the tool reports it) for Usage.
      const now = Date.now(), cur = this.store.agent(agentId);
      const ledger = [...(cur?.ledger || []), { at: now, ms: now - run.startedAt, cost: outcome.cost ?? null, ok: !outcome.error }].slice(-500);
      // A channel's run never changes the agent's own chat status (done / stopped) in Messages.
      this.store.updateAgent(agentId, by ? { ledger } : { ledger, last: { state: outcome.error ? (outcome.stopped ? 'stopped' : 'failed') : 'done', at: now, cost: outcome.cost ?? null, seen: false } });
      // What the DM has used so far (tokens, cost, how full its context is): the Context tab reads it.
      if (!by) this.#noteUsage(agentId, outcome);
      this.emit({ type: 'messages', agentId: conv });
    };
    // Its helpers (sub-agents), saved with the conversation so they can be opened again later, and the commands that
    // are running long enough to show above the box.
    run.onHelper = (h) => { this.store.putHelper(conv, h); this.#emitHelper(run, h); };
    run.conv = conv;
    this.#start(run, agent.operator, { cwd, sessionId: session, model: agent.model, permission: modeOf(agent.permission), alwaysEdits: !!agent.alwaysEdits, append: this.appendFor(agent, ws), work: isWork(sent.text), setup: !!agent.claudeSetup, images, rewindAt: by ? null : agent.rewindAt || null }, prompt);
    if (!by && agent.rewindAt) this.store.updateAgent(agentId, { rewindAt: null });
  }

  // ---- existing chats (continue a Claude Code / Codex chat as it is) ---------------------------
  sendToChat(chat, text) {
    const key = `chat:${chat.operator}:${chat.id}`;
    if (this.runs.has(key)) throw new Error('This chat is still working.');
    const run = this.#newRun(key, { chat: { operator: chat.operator, id: chat.id }, operator: chat.operator });
    run.onText = (t) => this.emit({ type: 'chat-line', key, line: { role: 'assistant', text: t } });
    run.onTool = (d) => this.emit({ type: 'chat-line', key, line: { role: 'tool', verb: d.verb, text: d.line } });
    run.onEnd = (o) => this.emit({ type: 'chat-end', key, error: o.error || null });
    this.#start(run, chat.operator, { cwd: chat.cwd || HOME, sessionId: chat.id, permission: 'ask', append: '' }, text);
    return key;
  }

  // Stop is instant: the run ends here and now (the app shows it stopped at once), then the tool is told to abort and
  // winds down in the background. Anything it says after this is ignored (see #finish / `run.ended`).
  stop(key) {
    const run = this.runs.get(key);
    if (!run) return false;
    run.stopped = true;
    try { run.abort?.(); } catch {}
    this.#finish(run, { error: 'Stopped.' });
    return true;
  }

  stopAll() { for (const k of this.runs.keys()) this.stop(k); }

  // A message you send while the agent works goes into what it's doing (Claude: into the same request; Codex: into
  // the running turn). Returns false when it can't (it just finished, or the tool can't), so the app sends it after.
  steer(agentId, text, images = []) {
    const run = this.runs.get(`agent:${agentId}`);
    if (!run || run.ended || !run.push) return false;
    const m = run.onSteer?.(String(text), images);
    if (!run.push(String(text), images)) { if (m) { this.store.removeMessage(run.conv, m.id); this.emit({ type: 'messages', agentId: run.conv }); } return false; }
    return true;
  }

  // Back to just before one of your messages in a DM: it and everything after it leave the chat, the agent's own
  // session goes back to that point, and (Claude) the files it changed since are put back. Returns your words.
  async rewind(agentId, messageId) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    if (this.runs.has(`agent:${agentId}`)) throw new Error(`${agent.name} is still working. Stop it first.`);
    const all = [...this.store.messages(agentId)];
    const at = all.findIndex((m) => m.id === messageId);
    if (at < 0 || all[at].role !== 'user') throw new Error('That message is no longer in this chat.');
    const before = all.slice(0, at), dropped = all.slice(at);
    const keep = [...before].reverse().find((m) => m.sdk)?.sdk || null;
    let note = null;
    if (agent.operator === 'codex') {
      // Codex counts a message sent mid-turn as a turn of its own.
      const turns = dropped.filter((m) => m.role === 'user').length;
      if (agent.sessionId && turns) {
        const [, rolled] = await codexRpc(agent.cwd || HOME, [['thread/resume', { threadId: agent.sessionId, cwd: agent.cwd || HOME }], ['thread/rollback', { threadId: agent.sessionId, numTurns: turns }]]);
        if (!rolled) throw new Error('Codex couldn\u2019t go back in this chat.');
      }
      note = 'Codex keeps the files as they are now.';
    } else if (agent.sessionId) {
      note = await rewindClaudeFiles(agent, keep).catch((e) => `The files couldn't be put back: ${readable(e.message)}`);
      this.store.updateAgent(agentId, { rewindAt: keep, sessionId: keep ? agent.sessionId : null });
    }
    for (const m of dropped) this.store.removeMessage(agentId, m.id);
    this.emit({ type: 'messages', agentId });
    this.emit({ type: 'state' });
    return { text: all[at].text, images: all[at].images || [], note };
  }

  answer(id, decision, extra = null) {
    const a = this.approvals.get(id);
    if (!a) return false;
    // A note instead of yes: the agent hears it and goes another way (the request carries on).
    if (decision === 'note') {
      this.approvals.delete(id);
      a.resolve({ behavior: 'deny', message: `The user said: ${String(extra || '').trim()}` });
      const r = this.runs.get(a.key) || this.sides?.get(a.key); if (r) { r.activity = 'Working'; this.#emitRun(r); }
      this.emit({ type: 'approvals' });
      return true;
    }
    // Answers to its questions (AskUserQuestion): question → chosen labels.
    if (decision === 'answers') {
      this.approvals.delete(id);
      const answers = {};
      for (const q of a.input?.questions || []) { const v = extra?.[q.question]; if (v != null) answers[q.question] = Array.isArray(v) ? v.join(', ') : String(v); }
      a.resolve({ behavior: 'allow', updatedInput: { ...a.input, answers } });
      const r = this.runs.get(a.key) || this.sides?.get(a.key); if (r) { r.activity = 'Working'; this.#emitRun(r); }
      this.emit({ type: 'approvals' });
      return true;
    }
    this.approvals.delete(id);
    // "Allow for the rest of this request": this run stops asking for this kind of step (file changes, commands).
    if (decision === 'turn') { const r = this.runs.get(a.key) || this.sides?.get(a.key); if (r && ['write', 'host', 'net'].includes(a.risk)) (r.allowed ||= new Set()).add(a.risk); }
    // "Always allow file changes": this agent stops asking for them, whatever its mode, until you turn it off (the Mode
    // card shows it). Commands, deleting and sending keep following the mode.
    if (decision === 'always' && a.risk === 'write') {
      const r = this.runs.get(a.key) || this.sides?.get(a.key); if (r) (r.allowed ||= new Set()).add('write');
      if (a.agentId && this.store.state.agents?.some((x) => x.id === a.agentId)) { this.store.updateAgent(a.agentId, { alwaysEdits: true }); this.emit({ type: 'state' }); }
    }
    if (decision === 'deny') a.resolve({ behavior: 'deny', message: 'The user said no to this. Ask what they would like instead.' });
    else a.resolve({ behavior: 'allow', updatedInput: a.input, ...(decision === 'always' && a.risk !== 'write' && a.suggestions?.length ? { updatedPermissions: a.suggestions } : {}) });
    const run = this.runs.get(a.key);
    if (run) { run.activity = 'Working'; this.#emitRun(run); }
    this.emit({ type: 'approvals' });
    return true;
  }

  // A one-off question to Claude with no tools: used for summaries and decision lists, never shown as an agent.
  async ask(prompt, cwd = HOME) {
    let out = '';
    for await (const m of query({ prompt, options: { cwd, maxTurns: 1, persistSession: false, tools: [], settingSources: [], pathToClaudeCodeExecutable: findBinary('claude') || undefined, canUseTool: async () => ({ behavior: 'deny', message: 'No tools here.' }) } })) {
      if (m.type === 'result') {
        if (m.subtype !== 'success' || m.is_error) throw new Error((m.errors && m.errors[0]) || 'Claude could not answer.');
        out = m.result || '';
      }
    }
    return out.trim();
  }

  // ---- helpers, commands, side chats, compacting (engine/convo.js offers these to the app) --------------

  #liveRun(agentId) { return this.runs.get(`agent:${agentId}`) || null; }

  /// What a running command has printed so far (Claude: the last 8 KB of its task; Codex: what it streamed).
  async commandOutput(agentId, id) {
    const run = this.#liveRun(agentId);
    if (!run?.commands?.has(id)) return { output: '', truncated: false, running: false };
    if (run.commandOutput) return { ...run.commandOutput(id), running: true };
    if (!run.q?.getTaskOutput) return { output: '', truncated: false, running: true };
    const r = await run.q.getTaskOutput(id);
    return { output: String(r?.output || ''), truncated: !!r?.truncated, running: true };
  }

  /// Stops one running command. Claude stops that command alone (its task); Codex can only stop the whole turn.
  /// Returns what was stopped: 'command', 'turn', or 'gone' when it had already finished.
  async stopCommand(agentId, id) {
    const run = this.#liveRun(agentId);
    if (!run?.commands?.has(id)) return 'gone';
    if (run.stopCommand) return run.stopCommand(id);
    await run.q.stopTask(id);
    return 'command';
  }

  /// Stops one helper. A Claude helper with a task of its own stops alone; any other stops with the run.
  async stopHelper(agentId, helperId) {
    const run = this.#liveRun(agentId), h = run?.helpers?.get(helperId);
    if (!h || h.status !== 'running') return 'gone';
    if (h.taskId && run.q?.stopTask) { await run.q.stopTask(h.taskId); return 'helper'; }
    this.stop(run.key);
    return 'run';
  }

  /// A side question about a DM, answered by the same agent from its own copy of the session (Claude forks it; Codex
  /// forks the thread), only looking: it never adds to the chat or asks you anything. Runs quietly (no run events);
  /// `cb` hears its words (onDelta, onText), its steps (onTool, onToolDone) and its end (onEnd(outcome, sessionId)).
  side(agent, { key, sessionId, fork, rewindAt = null, prompt, images = [] }, cb) {
    const run = { key, quiet: true, startedAt: Date.now(), activity: '', preview: '', abort: null, stopped: false, agentId: agent.id, conv: key };
    run.onDelta = cb.onDelta; run.onText = (t) => cb.onText(t); run.onTool = cb.onTool; run.onToolDone = cb.onToolDone;
    run.onSession = (sid) => { if (sid) run.sessionId = sid; };
    (this.sides ||= new Map()).set(key, run);
    // A side chat is the same agent with the same access (its mode, its tools, its asks): only the conversation is
    // apart. It doesn't carry on the main task unless asked to.
    const rule = "This is a side chat: the user is asking something on the side, without adding to the main conversation above. Answer in your own voice. Don't carry on the main task unless the user asks you to here.";
    const codex = agent.operator === 'codex';
    const target = { cwd: agent.cwd || HOME, sessionId, fork: !!(sessionId && fork), rewindAt, model: agent.model, permission: modeOf(agent.permission), alwaysEdits: !!agent.alwaysEdits, side: true, work: true,
      setup: !!agent.claudeSetup, images, append: codex ? '' : `${this.appendFor(agent)}\n\n${rule}` };
    const go = codex ? this.#codex(run, target, `${rule}\n\n${prompt}`) : this.#claude(run, target, prompt);
    return go.then((o) => o || {}, (err) => ({ error: run.stopped ? 'Stopped.' : readable(err?.message || String(err)) })).then((o) => {
      this.sides.delete(key);
      if (run.stopped) o.error = 'Stopped.';
      try { cb.onEnd(o, run.sessionId || sessionId || null); } catch {}
      return o;
    });
  }
  stopSide(key) {
    const run = this.sides?.get(key);
    if (!run) return false;
    run.stopped = true;
    try { run.abort?.(); } catch {}
    return true;
  }

  /// Compacts a DM's conversation (Claude Code's /compact, Codex's thread compaction): the session keeps a summary
  /// instead of every word, so it has room again. The chat says so in a note. Returns { before, after } in tokens.
  async compact(agentId) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    if (this.runs.has(`agent:${agentId}`)) throw new Error(`${agent.name} is still working. Compact when it's done.`);
    if (!agent.sessionId) throw new Error('There is nothing to compact yet.');
    this.compacting ||= new Set();
    if (this.compacting.has(agentId)) throw new Error('Already compacting.');
    this.compacting.add(agentId);
    this.emit({ type: 'compact', agentId, state: 'running' });
    try {
      const r = agent.operator === 'codex' ? await codexCompact(agent.cwd || HOME, agent.sessionId) : await claudeCompact(agent);
      const cur = this.store.agent(agentId);
      if (cur) {
        const usage = { ...(cur.usage || {}) };
        if (r.cost) usage.cost = (usage.cost || 0) + r.cost;
        if (r.after) usage.context = { ...(usage.context || {}), used: r.after, window: r.window || usage.context?.window || null, at: Date.now() };
        this.store.updateAgent(agentId, { usage, ...(r.sessionId && r.sessionId !== cur.sessionId ? { sessionId: r.sessionId } : {}), ...(cur.rewindAt ? { rewindAt: null } : {}) });
      }
      const k = (n) => (n >= 1000 ? `${Math.round(n / 1000)}K` : String(n));
      this.store.addMessage(agentId, { role: 'note', text: `Compacted the conversation${r.before && r.after ? ` (${k(r.before)} → ${k(r.after)} tokens)` : ''}.` });
      this.emit({ type: 'messages', agentId });
      return { before: r.before || null, after: r.after || null, window: r.window || null };
    } finally {
      this.compacting.delete(agentId);
      this.emit({ type: 'compact', agentId, state: 'done' });
    }
  }

  /// How full a DM's context is now, by part (system prompt, tools, messages…), asked of Claude Code without sending
  /// anything. Null for Codex, or while the agent works (the numbers saved after each run stand in).
  async liveContext(agentId) {
    const agent = this.store.agent(agentId);
    if (!agent || agent.operator === 'codex' || !agent.sessionId || this.runs.has(`agent:${agentId}`) || this.compacting?.has(agentId)) return null;
    return claudeContext(agent);
  }

  // ---- what the box offers ----------------------------------------------------------------------
  // `/` commands (the tool's own, and with the setup on your skills' and plugins'), the helpers `@` can hand work to,
  // and its models. Asked of the tool itself, without sending anything; remembered for ten minutes per agent and setup.
  /** The commands and skills an agent's tool knows, from the catalog already asked for (the box asks when it opens). */
  commandNames(agent) {
    const key = `${agent.operator}:${agent.claudeSetup ? 'setup' : 'plain'}:${agent.cwd || HOME}`;
    return new Set((this.catalogs?.get(key)?.value?.commands || []).map((c) => String(c.name).toLowerCase()));
  }

  async catalog(agentId, fresh = false) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    const key = `${agent.operator}:${agent.claudeSetup ? 'setup' : 'plain'}:${agent.cwd || HOME}`;
    this.catalogs ||= new Map();
    const hit = this.catalogs.get(key);
    if (hit && !fresh && Date.now() - hit.at < 600_000) return hit.value;
    const value = agent.operator === 'codex' ? await codexCatalog(agent.cwd || HOME) : await claudeCatalog(agent);
    this.catalogs.set(key, { at: Date.now(), value });
    return value;
  }

  // The plugins installed for an agent's tool, and whether each is on.
  async plugins(agentId) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    if (agent.operator === 'codex') {
      const r = await codexRpc(agent.cwd || HOME, [['plugin/installed', { cwds: [agent.cwd || HOME] }]]);
      const all = (r[0]?.marketplaces || []).flatMap((m) => m.plugins || []).filter((p) => p.installed !== false);
      return all.map((p) => ({ id: p.id, name: p.interface?.displayName || p.name || p.id, about: p.interface?.shortDescription || '', enabled: p.enabled !== false }));
    }
    const out = await run(findBinary('claude'), ['plugin', 'list', '--json']);
    let list = []; try { list = JSON.parse(out); } catch {}
    return list.map((p) => ({ id: p.id, name: String(p.id).split('@')[0], about: p.version ? `v${p.version}` : '', enabled: !!p.enabled }));
  }

  async setPlugin(agentId, pluginId, on) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    if (agent.operator === 'codex') {
      await codexRpc(agent.cwd || HOME, [['config/value/write', { keyPath: `plugins."${pluginId}".enabled`, value: on, mergeStrategy: 'upsert' }]]);
    } else {
      const out = await run(findBinary('claude'), ['plugin', on ? 'enable' : 'disable', pluginId]);
      if (!/Successfully/.test(out)) throw new Error(clip(out.split('\n').filter(Boolean).pop()?.replace(/^✘\s*/, '') || 'Claude Code didn\u2019t change it.', 200));
    }
    this.catalogs?.clear();          // its commands change with it
    return true;
  }

  // ---- internals -------------------------------------------------------------------------------
  #newRun(key, extra) {
    const run = { key, startedAt: Date.now(), activity: 'Starting', preview: '', abort: null, stopped: false, ...extra };
    this.runs.set(key, run);
    this.#emitRun(run);
    return run;
  }

  /// The words so far: to the app's draft for the run, or to whoever runs it quietly (a side chat).
  #delta(run) {
    if (run.onDelta) return run.onDelta(run.draft || '');
    this.emit({ type: 'delta', key: run.key, text: run.draft, turn: run.turn || null });
  }

  /// A helper changed: saved at once, told to the app at most every 200 ms (a busy helper changes many times a second;
  /// `now` for a start or an end).
  #emitHelper(run, h, now = false) {
    run.helperTimers ||= new Map();
    const send = () => { run.helperTimers.delete(h.id); this.emit({ type: 'helper', key: run.key, agentId: run.conv || run.agentId, helperId: h.id, helper: h }); };
    if (now || h.status !== 'running') { clearTimeout(run.helperTimers.get(h.id)); return send(); }
    if (!run.helperTimers.has(h.id)) run.helperTimers.set(h.id, setTimeout(send, 200));
  }

  /// The commands running long enough to show above the box (Claude: ones that became tasks, after about 3 s).
  #emitCommands(run) {
    if (run.quiet) return;
    this.emit({ type: 'commands', key: run.key, agentId: run.conv || run.agentId, commands: [...(run.commands?.values() || [])].map(({ output, ...c }) => c) });
  }

  /// Adds a run's tokens and cost to what the agent's DM has used, and keeps how full its context was at the end.
  #noteUsage(agentId, outcome) {
    const u = outcome.usage, cur = this.store.agent(agentId);
    if (!cur || (!u && outcome.cost == null)) return;
    const was = cur.usage || {};
    const sum = (k) => (u?.mode === 'set' ? u[k] ?? was[k] ?? 0 : (was[k] || 0) + (u?.[k] || 0));
    const next = { input: sum('input'), output: sum('output'), cacheRead: sum('cacheRead'), cacheWrite: sum('cacheWrite'),
      cost: (was.cost || 0) + (outcome.cost || 0), runs: (was.runs || 0) + 1, model: u?.model || was.model || null,
      context: u?.context?.used ? { ...u.context, at: Date.now() } : was.context || null, since: was.since || Date.now() };
    this.store.updateAgent(agentId, { usage: next });
  }

  #emitRun(run) { if (run.quiet) return; this.emit({ type: 'run', run: { key: run.key, agentId: run.agentId, conv: run.conv || null, by: run.by || null, chat: run.chat, operator: run.operator, startedAt: run.startedAt, activity: run.activity, detail: run.detail || null, preview: run.preview, turn: run.turn || null } }); }

  #start(run, operator, target, text) {
    const go = operator === 'codex' ? this.#codex(run, target, text) : this.#claude(run, target, text);
    go.then((o) => this.#finish(run, o || {}), (err) => this.#finish(run, { error: run.stopped ? 'Stopped.' : readable(err?.message || String(err)) }));
  }

  #finish(run, outcome) {
    if (run.ended) return;                       // already ended (stopped, then the tool finished winding down)
    run.ended = true;
    if (run.openTool) { run.onToolDone?.(run.openTool, !!outcome.error); run.openTool = null; }
    // Helpers still at work when the run ends end with it (its process is gone); its commands too.
    for (const h of run.helpers?.values() || []) if (h.status === 'running') { h.status = run.stopped || outcome.error ? 'stopped' : 'done'; h.endedAt = Date.now(); run.onHelper?.(h, true); }
    if (run.commands?.size) { run.commands.clear(); this.#emitCommands(run); }
    for (const [id, a] of this.approvals) if (a.key === run.key) { this.approvals.delete(id); a.resolve({ behavior: 'deny', message: 'Stopped.' }); }
    this.runs.delete(run.key);
    if (run.stopped && !outcome.error) outcome.error = 'Stopped.';
    outcome.stopped = run.stopped;
    try { run.onEnd?.(outcome); } catch {}
    this.emit({ type: 'run-end', key: run.key, agentId: run.agentId, conv: run.conv || null, error: outcome.error || null });
    this.emit({ type: 'approvals' });
  }

  // Claude passes its call id and round. Codex reports a step only once it's finished, so each call is its own round.
  #tool(run, d) {
    if (run.ended) return;
    if (!d.id) {
      if (run.openTool) { run.onToolDone?.(run.openTool, false); run.openTool = null; }
      d = { ...d, id: newId('t'), round: (run.round = (run.round || 0) + 1) };
      if (d.finished) setTimeout(() => run.onToolDone?.(d.id, false), 0); else run.openTool = d.id;
    }
    run.activity = `${d.verb} ${d.line}`; run.onTool?.(d); this.#emitRun(run);
  }

  #text(run, t, sdk = null) {
    if (run.ended || !t?.trim()) return;
    run.said = `${run.said || ''}${t}`;
    if (run.openTool) { run.onToolDone?.(run.openTool, false); run.openTool = null; }
    run.preview = clip(t, 160);
    run.activity = 'Writing';
    run.onText?.(t, sdk);
    this.#emitRun(run);
  }

  async #claude(run, target, text) {
    const ac = new AbortController();
    run.abort = () => ac.abort();
    // The request stays open while it works, so a message you send meanwhile goes in (run.push); it closes once
    // Claude Code says the request is done and no helper of its is still at work.
    const input = inputQueue();
    input.push(userMessage(text, target.images));
    run.push = (t, images) => (input.closed ? false : (input.push(userMessage(t, images)), true));
    const options = {
      cwd: fs.existsSync(target.cwd) ? target.cwd : HOME,
      abortController: ac,
      includePartialMessages: true,
      pathToClaudeCodeExecutable: findBinary('claude') || undefined,
      // Every step that needs a decision comes to #approval, which applies the agent's mode (MODES). Read only also
      // takes the editing tools away, so the agent knows it can't change files.
      permissionMode: 'default',
      // With your setup on it asks you its questions as Claude Code does; Agent Lab's own agents ask in one line.
      disallowedTools: [...(target.setup ? [] : ['AskUserQuestion', 'TodoWrite']), ...(target.permission === 'read' ? ['Edit', 'Write', 'MultiEdit', 'NotebookEdit'] : [])],
      // An agent with "Use my Claude Code setup" on starts with your skills, plugins, CLAUDE.md and settings, and offers
      // their commands; off, it starts on Agent Lab's rules alone (faster, and every agent answers the same way).
      settingSources: target.setup ? ['user', 'project', 'local'] : [],
      // Files are checkpointed as it changes them, so going back to an earlier message can put them back.
      enableFileCheckpointing: true,
      env: { ...subscriptionEnvironment(), CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING: '1' },
      thinking: target.work === false ? { type: 'disabled' } : { type: 'adaptive' },
      canUseTool: (toolName, toolInput, { signal, suggestions }) => this.#approval(run, toolName, toolInput, signal, suggestions, target),
      // A side chat answers at once; only the agent's own turns wait for their opening sentence.
      hooks: target.side ? {} : { PreToolUse: [{ hooks: [async (hookInput) => this.#openingFirst(run, hookInput)] }] },
      stderr: (d) => { run.stderr = `${run.stderr || ''}${d}`.slice(-4000); },
    };
    // Its hands on the app: the Browser pane, the Terminal's shell and the side panes (hands.js). Looking needs no ask.
    if (run.agentId) { options.mcpServers = { [hands.SERVER]: hands.server(handsId(run)) }; options.allowedTools = hands.allowed(); }
    if (target.sessionId) options.resume = target.sessionId;
    if (target.sessionId && target.rewindAt) options.resumeSessionAt = target.rewindAt;
    // A side chat reads the chat as it is without adding to it: its own copy of the session.
    if (target.sessionId && target.fork) options.forkSession = true;
    if (target.model) options.model = target.model;
    if (target.append) options.systemPrompt = { type: 'preset', preset: 'claude_code', append: target.append };
    let result = null;
    const calls = new Map();                       // tool id → its name and input (for its result's diff)
    // Helpers (Task / Agent calls): their own words and steps come with the call's id as parent_tool_use_id.
    const helpers = run.helpers = new Map();       // the call's id → its helper
    const tasks = new Map();                       // Claude Code's task id → { helper } or { command }
    run.commands = new Map();                      // task id → a command running long enough to show
    let thinkingSince = null, thought = '';
    let lastUsage = null;                          // the last request's usage: how full the context is now
    const helperOf = (parent) => (parent ? helpers.get(parent) || null : null);
    const startHelper = (b, parent) => {
      const h = { id: b.id, title: clip(b.input?.description || b.input?.prompt || 'a helper', 80), prompt: String(b.input?.prompt || '').slice(0, 8000),
        kind: b.input?.subagent_type || null, parent: parent || null, status: 'running', startedAt: Date.now(), endedAt: null, activity: 'Starting', round: 0, messages: [] };
      helpers.set(b.id, h);
      run.onHelper?.(h, true);
    };
    const endHelper = (h, status, error) => {
      if (!h || h.status !== 'running') return;
      h.status = status; h.endedAt = Date.now(); h.activity = null;
      if (error) h.error = clip(error, 300);
      for (const m of h.messages) if (m.role === 'tool' && !m.done) { m.done = true; m.failed = status === 'failed'; }
      run.onHelper?.(h, true);
      // The request was only held open for its helpers: once the last is done (and its answer turn, if any, has come
      // back as another result), it can close.
      if (result && ![...helpers.values()].some((x) => x.status === 'running')) input.close();
    };
    run.activity = 'Thinking';
    this.#emitRun(run);
    const setActivity = (a) => { if (run.activity !== a && !run.ended) { run.activity = a; run.detail = null; this.#emitRun(run); } };
    // A line under the status saying what's happening right now (Claude Code's): the thought it's on, or the file it's
    // writing and how far it's got. At most a few times a second.
    let detailAt = 0, toolInput = '', toolName = '';
    const setDetail = (d) => {
      const now = Date.now(); if (run.ended || d === run.detail || now - detailAt < 250) return;
      detailAt = now; run.detail = d; this.#emitRun(run);
    };
    const q = query({ prompt: input.iterable, options });
    run.q = q;
    try {
      for await (const m of q) {
        const parent = m.parent_tool_use_id || null;
        if (m.type === 'system' && m.subtype === 'init') run.onSession?.(m.session_id);
        else if (m.type === 'system' && m.subtype === 'api_retry') {
          run.activity = `Couldn't reach Claude, trying again (attempt ${m.attempt || 1})`; this.#emitRun(run);
        } else if (m.type === 'system' && m.subtype === 'task_started') {
          // A helper's task, or a command that has run long enough to become one (about 3 s): it can be read and stopped.
          if (m.task_type === 'local_agent' && helpers.has(m.tool_use_id)) { const h = helpers.get(m.tool_use_id); h.taskId = m.task_id; tasks.set(m.task_id, { helper: h }); run.onHelper?.(h); }
          else if (m.task_type === 'local_bash' && !m.ambient) {
            const call = calls.get(m.tool_use_id);
            const c = { id: m.task_id, toolId: m.tool_use_id || null, line: clip(call?.input?.command || m.description || 'a command', 120), about: m.description || '',
              helper: call?.helper || null, background: !!m.is_backgrounded, startedAt: Date.now() };
            tasks.set(m.task_id, { command: c });
            run.commands.set(m.task_id, c);
            this.#emitCommands(run);
          }
        } else if (m.type === 'system' && m.subtype === 'task_progress') {
          const t = tasks.get(m.task_id);
          if (t?.helper && m.description) { t.helper.activity = clip(m.summary || m.description, 100); run.onHelper?.(t.helper); }
        } else if (m.type === 'system' && (m.subtype === 'task_notification' || (m.subtype === 'task_updated' && ['completed', 'failed', 'killed'].includes(m.patch?.status)))) {
          const t = tasks.get(m.task_id), st = m.status || m.patch?.status;
          if (t?.helper) endHelper(t.helper, st === 'completed' ? 'done' : st === 'failed' ? 'failed' : 'stopped', m.patch?.error);
          if (t?.command && run.commands.delete(m.task_id)) this.#emitCommands(run);
        } else if (m.type === 'stream_event' && !parent) {
          const e = m.event;
          if (run.ended) continue;
          if (e?.type === 'content_block_start' && (e.content_block?.type === 'thinking' || e.content_block?.type === 'redacted_thinking')) { thinkingSince = Date.now(); thought = ''; setActivity('Thinking'); }
          // A step being written, before it runs: the line says what's coming ("Preparing a command"), as Mavis's does.
          else if (e?.type === 'content_block_start' && e.content_block?.type === 'tool_use') { toolName = e.content_block.name; toolInput = ''; setActivity('Preparing ' + stepName(toolName)); }
          else if (e?.type === 'content_block_delta' && e.delta?.type === 'thinking_delta') { thought += e.delta.thinking || ''; setDetail(thoughtLine(thought)); }
          else if (e?.type === 'content_block_delta' && e.delta?.type === 'input_json_delta') { toolInput += e.delta.partial_json || ''; setDetail(writingLine(toolName, toolInput)); }
          else if (e?.type === 'content_block_delta' && e.delta?.type === 'text_delta') { run.draft = `${run.draft || ''}${e.delta.text}`; this.#delta(run); }
        } else if (m.type === 'assistant' && !parent) {
          const blocks = m.message?.content || [];
          if (m.message?.usage) lastUsage = { ...m.message.usage, model: m.message.model };
          if (blocks.some((b) => b.type === 'tool_use')) run.round = (run.round || 0) + 1;
          for (const b of blocks) {
            if (b.type === 'thinking' || b.type === 'redacted_thinking') {
              const seconds = thinkingSince ? Math.max(1, Math.round((Date.now() - thinkingSince) / 1000)) : 1;
              if (!run.ended) run.onThought?.({ text: b.thinking || thought, seconds });
              thinkingSince = null; thought = '';
            } else if (b.type === 'text') { run.draft = ''; this.#text(run, b.text, m.uuid); }
            else if (b.type === 'tool_use') {
              calls.set(b.id, { name: b.name, input: b.input });
              if ((b.name === 'Task' || b.name === 'Agent') && !run.ended) startHelper(b, null);
              this.#tool(run, { ...describeTool(b.name, b.input), diff: diffOf(b.name, b.input), id: b.id, round: run.round, sdk: m.uuid });
            }
          }
        } else if (m.type === 'assistant' && helperOf(parent)) {
          // A helper at work: its words and steps go into its own transcript.
          const h = helperOf(parent), blocks = m.message?.content || [];
          if (run.ended || h.status !== 'running') continue;
          if (blocks.some((b) => b.type === 'tool_use')) h.round += 1;
          for (const b of blocks) {
            if (b.type === 'text' && b.text?.trim()) h.messages.push({ id: newId('m'), role: 'assistant', text: b.text, at: Date.now(), turn: h.id });
            else if (b.type === 'tool_use') {
              calls.set(b.id, { name: b.name, input: b.input, helper: h.id });
              if (b.name === 'Task' || b.name === 'Agent') startHelper(b, h.id);
              const d = describeTool(b.name, b.input), diff = diffOf(b.name, b.input);
              h.messages.push({ id: newId('m'), role: 'tool', verb: d.verb, text: d.line, toolId: b.id, round: h.round, done: false, failed: false, at: Date.now(), turn: h.id,
                ...(d.detail ? { detail: String(d.detail).slice(0, 4000) } : {}), ...(diff.length ? { diff } : {}) });
              h.activity = `${d.verb} ${d.line}`;
            }
          }
          run.onHelper?.(h);
        } else if (m.type === 'user' && helperOf(parent)) {
          const h = helperOf(parent);
          const extra = m.tool_use_result && typeof m.tool_use_result === 'object' ? m.tool_use_result : null;
          for (const b of m.message?.content || []) {
            if (b?.type !== 'tool_result' || !b.tool_use_id) continue;
            const step = h.messages.find((x) => x.toolId === b.tool_use_id);
            if (!step) continue;
            // A command Claude left running in the background: its output and Stop in the Terminal tab.
            const call = calls.get(b.tool_use_id);
            if (call?.name === 'Bash' && call.input?.run_in_background && !b.is_error) { try { followBackground(run.agentId, { command: call.input.command || '', text: resultText(b.content, extra) }); } catch {} }
            const diff = extra?.structuredPatch?.length && extra.filePath ? [diffOfPatch(extra.filePath, extra.structuredPatch, extra.type === 'create')] : null;
            const output = resultText(b.content, extra);
            Object.assign(step, { done: true, failed: !!b.is_error, ...(output ? { output } : {}), ...(diff ? { diff } : {}) });
          }
          run.onHelper?.(h);
        } else if (m.type === 'user' && !parent) {
          setActivity('Thinking');                 // a step came back: what's next is being worked out
          // A tool's result is back: that step is finished, with what came back (and its real patch, for an edit).
          const extra = m.tool_use_result && typeof m.tool_use_result === 'object' ? m.tool_use_result : null;
          for (const b of m.message?.content || []) {
            if (b?.type !== 'tool_result' || !b.tool_use_id) continue;
            const diff = extra?.structuredPatch?.length && extra.filePath ? [diffOfPatch(extra.filePath, extra.structuredPatch, extra.type === 'create')] : null;
            const output = resultText(b.content, extra);
            run.onToolDone?.(b.tool_use_id, b.is_error, { output, diff });
            // A helper that ran in the foreground is finished when its call comes back (one in the background says it
            // launched, and finishes with its task).
            const h = helpers.get(b.tool_use_id);
            if (h && (b.is_error || !/^Async agent launched/i.test(output))) {
              const report = helperReport(output);
              if (report && !b.is_error && !h.messages.some((x) => x.role === 'assistant')) h.messages.push({ id: newId('m'), role: 'assistant', text: report, at: Date.now(), turn: h.id });
              endHelper(h, b.is_error ? 'failed' : 'done', b.is_error ? output : null);
            }
          }
        } else if (m.type === 'result') {
          result = m;
          if (m.session_id) run.onSession?.(m.session_id);
          // A helper still at work in the background brings its answer back in a turn of its own: the request stays
          // open until it has.
          if (![...helpers.values()].some((h) => h.status === 'running')) input.close();
        }
      }
    } finally { input.close(); run.push = null; run.q = null; }
    if (!result) return { error: run.stopped ? 'Stopped.' : (clip(run.stderr, 300) || 'Claude Code stopped without an answer.') };
    const usage = usageOfResult(result, lastUsage);
    if (result.subtype !== 'success' || result.is_error) return { error: readable((result.errors && result.errors.join(' ')) || result.result) || 'Claude Code could not finish.', cost: result.total_cost_usd, usage };
    return { cost: result.total_cost_usd, usage, result: result.result || '' };
  }

  // Runs before every tool call (before any approval): the first one in a turn waits for the opening sentence.
  async #openingFirst(run, input) {
    if (run.ended || run.opened) return {};
    if (hasOpening(`${run.said || ''}${run.draft || ''}`) || (run.nudges || 0) >= 2) { run.opened = true; return {}; }
    run.nudges = (run.nudges || 0) + 1;
    (run.turnedBack ||= new Set()).add(input?.tool_use_id);
    run.onTurnedBack?.(input?.tool_use_id);
    return { hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: OPENING_NUDGE } };
  }

  /** A Codex agent's step on the app's panes (hands.js): its mode decides, as for a command. true, or why not. */
  async gateHands(agentId, toolName, input) {
    // The exact run that asked ("a1" its DM, "a1@<conv>" a channel): an agent can run in both at once.
    const full = String(agentId);
    const run = [...this.runs.values()].find((r) => handsId(r) === full && r.operator === 'codex' && !r.ended);
    if (!run) return 'This agent is not working right now.';
    const answer = await this.#approval(run, toolName, input, null, [], run.target || {});
    return answer.behavior === 'allow' ? true : answer.message || 'Not allowed.';
  }

  #approval(run, toolName, input, signal, suggestions, target = {}) {
    return new Promise((resolve) => {
      const id = newId('ap');
      const d = describeTool(toolName, input);
      const risk = toolName === 'AskUserQuestion' ? 'question' : riskOf(toolName, input);
      // The mode first (MODES), then what you already allowed for this request or for good.
      let rule = risk === 'question' ? 'ask' : MODES[target.permission || 'ask']?.[risk] || 'ask';
      if (rule === 'look') rule = toolName === 'Bash' && onlyLooks(input?.command) ? 'yes' : 'no';
      if (risk === 'write' && target.alwaysEdits) rule = 'yes';
      if (rule === 'no') return resolve({ behavior: 'deny', message: 'This agent is in Read only mode: it can look and answer, but not change anything. Say what you found and what you would change.' });
      if (rule === 'yes' || run.allowed?.has(risk)) return resolve({ behavior: 'allow', updatedInput: input });
      const a = { id, key: run.key, agentId: run.agentId, conv: run.conv || null, chat: run.chat, tool: toolName, verb: d.verb, line: d.line, detail: d.detail || null, risk, input, suggestions, at: Date.now(), resolve };
      this.approvals.set(id, a);
      signal?.addEventListener('abort', () => { if (this.approvals.delete(id)) { resolve({ behavior: 'deny', message: 'Stopped.' }); this.emit({ type: 'approvals' }); } });
      run.activity = 'Waiting for you';
      this.#emitRun(run);
      this.emit({ type: 'approvals' });
    });
  }

  #spawnLines(run, bin, args, cwd, onLine) {
    return new Promise((resolve, reject) => {
      if (!bin) return reject(new Error('This tool is not installed on this Mac.'));
      const child = spawn(bin, args, { cwd: fs.existsSync(cwd) ? cwd : HOME, env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
      run.abort = () => { try { child.kill('SIGINT'); } catch {} setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, 3000); };
      let err = '';
      child.stderr.on('data', (d) => { err = `${err}${d}`.slice(-4000); });
      readline.createInterface({ input: child.stdout }).on('line', (line) => {
        let j; try { j = JSON.parse(line); } catch { return; }
        try { onLine(j); } catch {}
      });
      child.on('error', reject);
      child.on('close', (code) => resolve({ code, err }));
    });
  }

  // Codex through `codex app-server`: its words as they're written, each command with its output, each change with its
  // diff, its own approvals (through the agent's mode, as Claude's), a message you send meanwhile into the running turn,
  // and a stop that ends the turn cleanly.
  async #codex(run, target, text) {
    const bin = findBinary('codex');
    if (!bin) return { error: 'Codex is not installed on this Mac.' };
    // Its hands on the app's panes come as an MCP server Codex starts (hands-stdio.js); its steps pass #approval here.
    run.target = target;
    const child = spawn(bin, ['app-server', ...(run.agentId ? hands.codexConfig(handsId(run)) : [])], { cwd: fs.existsSync(target.cwd) ? target.cwd : HOME, env: process.env, stdio: ['pipe', 'pipe', 'pipe'] });
    let err = '';
    child.stderr.on('data', (d) => { err = `${err}${d}`.slice(-4000); });
    let next = 0;
    const replies = new Map();
    const write = (o) => { try { child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', ...o })}\n`); } catch {} };
    const call = (method, params) => new Promise((resolve, reject) => { const id = ++next; replies.set(id, { resolve, reject }); write({ id, method, params }); });
    let thread = null, turn = null, outcome = null, finish;
    const done = new Promise((r) => { finish = r; });
    const changes = new Map();                                 // file change id → its diff
    const reasoning = new Map();                               // reasoning id → when it started, what it said
    // Codex's own helpers (multi-agent: a spawnAgent call opens a thread of its own for each): their threads' items
    // go into the helper's transcript. Commands running over 3 s show above the box with their output so far.
    const helpers = run.helpers = new Map();                   // spawn call id → its helper
    const helperThreads = new Map();                           // a helper's thread id → its helper
    run.commands = new Map();
    const commandTimers = new Map();
    let tokenUsage = null, chosenModel = target.model || null;
    run.stopCommand = () => { if (thread && turn) call('turn/interrupt', { threadId: thread, turnId: turn }).catch(() => {}); return 'turn'; };
    run.commandOutput = (id) => ({ output: run.commands.get(id)?.output || '', truncated: false });
    const helperStep = (h, it, tool) => {
      h.round += 1;
      h.messages.push({ id: newId('m'), role: 'tool', verb: tool.verb, text: tool.line, toolId: it.id, round: h.round, done: false, failed: false, at: Date.now(), turn: h.id,
        ...(tool.detail ? { detail: String(tool.detail).slice(0, 4000) } : {}), ...(tool.diff?.length ? { diff: tool.diff } : {}) });
      h.activity = `${tool.verb} ${tool.line}`;
      run.onHelper?.(h);
    };
    const endHelper = (h, status, error) => {
      if (!h || h.status !== 'running') return;
      h.status = status; h.endedAt = Date.now(); h.activity = null;
      if (error) h.error = clip(error, 300);
      for (const x of h.messages) if (x.role === 'tool' && !x.done) { x.done = true; x.failed = status === 'failed'; }
      run.onHelper?.(h, true);
    };
    const collab = (it) => {
      // A spawn opens a helper per new thread; any collab call says how its helpers are doing.
      if (it.tool === 'spawnAgent' && !helpers.has(it.id)) {
        const h = { id: it.id, title: clip(it.prompt || 'a helper', 80), prompt: String(it.prompt || '').slice(0, 8000), kind: it.model || null, parent: null,
          status: 'running', startedAt: Date.now(), endedAt: null, activity: 'Starting', round: 0, messages: [], threads: [] };
        helpers.set(it.id, h);
        run.onHelper?.(h, true);
      }
      const h = helpers.get(it.id);
      if (h) for (const t of it.receiverThreadIds || []) if (!helperThreads.has(t)) { helperThreads.set(t, h); h.threads.push(t); }
      for (const [t, state] of Object.entries(it.agentsStates || {})) {
        const hh = helperThreads.get(t); if (!hh) continue;
        const st = String(state?.status || '');
        if (st === 'completed') { if (state.message && !hh.messages.some((x) => x.role === 'assistant')) hh.messages.push({ id: newId('m'), role: 'assistant', text: state.message, at: Date.now(), turn: hh.id }); endHelper(hh, 'done'); }
        else if (st === 'errored' || st === 'notFound') endHelper(hh, 'failed', state.message);
        else if (st === 'interrupted' || st === 'shutdown') endHelper(hh, 'stopped');
      }
    };
    const sandbox = target.permission === 'read' ? 'read-only' : target.permission === 'full' ? 'danger-full-access' : 'workspace-write';
    const approvalPolicy = target.permission === 'full' ? 'never' : 'on-request';

    run.abort = () => {
      if (thread && turn) call('turn/interrupt', { threadId: thread, turnId: turn }).catch(() => {});
      setTimeout(() => { try { child.kill('SIGTERM'); } catch {} }, 2000);
    };
    run.push = (t, images = []) => {
      if (!thread || !turn || outcome) return false;
      call('turn/steer', { threadId: thread, expectedTurnId: turn, input: inputOf(t, images) }).catch(() => {});
      return true;
    };

    const toolOf = (it) => {
      const t = String(it.type || '').toLowerCase();
      if (t === 'commandexecution') {
        const cmd = (it.commandActions?.[0]?.command) || String(it.command || '').replace(/^\/bin\/(zsh|bash) -lc '(.*)'$/s, '$2');
        return { verb: 'Run', line: clip(cmd, 120), detail: cmd };
      }
      if (t === 'filechange') {
        const diff = (it.changes || []).map((c) => diffOfUnified(c.path, c.diff, c.kind?.type || c.kind));
        return { verb: 'Edit', line: diff.map((d) => base(d.path)).slice(0, 3).join(', ') || 'files', diff };
      }
      if (t === 'websearch') return { verb: 'Search the web for', line: clip(it.query || '', 80) };
      if (t === 'mcptoolcall') return it.server === hands.SERVER ? hands.describe(it.tool, it.arguments || {}) : { verb: 'Use', line: `${it.server || ''} · ${it.tool || ''}` };
      if (t === 'imageview') return { verb: 'Look at', line: base(it.path), detail: it.path };
      return null;
    };

    const ask = (toolName, input, params) => this.#approval(run, toolName, input, null, [], target).then((answer) => {
      if (answer.behavior === 'allow') return 'accept';
      // A note: Codex hears it as a message into the turn.
      if (/^The user said: /.test(answer.message || '')) run.push?.(answer.message.replace(/^The user said: /, ''));
      return 'decline';
    });

    readline.createInterface({ input: child.stdout }).on('line', async (line) => {
      let m; try { m = JSON.parse(line); } catch { return; }
      if (m.id !== undefined && !m.method) {
        const r = replies.get(m.id); replies.delete(m.id);
        if (m.error) r?.reject(new Error(m.error.message || 'Codex refused.')); else r?.resolve(m.result);
        return;
      }
      const p = m.params || {};
      if (thread && p.threadId && p.threadId !== thread && !helperThreads.has(p.threadId)) return;
      const inHelper = p.threadId && helperThreads.get(p.threadId);
      // Codex asking: an approval.
      if (m.id !== undefined && m.method) {
        let result;
        if (m.method === 'item/commandExecution/requestApproval') result = { decision: await ask('Bash', { command: p.command || '' }, p) };
        else if (m.method === 'item/fileChange/requestApproval') {
          const d = changes.get(p.itemId);
          result = { decision: await ask('Edit', { file_path: d?.[0]?.path || p.grantRoot || 'files' }, p) };
        } else if (m.method === 'mcpServer/elicitation/request' && p.serverName === hands.SERVER) {
          // Codex asking to use the app's panes: the engine already applies the agent's mode to each step (gateHands).
          result = { action: 'accept', content: {} };
        } else { write({ id: m.id, error: { code: -32601, message: 'Not supported by Agent Lab' } }); return; }
        write({ id: m.id, result });
        return;
      }
      if (run.ended && m.method !== 'turn/completed') return;
      switch (m.method) {
        case 'turn/started': turn = p.turn?.id || turn; break;
        case 'item/agentMessage/delta':
          if (helperThreads.has(p.threadId)) break;
          run.draft = `${run.draft || ''}${p.delta || ''}`; this.#delta(run); break;
        case 'item/started': {
          const it = p.item || {};
          if (String(it.type).toLowerCase() === 'collabagenttoolcall') { collab(it); break; }
          if (inHelper) { const tool = toolOf(it); if (tool && inHelper.status === 'running') helperStep(inHelper, it, tool); break; }
          if (String(it.type).toLowerCase() === 'reasoning') reasoning.set(it.id, Date.now());
          const tool = toolOf(it);
          if (tool && String(it.type).toLowerCase() === 'commandexecution') {
            commandTimers.set(it.id, setTimeout(() => {
              commandTimers.delete(it.id);
              if (run.ended) return;
              run.commands.set(it.id, { id: it.id, toolId: it.id, line: tool.line, about: '', helper: null, background: false, startedAt: Date.now() - 3000, output: '' });
              this.#emitCommands(run);
            }, 3000));
          }
          if (tool) {
            if (tool.diff) changes.set(it.id, tool.diff);
            run.round = (run.round || 0) + 1;
            this.#tool(run, { ...tool, id: it.id, round: run.round });
          }
          break;
        }
        case 'item/commandExecution/outputDelta': {
          const c = run.commands.get(p.itemId);
          if (c) c.output = `${c.output || ''}${p.delta || ''}`.slice(-8000);
          break;
        }
        case 'thread/tokenUsage/updated': if (!inHelper) tokenUsage = p.tokenUsage || tokenUsage; break;
        case 'item/completed': {
          const it = p.item || {}, type = String(it.type).toLowerCase();
          if (type === 'collabagenttoolcall') { collab(it); break; }
          if (inHelper) {
            if (type === 'agentmessage' && it.text?.trim()) { inHelper.messages.push({ id: newId('m'), role: 'assistant', text: it.text, at: Date.now(), turn: inHelper.id }); run.onHelper?.(inHelper); }
            const step = inHelper.messages.find((x) => x.toolId === it.id);
            if (step) {
              const out = String(it.aggregatedOutput || '');
              Object.assign(step, { done: true, failed: (it.exitCode ?? 0) !== 0 || ['failed', 'declined'].includes(String(it.status).toLowerCase()), ...(out ? { output: out.slice(-16000) } : {}), ...(type === 'filechange' ? { diff: toolOf(it)?.diff } : {}) });
              run.onHelper?.(inHelper);
            }
            break;
          }
          if (type === 'commandexecution') { clearTimeout(commandTimers.get(it.id)); commandTimers.delete(it.id); if (run.commands.delete(it.id)) this.#emitCommands(run); }
          if (type === 'agentmessage') { run.draft = ''; this.#text(run, it.text || ''); }
          else if (type === 'reasoning') {
            const since = reasoning.get(it.id) || Date.now();
            run.onThought?.({ text: (it.summary || []).join('\n\n'), seconds: Math.max(1, Math.round((Date.now() - since) / 1000)) });
          } else if (type === 'commandexecution') {
            const out = String(it.aggregatedOutput || '');
            run.onToolDone?.(it.id, (it.exitCode ?? 0) !== 0 || ['failed', 'declined'].includes(String(it.status).toLowerCase()), { output: out.length > 16000 ? `…${out.slice(-16000)}` : out });
          } else if (type === 'filechange') {
            const tool = toolOf(it);
            run.onToolDone?.(it.id, ['failed', 'declined'].includes(String(it.status).toLowerCase()), { diff: tool?.diff });
          } else if (toolOf(it)) run.onToolDone?.(it.id, String(it.status).toLowerCase() === 'failed');
          break;
        }
        case 'error':
          if (p.willRetry) { run.activity = 'Couldn\u2019t reach Codex, trying again'; this.#emitRun(run); }
          else run.lastError = readable(p.error?.message);
          break;
        case 'turn/completed': {
          // A helper's thread finishing its turn: that helper is done (Codex reports it again on its next collab call).
          if (inHelper) { const st = p.turn?.status; endHelper(inHelper, st === 'failed' ? 'failed' : st === 'interrupted' ? 'stopped' : 'done', p.turn?.error?.message); break; }
          const st = p.turn?.status;
          outcome = st === 'failed' ? { error: readable(p.turn?.error?.message) || run.lastError || 'Codex could not finish.' } : st === 'interrupted' ? { error: 'Stopped.' } : {};
          finish();
          break;
        }
      }
    });
    child.on('close', () => { if (!outcome) { outcome = { error: run.stopped ? 'Stopped.' : clip(run.lastError || err, 300) || 'Codex stopped.' }; finish(); } });

    try {
      await call('initialize', { clientInfo: { name: 'agent-lab', title: 'Agent Lab', version: '1.0' }, capabilities: { experimentalApi: true, requestAttestation: false } });
      write({ method: 'initialized' });
      // A model this account can use: the agent's own, else the first Codex lists for it.
      let model = target.model;
      if (!model) { try { model = (await call('model/list', { includeHidden: false }))?.data?.[0]?.model || null; } catch {} }
      chosenModel = model;
      const params = { cwd: target.cwd, sandbox, approvalPolicy, ...(model ? { model } : {}) };
      // A side chat works on its own copy of the thread (thread/fork), so the chat itself never changes.
      const opened = target.sessionId ? await call(target.fork ? 'thread/fork' : 'thread/resume', { ...params, threadId: target.sessionId }) : await call('thread/start', params);
      thread = opened.thread.id;
      run.onSession?.(thread);
      run.activity = 'Thinking'; this.#emitRun(run);
      const started = await call('turn/start', { threadId: thread, input: inputOf(text, target.images), approvalPolicy, ...(model ? { model } : {}) });
      turn = started?.turn?.id || turn;
      await done;
    } catch (e) {
      if (!outcome) outcome = { error: run.stopped ? 'Stopped.' : readable(e.message) };
    } finally {
      run.push = null;
      // The thread is Codex's to write while this process lives: the turn is over only once it has exited, so the next
      // message (which opens the same thread) never finds it still held.
      if (child.exitCode === null && child.signalCode === null) {
        const exited = new Promise((r) => child.once('close', r));
        try { child.stdin.end(); child.kill('SIGTERM'); } catch {}
        const late = setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, 3000);
        await exited;
        clearTimeout(late);
      }
    }
    for (const t of commandTimers.values()) clearTimeout(t);
    // Codex keeps the thread's own totals: they replace what was known (Claude's are added run by run).
    const t = tokenUsage;
    const usage = t ? { mode: 'set', input: t.total?.inputTokens || 0, output: t.total?.outputTokens || 0, cacheRead: t.total?.cachedInputTokens || 0, cacheWrite: t.total?.cacheWriteInputTokens || 0, model: chosenModel,
      context: t.last ? { used: (t.last.inputTokens || 0) + (t.last.outputTokens || 0), window: t.modelContextWindow || null, model: chosenModel } : null } : null;
    if (run.stopped) return { error: 'Stopped.', usage };
    return { ...(outcome || {}), usage };
  }
}


// ---- helpers for what the box offers ----------------------------------------------------------------

/// Runs a command and returns what it printed (stdout and stderr together).
function run(bin, args) {
  return new Promise((resolve) => {
    if (!bin) return resolve('');
    execFile(bin, args, { env: process.env, maxBuffer: 8 * 1024 * 1024 }, (_e, out, err) => resolve(`${out || ''}${err || ''}`));
  });
}

/// What Claude Code offers an agent, asked of Claude Code itself without sending anything: it starts, says what it has,
/// and is closed.
async function claudeCatalog(agent) {
  let release;
  const waiting = new Promise((r) => { release = r; });
  const q = query({
    prompt: (async function* () { await waiting; })(),
    options: {
      cwd: fs.existsSync(agent.cwd || HOME) ? agent.cwd : HOME,
      pathToClaudeCodeExecutable: findBinary('claude') || undefined,
      settingSources: agent.claudeSetup ? ['user', 'project', 'local'] : [],
      env: subscriptionEnvironment(),
    },
  });
  try {
    const init = await Promise.race([q.initializationResult(), new Promise((_, no) => setTimeout(() => no(new Error('Claude Code took too long to start.')), 30_000))]);
    const kind = (c) => {
      const d = String(c.description || '');
      if (String(c.name).includes(':') || /\(plugin/.test(d)) return 'plugin';
      if (/\((user|project|managed)\)\s*$/.test(d)) return 'skill';
      return 'command';
    };
    return {
      commands: (init.commands || []).filter((c) => c.name && !c.name.startsWith('_')).map((c) => ({
        name: c.name, about: String(c.description || '').replace(/\s*\((user|project|managed)\)\s*$/, ''), hint: c.argumentHint || '', kind: kind(c),
      })),
      agents: (init.agents || []).map((a) => ({ name: a.name, about: a.description || '' })),
      models: (init.models || []).map((m) => ({ id: m.value === 'default' ? '' : m.value, name: m.displayName || m.value, about: m.description || '' })),
    };
  } finally {
    release();
    try { await q.interrupt(); } catch {}
    try { q.return?.(); } catch {}
  }
}

/// Waits for a promise at most `ms`.
function within(p, ms, what = 'Claude Code took too long.') {
  let t; return Promise.race([p, new Promise((_, no) => { t = setTimeout(() => no(new Error(what)), ms); })]).finally(() => clearTimeout(t));
}

/// The options to open an agent's own session again, without sending anything until asked.
function resumeOptions(agent) {
  return { cwd: fs.existsSync(agent.cwd || HOME) ? agent.cwd : HOME, resume: agent.sessionId, ...(agent.rewindAt ? { resumeSessionAt: agent.rewindAt } : {}),
    pathToClaudeCodeExecutable: findBinary('claude') || undefined, settingSources: agent.claudeSetup ? ['user', 'project', 'local'] : [],
    env: subscriptionEnvironment(), ...(agent.model ? { model: agent.model } : {}) };
}

/// Claude Code's own count of a session's context: total, the window it's measured against, and the parts.
async function claudeContext(agent) {
  let release;
  const waiting = new Promise((r) => { release = r; });
  const q = query({ prompt: (async function* () { await waiting; })(), options: resumeOptions(agent) });
  try {
    const c = await within(q.getContextUsage({ detail: 'summary' }), 45_000);
    return {
      used: c.totalTokens || 0, window: c.rawMaxTokens || c.maxTokens || null, percent: c.percentage ?? null, model: c.model || null,
      parts: (c.categories || []).filter((x) => x.kind === 'used' && x.tokens > 0).map((x) => ({ name: x.name, tokens: x.tokens })),
      free: (c.categories || []).filter((x) => x.kind === 'free').reduce((n, x) => n + x.tokens, 0),
    };
  } finally { release(); try { await q.interrupt(); } catch {} try { q.return?.(); } catch {} }
}

/// Runs /compact on a Claude session: Claude Code summarises it in place. Reports the tokens before and after.
async function claudeCompact(agent) {
  const input = inputQueue();
  input.push(userMessage('/compact'));
  const q = query({ prompt: input.iterable, options: resumeOptions(agent) });
  let before = null, after = null, sessionId = agent.sessionId, result = null, window = null, said = '';
  try {
    for await (const m of q) {
      if (m.type === 'system' && m.subtype === 'init' && m.session_id) sessionId = m.session_id;
      else if (m.type === 'system' && m.subtype === 'compact_boundary') { before = m.compact_metadata?.pre_tokens ?? before; after = m.compact_metadata?.post_tokens ?? after; }
      else if (m.type === 'system' && m.subtype === 'local_command_output') said = String(m.content || said);
      else if (m.type === 'result') {
        result = m;
        try { const c = await within(q.getContextUsage({ detail: 'summary' }), 20_000); after = c.totalTokens || after; window = c.rawMaxTokens || c.maxTokens || null; } catch {}
        input.close();
      }
    }
  } finally { input.close(); }
  if (!result) throw new Error('Claude Code stopped before it could compact.');
  if (result.subtype !== 'success' || result.is_error) throw new Error(readable((result.errors && result.errors.join(' ')) || result.result || said) || 'Claude Code couldn\u2019t compact this chat.');
  if (before == null && !after) throw new Error(readable(said || result.result) || 'Claude Code didn\u2019t compact this chat.');
  return { before, after, window, sessionId, cost: result.total_cost_usd || 0 };
}

/// Compacts a Codex thread (thread/compact/start) and waits for it to say it's done.
function codexCompact(cwd, threadId) {
  return new Promise((resolve, reject) => {
    const bin = findBinary('codex');
    if (!bin) return reject(new Error('Codex is not installed on this Mac.'));
    const child = spawn(bin, ['app-server'], { cwd: fs.existsSync(cwd) ? cwd : HOME, env: process.env, stdio: ['pipe', 'pipe', 'ignore'] });
    let id = 0, before = null, after = null, window = null, done = false;
    const send = (method, params) => child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id: ++id, method, params })}\n`);
    const end = (err) => { if (done) return; done = true; clearTimeout(timer); try { child.kill(); } catch {} if (err) reject(err); else resolve({ before, after, window, sessionId: threadId }); };
    const timer = setTimeout(() => end(new Error('Codex took too long to compact.')), 300_000);
    readline.createInterface({ input: child.stdout }).on('line', (line) => {
      let m; try { m = JSON.parse(line); } catch { return; }
      if (m.method === 'thread/tokenUsage/updated' && m.params?.tokenUsage?.last) {
        const n = (m.params.tokenUsage.last.inputTokens || 0) + (m.params.tokenUsage.last.outputTokens || 0);
        if (before == null) before = n; else after = n;
        window = m.params.tokenUsage.modelContextWindow || window;
      }
      if (m.method === 'thread/compacted' || (m.method === 'turn/completed' && id >= 3)) return end();
      if (m.id === undefined || m.method) return;
      if (m.error) return end(new Error(m.error.message || 'Codex refused.'));
      if (m.id === 1) { child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'initialized' })}\n`); send('thread/resume', { threadId, cwd }); }
      else if (m.id === 2) send('thread/compact/start', { threadId });
    });
    child.on('error', (e) => end(e));
    child.on('close', () => end(done ? null : new Error('Codex stopped before it could compact.')));
    send('initialize', { clientInfo: { name: 'agent-lab', title: 'Agent Lab', version: '1.0' }, capabilities: { experimentalApi: true, requestAttestation: false } });
  });
}

/// Codex's commands (the ones it runs itself) and its skills.
async function codexCatalog(cwd) {
  const native = [
    { name: 'compact', about: 'Summarise the conversation to make room', hint: '', kind: 'command' },
    { name: 'review', about: 'Review the uncommitted changes, or what you ask', hint: '[what to review]', kind: 'command' },
    { name: 'init', about: 'Write an AGENTS.md with what Codex should know about this project', hint: '', kind: 'command' },
  ];
  try {
    const [skills, models] = await codexRpc(cwd, [['skills/list', { cwds: [cwd] }], ['model/list', { includeHidden: false }]]);
    const found = (skills?.data || []).flatMap((e) => e.skills || []).filter((k) => k.enabled !== false);
    return {
      commands: [...native, ...found.map((k) => ({ name: k.name, about: k.shortDescription || k.description || '', hint: '', kind: 'skill' }))],
      agents: [],
      models: (models?.data || []).map((m) => ({ id: m.model || m.id, name: m.displayName || m.model, about: m.description || '' })),
    };
  } catch { return { commands: native, agents: [], models: [] }; }
}

/// A few requests to `codex app-server`, one after another (each waits for the last), then it's closed. Returns each
/// result (null for one it refused).
export function codexRpc(cwd, calls) {
  return new Promise((resolve, reject) => {
    const bin = findBinary('codex');
    if (!bin) return reject(new Error('Codex is not installed on this Mac.'));
    const child = spawn(bin, ['app-server'], { cwd: fs.existsSync(cwd) ? cwd : HOME, env: process.env, stdio: ['pipe', 'pipe', 'ignore'] });
    const results = [];
    let id = 0, at = -1;
    const send = (method, params) => child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id: ++id, method, params })}\n`);
    const end = () => { clearTimeout(timer); child.kill(); resolve(results); };
    const timer = setTimeout(end, 60_000);
    const nextCall = () => { at += 1; if (at >= calls.length) return end(); send(calls[at][0], calls[at][1]); };
    readline.createInterface({ input: child.stdout }).on('line', (line) => {
      let m; try { m = JSON.parse(line); } catch { return; }
      if (m.id === undefined || m.method) return;
      if (m.id === 1) { child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'initialized' })}\n`); return nextCall(); }
      results[at] = m.error ? null : m.result;
      if (m.error) console.log(`codex ${calls[at][0]}: ${m.error.message}`);
      nextCall();
    });
    child.on('error', (e) => { clearTimeout(timer); reject(e); });
    send('initialize', { clientInfo: { name: 'agent-lab', title: 'Agent Lab', version: '1.0' }, capabilities: { experimentalApi: true, requestAttestation: false } });
  });
}


/// A helper's report as Claude Code hands it back to the agent, without the frame around it: the words after "The
/// report follows:", un-indented, up to the agent id and usage lines.
export function helperReport(text) {
  let t = String(text || '');
  const at = t.indexOf('The report follows:');
  if (at >= 0) t = t.slice(at + 'The report follows:'.length);
  t = t.replace(/<tools-used-before-summary>[\s\S]*?<\/tools-used-before-summary>/g, '');
  const lines = [];
  for (const l of t.split('\n')) {
    if (/^(agentId:|<usage>)/.test(l)) break;
    lines.push(l.startsWith('  ') ? l.slice(2) : l);
  }
  return lines.join('\n').trim();
}

/// The window a model's context fits in, when Claude Code doesn't say: the 1M variants by name, else 200K.
export function windowOf(model) {
  const m = String(model || '').toLowerCase();
  if (/\[1m\]|-1m\b|1m-context/.test(m)) return 1_000_000;
  return 200_000;
}

/// The tokens a Claude run used (every model it called, its helpers' too) and how full the context was at its last
/// request (what that request read, cached or not, plus what it wrote).
export function usageOfResult(result, last) {
  const models = Object.entries(result?.modelUsage || {});
  const add = (k) => models.reduce((n, [, m]) => n + (m?.[k] || 0), 0);
  const u = models.length ? { input: add('inputTokens'), output: add('outputTokens'), cacheRead: add('cacheReadInputTokens'), cacheWrite: add('cacheCreationInputTokens') }
    : { input: result?.usage?.input_tokens || 0, output: result?.usage?.output_tokens || 0, cacheRead: result?.usage?.cache_read_input_tokens || 0, cacheWrite: result?.usage?.cache_creation_input_tokens || 0 };
  const model = last?.model || models[0]?.[0] || null;
  const info = (model && result?.modelUsage?.[model]) || models.find(([k]) => model && k.startsWith(model))?.[1] || null;
  const used = last ? (last.input_tokens || 0) + (last.cache_read_input_tokens || 0) + (last.cache_creation_input_tokens || 0) + (last.output_tokens || 0) : 0;
  return { mode: 'add', ...u, model, context: used ? { used, window: info?.contextWindow || windowOf(model), model } : null };
}

/// An input stream for a Claude request: messages pushed in go to Claude Code in order; closing ends the request.
function inputQueue() {
  const items = [];
  let wake = null;
  const q = {
    closed: false,
    push(m) { if (q.closed) return; items.push(m); wake?.(); },
    close() { q.closed = true; wake?.(); },
    iterable: (async function* () {
      while (true) {
        if (items.length) { yield items.shift(); continue; }
        if (q.closed) return;
        await new Promise((r) => { wake = r; });
        wake = null;
      }
    })(),
  };
  return q;
}

/// One message from you: words, and pictures as images.
function userMessage(text, images = []) {
  const blocks = [];
  for (const file of images || []) {
    try {
      const data = fs.readFileSync(file).toString('base64');
      const ext = path.extname(file).toLowerCase();
      const media = ext === '.png' ? 'image/png' : ext === '.gif' ? 'image/gif' : ext === '.webp' ? 'image/webp' : 'image/jpeg';
      blocks.push({ type: 'image', source: { type: 'base64', media_type: media, data } });
    } catch {}
  }
  return { type: 'user', message: { role: 'user', content: blocks.length ? [...blocks, { type: 'text', text }] : text }, parent_tool_use_id: null, session_id: '' };
}

/// Where Claude Code keeps a session's transcript.
function claudeTranscript(sessionId) {
  const root = path.join(HOME, '.claude', 'projects');
  for (const dir of (fs.existsSync(root) ? fs.readdirSync(root) : [])) {
    const f = path.join(root, dir, `${sessionId}.jsonl`);
    if (fs.existsSync(f)) return f;
  }
  return null;
}

/// Puts back the files Claude changed after `keep` (the last reply kept): finds your message after it in Claude's
/// transcript, then asks Claude Code to rewind its file checkpoints to it. Returns a line for the chat.
async function rewindClaudeFiles(agent, keep) {
  const file = claudeTranscript(agent.sessionId);
  if (!file) return 'The files stay as they are (Claude Code\u2019s record of this chat is gone).';
  let target = null;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.type !== 'user' || o.isMeta || o.isSidechain) continue;
    if (Array.isArray(o.message?.content) && o.message.content.some((b) => b.type === 'tool_result')) continue;
    if ((keep ? o.parentUuid === keep : !target)) { target = o.uuid; if (keep) break; }
  }
  if (!target) return 'The files stay as they are (no checkpoint for that message).';
  let release;
  const waiting = new Promise((r) => { release = r; });
  const q = query({
    prompt: (async function* () { await waiting; })(),
    options: { cwd: fs.existsSync(agent.cwd || HOME) ? agent.cwd : HOME, resume: agent.sessionId, enableFileCheckpointing: true,
               pathToClaudeCodeExecutable: findBinary('claude') || undefined, settingSources: [],
               env: { ...subscriptionEnvironment(), CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING: '1' } },
  });
  try {
    const r = await q.rewindFiles(target);
    if (r?.canRewind === false) return `The files stay as they are (${r.error || 'nothing to put back'}).`;
    const n = r?.filesChanged?.length || 0;
    return n ? `Put back ${n} file${n === 1 ? '' : 's'} as they were.` : 'No files had changed since then.';
  } finally { release(); try { await q.interrupt(); } catch {} }
}

/// Codex's input for one message: words, and pictures by path.
function inputOf(text, images = []) {
  return [{ type: 'text', text, text_elements: [] }, ...(images || []).map((p) => ({ type: 'localImage', path: p }))];
}

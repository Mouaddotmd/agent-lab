// Runs agents through the tools you already use, as themselves:
//   Claude Code through the Claude Agent SDK (your claude login, your settings, Claude Code's own system prompt),
//   Codex through `codex exec --json`, Cursor through `cursor-agent -p --output-format stream-json`.
// Agent Lab adds nothing to how they behave except two things you write yourself: an agent's job, and the
// decisions you saved to Memory. Leave both empty and the agent answers exactly as the tool does on its own.
import { query } from '@anthropic-ai/claude-agent-sdk';
import { spawn, execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { newId } from './store.js';

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
  cursor: { name: 'Cursor', bin: 'cursor-agent', approvals: false },
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
    default: return { verb: 'Use', line: name.replace(/^mcp__/, '').replace(/__/g, ' · ') };
  }
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
    return [...this.runs.values()].map((r) => ({ key: r.key, agentId: r.agentId, chat: r.chat, operator: r.operator, startedAt: r.startedAt, activity: r.activity, preview: r.preview }));
  }

  pending() {
    return [...this.approvals.values()].map(({ resolve, signal, ...a }) => a);
  }

  // What every Claude Code agent is told on top of Claude Code's own prompt: only what you wrote.
  appendFor(agent) {
    const parts = [];
    if (agent.job?.trim()) parts.push(`Your job, set by the user: ${agent.job.trim()}`);
    const ws = this.store.state.workspaces.find((w) => agent.cwd && (agent.cwd === w.path || agent.cwd.startsWith(`${w.path}/`) || agent.baseRepo === w.path));
    const decisions = this.store.state.memory.filter((d) => !d.workspace || d.workspace === ws?.id);
    if (decisions.length) parts.push(`Decisions the user has made. Follow them:\n${decisions.map((d) => `- ${d.text}`).join('\n')}`);
    return parts.join('\n\n');
  }

  // ---- agents ----------------------------------------------------------------------------------
  sendToAgent(agentId, text) {
    const agent = this.store.agent(agentId);
    if (!agent) throw new Error('That agent no longer exists.');
    const key = `agent:${agentId}`;
    if (this.runs.has(key)) throw new Error(`${agent.name} is still working. Stop it first, or wait.`);
    this.store.addMessage(agentId, { role: 'user', text });
    this.emit({ type: 'messages', agentId });
    const run = this.#newRun(key, { agentId, operator: agent.operator });
    run.onSession = (sid) => { if (sid && sid !== agent.sessionId) this.store.updateAgent(agentId, { sessionId: sid }); };
    run.onText = (t) => { this.store.addMessage(agentId, { role: 'assistant', text: t }); this.emit({ type: 'messages', agentId }); };
    run.onTool = (d) => { this.store.addMessage(agentId, { role: 'tool', verb: d.verb, text: d.line }); this.emit({ type: 'messages', agentId }); };
    run.onEnd = (outcome) => {
      if (outcome.error) this.store.addMessage(agentId, { role: 'error', text: outcome.error });
      this.store.updateAgent(agentId, { last: { state: outcome.error ? (outcome.stopped ? 'stopped' : 'failed') : 'done', at: Date.now(), cost: outcome.cost ?? null, seen: false } });
      this.emit({ type: 'messages', agentId });
    };
    const target = { cwd: agent.cwd || HOME, sessionId: agent.sessionId, model: agent.model, permission: agent.permission, append: this.appendFor(agent) };
    this.#start(run, agent.operator, target, text);
    return run.key;
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

  stop(key) {
    const run = this.runs.get(key);
    if (!run) return false;
    run.stopped = true;
    run.abort?.();
    return true;
  }

  stopAll() { for (const k of this.runs.keys()) this.stop(k); }

  answer(id, decision) {
    const a = this.approvals.get(id);
    if (!a) return false;
    this.approvals.delete(id);
    if (decision === 'deny') a.resolve({ behavior: 'deny', message: 'The user said no to this. Ask what they would like instead.' });
    else a.resolve({ behavior: 'allow', updatedInput: a.input, ...(decision === 'always' && a.suggestions?.length ? { updatedPermissions: a.suggestions } : {}) });
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

  // ---- internals -------------------------------------------------------------------------------
  #newRun(key, extra) {
    const run = { key, startedAt: Date.now(), activity: 'Starting', preview: '', abort: null, stopped: false, ...extra };
    this.runs.set(key, run);
    this.#emitRun(run);
    return run;
  }

  #emitRun(run) { this.emit({ type: 'run', run: { key: run.key, agentId: run.agentId, chat: run.chat, operator: run.operator, startedAt: run.startedAt, activity: run.activity, preview: run.preview } }); }

  #start(run, operator, target, text) {
    const go = operator === 'codex' ? this.#codex(run, target, text) : operator === 'cursor' ? this.#cursor(run, target, text) : this.#claude(run, target, text);
    go.then((o) => this.#finish(run, o || {}), (err) => this.#finish(run, { error: run.stopped ? 'Stopped.' : readable(err?.message || String(err)) }));
  }

  #finish(run, outcome) {
    for (const [id, a] of this.approvals) if (a.key === run.key) { this.approvals.delete(id); a.resolve({ behavior: 'deny', message: 'Stopped.' }); }
    this.runs.delete(run.key);
    if (run.stopped && !outcome.error) outcome.error = 'Stopped.';
    outcome.stopped = run.stopped;
    try { run.onEnd?.(outcome); } catch {}
    this.emit({ type: 'run-end', key: run.key, agentId: run.agentId, error: outcome.error || null });
    this.emit({ type: 'approvals' });
  }

  #tool(run, d) { run.activity = `${d.verb} ${d.line}`; run.onTool?.(d); this.#emitRun(run); }

  #text(run, t) {
    if (!t?.trim()) return;
    run.preview = clip(t, 160);
    run.activity = 'Writing';
    run.onText?.(t);
    this.#emitRun(run);
  }

  async #claude(run, target, text) {
    const ac = new AbortController();
    run.abort = () => ac.abort();
    const options = {
      cwd: fs.existsSync(target.cwd) ? target.cwd : HOME,
      abortController: ac,
      includePartialMessages: true,
      pathToClaudeCodeExecutable: findBinary('claude') || undefined,
      permissionMode: target.permission === 'edits' ? 'acceptEdits' : target.permission === 'plan' ? 'plan' : 'default',
      disallowedTools: ['AskUserQuestion'],
      canUseTool: (toolName, input, { signal, suggestions }) => this.#approval(run, toolName, input, signal, suggestions),
      stderr: (d) => { run.stderr = `${run.stderr || ''}${d}`.slice(-4000); },
    };
    if (target.sessionId) options.resume = target.sessionId;
    if (target.model) options.model = target.model;
    if (target.append) options.systemPrompt = { type: 'preset', preset: 'claude_code', append: target.append };
    let result = null;
    run.activity = 'Thinking';
    this.#emitRun(run);
    for await (const m of query({ prompt: text, options })) {
      if (m.type === 'system' && m.subtype === 'init') run.onSession?.(m.session_id);
      else if (m.type === 'stream_event' && !m.parent_tool_use_id) {
        const e = m.event;
        if (e?.type === 'content_block_delta' && e.delta?.type === 'text_delta') { run.draft = `${run.draft || ''}${e.delta.text}`; this.emit({ type: 'delta', key: run.key, text: run.draft }); }
      } else if (m.type === 'assistant' && !m.parent_tool_use_id) {
        for (const b of m.message?.content || []) {
          if (b.type === 'text') { run.draft = ''; this.#text(run, b.text); }
          else if (b.type === 'tool_use') this.#tool(run, describeTool(b.name, b.input));
        }
      } else if (m.type === 'result') {
        result = m;
        if (m.session_id) run.onSession?.(m.session_id);
      }
    }
    if (!result) return { error: run.stopped ? 'Stopped.' : (clip(run.stderr, 300) || 'Claude Code stopped without an answer.') };
    if (result.subtype !== 'success' || result.is_error) return { error: readable((result.errors && result.errors.join(' ')) || result.result) || 'Claude Code could not finish.', cost: result.total_cost_usd };
    return { cost: result.total_cost_usd };
  }

  #approval(run, toolName, input, signal, suggestions) {
    return new Promise((resolve) => {
      const id = newId('ap');
      const d = describeTool(toolName, input);
      const a = { id, key: run.key, agentId: run.agentId, chat: run.chat, tool: toolName, verb: d.verb, line: d.line, detail: d.detail || null, input, suggestions, at: Date.now(), resolve };
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

  async #codex(run, target, text) {
    const args = ['exec', '--json', '--skip-git-repo-check'];
    if (target.model) args.push('-m', target.model);
    args.push('-s', target.permission === 'plan' ? 'read-only' : 'workspace-write');
    if (target.sessionId) args.push('resume', target.sessionId);
    args.push(text);
    let failed = null, done = false;
    run.activity = 'Thinking';
    this.#emitRun(run);
    const { code, err } = await this.#spawnLines(run, findBinary('codex'), args, target.cwd, (j) => {
      if (j.type === 'thread.started' && j.thread_id) run.onSession?.(j.thread_id);
      else if (j.type === 'item.completed') {
        const it = j.item || {};
        if (it.type === 'agent_message') this.#text(run, it.text);
        else if (it.type === 'command_execution') this.#tool(run, { verb: 'Run', line: clip(it.command, 120) });
        else if (it.type === 'file_change') this.#tool(run, { verb: 'Edit', line: (it.changes || []).map((c) => base(c.path)).slice(0, 3).join(', ') || 'files' });
        else if (it.type === 'web_search') this.#tool(run, { verb: 'Search the web for', line: clip(it.query, 80) });
        else if (it.type === 'mcp_tool_call') this.#tool(run, { verb: 'Use', line: it.tool || 'a tool' });
      } else if (j.type === 'turn.completed') done = true;
      else if (j.type === 'turn.failed') failed = readable(j.error?.message) || 'Codex could not finish.';
      else if (j.type === 'error' && j.message && !done) run.lastError = readable(j.message);
    });
    if (run.stopped) return { error: 'Stopped.' };
    if (failed) return { error: failed };
    if (!done && code !== 0) return { error: clip(run.lastError || err, 300) || `Codex exited with code ${code}.` };
    return {};
  }

  async #cursor(run, target, text) {
    const args = ['-p', text, '--output-format', 'stream-json', '--stream-partial-output'];
    if (target.permission === 'edits') args.push('--force');
    if (target.model) args.push('--model', target.model);
    if (target.sessionId) args.push('--resume', target.sessionId);
    let failed = null, buffer = '';
    run.activity = 'Thinking';
    this.#emitRun(run);
    const flush = () => { if (buffer.trim()) { const t = buffer; buffer = ''; run.draft = ''; this.#text(run, t); } };
    const { code, err } = await this.#spawnLines(run, findBinary('cursor-agent'), args, target.cwd, (j) => {
      if (j.type === 'system' && j.subtype === 'init' && j.session_id) run.onSession?.(j.session_id);
      else if (j.type === 'assistant') {
        const t = (j.message?.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
        if (t) { buffer += t; run.draft = buffer; this.emit({ type: 'delta', key: run.key, text: buffer }); }
      } else if (j.type === 'tool_call' && j.subtype === 'started') {
        flush();
        const call = j.tool_call || {}; const name = Object.keys(call)[0] || 'tool'; const a = call[name]?.args || {};
        if (/read/i.test(name)) this.#tool(run, { verb: 'Read', line: base(a.path) });
        else if (/edit|write/i.test(name)) this.#tool(run, { verb: 'Edit', line: base(a.path) });
        else if (/shell/i.test(name)) this.#tool(run, { verb: 'Run', line: clip(a.command, 120) });
        else this.#tool(run, { verb: 'Use', line: name.replace(/ToolCall$/, '') });
      } else if (j.type === 'result') { flush(); if (j.is_error) failed = readable(j.result) || 'Cursor stopped with an error.'; }
    });
    flush();
    if (run.stopped) return { error: 'Stopped.' };
    if (failed) return { error: failed };
    if (code !== 0) return { error: clip(err, 300) || `Cursor exited with code ${code}.` };
    return {};
  }
}

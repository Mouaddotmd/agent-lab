// Commands an agent leaves running, for the Terminal tab (TerminalTab.swift): each shows there with its live output
// and Stop. Two kinds:
//   - run:    a command started here (terminal:run), in the agent's folder, in its own process group.
//   - follow: a command Claude Code started in the background (Bash with run_in_background): its output file is read as
//             it grows, and Stop ends its process and everything it started.
// Events: { type: 'terminal-run', agentId, run }  when one starts or changes state (running, done, failed, stopped)
//         { type: 'terminal-output', agentId, id, data }  new output, gathered into one event every ~80 ms.
// The interactive shell itself is not here: the app runs it on its own pseudo-terminal.
import { spawn, execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';

const runs = new Map();
let emit = () => {};
let seq = 0;
const TAIL = 200_000;          // what's kept of each run's output, for a tab opened later
const CHUNK = 64 * 1024;       // most output in one event

const info = (r) => ({ id: r.id, agentId: r.agentId, command: r.command, cwd: r.cwd, state: r.state, code: r.code ?? null, startedAt: r.startedAt, endedAt: r.endedAt || null, kind: r.kind });
const changed = (r) => emit({ type: 'terminal-run', agentId: r.agentId, run: info(r) });

function output(r, text) {
  if (!text) return;
  r.tail = (r.tail + text).slice(-TAIL);
  r.pending += text;
  if (!r.timer) r.timer = setTimeout(() => flush(r), 80);
}
function flush(r) {
  r.timer = null;
  if (!r.pending) return;
  const data = r.pending.slice(0, CHUNK);
  r.pending = r.pending.slice(CHUNK);
  emit({ type: 'terminal-output', agentId: r.agentId, id: r.id, data });
  if (r.pending) r.timer = setTimeout(() => flush(r), 80);
}
function finish(r, state, code) {
  if (r.state !== 'running') return;
  if (r.kind === 'follow') readMore(r);
  r.state = r.stopping ? 'stopped' : state;
  r.code = code ?? null;
  r.endedAt = Date.now();
  clearInterval(r.poll); clearInterval(r.alive);
  if (r.timer) { clearTimeout(r.timer); r.timer = null; }
  while (r.pending) flush(r);
  changed(r);
}
const newRun = (agentId, kind, command, cwd) => {
  const r = { id: `t${Date.now().toString(36)}${(++seq).toString(36)}`, agentId: String(agentId), kind, command: String(command), cwd: cwd || os.homedir(), state: 'running', code: null, startedAt: Date.now(), tail: '', pending: '', timer: null };
  runs.set(r.id, r);
  return r;
};

// A command started here: the user's login shell runs it, so PATH and the rest are as in their terminal.
export function run(agentId, command, cwd) {
  if (!agentId || !String(command || '').trim()) throw new Error('Nothing to run.');
  const dir = cwd && fs.existsSync(cwd) ? cwd : os.homedir();
  const r = newRun(agentId, 'run', command, dir);
  const shell = process.env.SHELL || '/bin/zsh';
  const child = spawn(shell, ['-lc', String(command)], { cwd: dir, detached: true, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '1', CLICOLOR_FORCE: '1' } });
  r.child = child;
  child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
  child.stdout.on('data', (d) => output(r, d));
  child.stderr.on('data', (d) => output(r, d));
  child.on('error', (e) => { output(r, `${e.message}\n`); finish(r, 'failed', null); });
  child.on('exit', (code, sig) => finish(r, code === 0 ? 'done' : 'failed', code ?? (sig ? 128 + (os.constants.signals[sig] || 0) : null)));
  changed(r);
  return info(r);
}

// Claude Code's background command. `text` is what its tool call answered ("… Output is being written to: <file>");
// `file` and `pid` can be given directly instead.
export function follow(agentId, { command = '', text = '', file = null, pid = null } = {}) {
  const said = String(text || '');
  const out = file || (said.match(/written to:?\s*(\/\S+?)[.,]?(?:\s|$)/i) || said.match(/(\/\S+\.(?:output|log|txt))/) || [])[1] || null;
  for (const r of runs.values()) if (r.kind === 'follow' && r.state === 'running' && out && r.file === out) return info(r);
  const r = newRun(agentId, 'follow', command || 'Background command', null);
  r.file = out; r.offset = 0; r.pid = pid || null;
  if (r.file) r.poll = setInterval(() => readMore(r), 250);
  else output(r, "(Its output isn't available here.)\n");
  // Ended when its process is gone; the process is looked up by its command when Claude didn't say which it is.
  let tries = 0;
  r.alive = setInterval(async () => {
    if (!r.pid && tries++ < 10) r.pid = await findProcess(r.command);
    if (r.pid && !alive(r.pid)) finish(r, 'done', null);
  }, 1000);
  changed(r);
  return info(r);
}

function readMore(r) {
  if (!r.file) return;
  let st;
  try { st = fs.statSync(r.file); } catch { return; }
  if (st.size < r.offset) r.offset = 0;      // started over
  if (st.size === r.offset) return;
  const len = Math.min(st.size - r.offset, 1 << 20);
  const buf = Buffer.alloc(len);
  let fd;
  try { fd = fs.openSync(r.file, 'r'); fs.readSync(fd, buf, 0, len, r.offset); } catch { return; } finally { if (fd != null) fs.closeSync(fd); }
  r.offset += len;
  output(r, buf.toString('utf8'));
}

const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };

function table() {
  return new Promise((resolve) => execFile('/bin/ps', ['-axo', 'pid=,ppid=,command='], { maxBuffer: 8 << 20 }, (err, out) => {
    if (err) return resolve([]);
    resolve(out.split('\n').map((l) => l.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/)).filter(Boolean).map((m) => ({ pid: +m[1], ppid: +m[2], command: m[3] })));
  }));
}
// The process running `command` (quotes and escapes aside, since the shell that runs it may have re-quoted it).
async function findProcess(command) {
  const flat = (s) => s.replace(/["'\\]/g, '').replace(/\s+/g, ' ').trim();
  const want = flat(command).slice(0, 200);
  if (want.length < 2) return null;
  const all = await table();
  const byPid = new Map(all.map((p) => [p.pid, p]));
  const up = (pid) => { const out = []; for (let p = byPid.get(pid); p && p.pid > 1 && out.length < 64; p = byPid.get(p.ppid)) out.push(p); return out; };
  // Never the engine, the app or anything above them.
  const mine = new Set([process.pid, ...up(process.pid).map((p) => p.pid)]);
  let hits = all.filter((p) => !mine.has(p.pid) && !p.command.startsWith('/bin/ps ') && flat(p.command).includes(want));
  // Started by Claude Code when there's such a one; the outermost of them (the shell that runs it), the newest first.
  const underClaude = hits.filter((h) => up(h.ppid).some((a) => /claude/i.test(a.command)));
  if (underClaude.length) hits = underClaude;
  const ids = new Set(hits.map((h) => h.pid));
  const top = hits.filter((h) => !up(h.ppid).some((a) => ids.has(a.pid)));
  return top.length ? Math.max(...top.map((p) => p.pid)) : null;
}
// A process and everything under it, deepest first.
async function tree(pid) {
  const all = await table();
  const out = [];
  const walk = (p) => { for (const c of all) if (c.ppid === p) walk(c.pid); out.push(p); };
  walk(pid);
  return out;
}
const signal = (pids, sig) => { for (const p of pids) { try { process.kill(p, sig); } catch {} } };

export async function stop(id) {
  const r = runs.get(id);
  if (!r || r.state !== 'running') return r ? info(r) : null;
  r.stopping = true;
  if (r.kind === 'run' && r.child?.pid) {
    // Its own process group: the command and whatever it started.
    try { process.kill(-r.child.pid, 'SIGTERM'); } catch {}
    setTimeout(() => { if (r.state === 'running') { try { process.kill(-r.child.pid, 'SIGKILL'); } catch {} } }, 2000);
    return info(r);
  }
  if (!r.pid) r.pid = await findProcess(r.command);
  if (!r.pid) { finish(r, 'stopped', null); return info(r); }
  // Not by process group: Claude Code may share one with what it starts, and it must keep running.
  const pids = await tree(r.pid);
  signal(pids, 'SIGTERM');
  setTimeout(() => { signal(pids.filter(alive), 'SIGKILL'); if (r.state === 'running') finish(r, 'stopped', null); }, 2000);
  return info(r);
}

export default function calls(ctx) {
  emit = (event) => ctx.out({ event });
  // Commands started here end with the engine (the app quitting), as a terminal's jobs do when it closes.
  process.on('exit', () => { for (const r of runs.values()) if (r.kind === 'run' && r.state === 'running' && r.child?.pid) { try { process.kill(-r.child.pid, 'SIGHUP'); } catch {} } });
  return {
    'terminal:run': (agentId, command, cwd) => run(agentId, command, cwd || ctx.store.agent?.(agentId)?.cwd),
    'terminal:follow': (agentId, spec) => follow(agentId, spec || {}),
    'terminal:stop': (id) => stop(id),
    'terminal:forget': (id) => { const r = runs.get(id); if (r && r.state === 'running') return false; runs.delete(id); return true; },
    // The agent's runs, with the last part of each one's output.
    'terminal:runs': (agentId) => [...runs.values()].filter((r) => r.agentId === String(agentId)).map((r) => ({ ...info(r), tail: r.tail })),
  };
}

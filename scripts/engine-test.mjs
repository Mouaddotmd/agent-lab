// Drives the engine server the way the app does: real Claude Code, real git, a throwaway data folder and repo.
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';

const data = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-data-'));
const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-repo-'));
const g = (...a) => execFileSync('git', ['-c', 'user.name=T', '-c', 'user.email=t@t', ...a], { cwd: repo });
g('init', '-q', '-b', 'main'); fs.writeFileSync(path.join(repo, 'README.md'), '# t\n'); g('add', '.'); g('commit', '-qm', 'init');

const srv = spawn(process.execPath, ['engine/server.js'], { env: { ...process.env, AGENT_LAB_DATA: data }, stdio: ['pipe', 'pipe', 'inherit'] });
const pending = new Map(); const events = []; const waiters = [];
let next = 1;
readline.createInterface({ input: srv.stdout }).on('line', (l) => {
  const m = JSON.parse(l);
  if (m.event) { events.push(m.event); waiters.splice(0).forEach((w) => w()); return; }
  const p = pending.get(m.id); pending.delete(m.id);
  m.ok ? p.resolve(m.value) : p.reject(new Error(m.error));
});
const call = (method, ...params) => new Promise((resolve, reject) => { const id = next++; pending.set(id, { resolve, reject }); srv.stdin.write(`${JSON.stringify({ id, method, params })}\n`); });
const until = async (pred, ms, label) => { const t = Date.now(); while (Date.now() - t < ms) { const e = events.find(pred); if (e) return e; await new Promise((r) => { waiters.push(r); setTimeout(r, 500); }); } throw new Error(`timed out: ${label}`); };
const ok = (c, what) => { if (!c) throw new Error(`FAILED: ${what}`); console.log(`ok  ${what}`); };

try {
  await until((e) => e.type === 'ready', 10000, 'ready');
  const st = await call('state');
  ok(st.operators['claude-code'].path, 'Claude Code found');
  const a = await call('agent:create', { name: 'Juno', operator: 'claude-code', model: 'claude-haiku-5-5', permission: 'ask', cwd: repo, ownBranch: true });
  ok(a.branch === 'agent/juno' && fs.existsSync(a.worktree), 'agent on its own branch and folder');
  await call('agent:send', a.id, 'Create a file named hello.txt in the current folder containing exactly: hi from Juno. Then reply with one short sentence.');
  let asked = 0;
  for (;;) {
    const e = await until((x) => (x.type === 'approvals' && !x.seen) || (x.type === 'run-end' && x.key === `agent:${a.id}`), 180000, 'approval or end');
    e.seen = true;
    if (e.type === 'run-end') { ok(!e.error, `run finished${e.error ? `: ${e.error}` : ''}`); break; }
    for (const p of await call('approvals')) { asked++; await call('approval:answer', p.id, 'allow'); }
  }
  ok(asked > 0, `asked before acting (${asked})`);
  ok(fs.existsSync(path.join(a.worktree, 'hello.txt')) && !fs.existsSync(path.join(repo, 'hello.txt')), 'wrote only in its own folder');
  const msgs = await call('agent:messages', a.id);
  ok(msgs.some((m) => m.role === 'assistant'), 'reply saved');
  const ch = await call('git:changes', a.id);
  ok(ch.files.some((f) => f.path === 'hello.txt'), 'review lists the file');
  ok((await call('git:diff', a.id, 'hello.txt')).some((l) => l.startsWith('+hi from Juno')), 'diff shows the line');
  await call('git:merge', a.id);
  ok(fs.existsSync(path.join(repo, 'hello.txt')), 'merge brought it into main');
  const juno = (await call('agents')).find((x) => x.id === a.id);
  ok(juno.sessionId, 'kept its Claude Code session');
  ok((await call('chat:summary', 'claude-code', juno.sessionId)).length > 10, 'hand-off note');
  ok(Array.isArray(await call('chat:decisions', 'claude-code', juno.sessionId)), 'decision finder');
  ok((await call('chats:list', 'claude-code')).length > 0, 'Claude Code chats listed');
  const d = await call('memory:add', 'Never merge without tests', null, null);
  ok((await call('state')).memory.some((m) => m.id === d.id), 'memory saved');
  const mv = await call('mavis:scan');
  if (mv.found) { await call('mavis:import'); ok((await call('state')).imported > 0, 'Mavis conversations imported'); }
  console.log('\nENGINE TEST PASSED');
} catch (e) { console.error(`\n${e.message}`); process.exitCode = 1; }
finally { srv.stdin.end(); await new Promise((r) => srv.on('exit', r)); fs.rmSync(data, { recursive: true, force: true }); fs.rmSync(repo, { recursive: true, force: true }); }

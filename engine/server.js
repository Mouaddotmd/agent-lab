// Agent Lab's engine as a headless process for the native app.
// Protocol: one JSON object per line.
//   in  (stdin):  { "id": 1, "method": "agent:send", "params": [...] }
//   out (stdout): { "id": 1, "ok": true, "value": ... }  or  { "id": 1, "ok": false, "error": "…" }
//   out (stdout): { "event": { "type": "run", ... } }
// stdout carries only protocol lines; anything else goes to stderr. When stdin closes, the engine stops.
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import readline from 'node:readline';
import { Store, GENERAL, normalize } from './store.js';
import { Engine } from './engine.js';
import * as history from './history.js';
import * as git from './git.js';
import * as hands from './hands.js';
import * as apps from './apps.js';

const DATA = process.env.AGENT_LAB_DATA || path.join(os.homedir(), 'Library', 'Application Support', 'Agent Lab');
fs.mkdirSync(DATA, { recursive: true });

const out = (obj) => process.stdout.write(`${JSON.stringify(obj)}\n`);
console.log = (...a) => process.stderr.write(`${a.join(' ')}\n`);
console.info = console.log;
console.warn = console.log;

const store = new Store(DATA);
const engine = new Engine(store, (event) => out({ event }));
apps.init(DATA);
hands.connect((event) => out({ event }));
// Codex agents reach the panes through this socket (hands-stdio.js).
// One per engine (a test's engine never takes the app's), gone when it stops.
const handsSock = path.join(DATA, `hands-${process.pid}.sock`);
hands.listen(handsSock, (agentId, tool, input) => engine.gateHands(agentId, tool, input), apps.fromCodex);
process.on('exit', () => { try { fs.unlinkSync(handsSock); } catch {} });
const mavisCache = { list: null };

function allChats(operator, everything = false) {
  if (operator === 'claude-code') return history.claudeChats({ all: everything });
  if (operator === 'codex') return history.codexChats({ all: everything });
  if (operator === 'mavis') return store.state.imported;
  return [];
}
function findChat(operator, id) {
  const c = allChats(operator, true).find((x) => x.id === id);
  if (!c) throw new Error('That chat is no longer on this Mac.');
  return c;
}
const strip = ({ lines, file, ...c }) => c;
// When an agent last said something in any of a workspace's channels (what "unread" is measured against).
function activityOf(w) {
  let at = 0;
  for (const c of (w.categories || []).flatMap((x) => x.channels || [])) {
    for (const m of store.messages(`c_${w.id}_${c.id}`)) if (m.role !== 'user' && (m.at || 0) > at) at = m.at || 0;
  }
  return at;
}

const methods = {
  async state() {
    return {
      agents: store.state.agents, workspaces: store.state.workspaces.map((w) => ({ ...w, activityAt: activityOf(w) })), memory: store.state.memory,
      runs: engine.snapshot(), approvals: engine.pending(), operators: await engine.operators(),
      codexModels: history.codexModels(), imported: store.state.imported.length, home: os.homedir(),
    };
  },
  agents: () => store.state.agents,
  approvals: () => engine.pending(),
  runs: () => engine.snapshot(),
  // The app's answer to an agent's step on its panes (hands.js).
  'lab:reply': (id, ok, value) => hands.reply(id, !!ok, value),

  async 'agent:create'(spec) {
    const clean = { name: String(spec.name || '').trim() || 'Agent', job: String(spec.job || ''), color: Number.isInteger(spec.color) ? spec.color : null, look: spec.look && typeof spec.look === "object" ? spec.look : null, operator: spec.operator || 'claude-code', model: spec.model || null, permission: spec.permission || 'ask', cwd: spec.cwd || os.homedir(), pinned: !!spec.pinned, sessionId: spec.sessionId || null, origin: spec.origin || null, workspace: typeof spec.workspace === 'string' ? spec.workspace : null };
    if (spec.ownBranch) {
      const wt = await git.createWorktree(clean.cwd, clean.name, path.join(DATA, 'worktrees'));
      Object.assign(clean, wt, { cwd: wt.worktree });
    }
    // Made inside a workspace: it's invited there. Agents belong to nobody; workspaces list their members.
    const ws = clean.workspace; clean.workspace = null;
    const a = store.addAgent(clean);
    if (ws && store.workspace(ws)) store.setMember(ws, a.id, true);
    return a;
  },
  // A copy of an agent: same job, look, model, mode, folder, notes and workspaces; a conversation of its own.
  'agent:duplicate'(id) {
    const a = store.agent(id);
    if (!a) throw new Error('That agent no longer exists.');
    const names = new Set(store.state.agents.map((x) => x.name));
    let name = `${a.name} copy`;
    for (let n = 2; names.has(name); n++) name = `${a.name} copy ${n}`;
    const copy = store.addAgent({ name, job: a.job || '', color: a.color ?? null, look: a.look || null, operator: a.operator, model: a.model || null,
      permission: a.permission || 'ask', cwd: a.cwd || os.homedir(), pinned: false, sessionId: null, origin: a.origin || null, workspace: null,
      claudeSetup: !!a.claudeSetup, alwaysEdits: !!a.alwaysEdits });
    if (a.memory?.length) store.updateAgent(copy.id, { memory: a.memory.map((m) => ({ ...m })) });
    for (const w of store.state.workspaces || []) if ((w.members || []).includes(id)) store.setMember(w.id, copy.id, true);
    return store.agent(copy.id);
  },
  'agent:update'(id, patch) {
    const allowed = ['name', 'job', 'color', 'look', 'workspace', 'model', 'permission', 'alwaysEdits', 'pinned', 'last', 'claudeSetup', 'apps'];
    const p = Object.fromEntries(Object.entries(patch || {}).filter(([k]) => allowed.includes(k)));
    const a = store.updateAgent(id, p);
    if (!a) throw new Error('That agent no longer exists.');
    return a;
  },
  async 'agent:delete'(id, opts = {}) {
    const a = store.agent(id);
    if (!a) return true;
    engine.stop(`agent:${id}`);
    if (a.worktree) await git.removeWorktree(a, { deleteBranch: !!opts.deleteBranch });
    store.removeAgent(id);
    return true;
  },
  'agent:messages': (id) => store.messages(id),
  'agent:send': (id, text, images) => engine.sendToAgent(id, String(text), Array.isArray(images) ? images : []),
  // What the box offers for an agent: its `/` commands, the helpers `@` can name, its models (cached a while).
  'agent:catalog': (id, fresh) => engine.catalog(id, !!fresh),
  'agent:plugins': (id) => engine.plugins(id),
  'agent:plugin': (id, pluginId, on) => engine.setPlugin(id, String(pluginId), !!on),
  'run:stop': (key) => engine.stop(key),
  'approval:answer': (id, decision, extra) => engine.answer(id, decision, extra ?? null),
  // A message sent while the agent works: into what it's doing. False: it couldn't (the app sends it after).
  'agent:steer': (id, text, images) => engine.steer(id, String(text), Array.isArray(images) ? images : []),
  // Back to just before one of your messages in a DM: returns { text, images, note }.
  'agent:rewind': (id, messageId) => engine.rewind(id, String(messageId)),

  'chats:list': (operator) => allChats(operator).map(strip),
  'chat:transcript': (operator, id) => history.transcript(findChat(operator, id)),
  'chat:send'(operator, id, text) {
    if (operator === 'mavis') throw new Error('Mavis chats can be read here, not continued. Hand it to an agent to keep going.');
    return engine.sendToChat(findChat(operator, id), String(text));
  },
  async 'chat:decisions'(operator, id) {
    const text = history.asText(history.transcript(findChat(operator, id)));
    if (!text.trim()) return [];
    const answer = await engine.ask(`Here is a conversation between a user and an AI assistant.\n\n<conversation>\n${text}\n</conversation>\n\nList the decisions the user made or agreed to that should guide future work: rules, choices, constraints. One per line, each starting with "- ", each one short sentence in plain words. If there are none, reply with exactly: none`);
    if (/^none\.?$/i.test(answer.trim())) return [];
    return answer.split('\n').map((l) => l.replace(/^\s*[-*•]\s*/, '').trim()).filter((l) => l && l.length < 300).slice(0, 12);
  },
  async 'chat:summary'(operator, id) {
    const text = history.asText(history.transcript(findChat(operator, id)));
    if (!text.trim()) return '';
    return engine.ask(`Here is a conversation between a user and an AI assistant.\n\n<conversation>\n${text}\n</conversation>\n\nWrite a short hand-off note for someone continuing this work: what the goal is, what was done or decided, and what is left. At most 8 short lines, plain words, no headings.`);
  },

  async 'mavis:scan'() {
    const m = await history.readMavis();
    mavisCache.list = m;
    const have = new Set(store.state.imported.map((c) => c.id));
    return { found: m.found, bots: m.bots.length, chats: m.chats.length, newChats: m.chats.filter((c) => !have.has(c.id)).length, newAgents: m.bots.filter((b) => !store.state.agents.some((a) => a.origin?.type === 'mavis-bot' && a.origin.ref === b.id)).length };
  },
  async 'mavis:import'() {
    const m = mavisCache.list || (await history.readMavis());
    if (!m.found) throw new Error('Mavis data was not found on this Mac.');
    const have = new Set(store.state.imported.map((c) => c.id));
    const added = m.chats.filter((c) => !have.has(c.id));
    store.state.imported.push(...added);
    let agents = 0;
    for (const b of m.bots) {
      if (store.state.agents.some((a) => a.origin?.type === 'mavis-bot' && a.origin.ref === b.id)) continue;
      store.addAgent({ name: b.name, job: '', color: null, operator: 'claude-code', model: null, permission: 'ask', cwd: os.homedir(), pinned: true, origin: { type: 'mavis-bot', ref: b.id, title: 'Brought from Mavis' } });
      agents++;
    }
    store.save();
    return { chats: added.length, agents };
  },

  'memory:add': (text, workspace, source) => store.addDecision(String(text).trim(), { workspace: workspace || null, source: source || null }),
  'memory:remove': (id) => { store.removeDecision(id); return true; },

  'folder:info': async (dir) => ({ exists: !!dir && fs.existsSync(dir), repo: await git.repoInfo(dir) }),
  'workspace:add': (dir) => store.addWorkspace(dir),
  // A workspace is its own place, like a server: a name and a picture. A folder is optional.
  'workspace:create': ({ name, about, image, color, path: dir } = {}) => {
    const w = { id: `w${Math.random().toString(36).slice(2, 10)}`, members: [], categories: GENERAL(), path: dir || null, name: String(name || '').trim().slice(0, 40) || 'New workspace', color: /^#[0-9a-f]{6}$/i.test(color || '') ? color : '#5D6B8C', about: String(about || '').trim().slice(0, 140) };
    if (typeof image === 'string' && /^data:image\/(png|jpeg|webp);base64,/.test(image) && image.length < 400000) w.image = image;
    store.state.workspaces.push(w);
    store.save();
    return w;
  },
  'workspace:remove': (id) => { store.removeWorkspace(id); return true; },
  'workspace:member': (wsId, agentId, on) => store.setMember(wsId, agentId, on !== false),
  'channel:send': (wsId, chId, text, images) => engine.sendToChannel(wsId, chId, String(text), Array.isArray(images) ? images : []),
  'agent:forget': (agentId, noteId) => { const a = store.agent(agentId); if (a) store.updateAgent(agentId, { memory: (a.memory || []).filter((m) => m.id !== noteId) }); return true; },
  'workspace:update': (id, patch = {}) => {
    const w = store.state.workspaces.find((x) => x.id === id);
    if (!w) throw new Error('That project was removed.');
    if (typeof patch.name === 'string' && patch.name.trim()) w.name = patch.name.trim().slice(0, 40);
    if (typeof patch.color === 'string' && /^#[0-9a-f]{6}$/i.test(patch.color)) w.color = patch.color;
    if (typeof patch.about === 'string') w.about = patch.about.trim().slice(0, 140);
    // Muted: no badge, no unread dot. Read up to: when you last caught up (Mark as read, or opening it).
    if (typeof patch.muted === 'boolean') w.muted = patch.muted;
    if (typeof patch.readAt === 'number') w.readAt = patch.readAt;
    if (patch.image === null) delete w.image;
    else if (typeof patch.image === 'string' && /^data:image\/(png|jpeg|webp);base64,/.test(patch.image) && patch.image.length < 400000) w.image = patch.image;
    // Categories of text channels, like a Discord server. Names are cleaned; ids are kept stable.
    if (Array.isArray(patch.categories)) {
      const id = (v) => (typeof v === 'string' && /^[\w-]{1,40}$/.test(v) ? v : `c${Math.random().toString(36).slice(2, 10)}`);
      const chName = (v) => String(v || '').toLowerCase().trim().replace(/[^\p{L}\p{N}_-]+/gu, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'channel';
      w.categories = patch.categories.slice(0, 20).map((c) => ({
        id: id(c?.id), name: String(c?.name || '').trim().slice(0, 40) || 'Category', open: c?.open !== false,
        ...(/^#[0-9a-f]{6}$/i.test(c?.color || '') ? { color: c.color } : {}),
        channels: (Array.isArray(c?.channels) ? c.channels : []).slice(0, 50).map((x) => ({ id: id(x?.id), name: chName(x?.name), ...(Array.isArray(x?.agents) ? { agents: x.agents.filter((v) => typeof v === 'string').slice(0, 20) } : typeof x?.agent === 'string' && x.agent ? { agents: [x.agent] } : {}) })),
      }));
      normalize(store.state);                         // never left without a channel
    }
    store.save();
    return w;
  },

  'git:changes': (agentId) => git.changes(store.agent(agentId)),
  'git:diff': (agentId, file) => git.fileDiff(store.agent(agentId), file),
  async 'git:merge'(agentId) { const r = await git.merge(store.agent(agentId)); out({ event: { type: 'git' } }); return r; },
  async 'git:discard'(agentId) { await git.discard(store.agent(agentId)); out({ event: { type: 'git' } }); return true; },
  'git:overlaps': () => git.overlaps(store.state.agents),
};

// More calls, one module per area (each exports a function that returns { 'name': fn }): files.js, changes.js,
// terminal.js, convo.js (helpers, side chats, fork, hand off, context), palette.js.
for (const mod of ['files.js', 'changes.js', 'terminal.js', 'convo.js', 'palette.js', 'apps.js']) {
  try { Object.assign(methods, (await import(`./${mod}`)).default({ store, engine, git, history, out, DATA })); }
  catch (err) { process.stderr.write(`engine module ${mod}: ${err?.stack || err}\n`); }
}

readline.createInterface({ input: process.stdin }).on('line', async (line) => {
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  const fn = methods[msg.method];
  if (!fn) return out({ id: msg.id, ok: false, error: `Unknown call: ${msg.method}` });
  if (store.refresh()) out({ event: { type: 'state' } });
  try {
    const value = await fn(...(Array.isArray(msg.params) ? msg.params : []));
    out({ id: msg.id, ok: true, value: value === undefined ? null : value });
  } catch (err) {
    out({ id: msg.id, ok: false, error: err?.message || String(err) });
  }
}).on('close', () => { engine.stopAll(); store.flush(); process.exit(0); });

process.on('SIGTERM', () => { engine.stopAll(); store.flush(); process.exit(0); });
process.on('uncaughtException', (err) => process.stderr.write(`engine error: ${err?.stack || err}\n`));
process.on('unhandledRejection', (err) => process.stderr.write(`engine error: ${err?.stack || err}\n`));
out({ event: { type: 'ready', data: DATA } });
// Pick up saves from the other window within a second, even when this one is idle.
setInterval(() => { if (store.refresh()) out({ event: { type: 'state' } }); }, 1000).unref();

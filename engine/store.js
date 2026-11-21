// Everything Agent Lab remembers, as plain JSON in the app's data folder.
// state.json holds agents, workspaces, memory and imported chats; each agent's conversation is its own file.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const EMPTY = { version: 1, agents: [], workspaces: [], memory: [], imported: [], nextDecision: 1 };

export const newId = (prefix) => `${prefix}_${crypto.randomUUID().slice(0, 8)}`;

// Agents are people; workspaces are servers they're invited to. Every workspace has a member list (agent ids) and
// channels grouped in categories (at least #general). Older data put each agent in one workspace (`agent.workspace`):
// those agents become members. Safe to run any number of times.
export const GENERAL = () => [{ id: 'text', name: 'Main', open: true, channels: [{ id: 'general', name: 'general' }] }];
export function normalize(state) {
  // Mavis final launch's four modes; the old three levels map onto them (plans only → read, edits freely → auto).
  for (const a of state.agents) a.permission = ({ plan: 'read', edits: 'auto' })[a.permission] || (['read', 'ask', 'auto', 'full'].includes(a.permission) ? a.permission : 'ask');
  const ids = new Set(state.agents.map((a) => a.id));
  for (const w of state.workspaces) {
    if (!Array.isArray(w.members)) w.members = state.agents.filter((a) => a.workspace === w.id).map((a) => a.id);
    w.members = [...new Set(w.members)].filter((id) => ids.has(id));
    if (!Array.isArray(w.categories) || !w.categories.some((c) => c.channels?.length)) w.categories = GENERAL();
    // Old channels named one answering agent (agent): it's the first of their agents now; gone agents leave.
    for (const c of w.categories) for (const ch of c.channels || []) {
      if (typeof ch.agent === 'string') { ch.agents = [...new Set([ch.agent, ...(ch.agents || [])])]; delete ch.agent; }
      if (Array.isArray(ch.agents)) ch.agents = ch.agents.filter((id) => ids.has(id));
    }
  }
  return state;
}
// A channel's conversation id (its message file): c_<workspace>_<channel>. An agent's DM is just its own id.
export const channelConv = (wsId, chId) => `c_${wsId}_${chId}`;

export class Store {
  constructor(dir) {
    this.dir = dir;
    this.file = path.join(dir, 'state.json');
    this.msgDir = path.join(dir, 'messages');
    fs.mkdirSync(this.msgDir, { recursive: true });
    this.state = this.#read(this.file, EMPTY);
    for (const k of Object.keys(EMPTY)) if (this.state[k] === undefined) this.state[k] = structuredClone(EMPTY[k]);
    normalize(this.state);
    this.msgCache = new Map();
    this.timer = null;
    this.seen = this.#mtime();
  }

  #mtime() { try { return fs.statSync(this.file).mtimeMs; } catch { return 0; } }

  // Two windows (the web app and the Mac app) can share one data folder. Before each call, pick up
  // what the other one saved, so neither overwrites the other's agents. Skipped while our own save is pending.
  refresh() {
    if (this.timer) return false;
    const m = this.#mtime();
    if (!m || m === this.seen) return false;
    const next = this.#read(this.file, null);
    if (!next) return false;
    for (const k of Object.keys(EMPTY)) if (next[k] === undefined) next[k] = structuredClone(EMPTY[k]);
    normalize(next);
    this.state = next; this.seen = m;
    return true;
  }

  #read(file, fallback) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return structuredClone(fallback); }
  }

  // Atomic write: a crash mid-save never leaves a half-written file.
  #write(file, data) {
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(data, null, 1));
    fs.renameSync(tmp, file);
  }

  save() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), 150);
  }

  flush() {
    clearTimeout(this.timer); this.timer = null;
    this.#write(this.file, this.state);
    this.seen = this.#mtime();
    for (const [id, list] of this.msgCache) if (list.dirty) { delete list.dirty; this.#write(this.#msgFile(id), list); }
  }

  #msgFile(id) { return path.join(this.msgDir, `${id.replace(/[^\w-]/g, '_')}.json`); }

  messages(agentId) {
    if (!this.msgCache.has(agentId)) this.msgCache.set(agentId, this.#read(this.#msgFile(agentId), []));
    return this.msgCache.get(agentId);
  }

  addMessage(agentId, msg) {
    const list = this.messages(agentId);
    const m = { id: newId('m'), at: Date.now(), ...msg };
    list.push(m);
    list.dirty = true;
    this.save();
    return m;
  }

  updateMessage(agentId, id, patch) {
    const list = this.messages(agentId);
    const m = list.find((x) => x.id === id);
    if (!m) return null;
    Object.assign(m, patch);
    list.dirty = true;
    this.save();
    return m;
  }

  removeMessage(convId, id) {
    const list = this.messages(convId);
    const i = list.findIndex((x) => x.id === id);
    if (i < 0) return false;
    list.splice(i, 1);
    list.dirty = true;
    this.save();
    return true;
  }

  // Lists kept beside a conversation, one file each, saved the same way as its messages: its helpers (Claude's
  // sub-agents, by their call's id) and an agent's side chats.
  helpers(conv) { return this.messages(`helpers_${conv}`); }
  sides(agentId) { return this.messages(`sides_${agentId}`); }
  /// Adds or replaces an item (by id) in one of those lists.
  put(listId, item) {
    const list = this.messages(listId);
    const i = list.findIndex((x) => x.id === item.id);
    if (i < 0) list.push(item); else list[i] = item;
    list.dirty = true;
    this.save();
    return item;
  }
  putHelper(conv, h) { return this.put(`helpers_${conv}`, h); }
  /// Takes items out of one of those lists.
  drop(listId, keep) {
    const list = this.messages(listId);
    const kept = list.filter(keep);
    if (kept.length === list.length) return;
    list.splice(0, list.length, ...kept);
    list.dirty = true;
    this.save();
  }

  agent(id) { return this.state.agents.find((a) => a.id === id) || null; }

  /** The channels' own assistant: answers in a channel no agent has been given. Hidden from every list of agents. */
  assistant() {
    return this.state.agents.find((a) => a.hidden) || this.addAgent({
      name: 'Assistant', job: '', color: null, look: null, operator: 'claude-code', model: null, permission: 'ask',
      cwd: process.env.HOME || '/', pinned: false, sessionId: null, origin: null, workspace: null, hidden: true,
    });
  }

  addAgent(spec) {
    const a = { id: newId('a'), createdAt: Date.now(), sessionId: null, last: null, ...spec };
    this.state.agents.push(a);
    this.save();
    return a;
  }

  updateAgent(id, patch) {
    const a = this.agent(id);
    if (!a) return null;
    Object.assign(a, patch);
    this.save();
    return a;
  }

  removeAgent(id) {
    this.state.agents = this.state.agents.filter((a) => a.id !== id);
    for (const w of this.state.workspaces) w.members = (w.members || []).filter((m) => m !== id);
    for (const f of [id, `helpers_${id}`, `sides_${id}`]) {
      this.msgCache.delete(f);
      try { fs.unlinkSync(this.#msgFile(f)); } catch {}
    }
    this.save();
  }

  addDecision(text, { workspace = null, by = 'You', source = null } = {}) {
    const d = { id: newId('d'), n: this.state.nextDecision++, text, workspace, by, source, at: Date.now() };
    this.state.memory.push(d);
    this.save();
    return d;
  }

  removeDecision(id) {
    this.state.memory = this.state.memory.filter((d) => d.id !== id);
    this.save();
  }

  addWorkspace(dir) {
    const existing = this.state.workspaces.find((w) => w.path === dir);
    if (existing) return existing;
    const hues = ['#5E9C83', '#7C83C9', '#C27BA0', '#C9A15E', '#5E8FC9', '#B0775E', '#8BA35E'];
    const w = { id: newId('w'), path: dir, name: path.basename(dir), color: hues[this.state.workspaces.length % hues.length] };
    this.state.workspaces.push(w);
    this.save();
    return w;
  }

  workspace(id) { return this.state.workspaces.find((w) => w.id === id) || null; }

  // Invite an agent (same agent, same memory) or take it out again. Its DM and memory stay with it either way.
  setMember(wsId, agentId, on) {
    const w = this.workspace(wsId);
    if (!w) throw new Error('That workspace was removed.');
    if (!this.agent(agentId)) throw new Error('That agent no longer exists.');
    w.members = (w.members || []).filter((m) => m !== agentId);
    if (on) w.members.push(agentId);
    // Out of the workspace: out of its channels too (it kept answering there).
    else for (const c of w.categories || []) for (const ch of c.channels || []) if (Array.isArray(ch.agents)) ch.agents = ch.agents.filter((a) => a !== agentId);
    this.save();
    return w;
  }

  // What an agent noted to remember (⟦remember: …⟧): one list per agent, used in every DM and channel it's in.
  remember(agentId, text) {
    const a = this.agent(agentId);
    const t = String(text || '').replace(/\s+/g, ' ').trim().slice(0, 300);
    if (!a || !t || (a.memory || []).some((m) => m.text.toLowerCase() === t.toLowerCase())) return;
    a.memory = [...(a.memory || []), { id: newId('n'), text: t, at: Date.now() }].slice(-100);
    this.save();
  }

  removeWorkspace(id) {
    this.state.workspaces = this.state.workspaces.filter((w) => w.id !== id);
    for (const a of this.state.agents) if (a.workspace === id) a.workspace = null;   // its agents go back to Personal
    this.save();
  }
}

// Everything Agent Lab remembers, as plain JSON in the app's data folder.
// state.json holds agents, workspaces, memory and imported chats; each agent's conversation is its own file.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const EMPTY = { version: 1, agents: [], workspaces: [], memory: [], imported: [], nextDecision: 1 };

export const newId = (prefix) => `${prefix}_${crypto.randomUUID().slice(0, 8)}`;

export class Store {
  constructor(dir) {
    this.dir = dir;
    this.file = path.join(dir, 'state.json');
    this.msgDir = path.join(dir, 'messages');
    fs.mkdirSync(this.msgDir, { recursive: true });
    this.state = this.#read(this.file, EMPTY);
    for (const k of Object.keys(EMPTY)) if (this.state[k] === undefined) this.state[k] = structuredClone(EMPTY[k]);
    this.msgCache = new Map();
    this.timer = null;
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
    clearTimeout(this.timer);
    this.#write(this.file, this.state);
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

  agent(id) { return this.state.agents.find((a) => a.id === id) || null; }

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
    this.msgCache.delete(id);
    try { fs.unlinkSync(this.#msgFile(id)); } catch {}
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

  removeWorkspace(id) {
    this.state.workspaces = this.state.workspaces.filter((w) => w.id !== id);
    this.save();
  }
}

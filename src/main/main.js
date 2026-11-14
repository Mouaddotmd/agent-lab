import { app, BrowserWindow, ipcMain, dialog, shell, Menu } from 'electron';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { Store } from './store.js';
import { Engine } from './engine.js';
import * as history from './history.js';
import * as git from './git.js';

const here = path.dirname(fileURLToPath(import.meta.url));
let win = null;
let store = null;
let engine = null;
const mavisChats = { list: null };

const send = (payload) => { if (win && !win.isDestroyed()) win.webContents.send('event', payload); };

// Errors become a readable sentence in the window instead of a crash.
function handle(channel, fn) {
  ipcMain.handle(channel, async (_e, ...args) => {
    try { return { ok: true, value: await fn(...args) }; } catch (err) { return { ok: false, error: err?.message || String(err) }; }
  });
}

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
const strip = ({ lines, ...c }) => c;

function registerIpc() {
  handle('state', async () => ({
    agents: store.state.agents, workspaces: store.state.workspaces, memory: store.state.memory,
    runs: engine.snapshot(), approvals: engine.pending(), operators: await engine.operators(), codexModels: history.codexModels(),
    imported: store.state.imported.length, home: os.homedir(),
  }));

  // agents
  handle('agent:create', async (spec) => {
    const clean = { name: String(spec.name || '').trim() || 'Agent', job: String(spec.job || ''), look: spec.look, operator: spec.operator || 'claude-code', model: spec.model || null, permission: spec.permission || 'ask', cwd: spec.cwd || os.homedir(), pinned: !!spec.pinned, sessionId: spec.sessionId || null, origin: spec.origin || null };
    if (spec.ownBranch) {
      const wt = await git.createWorktree(clean.cwd, clean.name, path.join(app.getPath('userData'), 'worktrees'));
      Object.assign(clean, wt, { cwd: wt.worktree });
    }
    const a = store.addAgent(clean);
    if (spec.firstMessages?.length) for (const m of spec.firstMessages) store.addMessage(a.id, m);
    return a;
  });
  handle('agent:update', (id, patch) => {
    const allowed = ['name', 'job', 'look', 'model', 'permission', 'pinned', 'last'];
    const p = Object.fromEntries(Object.entries(patch || {}).filter(([k]) => allowed.includes(k)));
    return store.updateAgent(id, p);
  });
  handle('agent:delete', async (id, { deleteBranch = false } = {}) => {
    const a = store.agent(id);
    if (!a) return true;
    engine.stop(`agent:${id}`);
    if (a.worktree) await git.removeWorktree(a, { deleteBranch });
    store.removeAgent(id);
    return true;
  });
  handle('agents', () => store.state.agents);
  handle('approvals', () => engine.pending());
  handle('agent:messages', (id) => store.messages(id));
  handle('agent:send', (id, text) => engine.sendToAgent(id, String(text)));
  handle('run:stop', (key) => engine.stop(key));
  handle('approval:answer', (id, decision) => engine.answer(id, decision));

  // chats from your tools
  handle('chats:list', (operator) => allChats(operator).map(strip));
  handle('chat:transcript', (operator, id) => history.transcript(findChat(operator, id)));
  handle('chat:send', (operator, id, text) => {
    if (operator === 'mavis') throw new Error('Mavis chats can be read here, not continued. Hand it to an agent to keep going.');
    return engine.sendToChat(findChat(operator, id), String(text));
  });
  handle('chat:decisions', async (operator, id) => {
    const text = history.asText(history.transcript(findChat(operator, id)));
    if (!text.trim()) return [];
    const answer = await engine.ask(`Here is a conversation between a user and an AI assistant.\n\n<conversation>\n${text}\n</conversation>\n\nList the decisions the user made or agreed to that should guide future work: rules, choices, constraints. One per line, each starting with "- ", each one short sentence in plain words. If there are none, reply with exactly: none`);
    if (/^none\.?$/i.test(answer.trim())) return [];
    return answer.split('\n').map((l) => l.replace(/^\s*[-*•]\s*/, '').trim()).filter((l) => l && l.length < 300).slice(0, 12);
  });
  handle('chat:summary', async (operator, id) => {
    const text = history.asText(history.transcript(findChat(operator, id)));
    if (!text.trim()) return '';
    return engine.ask(`Here is a conversation between a user and an AI assistant.\n\n<conversation>\n${text}\n</conversation>\n\nWrite a short hand-off note for someone continuing this work: what the goal is, what was done or decided, and what is left. At most 8 short lines, plain words, no headings.`);
  });

  // Mavis: bring names and conversations, nothing else
  handle('mavis:scan', async () => {
    const m = await history.readMavis();
    mavisChats.list = m;
    return { found: m.found, bots: m.bots.length, chats: m.chats.length, alreadyImported: store.state.imported.length };
  });
  handle('mavis:import', async (look) => {
    const m = mavisChats.list || (await history.readMavis());
    if (!m.found) throw new Error('Mavis data was not found on this Mac.');
    const have = new Set(store.state.imported.map((c) => c.id));
    const added = m.chats.filter((c) => !have.has(c.id));
    store.state.imported.push(...added);
    const agents = [];
    for (const b of m.bots) {
      if (store.state.agents.some((a) => a.origin?.type === 'mavis-bot' && a.origin.ref === b.id)) continue;
      agents.push(store.addAgent({ name: b.name, job: '', look: look?.[agents.length] || null, operator: 'claude-code', model: null, permission: 'ask', cwd: os.homedir(), pinned: true, origin: { type: 'mavis-bot', ref: b.id, title: 'Brought from Mavis' } }));
    }
    store.save();
    return { chats: added.length, agents: agents.length };
  });

  // memory
  handle('memory:add', (text, workspace, source) => store.addDecision(String(text).trim(), { workspace: workspace || null, source: source || null }));
  handle('memory:remove', (id) => { store.removeDecision(id); return true; });

  // workspaces and folders
  handle('folder:pick', async (title) => {
    const r = await dialog.showOpenDialog(win, { title: title || 'Choose a folder', properties: ['openDirectory', 'createDirectory'] });
    return r.canceled ? null : r.filePaths[0];
  });
  handle('folder:info', async (dir) => ({ exists: !!dir && fs.existsSync(dir), repo: await git.repoInfo(dir) }));
  handle('workspace:add', (dir) => store.addWorkspace(dir));
  handle('workspace:remove', (id) => { store.removeWorkspace(id); return true; });
  handle('open:folder', (dir) => shell.openPath(dir));

  // review
  handle('git:changes', (agentId) => git.changes(store.agent(agentId)));
  handle('git:diff', (agentId, file) => git.fileDiff(store.agent(agentId), file));
  handle('git:merge', async (agentId) => { const r = await git.merge(store.agent(agentId)); send({ type: 'git' }); return r; });
  handle('git:discard', async (agentId) => { await git.discard(store.agent(agentId)); send({ type: 'git' }); return true; });
  handle('git:overlaps', () => git.overlaps(store.state.agents));
}

function createWindow() {
  win = new BrowserWindow({
    width: 1440, height: 900, minWidth: 980, minHeight: 620,
    backgroundColor: '#080807', titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 16, y: 18 },
    show: false,
    webPreferences: { preload: path.join(here, '..', 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  win.once('ready-to-show', () => win.show());
  win.loadFile(path.join(here, '..', 'renderer', 'index.html'));
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('file:')) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); } });
}

app.setName('Agent Lab');
// Test mode: a throwaway data folder, so tests never touch your real agents.
if (process.env.AGENT_LAB_DATA) app.setPath('userData', process.env.AGENT_LAB_DATA);
app.whenReady().then(() => {
  store = new Store(app.getPath('userData'));
  engine = new Engine(store, send);
  registerIpc();
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { role: 'appMenu' }, { role: 'editMenu' },
    { label: 'View', submenu: [
      { label: 'Search Everything', accelerator: 'CmdOrCtrl+K', click: () => send({ type: 'command', command: 'search' }) },
      { label: 'New Agent', accelerator: 'CmdOrCtrl+N', click: () => send({ type: 'command', command: 'new-agent' }) },
      { label: 'Show or Hide Right Now', accelerator: 'Alt+CmdOrCtrl+0', click: () => send({ type: 'command', command: 'toggle-now' }) },
      { type: 'separator' }, { role: 'reload' }, { role: 'toggleDevTools' }, { type: 'separator' }, { role: 'togglefullscreen' },
    ] },
    { role: 'windowMenu' },
  ]));
  createWindow();
  if (process.env.AGENT_LAB_E2E) import(path.join(here, '..', '..', 'scripts', 'e2e-driver.mjs')).then((m) => m.drive(win, app)).catch((e) => { console.error('E2E failed:', e); app.exit(1); });
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('before-quit', () => { engine?.stopAll(); store?.flush(); });
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });

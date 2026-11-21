// Your existing chats, read where each tool keeps them. Nothing is copied or uploaded.
//   Claude Code: ~/.claude/projects/<folder>/<session>.jsonl
//   Codex:       ~/.codex/sessions/**/rollout-*.jsonl
//   Mavis:       ~/Library/Application Support/MAVIS Shell Live/mavis.sqlite (names and conversations only;
//                Mavis's own prompts, rules and injected context are left behind on purpose).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';

const HOME = os.homedir();
const CLAUDE_DIR = path.join(HOME, '.claude', 'projects');
const CODEX_DIR = path.join(HOME, '.codex', 'sessions');
const MAVIS_DIR = path.join(HOME, 'Library', 'Application Support', 'MAVIS Shell Live');

const clip = (s, n = 80) => { const t = String(s ?? '').replace(/\s+/g, ' ').trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };

// Text a person typed, not a tool's wrapper (commands, reminders, pasted instructions, environment blocks).
export function isHuman(text) {
  const t = String(text ?? '').trim();
  return !!t && !t.startsWith('<') && !t.startsWith('[Request interrupted') && !t.startsWith('Caveat:') && !t.startsWith('# AGENTS.md') && !t.startsWith('This session is being continued');
}

function readSlice(file, start, length) {
  const fd = fs.openSync(file, 'r');
  try { const buf = Buffer.alloc(length); const n = fs.readSync(fd, buf, 0, length, start); return buf.subarray(0, n).toString('utf8'); } finally { fs.closeSync(fd); }
}
function lines(text, dropFirst, dropLast) {
  const parts = text.split('\n');
  if (dropFirst) parts.shift();
  if (dropLast) parts.pop();
  const out = [];
  for (const p of parts) { if (!p.trim()) continue; try { out.push(JSON.parse(p)); } catch {} }
  return out;
}
function head(file, size, bytes = 96 * 1024) { return lines(readSlice(file, 0, Math.min(bytes, size)), false, size > bytes); }
function tail(file, size, bytes = 128 * 1024) { const start = Math.max(0, size - bytes); return lines(readSlice(file, start, size - start), start > 0, false); }
function all(file) { try { return lines(fs.readFileSync(file, 'utf8'), false, false); } catch { return []; } }

const cache = new Map(); // file -> { size, mtime, chat }
function cached(file, read) {
  let st; try { st = fs.statSync(file); } catch { return null; }
  const hit = cache.get(file);
  if (hit && hit.size === st.size && hit.mtime === st.mtimeMs) return hit.chat;
  const chat = read(st);
  cache.set(file, { size: st.size, mtime: st.mtimeMs, chat });
  return chat;
}

// Folders that are tools' own scratch space, not your projects.
const isScratch = (cwd) => !cwd || cwd.startsWith('/private/tmp') || cwd.startsWith('/tmp') || cwd.startsWith('/var/folders/') || cwd.startsWith('/private/var/folders/') || cwd.includes('/Application Support/Agent Lab/worktrees/') || cwd.includes('/Application Support/Claude/scratch') || cwd.includes('/.claude-spares/');

// ---- Claude Code ------------------------------------------------------------------------------
function claudeUserText(line) {
  if (line.type !== 'user' || line.isMeta || line.isSidechain) return null;
  const c = line.message?.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c) && !c.some((b) => b.type === 'tool_result')) return c.filter((b) => b.type === 'text').map((b) => b.text).join('\n') || null;
  return null;
}

export function claudeChats({ all: everything = false } = {}) {
  const out = [];
  let dirs = [];
  try { dirs = fs.readdirSync(CLAUDE_DIR); } catch { return out; }
  for (const d of dirs) {
    let files = [];
    try { files = fs.readdirSync(path.join(CLAUDE_DIR, d)).filter((f) => f.endsWith('.jsonl')); } catch { continue; }
    for (const f of files) {
      const file = path.join(CLAUDE_DIR, d, f);
      const chat = cached(file, (st) => {
        let cwd = '', first = '', title = '';
        for (const l of head(file, st.size)) {
          if (!cwd && l.cwd) cwd = l.cwd;
          const t = claudeUserText(l);
          if (!first && t && isHuman(t)) first = t;
        }
        for (const l of tail(file, st.size)) if (l.type === 'custom-title' && l.customTitle) title = l.customTitle;
        if (!first && !title) return null;
        return { operator: 'claude-code', id: f.replace(/\.jsonl$/, ''), file, cwd, title: clip(title || first, 80), updated: st.mtimeMs, size: st.size };
      });
      if (chat && (everything || !isScratch(chat.cwd))) out.push(chat);
    }
  }
  return out.sort((a, b) => b.updated - a.updated);
}

function claudeTranscript(file) {
  const items = [];
  for (const l of all(file)) {
    if (l.isSidechain) continue;
    const t = claudeUserText(l);
    if (t && isHuman(t)) { items.push({ role: 'user', text: t }); continue; }
    if (l.type === 'assistant' && Array.isArray(l.message?.content)) {
      for (const b of l.message.content) {
        if (b.type === 'text' && b.text?.trim()) items.push({ role: 'assistant', text: b.text });
        else if (b.type === 'tool_use') items.push({ role: 'tool', verb: b.name === 'Bash' ? 'Run' : b.name, text: clip(b.input?.command || b.input?.file_path || b.input?.pattern || b.input?.url || b.input?.description || '', 120) });
      }
    }
  }
  return items;
}

// ---- Codex ------------------------------------------------------------------------------------
function walk(dir, out = []) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.startsWith('rollout-') && e.name.endsWith('.jsonl')) out.push(p);
  }
  return out;
}
function codexUserText(l) {
  if (l.type !== 'response_item' || l.payload?.type !== 'message' || l.payload?.role !== 'user') return null;
  const t = (l.payload.content || []).map((c) => c.text).filter(Boolean).join('\n');
  return t || null;
}

export function codexChats({ all: everything = false } = {}) {
  const out = [];
  for (const file of walk(CODEX_DIR)) {
    const chat = cached(file, (st) => {
      let id = '', cwd = '', first = '', model = null;
      for (const l of head(file, st.size, 256 * 1024)) {
        if (l.type === 'session_meta') { id = l.payload?.id || l.payload?.session_id || id; cwd = l.payload?.cwd || cwd; }
        if (!model && l.type === 'turn_context' && l.payload?.model) model = l.payload.model;
        const t = codexUserText(l);
        if (!first && t && isHuman(t)) first = t;
      }
      if (!id || !first) return null;
      // A model only counts once Codex actually answered on it.
      const answered = tail(file, st.size).some((l) => l.type === 'response_item' && l.payload?.type === 'message' && l.payload?.role === 'assistant');
      return { operator: 'codex', id, file, cwd, title: clip(first, 80), updated: st.mtimeMs, size: st.size, model: answered ? model : null };
    });
    if (chat && (everything || !isScratch(chat.cwd))) out.push(chat);
  }
  return out.sort((a, b) => b.updated - a.updated);
}

// Models Codex has answered on in your chats, newest first.
export function codexModels() {
  const seen = [];
  for (const c of codexChats({ all: true })) if (c.model && !seen.includes(c.model)) seen.push(c.model);
  return seen;
}

function codexTranscript(file) {
  const items = [];
  for (const l of all(file)) {
    if (l.type !== 'response_item') continue;
    const p = l.payload || {};
    if (p.type === 'message') {
      const t = (p.content || []).map((c) => c.text).filter(Boolean).join('\n');
      if (p.role === 'user' && isHuman(t)) items.push({ role: 'user', text: t });
      else if (p.role === 'assistant' && t.trim()) items.push({ role: 'assistant', text: t });
    } else if (p.type === 'function_call' || p.type === 'custom_tool_call' || p.type === 'local_shell_call') {
      let a = {}; try { a = JSON.parse(p.arguments || p.input || '{}'); } catch {}
      const cmd = Array.isArray(a.command) ? a.command.join(' ') : a.cmd || a.command || p.name || 'a tool';
      items.push({ role: 'tool', verb: 'Run', text: clip(cmd, 120) });
    }
  }
  return items;
}

// ---- Mavis (names and conversations only) ------------------------------------------------------
// Strips the context Mavis injected into messages (<pointing trust="untrusted_data">…</pointing> and the like).
export function cleanMavis(text) {
  return String(text ?? '')
    .replace(/<([a-zA-Z][\w-]*)\b[^>]*>[\s\S]*?<\/\1>/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function sqlite(db, sql) {
  return new Promise((resolve, reject) => {
    execFile('/usr/bin/sqlite3', ['-json', db, sql], { maxBuffer: 64 * 1024 * 1024 }, (err, out) => {
      if (err) return reject(err);
      try { resolve(out.trim() ? JSON.parse(out) : []); } catch (e) { reject(e); }
    });
  });
}

// Reads a copy, so Mavis can keep running while we look.
export async function readMavis() {
  const src = path.join(MAVIS_DIR, 'mavis.sqlite');
  if (!fs.existsSync(src)) return { found: false, bots: [], chats: [] };
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-mavis-'));
  const db = path.join(tmp, 'mavis.sqlite');
  try {
    for (const ext of ['', '-wal', '-shm']) if (fs.existsSync(src + ext)) fs.copyFileSync(src + ext, db + ext);
    const bots = await sqlite(db, "select id, name from bots where deleted_at is null and hidden = 0");
    const tasks = await sqlite(db, "select id, title, bot_id, updated_at from tasks where deleted_at is null and kind = 'direct'");
    const msgs = await sqlite(db, "select task_id, role, content, created_at from messages where task_id is not null and status != 'failed' order by created_at");
    let places = {};
    try { places = JSON.parse(fs.readFileSync(path.join(MAVIS_DIR, 'projects.json'), 'utf8')); } catch {}
    const byTask = new Map();
    for (const m of msgs) {
      const text = cleanMavis(m.content);
      if (!text || (m.role !== 'user' && m.role !== 'assistant')) continue;
      if (!byTask.has(m.task_id)) byTask.set(m.task_id, []);
      byTask.get(m.task_id).push({ role: m.role, text });
    }
    const botName = (id) => { const b = bots.find((x) => x.id === id); return b ? (b.name === 'MAVIS' ? 'Mavis' : b.name) : 'Mavis'; };
    const chats = tasks.filter((t) => byTask.get(t.id)?.length).map((t) => ({
      operator: 'mavis', id: `mavis:${t.id}`, title: clip(t.title, 80), botId: t.bot_id, bot: botName(t.bot_id),
      cwd: places[t.id] || '', updated: Date.parse(t.updated_at) || Date.now(), lines: byTask.get(t.id),
    }));
    return { found: true, bots: bots.map((b) => ({ id: b.id, name: b.name === 'MAVIS' ? 'Mavis' : b.name })), chats };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// ---- shared -------------------------------------------------------------------------------------
export function transcript(chat) {
  if (chat.operator === 'claude-code') return claudeTranscript(chat.file);
  if (chat.operator === 'codex') return codexTranscript(chat.file);
  return chat.lines || [];
}

// A compact, faithful text of a chat for a summary or a hand-off (most recent part when it is long).
export function asText(items, limit = 60000) {
  const parts = items.filter((i) => i.role !== 'tool').map((i) => `${i.role === 'user' ? 'User' : 'Assistant'}: ${i.text}`);
  let text = parts.join('\n\n');
  if (text.length > limit) text = `[Earlier messages left out]\n\n${text.slice(text.length - limit)}`;
  return text;
}

// The command palette's searches (⌘K): words across every conversation, and the files of an agent's folder.
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';

// Lines worth finding: what you wrote and what the agents answered (not tool steps, thinking or errors).
const SEARCHED = new Set(['user', 'assistant']);
// Folders never worth listing (big, generated, or not yours).
const SKIP = new Set(['.git', 'node_modules', '.build', 'build', 'dist', 'DerivedData', '.next', '.cache', 'Pods', '.venv', 'venv', '__pycache__', 'Library', '.Trash']);
const FILE_LIMIT = 20000;

// Every conversation: each agent's DM, then each workspace channel.
function conversations(store) {
  const list = store.state.agents.map((a) => ({ conv: a.id, agentId: a.id, title: a.name }));
  for (const w of store.state.workspaces) {
    for (const c of (w.categories || []).flatMap((x) => x.channels || [])) {
      list.push({ conv: `c_${w.id}_${c.id}`, workspaceId: w.id, channelId: c.id, title: `#${c.name}`, place: w.name });
    }
  }
  return list;
}

// A short piece of the line around the match, on one line, and where the match sits in it. The match starts with a
// non-space letter, so folding the whitespace before it gives its place in the folded line.
export function snippet(text, at, len) {
  const flat = text.replace(/\s+/g, ' ');
  const before = text.slice(0, at).replace(/\s+/g, ' ').length;
  const from = Math.max(0, before - 40);
  const to = Math.min(flat.length, before + len + 80);
  let piece = flat.slice(from, to);
  let start = before - from;
  const lead = piece.length - piece.trimStart().length;
  piece = piece.trimStart(); start -= lead;
  const dots = from > 0 ? '…' : '';
  return { text: dots + piece.trimEnd() + (to < flat.length ? '…' : ''), start: dots.length + start, length: len };
}

export default function calls(ctx) {
  const { store } = ctx;
  return {
    // Messages whose words contain every word of `query` (any case), newest first, at most `limit`.
    'palette:messages'(query, limit = 40) {
      const words = String(query || '').toLowerCase().split(/\s+/).filter(Boolean);
      if (!words.length || words.join('').length < 2) return [];
      const max = Math.max(1, Math.min(200, Number(limit) || 40));
      const hits = [];
      for (const c of conversations(store)) {
        for (const m of store.messages(c.conv)) {
          if (!SEARCHED.has(m.role) || typeof m.text !== 'string' || !m.text) continue;
          const low = m.text.toLowerCase();
          if (!words.every((w) => low.includes(w))) continue;
          const by = m.role === 'user' ? 'You' : (store.agent(m.by || c.agentId)?.name || 'Agent');
          hits.push({ conv: c.conv, agentId: c.agentId || null, workspaceId: c.workspaceId || null, channelId: c.channelId || null,
            title: c.title, place: c.place || null, id: m.id, role: m.role, by, at: m.at || 0,
            snippet: snippet(m.text, low.indexOf(words[0]), words[0].length) });
        }
      }
      hits.sort((a, b) => b.at - a.at);
      return hits.slice(0, max);
    },

    // The files of a folder, as paths relative to it: git's list when it's a repository (tracked and new, ignored left
    // out), else a walk that skips generated folders. At most 20 000.
    async 'palette:files'(folder) {
      const root = String(folder || '');
      if (!root || !fs.existsSync(root)) return { files: [], more: false };
      const viaGit = await new Promise((resolve) => {
        execFile('git', ['-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], { maxBuffer: 64 * 1024 * 1024, timeout: 8000 }, (err, stdout) => {
          resolve(err ? null : [...new Set(stdout.split('\0').filter(Boolean))]);
        });
      });
      if (viaGit) return { files: viaGit.slice(0, FILE_LIMIT), more: viaGit.length > FILE_LIMIT };
      // A folder like your home can be huge: the walk stops after a second and a half with what it has.
      const files = [], until = Date.now() + 1500;
      const walk = (dir, rel, depth) => {
        if (depth > 12 || Date.now() > until) return;
        let entries;
        try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
        for (const e of entries) {
          if (files.length >= FILE_LIMIT) return;
          if (SKIP.has(e.name) || e.name === '.DS_Store') continue;
          const r = rel ? `${rel}/${e.name}` : e.name;
          if (e.isDirectory()) { if (!e.name.startsWith('.')) walk(path.join(dir, e.name), r, depth + 1); }  // hidden folders (caches, settings) left out
          else if (e.isFile()) files.push(r);
        }
      };
      walk(root, '', 0);
      return { files, more: files.length >= FILE_LIMIT || Date.now() > until };
    },
  };
}

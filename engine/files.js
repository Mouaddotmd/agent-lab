// The Files tab: every file of a folder for ⌘P (open a file by name). In a git repository it's git's own list
// (tracked and new files, .gitignore respected), which is fast on big folders; elsewhere a walk that skips build
// output and dependencies. Paths are relative to the folder.
import fs from 'node:fs';
import path from 'node:path';

const LIMIT = 100_000;
const SKIP = new Set(['.git', 'node_modules', '.build', 'build', 'DerivedData', 'dist', '.next', 'Pods', '.venv', 'venv',
  '__pycache__', 'target', '.swiftpm', '.DS_Store', 'Library', 'Applications', 'Pictures', 'Music', 'Movies', '.Trash']);

export default function calls(ctx) {
  const run = ctx.git.git;

  async function list(folder) {
    if (!folder || !fs.existsSync(folder)) throw new Error('That folder is missing.');
    const inRepo = await run(folder, ['rev-parse', '--is-inside-work-tree'], { allowFail: true });
    if (inRepo.ok && inRepo.out.trim() === 'true') {
      const [r, deleted] = await Promise.all([
        run(folder, ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { allowFail: true }),
        run(folder, ['ls-files', '--deleted', '-z'], { allowFail: true }),
      ]);
      if (r.ok) {
        const seen = new Set(deleted.out.split('\0'));             // still in git's index, gone from the folder
        const files = [];
        for (const p of r.out.split('\0')) {
          if (!p || seen.has(p)) continue;                        // a conflicted file is listed once per stage
          seen.add(p);
          files.push(p);
          if (files.length >= LIMIT) break;
        }
        return { files, git: true, cut: files.length >= LIMIT };
      }
    }
    // Breadth first (near files first), a folder at a time with awaits between, so the engine never stalls on a big
    // folder such as your home; stops at the limit or after a few seconds.
    const files = [];
    const queue = [['', folder]];
    let next = 0;
    const until = Date.now() + 4000;
    while (next < queue.length && files.length < LIMIT && Date.now() < until) {
      const [rel, dir] = queue[next++];
      let entries;
      try { entries = await fs.promises.readdir(dir, { withFileTypes: true }); } catch { continue; }
      for (const e of entries) {
        if (SKIP.has(e.name)) continue;
        const r = rel ? `${rel}/${e.name}` : e.name;
        if (e.isDirectory()) { if (!e.name.startsWith('.') && !e.name.endsWith('.app')) queue.push([r, path.join(dir, e.name)]); }
        else if (e.isFile() || e.isSymbolicLink()) files.push(r);
      }
    }
    return { files, git: false, cut: next < queue.length || files.length >= LIMIT };
  }

  return {
    'files:list': (folder) => list(String(folder || '')),
  };
}

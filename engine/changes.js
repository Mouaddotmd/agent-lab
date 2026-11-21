// The Changes tab: what changed in an agent's folder, three ways:
//   uncommitted  the working tree against HEAD, new files included
//   base         against where the branch started: the merge-base with the base branch (an agent with its own branch:
//                the branch it was made from; otherwise the repository's default branch)
//   chat         the files this agent's chat changed (its steps' recorded edits); where git still has an uncommitted
//                change for one, git's diff is shown, with line numbers
// Also: one file's diff, discard one file, commit everything, and a commit message written by Claude.
// Every change made here is followed by { event: { type: 'git' } } so the panel, the tree and other windows refresh.
import fs from 'node:fs';
import path from 'node:path';

const MAX_LINES = 20000;

export default function calls(ctx) {
  const { store, engine, git, out } = ctx;
  const run = git.git;

  function agentOf(id) {
    const a = store.agent(id);
    if (!a) throw new Error('That agent no longer exists.');
    return a;
  }
  const folderOf = (a) => (a.worktree && fs.existsSync(a.worktree) ? a.worktree : (a.cwd || process.env.HOME));

  // The repository the folder is in, or null. `head` is false before the first commit.
  async function repo(folder) {
    if (!folder || !fs.existsSync(folder)) return null;
    const top = await run(folder, ['rev-parse', '--show-toplevel'], { allowFail: true });
    if (!top.ok) return null;
    const root = top.out.trim();
    const [br, head] = await Promise.all([
      run(root, ['symbolic-ref', '--quiet', '--short', 'HEAD'], { allowFail: true }),
      run(root, ['rev-parse', '--verify', '--quiet', 'HEAD'], { allowFail: true }),
    ]);
    // Before the first commit everything is compared with the empty tree (written once so git can read it).
    const ref = head.ok ? 'HEAD' : (await run(root, ['hash-object', '-w', '-t', 'tree', '/dev/null'])).out.trim();
    return { root, folder, branch: br.ok ? br.out.trim() : null, head: head.ok, ref };
  }

  // What "against base" compares with. Own branch: where it came from. Otherwise the default branch: origin's HEAD,
  // or a local main/master/trunk/develop. On the default branch itself, its remote copy (what isn't pushed yet).
  async function baseOf(a, r) {
    const has = async (ref) => (await run(r.root, ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`], { allowFail: true })).ok;
    if (a.worktree && a.baseBranch && await has(a.baseBranch)) return a.baseBranch;
    const sym = await run(r.root, ['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD'], { allowFail: true });
    const remote = sym.ok ? sym.out.trim() : null;                    // origin/main
    const local = remote ? remote.replace(/^origin\//, '') : null;
    for (const n of [...new Set([local, 'main', 'master', 'trunk', 'develop'].filter(Boolean))]) {
      if (n === r.branch) {
        if (await has(`origin/${n}`)) return `origin/${n}`;
        continue;
      }
      if (await has(n)) return n;
    }
    return null;
  }

  // -z name-status and numstat, joined by path: [{ path, from?, status, add, del, binary }].
  async function diffList(root, ref, spec) {
    const [ns, num] = await Promise.all([
      run(root, ['diff', '--name-status', '-z', '-M', ref, '--', ...spec]),
      run(root, ['diff', '--numstat', '-z', '-M', ref, '--', ...spec]),
    ]);
    const files = new Map();
    const t = ns.out.split('\0');
    for (let i = 0; i < t.length - 1;) {
      const code = t[i++];
      if (!code) continue;
      const k = code[0];
      if (k === 'R' || k === 'C') { const from = t[i++], to = t[i++]; files.set(to, { path: to, ...(k === 'R' ? { from } : {}), status: k === 'R' ? 'renamed' : 'added', add: 0, del: 0, binary: false }); }
      else { const p = t[i++]; files.set(p, { path: p, status: k === 'A' ? 'added' : k === 'D' ? 'deleted' : 'modified', add: 0, del: 0, binary: false }); }
    }
    const n = num.out.split('\0');
    for (let i = 0; i < n.length - 1;) {
      const head = n[i++];
      if (!head) continue;
      const [add, del, p] = head.split('\t');
      let key = p;
      if (p === '') { i++; key = n[i++]; }                         // a rename: "add\tdel\t" then from, then to
      const f = files.get(key);
      if (f) { f.binary = add === '-'; f.add = add === '-' ? 0 : +add; f.del = del === '-' ? 0 : +del; }
    }
    return [...files.values()];
  }

  // New files git doesn't know yet, with their line counts.
  async function untracked(root, spec) {
    const o = await run(root, ['ls-files', '--others', '--exclude-standard', '-z', '--', ...spec]);
    return o.out.split('\0').filter(Boolean).map((p) => ({ path: p, status: 'added', untracked: true, ...countLines(path.join(root, p)) }));
  }
  function countLines(file) {
    try {
      const st = fs.statSync(file);
      if (!st.isFile()) return { add: 0, del: 0, binary: false };
      if (st.size > 2_000_000) return { add: 0, del: 0, binary: false, big: true };
      const b = fs.readFileSync(file);
      if (b.subarray(0, 8000).includes(0)) return { add: 0, del: 0, binary: true };
      const s = b.toString('utf8');
      return { add: s ? s.split('\n').length - (s.endsWith('\n') ? 1 : 0) : 0, del: 0, binary: false };
    } catch { return { add: 0, del: 0, binary: false }; }
  }
  // The pathspec for the agent's folder inside its repository (the whole repository when they're the same).
  const specOf = (r) => {
    let rel = '';
    try { rel = path.relative(fs.realpathSync(r.root), fs.realpathSync(r.folder)); } catch {}
    return rel && !rel.startsWith('..') ? [rel] : ['.'];
  };

  // The files the chat's steps changed, in the order it first touched them, with its recorded edits.
  function chatFiles(a) {
    const byPath = new Map();
    for (const m of store.messages(a.id)) {
      if (m.failed || !Array.isArray(m.diff)) continue;
      for (const d of m.diff) {
        if (!d?.path) continue;
        const abs = path.resolve(folderOf(a), String(d.path));
        const f = byPath.get(abs);
        if (!f) byPath.set(abs, { abs, change: d.change, lines: [...(d.lines || [])] });
        else {
          f.lines.push({ k: '~', t: '' }, ...(d.lines || []));
          if (d.change === 'deleted') f.change = 'deleted';
          else if (f.change === 'deleted') f.change = 'updated';
        }
      }
    }
    return [...byPath.values()];
  }

  async function list(agentId, mode = 'uncommitted') {
    const a = agentOf(agentId);
    const folder = folderOf(a);
    const r = await repo(folder);
    const head = { folder, ownBranch: !!a.worktree, branch: r?.branch || null, repo: !!r, root: r?.root || null, mode };
    if (mode === 'chat') {
      const recorded = chatFiles(a);
      const live = new Map();
      const inRepo = (abs) => r && !path.relative(r.root, abs).startsWith('..');
      if (r && recorded.length) {
        const inside = recorded.filter((f) => inRepo(f.abs)).map((f) => path.relative(r.root, f.abs));
        if (inside.length) {
          const [tracked, fresh] = await Promise.all([
            diffList(r.root, r.ref, inside).catch(() => []),
            untracked(r.root, inside).catch(() => []),
          ]);
          for (const f of [...tracked, ...fresh]) live.set(path.join(r.root, f.path), f);
        }
      }
      const files = recorded.map((f) => {
        const g = live.get(f.abs);
        const rel = inRepo(f.abs) ? path.relative(r.root, f.abs) : f.abs;
        if (g) return { ...g, path: rel, abs: f.abs, source: 'git' };
        const add = f.lines.filter((l) => l.k === '+').length, del = f.lines.filter((l) => l.k === '-').length;
        // No uncommitted change left (committed since, or put back), or not in a repository: what the chat did.
        return { path: rel, abs: f.abs, status: f.change === 'created' ? 'added' : f.change === 'deleted' ? 'deleted' : 'modified', add, del, binary: false, source: 'chat', settled: !!inRepo(f.abs) };
      });
      return { ...head, files };
    }
    if (!r) return { ...head, files: [] };
    const spec = specOf(r);
    let ref = r.ref, base = null;
    if (mode === 'base') {
      base = await baseOf(a, r);
      if (!base) return { ...head, base: null, files: [], note: 'There is no base branch to compare with.' };
      const mb = await run(r.root, ['merge-base', base, 'HEAD'], { allowFail: true });
      if (!mb.ok) return { ...head, base, files: [], note: `This branch has nothing in common with ${base}.` };
      ref = mb.out.trim();
    }
    const [tracked, fresh] = await Promise.all([diffList(r.root, ref, spec), untracked(r.root, spec)]);
    const files = [...tracked, ...fresh].map((f) => ({ ...f, abs: path.join(r.root, f.path), source: 'git', ...(mode === 'base' ? { ref } : {}) }))
      .sort((x, y) => x.path.localeCompare(y.path));
    return { ...head, base, files };
  }

  // A unified diff as rows: { k: '+'|'-'|' '|'@', t, o, n } (o/n: old and new line numbers; '@' a hunk's header).
  function parseUnified(text) {
    const rows = [];
    let o = 0, n = 0, started = false, binary = false, cut = false;
    for (const raw of text.split('\n')) {
      if (raw.startsWith('@@')) {
        const m = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@ ?(.*)$/.exec(raw);
        if (m) { o = +m[1]; n = +m[2]; started = true; rows.push({ k: '@', t: m[3] || '', o, n }); }
        continue;
      }
      if (!started) { if (/^Binary files /.test(raw)) binary = true; continue; }
      if (raw.startsWith('\\')) continue;
      if (raw.startsWith('+')) rows.push({ k: '+', t: raw.slice(1), n: n++ });
      else if (raw.startsWith('-')) rows.push({ k: '-', t: raw.slice(1), o: o++ });
      else if (raw.startsWith(' ')) rows.push({ k: ' ', t: raw.slice(1), o: o++, n: n++ });
      if (rows.length >= MAX_LINES) { cut = true; break; }
    }
    return { rows, binary, cut };
  }

  // One file's diff. `file` is the entry `changes:list` gave (its path, from, untracked, source, ref).
  async function diff(agentId, mode, file) {
    const a = agentOf(agentId);
    const f = typeof file === 'object' && file ? file : (await list(agentId, mode)).files.find((x) => x.path === file || x.abs === file);
    if (!f) return { rows: [], gone: true };
    if (f.source === 'chat') {
      const rec = chatFiles(a).find((x) => x.abs === f.abs);
      return { rows: (rec?.lines || []).map((l) => (l.k === '~' ? { k: '@', t: '' } : { k: l.k, t: l.t })), recorded: true };
    }
    const r = await repo(folderOf(a));
    if (!r) return { rows: [] };
    if (f.binary) return { rows: [], binary: true };
    if (f.big) return { rows: [], big: true };
    let d;
    if (f.untracked) d = await run(r.root, ['diff', '--no-index', '--no-color', '-U3', '--', '/dev/null', f.path], { allowFail: true });
    else {
      const ref = mode === 'base' && f.ref ? f.ref : (r.ref);
      d = await run(r.root, ['diff', '--no-color', '-U3', '-M', ref, '--', ...(f.from ? [f.from, f.path] : [f.path])], { allowFail: true });
    }
    return parseUnified(d.out);
  }

  // Puts one file back as it was at the last commit: a new file is deleted; a rename comes back under its old name.
  async function discard(agentId, file) {
    const a = agentOf(agentId);
    const r = await repo(folderOf(a));
    if (!r) throw new Error('This folder isn\'t a git repository, so there is nothing to put back.');
    const abs = path.isAbsolute(file) ? file : path.join(r.root, file);
    const f = (await list(agentId, 'uncommitted')).files.find((x) => x.abs === abs);
    if (!f) throw new Error('That file has no uncommitted changes.');
    const inHead = async (p) => r.head && (await run(r.root, ['cat-file', '-e', `HEAD:${p}`], { allowFail: true })).ok;
    if (f.untracked) fs.rmSync(abs, { force: true });
    else {
      for (const p of f.from ? [f.from, f.path] : [f.path]) {
        if (await inHead(p)) await run(r.root, ['restore', '--source=HEAD', '--staged', '--worktree', '--', p]);
        else {                                                         // added to git but never committed
          await run(r.root, ['rm', '-q', '--cached', '-f', '--ignore-unmatch', '--', p], { allowFail: true });
          fs.rmSync(path.join(r.root, p), { force: true });
        }
      }
    }
    out({ event: { type: 'git', agentId: a.id, folder: r.root } });
    return true;
  }

  async function commit(agentId, message) {
    const a = agentOf(agentId);
    const msg = String(message || '').trim();
    if (!msg) throw new Error('Write a message for the commit first.');
    const r = await repo(folderOf(a));
    if (!r) throw new Error('This folder isn\'t a git repository.');
    if (!r.branch) throw new Error('The repository isn\'t on a branch right now. Switch to a branch, then commit.');
    // Only the agent's folder: when it's part of a bigger repository, what's staged elsewhere stays out.
    const spec = specOf(r);
    await run(r.root, ['add', '-A', '--', ...spec]);
    if ((await run(r.root, ['diff', '--cached', '--quiet', '--', ...spec], { allowFail: true })).ok) throw new Error('There is nothing to commit.');
    const only = spec[0] === '.' ? [] : ['--', ...spec];
    let c = await run(r.root, ['commit', '-q', '-m', msg, ...only], { allowFail: true });
    // No name or email set for git on this Mac: commit as Agent Lab rather than fail.
    if (!c.ok && /tell me who you are|empty ident|user\.email|user\.name/i.test(c.err)) {
      c = await run(r.root, ['-c', 'user.name=Agent Lab', '-c', 'user.email=agent-lab@localhost', 'commit', '-q', '-m', msg, ...only], { allowFail: true });
    }
    if (!c.ok) {
      const words = (c.err || c.out).trim().split('\n').filter(Boolean).slice(-6).join('\n');
      const hooks = await hooksOf(r.root);
      out({ event: { type: 'git', agentId: a.id, folder: r.root } });
      throw new Error(hooks.length ? `A commit hook (${hooks.join(', ')}) stopped the commit. Your changes are staged.\n${words}` : `Git didn't commit.\n${words}`);
    }
    const sha = (await run(r.root, ['rev-parse', '--short', 'HEAD'])).out.trim();
    const n = (await run(r.root, ['show', '--name-only', '--format=', 'HEAD'])).out.split('\n').filter(Boolean).length;
    out({ event: { type: 'git', agentId: a.id, folder: r.root } });
    return { sha, files: n, branch: r.branch };
  }
  async function hooksOf(root) {
    const custom = await run(root, ['config', 'core.hooksPath'], { allowFail: true });
    const dir = custom.ok && custom.out.trim() ? path.resolve(root, custom.out.trim()) : path.resolve(root, (await run(root, ['rev-parse', '--git-path', 'hooks'])).out.trim());
    return ['pre-commit', 'prepare-commit-msg', 'commit-msg'].filter((h) => { try { return !!(fs.statSync(path.join(dir, h)).mode & 0o111); } catch { return false; } });
  }

  // One line for the commit, from the diff, by Claude (no tools).
  async function message(agentId) {
    const a = agentOf(agentId);
    const r = await repo(folderOf(a));
    if (!r) throw new Error('This folder isn\'t a git repository.');
    const spec = specOf(r);
    const ref = r.ref;
    const [stat, patch, fresh] = await Promise.all([
      run(r.root, ['diff', '--stat', ref, '--', ...spec]),
      run(r.root, ['diff', '--no-color', '-U1', ref, '--', ...spec]),
      run(r.root, ['ls-files', '--others', '--exclude-standard', '--', ...spec]),
    ]);
    const added = fresh.out.split('\n').filter(Boolean);
    if (!stat.out.trim() && !added.length) throw new Error('There is nothing to commit.');
    const text = [stat.out.trim(), added.length ? `New files:\n${added.slice(0, 60).join('\n')}` : '', patch.out.slice(0, 14000)].filter(Boolean).join('\n\n');
    const answer = await engine.ask(`Here are the uncommitted changes in a git repository.\n\n<changes>\n${text}\n</changes>\n\nWrite a one-line git commit message for them: imperative mood, plain words, at most 72 characters, no trailing period. Reply with only the message.`, r.root);
    return answer.split('\n').map((l) => l.trim()).find(Boolean)?.replace(/^["'`]+|["'`]+$/g, '').slice(0, 120) || '';
  }

  // "Create a git repository" from the not-a-repository state.
  async function init(agentId) {
    const a = agentOf(agentId);
    const folder = folderOf(a);
    if (!folder || !fs.existsSync(folder)) throw new Error('The agent\'s folder is missing.');
    await run(folder, ['init', '-q']);
    out({ event: { type: 'git', agentId: a.id, folder } });
    return true;
  }

  return {
    'changes:list': (agentId, mode) => list(agentId, mode),
    'changes:diff': (agentId, mode, file) => diff(agentId, mode, file),
    'changes:discard': (agentId, file) => discard(agentId, file),
    'changes:commit': (agentId, msg) => commit(agentId, msg),
    'changes:message': (agentId) => message(agentId),
    'changes:init': (agentId) => init(agentId),
  };
}

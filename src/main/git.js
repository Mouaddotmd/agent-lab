// Each agent can work on its own branch in its own folder (a git worktree), so agents never overwrite each
// other or you. Review shows its changes against the branch it started from; Merge brings them in.
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

function git(cwd, args, { allowFail = false } = {}) {
  return new Promise((resolve, reject) => {
    execFile('git', args, { cwd, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } }, (err, stdout, stderr) => {
      if (err && !allowFail) return reject(new Error(String(stderr || err.message).trim().split('\n').slice(-3).join(' ')));
      resolve({ ok: !err, out: String(stdout), err: String(stderr) });
    });
  });
}

export async function repoInfo(dir) {
  if (!dir || !fs.existsSync(dir)) return null;
  const top = await git(dir, ['rev-parse', '--show-toplevel'], { allowFail: true });
  if (!top.ok) return null;
  const root = top.out.trim();
  const br = await git(root, ['rev-parse', '--abbrev-ref', 'HEAD'], { allowFail: true });
  const head = await git(root, ['rev-parse', '--verify', 'HEAD'], { allowFail: true });
  return { root, branch: br.ok ? br.out.trim() : null, hasCommits: head.ok };
}

const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 32) || 'agent';

// Creates agent/<name> from the repo's current branch, checked out in its own folder.
export async function createWorktree(repoDir, agentName, worktreesDir) {
  const info = await repoInfo(repoDir);
  if (!info) throw new Error('That folder is not a git repository.');
  if (!info.hasCommits) throw new Error('That repository has no commits yet, so there is nothing to branch from.');
  if (!info.branch || info.branch === 'HEAD') throw new Error('The repository is not on a branch right now.');
  let branch = `agent/${slug(agentName)}`;
  for (let i = 2; (await git(info.root, ['rev-parse', '--verify', '--quiet', branch], { allowFail: true })).ok; i++) branch = `agent/${slug(agentName)}-${i}`;
  fs.mkdirSync(worktreesDir, { recursive: true });
  const dir = path.join(worktreesDir, `${slug(path.basename(info.root))}-${branch.split('/')[1]}`);
  await git(info.root, ['worktree', 'add', '-b', branch, dir, info.branch]);
  return { worktree: dir, branch, baseRepo: info.root, baseBranch: info.branch };
}

// Files changed on the agent's folder versus where it started, including new files and uncommitted work.
export async function changes(agent) {
  if (!agent.worktree || !fs.existsSync(agent.worktree)) return { files: [], missing: true };
  await git(agent.worktree, ['add', '-A', '--intent-to-add'], { allowFail: true });
  const mergeBase = (await git(agent.worktree, ['merge-base', agent.baseBranch, 'HEAD'])).out.trim();
  const stat = await git(agent.worktree, ['diff', '--numstat', mergeBase]);
  const files = stat.out.trim().split('\n').filter(Boolean).map((l) => {
    const [add, del, ...p] = l.split('\t');
    return { path: p.join('\t'), add: add === '-' ? 0 : +add, del: del === '-' ? 0 : +del, binary: add === '-' };
  });
  return { files, mergeBase };
}

export async function fileDiff(agent, file) {
  const { mergeBase } = await changes(agent);
  const d = await git(agent.worktree, ['diff', '--no-color', '-U3', mergeBase, '--', file]);
  return d.out.split('\n').filter((l) => !/^(diff --git|index |--- |\+\+\+ |new file mode|deleted file mode)/.test(l));
}

async function commitAll(agent) {
  await git(agent.worktree, ['add', '-A']);
  const st = await git(agent.worktree, ['status', '--porcelain']);
  if (st.out.trim()) await git(agent.worktree, ['-c', 'user.name=Agent Lab', '-c', 'user.email=agent-lab@localhost', 'commit', '-m', `${agent.name}: work from Agent Lab`]);
}

export async function merge(agent) {
  const { files } = await changes(agent);
  if (!files.length) throw new Error('There is nothing to merge yet.');
  const st = await git(agent.baseRepo, ['status', '--porcelain', '--untracked-files=no']);
  if (st.out.trim()) throw new Error(`${path.basename(agent.baseRepo)} has uncommitted changes. Commit or stash them first, then merge.`);
  const cur = (await git(agent.baseRepo, ['rev-parse', '--abbrev-ref', 'HEAD'])).out.trim();
  if (cur !== agent.baseBranch) throw new Error(`${path.basename(agent.baseRepo)} is on ${cur}, not ${agent.baseBranch}. Switch back, then merge.`);
  await commitAll(agent);
  const m = await git(agent.baseRepo, ['-c', 'user.name=Agent Lab', '-c', 'user.email=agent-lab@localhost', 'merge', '--no-ff', '-m', `Merge ${agent.branch} (${agent.name})`, agent.branch], { allowFail: true });
  if (!m.ok) {
    await git(agent.baseRepo, ['merge', '--abort'], { allowFail: true });
    throw new Error('These changes conflict with what is on the branch now. Nothing was merged. Ask the agent to update its branch.');
  }
  // The agent keeps going from the merged point.
  await git(agent.worktree, ['merge', '--ff-only', agent.baseBranch], { allowFail: true });
  return { merged: files.length };
}

export async function discard(agent) {
  const { mergeBase } = await changes(agent);
  await git(agent.worktree, ['reset', '--hard', mergeBase]);
  await git(agent.worktree, ['clean', '-fd']);
}

export async function removeWorktree(agent, { deleteBranch = false } = {}) {
  if (!agent.worktree) return;
  await git(agent.baseRepo, ['worktree', 'remove', '--force', agent.worktree], { allowFail: true });
  if (deleteBranch) await git(agent.baseRepo, ['branch', '-D', agent.branch], { allowFail: true });
}

// Files two agents in the same repository both changed: merge one first and the other updates cleanly.
export async function overlaps(agents) {
  const byRepo = new Map();
  for (const a of agents) if (a.worktree && fs.existsSync(a.worktree)) {
    try { const { files } = await changes(a); if (files.length) { if (!byRepo.has(a.baseRepo)) byRepo.set(a.baseRepo, []); byRepo.get(a.baseRepo).push({ agent: a.id, files: new Set(files.map((f) => f.path)) }); } } catch {}
  }
  const out = [];
  for (const list of byRepo.values()) for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
    const shared = [...list[i].files].filter((f) => list[j].files.has(f));
    if (shared.length) out.push({ id: `ov:${list[i].agent}:${list[j].agent}`, agents: [list[i].agent, list[j].agent], files: shared });
  }
  return out;
}

// End-to-end test: drives the real app (real Claude Code, real git) on a throwaway data folder and a
// throwaway repository, saving a screenshot at each step. Run with `npm run e2e`.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const OUT = process.env.AGENT_LAB_E2E_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-shots-'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log('[e2e]', ...a);

export async function drive(win, app) {
  fs.mkdirSync(OUT, { recursive: true });
  const js = (code) => win.webContents.executeJavaScript(code, true);
  const shot = async (name) => { const img = await win.webContents.capturePage(); fs.writeFileSync(path.join(OUT, `${name}.png`), img.toPNG()); log('shot', name); };
  const waitFor = async (cond, ms, label) => {
    const t = Date.now();
    while (Date.now() - t < ms) { try { if (await js(cond)) return; } catch {} await sleep(400); }
    await shot(`timeout-${label.replace(/\W+/g, '-')}`);
    throw new Error(`Timed out waiting for: ${label}`);
  };
  const click = (sel) => js(`(()=>{const e=document.querySelector(${JSON.stringify(sel)}); if(!e) throw new Error('missing ${sel.replace(/'/g, '')}'); e.click(); return true})()`);
  const check = (ok, what) => { if (!ok) throw new Error(`Check failed: ${what}`); log('ok', what); };

  win.webContents.on('console-message', (_e, level, message) => { if (String(message).startsWith('[go]') || level >= 2) log('console:', String(message).slice(0, 300)); });
  // Type into the composer and press Enter, the way a person does.
  const say = async (text) => {
    await sleep(400);
    await js(`(()=>{const i=document.querySelector('#cmpInput'); i.focus(); i.value=${JSON.stringify(text)}; i.dispatchEvent(new Event('input',{bubbles:true})); i.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true})); return true})()`);
  };
  win.setSize(1440, 900);
  await waitFor("!!document.querySelector('.side-body')", 20000, 'boot');
  await js('window.__trace = true');
  await sleep(800);
  await shot('01-empty');
  check(await js("document.body.innerText.includes('No agents yet')"), 'empty state shows');

  // A throwaway repository with one commit.
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-repo-'));
  const g = (...args) => execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=t@t', ...args], { cwd: repo });
  g('init', '-q', '-b', 'main'); fs.writeFileSync(path.join(repo, 'README.md'), '# test\n'); g('add', '.'); g('commit', '-qm', 'init');

  await js(`lab.call('workspace:add', ${JSON.stringify(repo)})`);
  const agent = await js(`lab.call('agent:create', {name:'Juno', job:'', operator:'claude-code', model:'claude-haiku-5-5', permission:'ask', cwd:${JSON.stringify(repo)}, ownBranch:true, look:null})`);
  check(agent.branch === 'agent/juno' && fs.existsSync(agent.worktree), 'agent has its own branch and folder');
  await js('window.__old = true; location.reload(); true');
  await waitFor("!window.__old && !!document.querySelector('.side-body')", 20000, 'reload');
  await js('window.__trace = true');
  await sleep(600);
  await shot('02-one-agent');

  // Talk to it: it must ask before writing, then write, then answer.
  await click('.srow[data-act=dm]');
  await say('Create a file named hello.txt in the current folder containing exactly this line: hi from Juno. Then reply with one short sentence.');
  await waitFor("!!document.querySelector('.approval [data-decision=allow]') || (!document.querySelector('.send.stop') && document.querySelectorAll('.msg:not(.mine) .bubble').length>0)", 180000, 'approval or reply');
  let approvals = 0;
  for (let n = 0; n < 8; n++) {
    if (!(await js("!!document.querySelector('.approval [data-decision=allow]')"))) break;
    approvals++;
    if (approvals === 1) await shot('03-approval');
    const apId = await js("document.querySelector('.approval [data-decision=allow]').dataset.id");
    log('approving:', await js("document.querySelector('.approval .card-title').textContent"));
    await click('.approval [data-decision=allow]');
    await waitFor(`!document.querySelector('[data-id="${apId}"]')`, 10000, 'card leaves');
    await waitFor("!!document.querySelector('.approval [data-decision=allow]') || (!document.querySelector('.send.stop') && document.querySelectorAll('.msg:not(.mine) .bubble').length>0)", 180000, 'next approval or reply');
  }
  if (approvals) check(true, `the agent asked before acting (${approvals} ${approvals === 1 ? 'request' : 'requests'})`);
  else log('note: your Claude Code settings allowed this without asking');
  await waitFor("!document.querySelector('.send.stop') && document.querySelectorAll('.msg:not(.mine) .bubble').length>0 && !document.querySelector('.approval')", 180000, 'reply');
  await sleep(800);
  await shot('04-reply');
  check(fs.existsSync(path.join(agent.worktree, 'hello.txt')), 'the agent wrote hello.txt in its own folder');
  check(!fs.existsSync(path.join(repo, 'hello.txt')), 'the main folder is untouched before merge');

  // Review and merge.
  await click('[data-act=review]');
  await waitFor("!!document.querySelector('.file-head')", 30000, 'review files');
  await sleep(1200);
  await shot('05-review');
  await click('[data-act=merge]');
  await waitFor("document.body.innerText.includes('No changes yet')", 30000, 'merged');
  check(fs.existsSync(path.join(repo, 'hello.txt')), 'merge brought hello.txt into main');
  await shot('06-merged');

  // Hand-off note and decision finder, on Juno's own small session.
  const juno = (await js("lab.call('agents')")).find((x) => x.id === agent.id);
  check(!!juno?.sessionId, 'the agent kept its Claude Code session');
  const note = await js(`lab.call('chat:summary', 'claude-code', ${JSON.stringify(juno.sessionId)})`).catch((e) => `ERR ${e.message}`);
  check(typeof note === 'string' && note.length > 10 && !note.startsWith('ERR'), `hand-off note written from a chat${String(note).startsWith('ERR') ? ` (${note})` : ''}`);
  const decisions = await js(`lab.call('chat:decisions', 'claude-code', ${JSON.stringify(juno.sessionId)})`).catch((e) => `ERR ${e.message}`);
  check(Array.isArray(decisions), `decision finder answered (${Array.isArray(decisions) ? decisions.length : decisions})`);

  // Stop: start a long task, stop it, and see it stop.
  await click(`.srow[data-act=dm][data-id="${agent.id}"]`);
  await waitFor("document.querySelector('.strip .title')?.textContent.includes('Juno')", 10000, 'Juno open');
  await say('Write a 2000 word essay about the history of version control. Do not use any tools.');
  await waitFor("!!document.querySelector('.send.stop')", 30000, 'run started').catch(async (e) => { log('diag', await js("JSON.stringify({input: document.querySelector('#cmpInput')?.value, msgs: document.querySelectorAll('.msg').length, title: document.querySelector('.strip .title')?.textContent})")); throw e; });
  await sleep(4000);
  await click('.send.stop');
  await waitFor("!document.querySelector('.send.stop') && document.body.innerText.includes('You stopped this run')", 30000, 'stopped');
  check(true, 'stop halts a running agent');

  // Codex runs as itself.
  const cxModel = (await js("lab.call('state')")).codexModels?.[0] || null;
  log('codex model learned from your chats:', cxModel);
  const cx = await js(`lab.call('agent:create', {name:'Rook', job:'', operator:'codex', model:${JSON.stringify(cxModel)}, permission:'plan', cwd:${JSON.stringify(repo)}, look:null})`);
  await js('window.__old = true; location.reload(); true');
  await waitFor("!window.__old && !!document.querySelector('.side-body')", 20000, 'reload 2');
  await click(`.srow[data-act=dm][data-id="${cx.id}"]`);
  await waitFor("document.querySelector('.strip .title')?.textContent.includes('Rook')", 10000, 'Rook open');
  await say('Reply with exactly the word: ok');
  await waitFor("!document.querySelector('.send.stop') && (document.querySelectorAll('.msg:not(.mine) .bubble').length>0 || document.querySelector('.step.err'))", 180000, 'codex reply');
  await sleep(600);
  await shot('06b-codex');
  const codexErr = await js("document.querySelector('.step.err')?.innerText || ''");
  check(!codexErr, `Codex agent replied${codexErr ? ` (error: ${codexErr})` : ''}`);

  // Your Claude Code chats, beside the open chat.
  await click('.rbtn[data-act=space][data-id=home]');
  await sleep(400);
  await click('.srow[data-act=op][data-id="claude-code"]');
  await waitFor("!!document.querySelector('.crow')", 60000, 'claude chats');
  await waitFor("!!document.querySelector('#paneDetail .who')", 60000, 'chat opened');
  await sleep(1200);
  await shot('07-claude-chats');
  const nChats = await js("document.querySelectorAll('.crow').length");
  check(nChats > 0, `Claude Code chats listed (${nChats})`);

  // Make a real chat an agent from the list.
  const before = (await js("lab.call('agents')")).length;
  const picked = await js("document.querySelector('.crow.on')?.dataset.id");
  await click('[data-act=promote]');
  await waitFor("!!document.querySelector('#pName')", 10000, 'promote form');
  await shot('07b-promote');
  await js("(()=>{document.querySelector('#pName').value='Echo'; return true})()");
  await click('[data-act=promo-save]');
  await waitFor("document.querySelector('.strip .title')?.textContent.includes('Echo')", 15000, 'promoted agent opens');
  const after = await js("lab.call('agents')");
  const echo = after.find((x) => x.name === 'Echo');
  check(after.length === before + 1 && echo?.sessionId === picked, 'chat became an agent that continues the same session');
  await shot('07c-promoted');
  await js(`lab.call('agent:delete', ${JSON.stringify(echo.id)})`);
  await js('window.__old = true; location.reload(); true');
  await waitFor("!window.__old && !!document.querySelector('.side-body')", 20000, 'reload 3');

  // Memory.
  await click('.srow[data-act=view][data-id=memory]');
  await js(`(()=>{document.querySelector('#memInput').value='Never merge to main without tests passing'; document.querySelector('#memForm').requestSubmit(); return true})()`);
  await waitFor("!!document.querySelector('.mem-row') && document.querySelector('.mem-row').innerText.includes('Never merge to main')", 10000, 'decision listed');
  const mem = (await js("lab.call('state')")).memory;
  check(mem.some((d) => d.text.startsWith('Never merge to main')), 'decision saved and listed');
  await shot('08-memory');

  // Mavis: names and conversations only.
  await click('.srow[data-act=view][data-id=connections]');
  await click('[data-act=mavis-scan]');
  await waitFor("!!document.querySelector('[data-act=mavis-import]') || document.body.innerText.includes('No Mavis data')", 30000, 'mavis scan');
  if (await js("!!document.querySelector('[data-act=mavis-import]')")) {
    await click('[data-act=mavis-import]');
    await waitFor("document.body.innerText.includes('already here')", 30000, 'mavis import');
    const st = await js("lab.call('state')");
    check(st.imported > 0, `Mavis conversations imported (${st.imported})`);
  }
  await sleep(600);
  await shot('09-connections');

  // Search everything.
  await js("document.dispatchEvent(new KeyboardEvent('keydown',{key:'k',metaKey:true,bubbles:true}))");
  await waitFor("!!document.querySelector('#cmdInput')", 5000, 'search opens');
  await js("(()=>{const i=document.querySelector('#cmdInput'); i.value='mavis'; i.dispatchEvent(new Event('input',{bubbles:true})); return true})()");
  await sleep(1500);
  await shot('10-search');
  await js("document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))");

  await click('.srow[data-act=view][data-id=agents]');
  await sleep(600);
  await shot('11-agents');
  log('PASS', OUT);
  fs.rmSync(repo, { recursive: true, force: true });
  app.exit(0);
}

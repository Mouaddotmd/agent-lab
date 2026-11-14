// Agent Lab interface. Every screen draws from real data the engine sends; nothing here is example content.
const lab = window.lab;
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clip = (s, n = 90) => { const t = String(s ?? '').replace(/\s+/g, ' ').trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };
const base = (p) => String(p || '').split('/').filter(Boolean).pop() || p || '';

const OPS = {
  'claude-code': { name: 'Claude Code', ab: 'CC', chats: true, models: [['', 'Claude Code default'], ['claude-opus-5-5', 'Opus 5.5'], ['claude-sonnet-5-5', 'Sonnet 5.5'], ['claude-haiku-5-5', 'Haiku 5.5']] },
  codex: { name: 'Codex', ab: 'Cx', chats: true, models: [['', 'Codex default']] },
  cursor: { name: 'Cursor', ab: 'Cu', chats: false, models: [['', 'Cursor default']] },
  mavis: { name: 'Mavis', ab: 'Mv', chats: true, models: [] },
};
const PERMS = { ask: 'Asks before changes', edits: 'Edits files freely', plan: 'Plans only' };
const STATE = { needs: { label: 'Waiting for you', o: 0 }, working: { label: 'Working', o: 1 }, failed: { label: 'Failed', o: 2 }, done: { label: 'Done', o: 3 }, idle: { label: 'Ready', o: 4 } };

const S = {
  data: null, runs: new Map(), approvals: [], drafts: new Map(), msgs: new Map(), chats: {}, transcripts: new Map(), live: new Map(),
  overlaps: [], space: 'home', view: { kind: 'agents' }, tab: 'all', fold: {}, nowHidden: false, opq: '', cmdSel: 0, quick: [], mavis: null,
};

// ---------------------------------------------------------------- helpers
const I = {
  agents: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.2a6.5 6.5 0 0 1 3.5 5.8"/>',
  memory: '<path d="M5 4h9a4 4 0 0 1 4 4v12H9a4 4 0 0 1-4-4z"/><path d="M5 16a4 4 0 0 1 4-4h9"/>',
  plug: '<path d="M9 3v5M15 3v5M6 8h12v3a6 6 0 0 1-12 0zM12 17v4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>', pen: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>',
  home: '<path d="M4 11 12 4l8 7v9h-5v-6H9v6H4z"/>', search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4-4"/>',
  chev: '<path d="m7 10 5 5 5-5"/>', more: '<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
  send: '<path d="M12 19V5M6 11l6-6 6 6"/>', stop: '<rect x="7" y="7" width="10" height="10" rx="2"/>', x: '<path d="M6 6l12 12M18 6 6 18"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>', panel: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M15 4.5v15"/>',
  folder: '<path d="M3.5 7a2 2 0 0 1 2-2H10l2 2h6.5a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>', trash: '<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/>',
  branch: '<circle cx="7" cy="6" r="2"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="8" r="2"/><path d="M7 8v8M17 10c0 4-10 2-10 6"/>',
};
const ic = (n, s = 16, w = 1.7) => `<svg class="ic" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${I[n]}</svg>`;
const tile = (op, size = '') => `<span class="eg ${size}" title="${esc(OPS[op]?.name || op)}">${esc(OPS[op]?.ab || '?')}</span>`;

function ago(t) {
  const s = Math.max(1, Math.round((Date.now() - t) / 1000));
  if (s < 60) return 'just now'; const m = Math.round(s / 60); if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60); if (h < 24) return `${h} h ago`; const d = Math.round(h / 24); if (d < 14) return `${d} d ago`;
  return new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}
const elapsed = (t) => { const s = Math.max(0, Math.floor((Date.now() - t) / 1000)); return s < 60 ? `${s} s` : s < 3600 ? `${Math.floor(s / 60)} min` : `${Math.floor(s / 3600)} h ${Math.floor((s % 3600) / 60)} min`; };

// Drawn faces, so each agent reads as someone.
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const PAL = { bg: ['#3A4436', '#47353F', '#2F3A45', '#45402F', '#3B3A47', '#44332F', '#34413F'], skin: ['#F1CDB0', '#E2B48F', '#C99A78', '#A8714F', '#8D5B3F', '#6B4430'], hair: ['#1F1A17', '#3B2A20', '#8A5A3B', '#C6613F', '#D9C7A8', '#6E6A63'], shirt: ['#D97757', '#7E9C8B', '#5D6B8C', '#9C6B85', '#A9B98A', '#B8A06A'] };
const randLook = () => ({ bg: pick(PAL.bg), skin: pick(PAL.skin), hair: pick(PAL.hair), style: Math.floor(Math.random() * 5), shirt: pick(PAL.shirt), glasses: Math.random() < 0.3 });
function seededLook(id) {
  let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  const at = (a, k) => a[(h >>> k) % a.length];
  return { bg: at(PAL.bg, 1), skin: at(PAL.skin, 4), hair: at(PAL.hair, 7), style: (h >>> 10) % 5, shirt: at(PAL.shirt, 13), glasses: ((h >>> 16) % 10) < 3 };
}
let fN = 0;
function face(l) {
  const id = `f${fN++}`;
  const crop = `<path d="M12.2 18c-.4-6.6 3.4-10.3 7.8-10.3s8.2 3.7 7.8 10.3c-1.4-3.4-4.3-5-7.8-5s-6.4 1.6-7.8 5z" fill="${l.hair}"/>`;
  const hair = { 0: crop, 1: `<path d="M11.4 19c0-7.5 4-11.3 8.6-11.3s8.6 3.8 8.6 11.3v10h-3.7V18c-1.7-3-8.1-3-9.8 0v11h-3.7z" fill="${l.hair}"/>`, 2: `<circle cx="20" cy="6.6" r="3.6" fill="${l.hair}"/>${crop}`, 3: `<g fill="${l.hair}">${[[13, 13], [15.5, 9.6], [19.5, 8.2], [23.6, 9.4], [26.6, 12.6], [12.6, 16.4], [27.4, 16.4], [17.5, 10.5], [22, 10.2]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="3.2"/>`).join('')}</g>`, 4: `<path d="M12.6 16.8c.2-5.6 3.4-8.4 7.4-8.4s7.2 2.8 7.4 8.4c-1.6-2-4.3-3-7.4-3s-5.8 1-7.4 3z" fill="${l.hair}" opacity=".9"/>` }[l.style] || crop;
  const gl = l.glasses ? '<g fill="none" stroke="#151514" stroke-width=".8"><circle cx="17" cy="19.2" r="2.3"/><circle cx="23" cy="19.2" r="2.3"/><path d="M19.3 19.2h1.4"/></g>' : '';
  return `<svg class="face" viewBox="0 0 40 40" aria-hidden="true"><defs><clipPath id="${id}"><circle cx="20" cy="20" r="20"/></clipPath></defs><g clip-path="url(#${id})"><rect width="40" height="40" fill="${l.bg}"/><path d="M5 44c0-9 6.6-13.5 15-13.5S35 35 35 44z" fill="${l.shirt}"/><rect x="17" y="24" width="6" height="7" rx="2" fill="${l.skin}"/><ellipse cx="20" cy="19" rx="7.6" ry="8.6" fill="${l.skin}"/>${hair}<circle cx="17.1" cy="19.4" r=".95" fill="#151514"/><circle cx="22.9" cy="19.4" r=".95" fill="#151514"/><path d="M17.7 23.1c1.3 1 3.3 1 4.6 0" fill="none" stroke="#151514" stroke-width=".9" stroke-linecap="round"/>${gl}</g></svg>`;
}
const lookOf = (a) => a.look || seededLook(a.id);
const avatar = (a, size = 40, bgc = null, st = true) => `<span class="av" style="--sz:${size}px;${bgc ? `--bgc:${bgc}` : ''}">${face(lookOf(a))}${st ? `<span class="st ${stateOf(a)}" title="${STATE[stateOf(a)].label}"><i></i></span>` : ''}</span>`;

// Light formatting for replies: paragraphs, lists, code. Everything is escaped first.
function md(text) {
  const blocks = String(text ?? '').split(/```/);
  return blocks.map((b, i) => {
    if (i % 2) { const body = b.replace(/^[\w+-]*\n/, ''); return `<pre><code>${esc(body.replace(/\n$/, ''))}</code></pre>`; }
    return b.split(/\n{2,}/).filter((p) => p.trim()).map((p) => {
      const inline = (s) => esc(s).replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
      const lines = p.split('\n');
      if (lines.every((l) => /^\s*[-*•]\s+/.test(l))) return `<ul>${lines.map((l) => `<li>${inline(l.replace(/^\s*[-*•]\s+/, ''))}</li>`).join('')}</ul>`;
      if (lines.every((l) => /^\s*\d+[.)]\s+/.test(l))) return `<ol>${lines.map((l) => `<li>${inline(l.replace(/^\s*\d+[.)]\s+/, ''))}</li>`).join('')}</ol>`;
      return `<p>${lines.map(inline).join('<br>')}</p>`;
    }).join('');
  }).join('');
}

let toastT;
function toast(t, error = false) { const el = $('#toast'); el.textContent = t; el.style.color = error ? 'var(--fail-text)' : ''; el.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove('show'), error ? 5200 : 2800); }
async function run(fn, okMsg) { try { const v = await fn(); if (okMsg) toast(okMsg); return v; } catch (e) { toast(e.message || String(e), true); return undefined; } }

// ---------------------------------------------------------------- derived state
const agents = () => S.data?.agents || [];
const ag = (id) => agents().find((a) => a.id === id);
const inDir = (dir, root) => !!dir && !!root && (dir === root || dir.startsWith(`${root}/`));
const wsOf = (a) => (S.data?.workspaces || []).find((w) => inDir(a.cwd, w.path) || a.baseRepo === w.path || inDir(a.baseRepo, w.path));
const curWs = () => (S.data?.workspaces || []).find((w) => w.id === S.space);
const agentIn = (a) => S.space === 'home' || wsOf(a)?.id === S.space;
const chatIn = (c) => S.space === 'home' || inDir(c.cwd, curWs()?.path);
const approvalsFor = (agentId) => S.approvals.filter((p) => p.agentId === agentId);
function stateOf(a) {
  if (approvalsFor(a.id).length) return 'needs';
  if (S.runs.has(`agent:${a.id}`)) return 'working';
  if (a.last?.state === 'failed') return 'failed';
  if (a.last?.state === 'done' && !a.last.seen) return 'done';
  return 'idle';
}
function statusLine(a) {
  const st = stateOf(a), r = S.runs.get(`agent:${a.id}`);
  if (st === 'needs') { const p = approvalsFor(a.id)[0]; return `Wants to ${p.verb.toLowerCase()} ${p.line}`; }
  if (st === 'working') return r.activity || 'Working';
  if (st === 'failed') return 'Stopped with an error';
  const m = S.msgs.get(a.id); const last = m && [...m].reverse().find((x) => x.role === 'assistant');
  if (last) return clip(last.text, 100);
  return a.job ? clip(a.job, 100) : a.origin?.title ? clip(a.origin.title, 100) : 'Ready when you are';
}
const waitingCount = () => S.approvals.filter((p) => !p.agentId || (ag(p.agentId) && agentIn(ag(p.agentId)))).length + S.overlaps.filter((o) => o.agents.some((id) => ag(id) && agentIn(ag(id)))).length;

// ---------------------------------------------------------------- data loading
async function loadState() {
  const d = await lab.call('state');
  S.data = d;
  S.runs = new Map(d.runs.map((r) => [r.key, r]));
  S.approvals = d.approvals;
  await Promise.all(d.agents.map(async (a) => { if (!S.msgs.has(a.id)) S.msgs.set(a.id, await lab.call('agent:messages', a.id)); }));
  if (!d.workspaces.find((w) => w.id === S.space)) S.space = 'home';
  refreshOverlaps();
}
async function reloadAgents() { const d = await lab.call('agents'); S.data.agents = d; }
async function loadChats(op, force = false) {
  if (!OPS[op]?.chats) return [];
  if (!S.chats[op] || force) S.chats[op] = await lab.call('chats:list', op);
  return S.chats[op];
}
// A chat that is an agent's own session belongs to that agent, so operator lists leave it out.
const ownedSessions = () => new Set(agents().map((a) => a.sessionId).filter(Boolean));
const visibleChats = (op) => { const own = ownedSessions(); return (S.chats[op] || []).filter((c) => !own.has(c.id)); };
async function refreshOverlaps() {
  if (!agents().some((a) => a.worktree)) { S.overlaps = []; return; }
  try { S.overlaps = await lab.call('git:overlaps'); } catch { S.overlaps = []; }
  scheduleRender();
}

let rafPending = false, keepScroll = true;
function scheduleRender(keep = true) { keepScroll = keepScroll && keep; if (rafPending) return; rafPending = true; requestAnimationFrame(() => { rafPending = false; render(keepScroll); keepScroll = true; }); }

// ---------------------------------------------------------------- rail
function renderRail() {
  const homeWait = S.approvals.length;
  const waitIn = (w) => S.approvals.filter((p) => { const a = ag(p.agentId); return a && wsOf(a)?.id === w.id; }).length;
  $('#rail').innerHTML = `
    <button class="rbtn ${S.space === 'home' ? 'on' : ''}" data-act="space" data-id="home" title="Home" aria-label="Home">${ic('home', 20)}${homeWait && S.space !== 'home' ? `<span class="dot">${homeWait}</span>` : ''}</button>
    <button class="rbtn plain" data-act="cmd" title="Search everything  ⌘K" aria-label="Search everything">${ic('search', 20)}</button>
    <div class="rail-sep"></div>
    ${(S.data?.workspaces || []).map((w) => { const n = waitIn(w); return `<button class="rbtn ws ${S.space === w.id ? 'on' : ''}" style="--c:${w.color}" data-act="space" data-id="${w.id}" title="${esc(w.name)}" aria-label="${esc(w.name)}${n ? `, ${n} waiting for you` : ''}">${esc((w.name.replace(/[^\p{L}\p{N}]/gu, '').slice(0, 2) || '··').replace(/^./, (c) => c.toUpperCase()))}${n && S.space !== w.id ? `<span class="dot">${n}</span>` : ''}</button>`; }).join('')}
    <button class="rbtn plain" data-act="ws-add" title="Add a workspace folder" aria-label="Add a workspace folder">${ic('plus', 20)}</button>
    <div class="rail-fill"></div>
    <button class="rbtn plain" data-act="view" data-id="connections" title="Connections" aria-label="Connections">${ic('plug', 20)}</button>`;
}

// ---------------------------------------------------------------- sidebar
const fold = (k, l) => `<button class="fold" data-act="fold" data-id="${k}" aria-expanded="${!S.fold[k]}">${ic('chev', 12, 2)}${l}</button>`;
function renderSide() {
  const v = S.view, w = curWs();
  const on = (k, id) => (v.kind === k && (id === undefined || v.id === id) ? 'on' : '');
  const scope = agents().filter(agentIn).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || b.createdAt - a.createdAt);
  const shown = scope.slice(0, 6), rest = scope.length - shown.length;
  S.quick = shown.map((a) => a.id);
  const waiting = waitingCount();
  const row = (a, i) => `<button class="srow tall ${on('dm', a.id)}" data-act="dm" data-id="${a.id}">${avatar(a, 32, on('dm', a.id) ? 'var(--i3)' : 'var(--side)')}<span class="grow"><span class="t">${esc(a.name)}</span><span class="s ${stateOf(a) === 'needs' ? 'wait' : stateOf(a) === 'failed' ? 'fail' : ''}">${esc(statusLine(a))}</span></span><kbd class="quick">⌘${i + 1}</kbd></button>`;
  const ops = Object.entries(OPS).filter(([id]) => id === 'mavis' ? S.data?.imported > 0 : S.data?.operators?.[id]?.path).map(([id, o]) => {
    const n = S.chats[id] ? visibleChats(id).filter(chatIn).length : null;
    const live = scope.filter((a) => a.operator === id && stateOf(a) === 'working').length;
    const sub = !o.chats ? 'Runs agents you make here' : n === null ? 'Chats on this Mac' : `${n} ${n === 1 ? 'chat' : 'chats'}`;
    return `<button class="srow tall ${on('op', id)}" data-act="op" data-id="${id}">${tile(id)}<span class="grow"><span class="t">${o.name}</span><span class="s">${sub}${live ? ` · ${live} working` : ''}</span></span></button>`;
  });
  $('#side').innerHTML = `
    <div class="side-head"><span class="name">${esc(w ? w.name : 'Agent Lab')}</span><button class="icon-btn" data-act="cmd" aria-label="Search everything" title="Search everything  ⌘K">${ic('search')}</button><button class="icon-btn" data-act="new-agent" aria-label="New agent" title="New agent  ⌘N">${ic('pen')}</button></div>
    <div class="side-body scroll">
      <button class="srow ${on('agents')}" data-act="view" data-id="agents">${ic('agents')}<span class="t">Agents</span>${waiting ? `<span class="count" title="${waiting} waiting for you">${waiting}</span>` : ''}</button>
      <button class="srow ${on('memory')}" data-act="view" data-id="memory">${ic('memory')}<span class="t">Memory</span></button>
      <button class="srow ${on('connections')}" data-act="view" data-id="connections">${ic('plug')}<span class="t">Connections</span></button>
      <div class="label">${fold('team', 'Team')}<button data-act="new-agent" aria-label="New agent">${ic('plus', 14)}</button></div>
      ${S.fold.team ? '' : shown.length ? shown.map(row).join('') : '<p class="meta" style="padding:0 var(--s2)">No agents yet</p>'}
      ${!S.fold.team && rest > 0 ? `<button class="srow" data-act="tab" data-id="all">${ic('more')}<span class="t">${rest} more</span></button>` : ''}
      <div class="label">${fold('ops', 'Operators')}<button data-act="view" data-id="connections" aria-label="Connections">${ic('plus', 14)}</button></div>
      ${S.fold.ops ? '' : ops.join('')}
    </div>`;
}

// ---------------------------------------------------------------- top bar
function renderStrip() {
  const v = S.view;
  const toggle = `<button class="icon-btn only-wide ${S.nowHidden ? '' : 'on'}" data-act="now-toggle" aria-pressed="${!S.nowHidden}" aria-label="${S.nowHidden ? 'Show' : 'Hide'} Right now" title="${S.nowHidden ? 'Show' : 'Hide'} Right now  ⌥⌘0">${ic('panel')}</button>`;
  let title = '', extra = '';
  if (v.kind === 'agents') {
    const n = waitingCount();
    const tabs = [['working', 'Working'], ['needs', 'Waiting for you'], ['done', 'Done'], ['all', 'All']];
    title = `${ic('agents')}Agents</div><span class="strip-dot"></span><div class="tabs" role="tablist">${tabs.map(([k, l]) => `<button class="tab ${S.tab === k ? 'on' : ''}" data-act="tab" data-id="${k}" role="tab" aria-selected="${S.tab === k}">${l}${k === 'needs' && n ? `<span class="count">${n}</span>` : ''}</button>`).join('')}`;
    extra = `<button class="btn ${S.tab === 'needs' && n ? 'second' : 'primary'}" data-act="new-agent">${ic('plus', 14, 2)}New agent</button>`;
  } else if (v.kind === 'dm') {
    const a = ag(v.id);
    if (a) { title = `${avatar(a, 24, 'var(--work)')}${esc(a.name)}<span class="meta">${STATE[stateOf(a)].label}</span>`; extra = `<button class="icon-btn" data-act="agent-edit" data-id="${a.id}" aria-label="Edit ${esc(a.name)}" title="Edit">${ic('more')}</button>`; }
  } else if (v.kind === 'op') {
    const c = selectedChat();
    title = `${tile(v.id, 'sm')}${OPS[v.id].name}${c ? `<span class="meta ellipsis">${esc(c.title)}</span>` : ''}`;
    if (c) extra = `<button class="btn second" data-act="handoff">Hand off</button><button class="btn primary" data-act="promote">Make this an agent</button>`;
  } else if (v.kind === 'review') {
    const a = ag(v.id);
    title = `${a ? avatar(a, 24, 'var(--work)') : ''}Review changes<span class="meta">${esc(a?.branch || '')}</span>`;
    extra = `<button class="btn danger" data-act="discard">Discard</button><button class="btn second" data-act="ask-changes">Ask for changes</button><button class="btn primary" data-act="merge">Merge into ${esc(a?.baseBranch || 'main')}</button>`;
  } else title = { memory: 'Memory', connections: 'Connections' }[v.kind] || '';
  $('#strip').innerHTML = `<div class="title">${title}</div><div class="end">${toggle}${extra}</div>`;
}

// ---------------------------------------------------------------- views
function renderView(keep) {
  const el = $('#view'), top = el.scrollTop, v = S.view;
  const pl = $('#paneList'), plTop = pl ? pl.scrollTop : 0, pd = $('#paneDetail'), pdTop = pd ? pd.scrollTop : 0;
  const pdAtEnd = pd ? pd.scrollHeight - pd.scrollTop - pd.clientHeight < 40 : true;
  const atEnd = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
  const focus = document.activeElement?.id, selStart = document.activeElement?.selectionStart;
  const draftVal = $('#cmpInput')?.value;
  el.innerHTML = v.kind === 'dm' ? dmView() : v.kind === 'op' ? opView() : v.kind === 'review' ? reviewView() : v.kind === 'memory' ? memoryView() : v.kind === 'connections' ? connectionsView() : agentsView();
  if (draftVal && $('#cmpInput') && !$('#cmpInput').value) $('#cmpInput').value = draftVal;
  if (v.kind === 'dm') el.scrollTop = keep && !atEnd ? top : el.scrollHeight;
  else el.scrollTop = keep ? top : 0;
  const npl = $('#paneList'); if (npl) npl.scrollTop = plTop;
  const npd = $('#paneDetail'); if (npd) npd.scrollTop = keep && !pdAtEnd ? pdTop : npd.scrollHeight;
  if (focus) { const f = document.getElementById(focus); if (f) { f.focus(); try { if (selStart != null) f.setSelectionRange(selStart, selStart); } catch {} } }
  autoGrow();
}

const TABS_FILTER = { all: () => true, working: (a) => stateOf(a) === 'working', needs: (a) => stateOf(a) === 'needs', done: (a) => ['done', 'failed', 'idle'].includes(stateOf(a)) };
function agentsView() {
  const scope = agents().filter(agentIn);
  if (!agents().length) return emptyHero();
  const empty = (a, b) => `<div class="empty"><div>${a}</div><div>${b}</div></div>`;
  if (S.tab === 'needs') {
    const aps = S.approvals.filter((p) => { const a = ag(p.agentId); return a && agentIn(a); });
    const ovs = S.overlaps.filter((o) => o.agents.some((id) => ag(id) && agentIn(ag(id))));
    let primary = true;
    return `<div class="col"><div class="group-head">Waiting for you<span class="meta">${aps.length + ovs.length}</span></div>
      <div class="inbox">${aps.map((p) => { const out = approvalCard(p, primary, true); primary = false; return out; }).join('')}
      ${ovs.map((o) => overlapCard(o)).join('')}</div>
      ${!aps.length && !ovs.length ? empty('Nothing is waiting for you', 'When an agent wants to change something, it asks here first') : ''}</div>`;
  }
  const list = scope.filter(TABS_FILTER[S.tab]).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || b.createdAt - a.createdAt);
  const groups = Object.keys(STATE).map((s) => [s, list.filter((a) => stateOf(a) === s)]).filter((g) => g[1].length);
  const body = groups.length ? groups.map(([s, l]) => `<section class="group"><div class="group-head">${STATE[s].label}<span class="meta">${l.length}</span></div>${l.map(arow).join('')}</section>`).join('')
    : S.tab === 'working' ? empty('Nobody is working right now', 'Message an agent, or hand off work with ⌘K') : empty('Nothing here yet', 'Agents show up here when they finish');
  if (S.tab !== 'all') return `<div class="col">${body}</div>`;
  const w = waitingCount(), k = scope.filter((a) => stateOf(a) === 'working').length;
  const hr = new Date().getHours(), part = hr < 12 ? 'Morning' : hr < 18 ? 'Afternoon' : 'Evening';
  const sub = `${w ? `<button class="w link-like" data-act="tab" data-id="needs">${w} ${w === 1 ? 'thing is' : 'things are'} waiting for you.</button> ` : 'Nothing is waiting for you. '}${k ? `${k} ${k === 1 ? 'agent is' : 'agents are'} working.` : 'Nobody is working right now.'}`;
  const crew = scope.slice().sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o);
  return `<div class="col">
    <h1 class="hello">${S.space === 'home' ? `${part}.` : esc(curWs()?.name)}</h1><p class="hello-sub">${sub}</p>
    ${crew.length ? `<div class="crew" aria-label="Your agents">${crew.map((a) => `<button class="mate" data-act="dm" data-id="${a.id}" aria-label="${esc(a.name)}, ${STATE[stateOf(a)].label}"><span class="halo ${stateOf(a)}">${avatar(a, 64, null, false)}</span><span class="n">${esc(a.name)}</span><span class="d">${STATE[stateOf(a)].label}</span></button>`).join('')}</div>` : ''}
    ${scope.length ? body : empty('No agents in this workspace yet', 'New agents made here work in this folder')}
  </div>`;
}
function emptyHero() {
  return `<div class="col"><div class="empty-hero">
    <h2>No agents yet</h2>
    <p>An agent is Claude Code, Codex or Cursor with a name, a folder and a job of your choosing. It answers exactly as that tool does, and asks you before it changes anything.</p>
    <div class="row"><button class="btn primary" data-act="new-agent">New agent</button><button class="btn second" data-act="op" data-id="claude-code">Make one from a chat</button><button class="btn second" data-act="mavis-start">Bring in from Mavis</button></div>
  </div></div>`;
}
function arow(a) {
  const st = stateOf(a);
  const act = st === 'needs' ? `<button class="btn second" data-act="dm" data-id="${a.id}">Review</button>` : `<button class="round msgbtn" data-act="dm" data-id="${a.id}" aria-label="Message ${esc(a.name)}"><span class="chat">${ic('pen')}</span></button>`;
  const where = wsOf(a)?.name || (a.cwd && a.cwd !== S.data.home ? base(a.cwd) : '');
  return `<div class="arow" data-act="dm" data-id="${a.id}" role="button" tabindex="0">${avatar(a, 48, 'var(--work)')}
    <div class="arow-main"><div class="arow-name">${esc(a.name)}<span class="tag">${OPS[a.operator]?.name || a.operator}</span></div>
    <div class="arow-sub ${st === 'needs' ? 'wait' : st === 'failed' ? 'fail' : ''}">${esc(statusLine(a))}${S.space === 'home' && where ? ` <span class="where">· ${esc(where)}</span>` : ''}</div></div>
    <div class="acts">${act}</div></div>`;
}
function approvalCard(p, primary, withWho) {
  const a = ag(p.agentId);
  return `<section class="ibx"><div class="card raised approval"><div class="card-main">
    <span class="badge wait">Waiting for you</span>
    ${withWho && a ? `<button class="who-line" data-act="dm" data-id="${a.id}">${avatar(a, 24, 'var(--i2)', false)}${esc(a.name)} wants to</button>` : ''}
    <div class="card-title">${esc(p.verb)} ${esc(p.line)}</div>
    ${p.detail && p.detail !== p.line ? `<code class="cmd selectable">${esc(clip(p.detail, 400))}</code>` : ''}
  </div><div class="card-acts">
    <button class="btn ${primary ? 'primary' : 'second'}" data-act="approve" data-id="${p.id}" data-decision="allow">Allow</button>
    ${p.suggestions?.length ? `<button class="btn second" data-act="approve" data-id="${p.id}" data-decision="always">Always allow</button>` : ''}
    <button class="btn danger" data-act="approve" data-id="${p.id}" data-decision="deny">Don’t allow</button>
  </div></div></section>`;
}
function overlapCard(o) {
  const [a, b] = o.agents.map(ag);
  if (!a || !b) return '';
  return `<section class="ibx"><div class="notice">${ic('branch')}<span><b>${esc(a.name)} and ${esc(b.name)} both changed ${esc(o.files.slice(0, 3).map(base).join(', '))}${o.files.length > 3 ? ` and ${o.files.length - 3} more` : ''}.</b> Merge one first; the other then updates from it instead of conflicting.</span></div>
    <div class="card-acts" style="padding:var(--s2) 0 0"><button class="btn second" data-act="review" data-id="${a.id}">Review ${esc(a.name)}</button><button class="btn second" data-act="review" data-id="${b.id}">Review ${esc(b.name)}</button></div></section>`;
}

// ---- agent conversation
function dmView() {
  const a = ag(S.view.id);
  if (!a) return '<div class="col"><div class="empty"><div>This agent was removed</div></div></div>';
  const key = `agent:${a.id}`, r = S.runs.get(key), msgs = S.msgs.get(a.id) || [];
  const ws = wsOf(a);
  const chips = [
    OPS[a.operator]?.chats ? `<button class="chip link" data-act="op" data-id="${a.operator}">Runs on ${OPS[a.operator].name}</button>` : `<span class="chip">Runs on ${OPS[a.operator]?.name || a.operator}</span>`,
    `<button class="chip link" data-act="open-folder" data-path="${esc(a.cwd)}" title="${esc(a.cwd)}">${ic('folder', 12)}${esc(ws?.name || base(a.cwd))}</button>`,
    a.worktree ? `<button class="chip link" data-act="review" data-id="${a.id}">${ic('branch', 12)}${esc(a.branch)} · Review changes</button>` : '',
    a.model ? `<span class="chip">${esc((OPS[a.operator]?.models.find((m) => m[0] === a.model) || [0, a.model])[1])}</span>` : '',
    `<span class="chip">${PERMS[a.permission] || PERMS.ask}</span>`,
    a.origin?.type === 'chat' ? `<button class="chip link" data-act="open-chat" data-op="${a.origin.operator}" data-id="${esc(a.origin.ref)}">From: ${esc(clip(a.origin.title, 40))}</button>` : a.origin?.title ? `<span class="chip">${esc(a.origin.title)}</span>` : '',
  ].filter(Boolean).join('');
  let prev = null, primary = true;
  const lines = msgs.map((m) => {
    let out = '';
    if (m.role === 'user') out = `<div class="msg mine ${prev === 'user' ? 'cont' : ''}"><div class="body">${prev === 'user' ? '' : `<span class="meta">${ago(m.at)}</span>`}<div class="bubble">${m.text.length > 1500 ? `${md(m.text.slice(0, 1200))}<p class="meta">…${m.text.length - 1200} more characters of context</p>` : md(m.text)}</div></div></div>`;
    else if (m.role === 'assistant') out = `<div class="msg ${prev === 'assistant' ? 'cont' : ''}">${avatar(a, 40, null, false)}<div class="body">${prev === 'assistant' ? '' : `<span class="meta">${esc(a.name)} · ${ago(m.at)}</span>`}<div class="bubble">${md(m.text)}</div></div></div>`;
    else if (m.role === 'tool') out = `<div class="step"><b>${esc(m.verb)}</b><span>${esc(m.text)}</span></div>`;
    else if (m.role === 'error') out = `<div class="step err"><b>${m.text === 'Stopped.' ? 'Stopped' : 'Error'}</b><span>${esc(m.text === 'Stopped.' ? 'You stopped this run.' : m.text)}</span></div>`;
    prev = m.role === 'tool' || m.role === 'error' ? prev : m.role;
    return out;
  }).join('');
  const draft = S.drafts.get(key);
  const aps = approvalsFor(a.id).map((p) => { const o = approvalCard(p, primary, false); primary = false; return o; }).join('');
  const working = r && !draft && !aps ? `<div class="typing"><i></i><i></i><i></i>&nbsp;${esc(a.name)} · ${esc(r.activity || 'Working')}</div>` : '';
  const intro = !msgs.length ? `<p class="meta" style="margin-top:var(--s6)">${a.sessionId ? `This agent continues an existing ${OPS[a.operator]?.name} session, so it already knows that conversation.` : `Say what you need. ${esc(a.name)} works in ${esc(a.cwd)}.`}</p>` : '';
  return `<div class="convo"><div class="thread">
    <div class="who">${avatar(a, 80)}<div><h2>${esc(a.name)}</h2>${a.job ? `<p class="selectable">${esc(a.job)}</p>` : `<p>Behaves exactly like ${OPS[a.operator]?.name || 'its tool'} normally does.</p>`}<div class="chips">${chips}</div></div></div>
    ${intro}${lines}
    ${draft ? `<div class="msg">${avatar(a, 40, null, false)}<div class="body"><span class="meta">${esc(a.name)}</span><div class="bubble draft" data-draft="${key}">${md(draft)}</div></div></div>` : ''}
    ${aps}${working}
  </div>${composer(`Message ${a.name}`, key, r)}</div>`;
}
function composer(placeholder, key, running) {
  return `<form class="composer" id="cmpForm" data-key="${esc(key)}" autocomplete="off"><div class="cmp"><textarea id="cmpInput" rows="1" placeholder="${esc(placeholder)}" aria-label="${esc(placeholder)}"></textarea>${running ? `<button class="send stop" type="button" data-act="stop" data-id="${esc(key)}" aria-label="Stop" title="Stop">${ic('stop', 16, 2)}</button>` : `<button class="send" type="submit" aria-label="Send" title="Send  ↵">${ic('send', 16, 2)}</button>`}</div></form>`;
}

// ---- operator: chat list beside the open chat
function selectedChat() { const op = S.view.id, list = S.chats[op]; return list && S.view.chat ? list.find((c) => c.id === S.view.chat) || null : null; }
function opView() {
  const op = S.view.id, o = OPS[op], list = S.chats[op];
  if (!o.chats) return `<div class="col"><div class="empty-hero"><h2>${o.name}</h2><p>Cursor keeps no chats other apps can read. Make a Cursor agent and its conversation lives here.</p><div class="row"><button class="btn primary" data-act="new-agent" data-op="${op}">New Cursor agent</button></div></div></div>`;
  if (!list) { loadChats(op).then(() => { if (S.view.kind === 'op' && S.view.id === op) { if (!S.view.chat) S.view.chat = visibleChats(op).filter(chatIn)[0]?.id || null; render(false); } }); return `<div class="col"><p class="loading">Reading your ${o.name} chats</p></div>`; }
  const q = S.opq.trim().toLowerCase();
  const vis = visibleChats(op);
  if (S.view.chat === undefined) S.view.chat = vis.filter(chatIn)[0]?.id || null;
  const scoped = vis.filter(chatIn), shown = scoped.filter((c) => !q || `${c.title} ${c.cwd}`.toLowerCase().includes(q));
  const groups = new Map();
  for (const c of shown) { const k = c.cwd || ''; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(c); }
  const sel = S.view.chat;
  const crow = (c) => `<button class="crow ${c.id === sel ? 'on' : ''}" data-act="pick" data-id="${esc(c.id)}" aria-current="${c.id === sel}"><span class="t">${esc(c.title)}</span><span class="meta">${ago(c.updated)}${c.bot ? ` · ${esc(c.bot)}` : ''}</span></button>`;
  const usedBy = agents().filter((a) => a.operator === op && agentIn(a));
  const listPane = `<div class="pane-list scroll" id="paneList">
    <div class="pane-head">${tile(op)}<div class="grow-col"><span>${o.name}</span><span class="meta">${scoped.length} ${scoped.length === 1 ? 'chat' : 'chats'}${S.space === 'home' ? ' on this Mac' : ` in ${esc(curWs()?.name)}`}</span></div></div>
    ${usedBy.length ? `<div class="people">${usedBy.map((a) => `<button class="person" data-act="dm" data-id="${a.id}">${avatar(a, 32, 'var(--i2)')}<span>${esc(a.name)}</span></button>`).join('')}</div>` : ''}
    ${scoped.length ? `<label class="find">${ic('search')}<input id="opq" type="search" placeholder="Find in ${o.name} chats" value="${esc(S.opq)}" aria-label="Find in ${o.name} chats"></label>` : ''}
    ${[...groups].map(([dir, cs]) => `<section class="cgroup"><div class="group-head" title="${esc(dir)}">${esc(base(dir) || 'No folder')}<span class="meta">${cs.length}</span></div>${cs.slice(0, 40).map(crow).join('')}${cs.length > 40 ? `<p class="meta more-note">${cs.length - 40} older chats in this folder. Search finds them.</p>` : ''}</section>`).join('')}
    ${!scoped.length ? `<div class="empty"><div>No ${o.name} chats${S.space === 'home' ? '' : ' in this workspace'}</div><div>${op === 'mavis' ? 'Bring them in from Connections' : 'They show up here as you use it'}</div></div>` : !shown.length ? `<div class="empty"><div>No chat matches “${esc(S.opq)}”</div></div>` : ''}
  </div>`;
  return `<div class="split">${listPane}<div class="pane-detail scroll" id="paneDetail">${chatDetail()}</div></div>`;
}
function chatDetail() {
  const c = selectedChat();
  if (!c) return '<div class="empty"><div>Pick a chat</div><div>↑ ↓ move through the list</div></div>';
  const tkey = `${c.operator}:${c.id}`, rkey = `chat:${c.operator}:${c.id}`;
  const items = S.transcripts.get(tkey);
  if (!items) {
    lab.call('chat:transcript', c.operator, c.id).then((t) => { S.transcripts.set(tkey, t); if (selectedChat()?.id === c.id) renderView(false); }, (e) => { S.transcripts.set(tkey, []); toast(e.message, true); });
    return '<div class="convo"><div class="thread"><p class="loading">Opening this chat</p></div></div>';
  }
  const all = [...items.slice(-400), ...(S.live.get(rkey) || [])];
  let prev = null;
  const lines = all.map((m) => {
    let out = '';
    if (m.role === 'user') out = `<div class="msg mine ${prev === 'user' ? 'cont' : ''}"><div class="body"><div class="bubble">${md(clip(m.text, 4000))}</div></div></div>`;
    else if (m.role === 'assistant') out = `<div class="msg ${prev === 'assistant' ? 'cont' : ''}"><span class="av" style="--sz:40px">${tile(c.operator, 'lg')}</span><div class="body">${prev === 'assistant' ? '' : `<span class="meta">${c.bot ? esc(c.bot) : OPS[c.operator].name}</span>`}<div class="bubble">${md(m.text)}</div></div></div>`;
    else if (m.role === 'tool') out = `<div class="step"><b>${esc(m.verb)}</b><span>${esc(m.text)}</span></div>`;
    prev = m.role === 'tool' ? prev : m.role;
    return out;
  }).join('');
  const r = S.runs.get(rkey), draft = S.drafts.get(rkey);
  const aps = S.approvals.filter((p) => p.key === rkey).map((p, i) => approvalCard(p, false, false)).join('');
  const canContinue = c.operator !== 'mavis' && S.data.operators[c.operator]?.path;
  return `<div class="convo"><div class="thread">
    <div class="who">${tile(c.operator, 'xl')}<div><h2>${esc(c.title)}</h2><div class="chips"><button class="chip link" data-act="open-folder" data-path="${esc(c.cwd)}">${ic('folder', 12)}${esc(base(c.cwd) || 'No folder')}</button><span class="chip">${ago(c.updated)}</span>${c.bot ? `<span class="chip">${esc(c.bot)}</span>` : ''}</div></div></div>
    ${items.length > 400 ? `<p class="meta">Showing the latest 400 of ${items.length} messages.</p>` : ''}
    ${lines || '<p class="meta">This chat has no messages to show.</p>'}
    ${draft ? `<div class="msg"><span class="av" style="--sz:40px">${tile(c.operator, 'lg')}</span><div class="body"><div class="bubble draft" data-draft="${rkey}">${md(draft)}</div></div></div>` : ''}
    ${aps}${r && !draft && !aps ? `<div class="typing"><i></i><i></i><i></i>&nbsp;${esc(r.activity || 'Working')}</div>` : ''}
  </div>${canContinue ? composer(`Continue in ${OPS[c.operator].name}`, rkey, r) : `<div class="composer"><div class="notice info">${c.operator === 'mavis' ? 'Mavis chats can be read here. Hand it off or make it an agent to keep going.' : `${OPS[c.operator].name} isn’t installed, so this chat can only be read.`}</div></div>`}</div>`;
}

// ---- review
const reviewCache = new Map();
function reviewView() {
  const a = ag(S.view.id);
  if (!a?.worktree) return '<div class="col"><div class="empty"><div>This agent doesn’t work on its own branch</div></div></div>';
  const rc = reviewCache.get(a.id);
  if (!rc) {
    reviewCache.set(a.id, { loading: true });
    lab.call('git:changes', a.id).then((c) => { reviewCache.set(a.id, { files: c.files, open: c.files[0]?.path || null, diffs: new Map() }); renderView(false); }, (e) => { reviewCache.set(a.id, { error: e.message }); renderView(false); });
  }
  const r = reviewCache.get(a.id);
  const head = `<div class="who">${avatar(a, 48)}<div><h2>${esc(a.name)}’s changes</h2><div class="chips"><span class="chip">${esc(a.branch)} → ${esc(a.baseBranch)}</span><button class="chip link" data-act="open-folder" data-path="${esc(a.worktree)}">${ic('folder', 12)}Its folder</button></div></div></div>`;
  if (r.loading) return `<div class="col">${head}<p class="loading">Reading the changes</p></div>`;
  if (r.error) return `<div class="col">${head}<div class="notice">${esc(r.error)}</div></div>`;
  const add = r.files.reduce((s, f) => s + f.add, 0), del = r.files.reduce((s, f) => s + f.del, 0);
  const ov = S.overlaps.find((o) => o.agents.includes(a.id));
  if (r.open && !r.diffs.has(r.open)) {
    const f = r.open; r.diffs.set(f, null);
    lab.call('git:diff', a.id, f).then((d) => { r.diffs.set(f, d); renderView(true); }, (e) => { r.diffs.set(f, [`Could not read this file: ${e.message}`]); renderView(true); });
  }
  const bars = (x, y) => { const t = x + y || 1, g = Math.round((x / t) * 5); return Array.from({ length: 5 }, (_, i) => `<i class="${i < g ? 'a' : 'd'}"></i>`).join(''); };
  return `<div class="col">${head}
    <div class="chips" style="margin-top:var(--s3)"><span class="chip">${r.files.length} ${r.files.length === 1 ? 'file' : 'files'} · <span class="c-add">+${add}</span> <span class="c-del">−${del}</span></span></div>
    ${ov ? `<div class="notice">${ic('agents')}<span><b>${esc(ag(ov.agents.find((x) => x !== a.id))?.name || 'Another agent')} also changed ${esc(ov.files.slice(0, 3).map(base).join(', '))}.</b> Merge one first; the other updates from it instead of conflicting.</span></div>` : ''}
    ${!r.files.length ? '<div class="empty"><div>No changes yet</div><div>When this agent edits files, they show up here</div></div>' : ''}
    <div class="files">${r.files.map((f) => `<div class="file">
      <button class="file-head" data-act="file" data-id="${esc(f.path)}" aria-expanded="${f.path === r.open}"><span class="path">${esc(f.path)}</span>${ov?.files.includes(f.path) ? '<span class="badge wait">Both changed</span>' : ''}<span class="chg">${f.binary ? 'binary' : `<span class="c-add">+${f.add}</span> <span class="c-del">−${f.del}</span>`}</span><span class="bars">${bars(f.add, f.del)}</span></button>
      ${f.path === r.open ? `<div class="diff">${r.diffs.get(f.path) ? r.diffs.get(f.path).map((l) => `<div class="${l.startsWith('+') ? 'add' : l.startsWith('-') ? 'del' : l.startsWith('@@') ? 'hunk' : ''}">${esc(l) || ' '}</div>`).join('') : '<div class="loading">Reading</div>'}</div>` : ''}
    </div>`).join('')}</div></div>`;
}

// ---- memory
function memoryView() {
  const ws = S.data.workspaces;
  const list = S.data.memory.filter((d) => S.space === 'home' || !d.workspace || d.workspace === S.space).sort((a, b) => b.n - a.n);
  return `<div class="col page"><h2>Memory</h2><p class="lede">Decisions you’ve made, once. Every Claude Code agent is told them before it starts, alongside Claude Code’s own instructions. Nothing else is added.</p>
    <form class="add-row" id="memForm"><input id="memInput" placeholder="A decision, like “Never merge to main without tests passing”" aria-label="New decision"><select id="memScope" aria-label="Where it applies"><option value="">Everywhere</option>${ws.map((w) => `<option value="${w.id}" ${S.space === w.id ? 'selected' : ''}>${esc(w.name)}</option>`).join('')}</select><button class="btn primary" type="submit">Add</button></form>
    <div class="list">${list.map((d) => `<div class="tile mem-row"><span class="mid">#${d.n}</span><div class="tile-main"><div class="selectable">${esc(d.text)}</div><div class="meta">${d.workspace ? esc(ws.find((w) => w.id === d.workspace)?.name || 'A removed workspace') : 'Everywhere'} · ${esc(d.by)}${d.source ? ` · from ${esc(d.source)}` : ''} · ${ago(d.at)}</div></div><button class="icon-btn" data-act="mem-remove" data-id="${d.id}" aria-label="Remove decision ${d.n}" title="Remove">${ic('trash')}</button></div>`).join('')}</div>
    ${!list.length ? '<div class="empty"><div>No decisions yet</div><div>Add one above, or save them from a chat when you make it an agent</div></div>' : ''}</div>`;
}

// ---- connections
function connectionsView() {
  const ops = S.data.operators;
  const opRow = (id) => { const o = ops[id]; return `<div class="tile mid-align">${tile(id, 'lg')}<div class="tile-main"><div>${OPS[id].name}</div><div class="meta">${o?.path ? `${esc(o.version || 'Installed')} · ${esc(o.path)}` : 'Not found on this Mac'}</div></div><span class="op-status ${o?.path ? 'ok' : ''}"><i></i>${o?.path ? 'Connected' : 'Not installed'}</span></div>`; };
  const folders = new Map();
  for (const c of [...(S.chats['claude-code'] || []), ...(S.chats.codex || [])]) if (c.cwd && c.cwd !== S.data.home) folders.set(c.cwd, (folders.get(c.cwd) || 0) + 1);
  const suggest = [...folders].filter(([p]) => !S.data.workspaces.some((w) => w.path === p)).sort((a, b) => b[1] - a[1]).slice(0, 8);
  if (!S.chats['claude-code']) loadChats('claude-code').then(() => { if (S.view.kind === 'connections') renderView(true); }, () => {});
  const m = S.mavis;
  return `<div class="col page"><h2>Connections</h2><p class="lede">Agents run through the tools already on this Mac, with your own logins and settings. Agent Lab never sees your passwords.</p>
    <div class="list">${['claude-code', 'codex', 'cursor'].map(opRow).join('')}</div>
    <section class="section"><h3>Mavis</h3><p class="lede">Brings Mavis’s agents and conversations in by name. Mavis’s own prompts and rules stay behind: agents here answer the way Claude Code does.</p>
      <div class="tile mid-align">${tile('mavis', 'lg')}<div class="tile-main"><div>Mavis on this Mac</div><div class="meta">${!m ? 'Not checked yet' : !m.found ? 'No Mavis data found' : `${m.bots} ${m.bots === 1 ? 'agent' : 'agents'} · ${m.chats} conversations${m.alreadyImported ? ` · ${m.alreadyImported} already here` : ''}`}</div></div>
      ${!m ? '<button class="btn second" data-act="mavis-scan">Check</button>' : m.found && (m.chats > m.alreadyImported || !agents().some((a) => a.origin?.type === 'mavis-bot')) ? '<button class="btn primary" data-act="mavis-import">Bring them in</button>' : m.found ? '<span class="mavis-ok">Everything is here</span>' : ''}</div></section>
    <section class="section"><h3>Workspaces</h3><p class="lede">A workspace is a folder. Agents made in it work there, and its chats and agents get their own space on the left.</p>
      <div class="list">${S.data.workspaces.map((w) => `<div class="tile mid-align"><span class="ws-dot" style="background:${w.color}"></span><div class="tile-main"><div>${esc(w.name)}</div><div class="meta">${esc(w.path)}</div></div><button class="icon-btn" data-act="ws-remove" data-id="${w.id}" aria-label="Remove ${esc(w.name)}" title="Remove from the sidebar">${ic('x')}</button></div>`).join('')}
      <button class="btn second" data-act="ws-add" style="align-self:flex-start">${ic('folder', 14)}Add a folder</button></div>
      ${suggest.length ? `<p class="meta" style="margin-top:var(--s4)">Folders you work in most, from your chats</p><div class="list" style="margin-top:var(--s2)">${suggest.map(([p, n]) => `<div class="tile mid-align"><span class="ws-dot" style="background:var(--i6)"></span><div class="tile-main"><div>${esc(base(p))}</div><div class="meta">${esc(p)} · ${n} chats</div></div><button class="btn second" data-act="ws-add-path" data-path="${esc(p)}">Add</button></div>`).join('')}</div>` : ''}
    </section></div>`;
}

// ---------------------------------------------------------------- Right now
function renderNow() {
  const runs = [...S.runs.values()].filter((r) => (r.agentId ? ag(r.agentId) && agentIn(ag(r.agentId)) : true));
  $('#now').innerHTML = `<header class="strip"><div class="title">Right now</div><div class="end"><button class="icon-btn only-narrow" data-act="now-close" aria-label="Close">${ic('x')}</button></div></header>
    <div class="now-body scroll">${runs.map((r) => {
      const a = r.agentId && ag(r.agentId);
      const chat = r.chat && (S.chats[r.chat.operator] || []).find((c) => c.id === r.chat.id);
      const who = a ? avatar(a, 40, 'var(--i2)') : `<span class="av" style="--sz:40px">${tile(r.operator, 'lg')}</span>`;
      const name = a ? a.name : chat ? clip(chat.title, 40) : OPS[r.operator]?.name;
      const go = a ? `data-act="dm" data-id="${a.id}"` : `data-act="open-chat" data-op="${r.chat?.operator}" data-id="${esc(r.chat?.id)}"`;
      return `<div class="live" ${go}><div class="live-top">${who}<div class="live-who"><div>${esc(name)}</div><div class="live-doing">${esc(r.activity || 'Working')} · <span data-since="${r.startedAt}">${elapsed(r.startedAt)}</span></div></div>${tile(r.operator, 'sm')}</div>${r.preview ? `<div class="live-body"><div class="pad"><div class="preview">${esc(r.preview)}</div></div></div>` : ''}</div>`;
    }).join('')}
    ${!runs.length ? '<div class="empty"><div>Nothing is running</div><div>Agents show up here while they work</div></div>' : ''}</div>`;
}

// The view goes before the top bar: it may pick the chat the bar's actions act on.
function render(keep = true) { renderRail(); renderSide(); renderView(keep); renderStrip(); renderNow(); $('#sheet').classList.toggle('no-now', S.nowHidden); }

// ---------------------------------------------------------------- navigation
function go(view) {
  if (window.__trace) console.log('[go]', JSON.stringify(view), new Error().stack.split('\n').slice(2, 5).join(' | '));
  if (view.kind === 'dm') {
    const a = ag(view.id);
    if (a && S.space !== 'home' && wsOf(a)?.id !== S.space) S.space = 'home';
    if (a?.last?.state && !a.last.seen) { a.last.seen = true; lab.call('agent:update', a.id, { last: a.last }).catch(() => {}); }
  }
  if (view.kind === 'op' && S.view.kind === 'op' && S.view.id === view.id && view.chat === undefined) view.chat = S.view.chat;
  if (view.kind === 'review') reviewCache.delete(view.id);
  S.view = view;
  closeDrawers();
  render(false);
}
function closeDrawers() { $('#now').classList.remove('open'); $('#scrim').classList.remove('show'); }
function pickChat(id) { S.view.chat = id; renderStrip(); renderView(false); const r = document.querySelector(`.crow[data-id="${CSS.escape(id)}"]`); if (r) r.scrollIntoView({ block: 'nearest' }); }

// ---------------------------------------------------------------- modals
const layer = (html) => { $('#layer').innerHTML = html; const f = $('#layer [autofocus]') || $('#layer input, #layer textarea, #layer button'); f?.focus(); };
const closeLayer = () => { $('#layer').innerHTML = ''; };
const modal = (label, body, foot) => `<div class="backdrop center" data-act="close-layer"><div class="overlay modal" role="dialog" aria-modal="true" aria-label="${esc(label)}">${body}<div class="m-foot">${foot}</div></div></div>`;

function confirmBox({ title, body, ok, danger }) {
  return new Promise((resolve) => {
    layer(modal(title, `<div class="m-head"><h3>${esc(title)}</h3><p>${esc(body)}</p></div>`, `<button class="btn second" data-act="confirm-no">Cancel</button><button class="btn ${danger ? 'danger' : 'primary'}" data-act="confirm-yes" autofocus>${esc(ok)}</button>`));
    confirmBox.resolve = (v) => { confirmBox.resolve = null; closeLayer(); resolve(v); };
  });
}

// New agent (also used to edit one)
let draft = null;
async function openAgentForm(spec = {}) {
  const base0 = curWs()?.path || S.data.home;
  draft = { name: '', job: '', look: randLook(), operator: Object.keys(OPS).find((k) => k !== 'mavis' && S.data.operators[k]?.path) || 'claude-code', model: '', permission: 'ask', cwd: base0, ownBranch: false, repo: null, ...spec };
  draft.repo = (await lab.call('folder:info', draft.cwd).catch(() => null))?.repo || null;
  drawAgentForm();
}
function drawAgentForm() {
  const d = draft, editing = !!d.id, op = OPS[d.operator];
  const models = d.operator === 'codex' ? [['', 'Codex default'], ...(S.data.codexModels || []).map((m) => [m, m])] : op.models;
  const ops = ['claude-code', 'codex', 'cursor'];
  const repoOk = d.repo?.hasCommits && d.repo.branch && d.repo.branch !== 'HEAD';
  layer(modal(editing ? `Edit ${d.name}` : 'New agent', `
    <div class="m-head"><span id="dface">${avatar({ id: 'draft', look: d.look, last: null }, 80, null, false)}</span><button class="btn second pill-btn" data-act="form-face">New face</button><h3>${editing ? `Edit ${esc(d.name)}` : 'New agent'}</h3></div>
    <form class="m-body" id="agentForm">
      <div class="field"><label for="fName">Name</label><input id="fName" value="${esc(d.name)}" maxlength="24" placeholder="Juno" autofocus></div>
      <div class="field"><label for="fJob">Its job <span class="meta">optional</span></label><textarea id="fJob" placeholder="Reviews every pull request in this repo before I do">${esc(d.job)}</textarea><span class="hint-text">Left empty, it behaves exactly like ${op.name} normally does.</span></div>
      ${editing ? '' : `<div class="field"><span class="lbl">Runs on</span><div class="engines">${ops.map((k) => `<button type="button" class="${d.operator === k ? 'on' : ''}" data-act="form-op" data-id="${k}" ${S.data.operators[k]?.path ? '' : 'disabled title="Not installed"'}>${OPS[k].name}</button>`).join('')}</div></div>`}
      ${models.length > 1 ? `<div class="field"><label for="fModel">Model</label><select id="fModel">${models.map(([v, l]) => `<option value="${v}" ${d.model === v ? 'selected' : ''}>${l}</option>`).join('')}</select></div>` : ''}
      ${editing ? '' : `<div class="field"><span class="lbl">Works in</span><button type="button" class="path-btn" data-act="form-folder">${ic('folder')}<span>${esc(d.cwd)}</span></button></div>
      <label class="check ${repoOk ? '' : 'disabled'}"><input type="checkbox" id="fBranch" ${d.ownBranch && repoOk ? 'checked' : ''} ${repoOk ? '' : 'disabled'}><span>Its own branch and folder<span class="meta">${repoOk ? `Branches from ${esc(d.repo.branch)}. You review and merge its changes.` : 'Needs a git repository with at least one commit.'}</span></span></label>`}
      <div class="field"><label for="fPerm">What it may do</label><select id="fPerm">${Object.entries(PERMS).map(([v, l]) => `<option value="${v}" ${d.permission === v ? 'selected' : ''}>${l}</option>`).join('')}</select>${d.operator !== 'claude-code' ? `<span class="hint-text">${op.name} can’t pause to ask, so “Asks before changes” lets it edit inside its own sandbox.</span>` : ''}</div>
    </form>`,
    `${editing ? `<button class="btn danger" data-act="agent-delete" data-id="${d.id}">Remove agent</button>` : '<button class="btn second" data-act="close-layer-btn">Cancel</button>'}<button class="btn primary" data-act="form-save">${editing ? 'Save' : 'Add agent'}</button>`));
}
function syncDraft() {
  if (!draft) return;
  const v = (id) => document.getElementById(id);
  if (v('fName')) draft.name = v('fName').value;
  if (v('fJob')) draft.job = v('fJob').value;
  if (v('fModel')) draft.model = v('fModel').value;
  if (v('fPerm')) draft.permission = v('fPerm').value;
  if (v('fBranch')) draft.ownBranch = v('fBranch').checked;
  if (v('pName')) draft.name = v('pName').value;
  if (v('pJob')) draft.job = v('pJob').value;
}
async function saveAgentForm() {
  syncDraft();
  const d = draft;
  if (!d.name.trim()) { toast('Give it a name first.', true); document.getElementById('fName')?.focus(); return; }
  const btn = $('[data-act="form-save"]'); if (btn) { btn.disabled = true; btn.textContent = d.ownBranch ? 'Making its branch…' : 'Saving…'; }
  if (d.id) {
    const a = await run(() => lab.call('agent:update', d.id, { name: d.name.trim(), job: d.job, look: d.look, model: d.model || null, permission: d.permission }));
    if (a) { Object.assign(ag(d.id), a); closeLayer(); draft = null; render(true); toast('Saved'); } else if (btn) { btn.disabled = false; btn.textContent = 'Save'; }
    return;
  }
  const a = await run(() => lab.call('agent:create', { name: d.name.trim(), job: d.job, look: d.look, operator: d.operator, model: d.model || null, permission: d.permission, cwd: d.cwd, ownBranch: d.ownBranch, sessionId: d.sessionId || null, origin: d.origin || null }));
  if (!a) { if (btn) { btn.disabled = false; btn.textContent = 'Add agent'; } return; }
  S.data.agents.push(a); S.msgs.set(a.id, []);
  closeLayer(); draft = null; toast(`${a.name} joined`); go({ kind: 'dm', id: a.id });
}

// Make a chat an agent: it continues that very session, with decisions saved to Memory if you want.
async function openPromote() {
  const c = selectedChat(); if (!c) return;
  const repo = (await lab.call('folder:info', c.cwd).catch(() => null))?.repo || null;
  draft = { name: '', job: '', look: randLook(), chat: c, decisions: null, keep: [], repo, permission: 'ask', ownBranch: false };
  drawPromote();
}
function drawPromote() {
  const d = draft, c = d.chat, sameSession = c.operator !== 'mavis';
  layer(modal('Make this chat an agent', `
    <div class="m-head"><span id="dface">${avatar({ id: 'draft', look: d.look }, 80, null, false)}</span><button class="btn second pill-btn" data-act="form-face">New face</button><h3>Make this chat an agent</h3><p>${esc(clip(c.title, 70))}</p></div>
    <form class="m-body" id="promoForm">
      <div class="field"><label for="pName">Name</label><input id="pName" value="${esc(d.name)}" maxlength="24" placeholder="Juno" autofocus></div>
      <div class="field"><label for="pJob">Its job <span class="meta">optional</span></label><input id="pJob" value="${esc(d.job)}" placeholder="Owns checkout reliability"></div>
      <div class="field"><span class="lbl">Brings along</span><div class="pack">
        <div class="pack-row on">${ic('check', 16, 2)}<span>${sameSession ? `This exact ${OPS[c.operator].name} session<span class="meta">It continues the same conversation, so it remembers everything in it</span>` : 'This conversation, handed over as context<span class="meta">Sent as its first message</span>'}</span></div>
        <div class="pack-row on">${ic('check', 16, 2)}<span>Works in ${esc(base(c.cwd) || 'your home folder')}<span class="meta">${esc(c.cwd || S.data.home)}</span></span></div>
        ${d.decisions === null ? `<div class="pack-row"><span style="flex:1">Decisions from this chat<span class="meta">Claude reads the chat and lists them. You choose which to keep.</span></span><button type="button" class="btn second sm" data-act="find-decisions">Find them</button></div>`
          : d.decisions === 'loading' ? '<div class="pack-row"><span class="loading">Reading the chat for decisions</span></div>'
          : d.decisions.length ? d.decisions.map((t, i) => `<label class="pack-row"><input type="checkbox" data-keep="${i}" ${d.keep[i] ? 'checked' : ''}><span>${esc(t)}<span class="meta">Saved to Memory</span></span></label>`).join('')
          : '<div class="pack-row"><span class="meta">No decisions found in this chat</span></div>'}
      </div></div>
      ${sameSession && d.repo?.hasCommits ? '<p class="meta">It continues in the chat’s own folder. To give it a separate branch, make a new agent instead.</p>' : ''}
      <div class="field"><label for="fPerm">What it may do</label><select id="fPerm">${Object.entries(PERMS).map(([v, l]) => `<option value="${v}" ${d.permission === v ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
    </form>`,
    '<button class="btn second" data-act="close-layer-btn">Cancel</button><button class="btn primary" data-act="promo-save">Make agent</button>'));
}
async function findDecisions() {
  syncDraft(); const d = draft; d.decisions = 'loading'; drawPromote();
  const list = await run(() => lab.call('chat:decisions', d.chat.operator, d.chat.id));
  if (draft !== d) return;
  d.decisions = list || []; d.keep = d.decisions.map(() => true); drawPromote();
}
async function savePromote() {
  syncDraft();
  const d = draft, c = d.chat;
  if (!d.name.trim()) { toast('Give it a name first.', true); return; }
  document.querySelectorAll('[data-keep]').forEach((x) => { d.keep[+x.dataset.keep] = x.checked; });
  const btn = $('[data-act="promo-save"]'); if (btn) { btn.disabled = true; btn.textContent = 'Making…'; }
  const spec = { name: d.name.trim(), job: d.job, look: d.look, permission: d.permission, cwd: c.cwd || S.data.home, origin: { type: 'chat', operator: c.operator, ref: c.id, title: c.title } };
  if (c.operator === 'mavis') Object.assign(spec, { operator: 'claude-code' });
  else Object.assign(spec, { operator: c.operator, sessionId: c.id });
  const a = await run(() => lab.call('agent:create', spec));
  if (!a) { if (btn) { btn.disabled = false; btn.textContent = 'Make agent'; } return; }
  const kept = Array.isArray(d.decisions) ? d.decisions.filter((_, i) => d.keep[i]) : [];
  const ws = S.data.workspaces.find((w) => inDir(a.cwd, w.path));
  for (const t of kept) { const m = await run(() => lab.call('memory:add', t, ws?.id || null, `“${clip(c.title, 40)}”`)); if (m) S.data.memory.push(m); }
  S.data.agents.push(a); S.msgs.set(a.id, []);
  closeLayer(); draft = null;
  toast(`${a.name} joined${kept.length ? ` with ${kept.length} ${kept.length === 1 ? 'decision' : 'decisions'} in Memory` : ''}`);
  go({ kind: 'dm', id: a.id });
  if (c.operator === 'mavis') {
    const items = await lab.call('chat:transcript', c.operator, c.id);
    const text = items.filter((i) => i.role !== 'tool').map((i) => `${i.role === 'user' ? 'Me' : 'Mavis'}: ${i.text}`).join('\n\n');
    sendTo(a.id, `Here is an earlier conversation I had, titled “${c.title}”. Read it so you know where things stand, then tell me in a sentence or two what you understood.\n\n${text}`);
  }
}

// Hand a chat to an agent: a short hand-off note written from the chat, then the agent picks it up.
function openHandoff() {
  const c = selectedChat(); if (!c) return;
  const list = agents().slice().sort((a, b) => (inDir(b.cwd, c.cwd) || inDir(c.cwd, b.cwd) ? 1 : 0) - (inDir(a.cwd, c.cwd) || inDir(c.cwd, a.cwd) ? 1 : 0));
  layer(modal('Hand off this chat', `<div class="m-head"><h3>Hand off this chat</h3><p>Claude writes a short note of where things stand, and the agent you pick starts from it.</p></div>
    <div class="m-body">${list.length ? list.map((a) => `<button class="choice" data-act="handoff-go" data-id="${a.id}">${avatar(a, 40, 'var(--i3)')}<span class="grow-col"><span>${esc(a.name)}</span><span class="meta">${esc(statusLine(a))}</span></span><span class="meta">${STATE[stateOf(a)].label}</span></button>`).join('') : '<p class="meta">You have no agents yet. Make this chat an agent instead.</p>'}</div>`,
    '<span class="meta">The chat stays as it is</span><button class="btn second" data-act="close-layer-btn">Cancel</button>'));
}
async function handoffGo(agentId) {
  const c = selectedChat(), a = ag(agentId);
  if (!c || !a) return;
  if (S.runs.has(`agent:${a.id}`)) { toast(`${a.name} is still working. Try again when it’s done.`, true); return; }
  $('#layer .m-body').innerHTML = '<p class="loading">Writing the hand-off note</p>';
  const note = await run(() => lab.call('chat:summary', c.operator, c.id));
  closeLayer();
  if (note === undefined) return;
  go({ kind: 'dm', id: a.id });
  sendTo(a.id, `I’m handing you a ${OPS[c.operator].name} chat called “${c.title}” (folder: ${c.cwd || 'none'}). Here is where it stands:\n\n${note}\n\nPick it up from here.`);
}

// ⌘K: search agents and every chat, or hand text straight to an agent.
function openCmd() {
  layer(`<div class="backdrop" data-act="close-layer"><div class="overlay" role="dialog" aria-modal="true" aria-label="Search everything">
    <form class="cmd-in" id="cmdForm">${ic('search', 18)}<input id="cmdInput" placeholder="Find an agent or a chat, or type what you need" aria-label="Search everything" autocomplete="off" autofocus></form>
    <div class="cmd-list scroll" id="cmdList"></div>
    <div class="cmd-foot"><span><kbd>↵</kbd> open or hand off</span><span><kbd>↑</kbd> <kbd>↓</kbd> choose</span><span><kbd>esc</kbd> close</span></div></div></div>`);
  S.cmdSel = 0; cmdList();
  Promise.all(['claude-code', 'codex'].filter((k) => S.data.operators[k]?.path).map((k) => loadChats(k))).then(() => { if ($('#cmdList')) cmdList(); }, () => {});
}
function cmdRows() {
  const q = ($('#cmdInput')?.value || '').trim(), t = q.toLowerCase();
  const as = agents().filter((a) => !t || `${a.name} ${a.job}`.toLowerCase().includes(t) || q.length > 12).slice(0, 6);
  const chats = t ? ['claude-code', 'codex', 'mavis'].flatMap((k) => (k === 'mavis' && S.data.imported && !S.chats.mavis ? (loadChats('mavis'), []) : visibleChats(k)).filter((c) => `${c.title} ${c.cwd}`.toLowerCase().includes(t)).slice(0, 4)) : [];
  return { q, as, chats };
}
function cmdList() {
  const { q, as, chats } = cmdRows();
  const total = as.length + chats.length; S.cmdSel = Math.max(0, Math.min(S.cmdSel, total - 1));
  const long = q.length > 12;
  $('#cmdList').innerHTML = (as.length ? `<div class="cmd-label">${long ? 'Hand it to' : 'Agents'}</div>` : '') + as.map((a, i) => `<button class="cmd-row ${i === S.cmdSel ? 'on' : ''}" data-act="cmd-agent" data-id="${a.id}">${avatar(a, 32, i === S.cmdSel ? 'var(--i4)' : 'var(--i2)')}<span class="grow-col"><span>${long ? `Hand to ${esc(a.name)}` : esc(a.name)}</span><span class="meta ellipsis">${long ? esc(clip(q, 80)) : esc(statusLine(a))}</span></span><span class="go">${STATE[stateOf(a)].label}</span></button>`).join('')
    + (chats.length ? `<div class="cmd-label">Chats</div>${chats.map((c, j) => { const i = as.length + j; return `<button class="cmd-row ${i === S.cmdSel ? 'on' : ''}" data-act="open-chat" data-op="${c.operator}" data-id="${esc(c.id)}">${tile(c.operator)}<span class="grow-col"><span class="ellipsis">${esc(c.title)}</span><span class="meta ellipsis">${OPS[c.operator].name} · ${esc(base(c.cwd) || 'No folder')} · ${ago(c.updated)}</span></span><span class="go">Open</span></button>`; }).join('')}` : '')
    + (!total ? `<div class="empty"><div>${agents().length ? 'Nothing matches' : 'No agents yet'}</div><div>${agents().length ? 'Try other words' : 'Press ⌘N to make one'}</div></div>` : '');
}
function cmdGo(row) {
  if (!row) return;
  const q = ($('#cmdInput')?.value || '').trim();
  if (row.dataset.act === 'open-chat') { closeLayer(); openChat(row.dataset.op, row.dataset.id); return; }
  const a = ag(row.dataset.id); closeLayer();
  go({ kind: 'dm', id: a.id });
  if (q.length > 12) sendTo(a.id, q);
}

async function openChat(op, id) {
  S.opq = '';
  await loadChats(op).catch(() => {});
  const c = (S.chats[op] || []).find((x) => x.id === id);
  if (c && S.space !== 'home' && !chatIn(c)) S.space = 'home';
  go({ kind: 'op', id: op, chat: id });
}

// ---------------------------------------------------------------- sending
async function sendTo(agentId, text) {
  const key = await run(() => lab.call('agent:send', agentId, text));
  if (key) { if (!S.runs.has(key)) S.runs.set(key, { key, agentId, operator: ag(agentId)?.operator, startedAt: Date.now(), activity: 'Starting' }); scheduleRender(false); }
}
async function sendChat(key, text) {
  const [, op, ...rest] = key.split(':'); const id = rest.join(':');
  const live = S.live.get(key) || []; live.push({ role: 'user', text }); S.live.set(key, live);
  const r = await run(() => lab.call('chat:send', op, id, text));
  if (r && !S.runs.has(key)) S.runs.set(key, { key, chat: { operator: op, id }, operator: op, startedAt: Date.now(), activity: 'Starting' });
  else live.pop();
  renderView(false); renderNow();
}

// ---------------------------------------------------------------- events from the engine
lab.on(async (ev) => {
  switch (ev.type) {
    case 'run': S.runs.set(ev.run.key, ev.run); scheduleRender(); break;
    case 'run-end':
      S.runs.delete(ev.key); S.drafts.delete(ev.key);
      if (ev.agentId) { await reloadAgents(); reviewCache.delete(ev.agentId); if (ev.error && ev.error !== 'Stopped.' && !(S.view.kind === 'dm' && S.view.id === ev.agentId)) toast(`${ag(ev.agentId)?.name || 'An agent'} stopped: ${ev.error}`, true); refreshOverlaps(); }
      scheduleRender(); break;
    case 'delta': {
      S.drafts.set(ev.key, ev.text);
      const el = document.querySelector(`[data-draft="${CSS.escape(ev.key)}"]`);
      if (el) { el.innerHTML = md(ev.text); const v = $('#paneDetail') || $('#view'); if (v.scrollHeight - v.scrollTop - v.clientHeight < 120) v.scrollTop = v.scrollHeight; }
      else scheduleRender();
      break;
    }
    case 'messages': S.msgs.set(ev.agentId, await lab.call('agent:messages', ev.agentId)); S.drafts.delete(`agent:${ev.agentId}`); scheduleRender(); break;
    case 'approvals': S.approvals = await lab.call('approvals'); scheduleRender(); break;
    case 'chat-line': { const l = S.live.get(ev.key) || []; l.push(ev.line); S.live.set(ev.key, l); S.drafts.delete(ev.key); scheduleRender(); break; }
    case 'chat-end': {
      const [, op, ...rest] = ev.key.split(':'); const id = rest.join(':');
      try { S.transcripts.set(`${op}:${id}`, await lab.call('chat:transcript', op, id)); S.live.delete(ev.key); } catch {}
      if (ev.error && ev.error !== 'Stopped.') toast(ev.error, true);
      loadChats(op, true).then(() => scheduleRender(), () => {}); break;
    }
    case 'git': refreshOverlaps(); break;
    case 'command':
      if (ev.command === 'search') openCmd();
      if (ev.command === 'new-agent') openAgentForm();
      if (ev.command === 'toggle-now') { S.nowHidden = !S.nowHidden; render(true); }
      break;
  }
});

// ---------------------------------------------------------------- input
document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-act]'); if (!t || t.disabled) return;
  const act = t.dataset.act, id = t.dataset.id;
  if (act === 'close-layer' && e.target !== t) return;
  switch (act) {
    case 'space': S.space = id; S.tab = 'all'; S.opq = ''; go(S.view.kind === 'op' ? { kind: 'op', id: S.view.id } : { kind: 'agents' }); break;
    case 'view': go({ kind: id }); break;
    case 'tab': S.tab = id; go({ kind: 'agents' }); break;
    case 'dm': e.stopPropagation(); go({ kind: 'dm', id }); break;
    case 'op': S.opq = ''; go({ kind: 'op', id }); break;
    case 'pick': pickChat(id); break;
    case 'open-chat': closeLayer(); openChat(t.dataset.op, id); break;
    case 'fold': S.fold[id] = !S.fold[id]; renderSide(); break;
    case 'cmd': openCmd(); break;
    case 'cmd-agent': cmdGo(t); break;
    case 'new-agent': openAgentForm(t.dataset.op ? { operator: t.dataset.op } : {}); break;
    case 'agent-edit': { const a = ag(id); if (a) { draft = { ...a, model: a.model || '', ownBranch: false }; drawAgentForm(); } break; }
    case 'agent-delete': {
      const a = ag(id); if (!a) break;
      const ok = await confirmBox({ title: `Remove ${a.name}?`, body: a.worktree ? `Its conversation here is deleted. Its branch ${a.branch} stays in the repository; its folder is removed.` : 'Its conversation here is deleted. Nothing in its folder changes.', ok: 'Remove', danger: true });
      if (ok && (await run(() => lab.call('agent:delete', a.id)))) { S.data.agents = agents().filter((x) => x.id !== a.id); S.msgs.delete(a.id); go({ kind: 'agents' }); toast(`${a.name} removed`); }
      break;
    }
    case 'form-face': syncDraft(); draft.look = randLook(); $('#dface').innerHTML = avatar({ id: 'draft', look: draft.look }, 80, null, false); break;
    case 'form-op': syncDraft(); draft.operator = id; draft.model = ''; drawAgentForm(); break;
    case 'form-folder': { syncDraft(); const p = await run(() => lab.call('folder:pick', 'Where should this agent work?')); if (p) { draft.cwd = p; draft.repo = (await lab.call('folder:info', p).catch(() => null))?.repo || null; draft.ownBranch = false; } drawAgentForm(); break; }
    case 'form-save': saveAgentForm(); break;
    case 'promote': openPromote(); break;
    case 'find-decisions': findDecisions(); break;
    case 'promo-save': savePromote(); break;
    case 'handoff': openHandoff(); break;
    case 'handoff-go': handoffGo(id); break;
    case 'close-layer': case 'close-layer-btn': closeLayer(); draft = null; break;
    case 'confirm-yes': confirmBox.resolve?.(true); break;
    case 'confirm-no': confirmBox.resolve?.(false); break;
    case 'approve': { S.approvals = S.approvals.filter((p) => p.id !== id); scheduleRender(); await run(() => lab.call('approval:answer', id, t.dataset.decision)); break; }
    case 'stop': run(() => lab.call('run:stop', id)); break;
    case 'review': go({ kind: 'review', id }); break;
    case 'file': { const r = reviewCache.get(S.view.id); if (r?.files) { r.open = r.open === id ? null : id; renderView(true); } break; }
    case 'merge': {
      const a = ag(S.view.id); if (!a) break;
      t.disabled = true;
      const r = await run(() => lab.call('git:merge', a.id));
      if (r) { toast(`Merged ${r.merged} ${r.merged === 1 ? 'file' : 'files'} into ${a.baseBranch}`); reviewCache.delete(a.id); refreshOverlaps(); renderView(false); } else t.disabled = false;
      break;
    }
    case 'discard': {
      const a = ag(S.view.id); if (!a) break;
      const ok = await confirmBox({ title: `Discard ${a.name}’s changes?`, body: `Every change on ${a.branch} since it started is deleted. This can’t be undone. ${a.baseBranch} is untouched.`, ok: 'Discard changes', danger: true });
      if (ok && (await run(() => lab.call('git:discard', a.id)))) { reviewCache.delete(a.id); refreshOverlaps(); renderView(false); toast('Discarded'); }
      break;
    }
    case 'ask-changes': { const a = ag(S.view.id); go({ kind: 'dm', id: a.id }); const i = $('#cmpInput'); if (i) { i.value = 'About your changes: '; i.focus(); autoGrow(); } break; }
    case 'open-folder': if (t.dataset.path) run(() => lab.call('open:folder', t.dataset.path)); break;
    case 'mem-remove': if (await run(() => lab.call('memory:remove', id))) { S.data.memory = S.data.memory.filter((d) => d.id !== id); renderView(true); } break;
    case 'ws-add': { const p = await run(() => lab.call('folder:pick', 'Add a workspace folder')); if (p) addWorkspace(p); break; }
    case 'ws-add-path': addWorkspace(t.dataset.path); break;
    case 'ws-remove': if (await run(() => lab.call('workspace:remove', id))) { S.data.workspaces = S.data.workspaces.filter((w) => w.id !== id); if (S.space === id) S.space = 'home'; render(true); } break;
    case 'mavis-scan': { t.disabled = true; t.textContent = 'Checking…'; S.mavis = await run(() => lab.call('mavis:scan')) || { found: false, bots: 0, chats: 0 }; renderView(true); break; }
    case 'mavis-import': {
      t.disabled = true; t.textContent = 'Bringing in…';
      const r = await run(() => lab.call('mavis:import', [randLook(), randLook(), randLook(), randLook()]));
      if (r) { await loadState(); S.chats.mavis = null; S.mavis = await lab.call('mavis:scan').catch(() => S.mavis); render(true); toast(`Brought in ${r.chats} conversations${r.agents ? ` and ${r.agents} ${r.agents === 1 ? 'agent' : 'agents'}` : ''}`); }
      else { t.disabled = false; t.textContent = 'Bring them in'; }
      break;
    }
    case 'mavis-start': go({ kind: 'connections' }); S.mavis = await run(() => lab.call('mavis:scan')) || S.mavis; renderView(true); break;
    case 'now-toggle': S.nowHidden = !S.nowHidden; render(true); break;
    case 'now-close': closeDrawers(); break;
  }
});
async function addWorkspace(p) {
  const w = await run(() => lab.call('workspace:add', p));
  if (w) { if (!S.data.workspaces.some((x) => x.id === w.id)) S.data.workspaces.push(w); S.space = w.id; go({ kind: 'agents' }); toast(`${w.name} added`); }
}

document.addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  if (f.id === 'cmpForm') {
    const i = $('#cmpInput'), text = i.value.trim(); if (!text) return;
    const key = f.dataset.key; i.value = ''; autoGrow();
    if (key.startsWith('agent:')) sendTo(key.slice(6), text); else sendChat(key, text);
  } else if (f.id === 'cmdForm') cmdGo(document.querySelectorAll('.cmd-row')[S.cmdSel]);
  else if (f.id === 'agentForm') saveAgentForm();
  else if (f.id === 'promoForm') savePromote();
  else if (f.id === 'memForm') {
    const text = $('#memInput').value.trim(); if (!text) return;
    const d = await run(() => lab.call('memory:add', text, $('#memScope').value || null, null));
    if (d) { S.data.memory.push(d); renderView(true); $('#memInput')?.focus(); toast(`Saved as decision #${d.n}`); }
  }
});

document.addEventListener('keydown', (e) => {
  const inField = /INPUT|TEXTAREA|SELECT/.test(e.target.tagName);
  if (e.target.id === 'cmpInput' && e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); $('#cmpForm')?.requestSubmit(); return; }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openCmd(); return; }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'n') { e.preventDefault(); openAgentForm(); return; }
  if (e.key === 'Escape') { if ($('#layer').innerHTML) { confirmBox.resolve ? confirmBox.resolve(false) : closeLayer(); confirmBox.resolve = null; draft = null; } else closeDrawers(); return; }
  if ((e.metaKey || e.ctrlKey) && !e.altKey && /^[1-9]$/.test(e.key) && S.quick[+e.key - 1]) { e.preventDefault(); go({ kind: 'dm', id: S.quick[+e.key - 1] }); return; }
  if (e.target.id === 'cmdInput') {
    const n = document.querySelectorAll('.cmd-row').length;
    if (n && e.key === 'ArrowDown') { e.preventDefault(); S.cmdSel = (S.cmdSel + 1) % n; cmdList(); }
    if (n && e.key === 'ArrowUp') { e.preventDefault(); S.cmdSel = (S.cmdSel - 1 + n) % n; cmdList(); }
    return;
  }
  if (S.view.kind === 'op' && (e.key === 'ArrowDown' || e.key === 'ArrowUp') && !inField && !$('#layer').innerHTML) {
    const ids = [...document.querySelectorAll('.crow')].map((x) => x.dataset.id);
    if (ids.length) { e.preventDefault(); const i = ids.indexOf(S.view.chat); pickChat(ids[Math.max(0, Math.min(ids.length - 1, (i < 0 ? 0 : i) + (e.key === 'ArrowDown' ? 1 : -1)))]); }
    return;
  }
  if ((e.key === 'Enter' || e.key === ' ') && e.target.classList?.contains('arow')) { e.preventDefault(); go({ kind: 'dm', id: e.target.dataset.id }); }
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'cmdInput') { S.cmdSel = 0; cmdList(); }
  if (e.target.id === 'opq') { S.opq = e.target.value; renderView(true); }
  if (e.target.id === 'cmpInput') autoGrow();
});
function autoGrow() { const i = $('#cmpInput'); if (!i) return; i.style.height = 'auto'; i.style.height = `${Math.min(200, i.scrollHeight)}px`; }
$('#scrim').addEventListener('click', closeDrawers);

// Live clocks in Right now.
setInterval(() => { document.querySelectorAll('[data-since]').forEach((el) => { el.textContent = elapsed(+el.dataset.since); }); }, 1000);

// ---------------------------------------------------------------- start
(async () => {
  try {
    await loadState();
    render(false);
    if (S.data.operators['claude-code']?.path) loadChats('claude-code').then(() => scheduleRender(), () => {});
    if (S.data.operators.codex?.path) loadChats('codex').then(() => scheduleRender(), () => {});
    if (S.data.imported) loadChats('mavis').then(() => scheduleRender(), () => {});
  } catch (e) {
    document.body.innerHTML = `<div class="empty-hero"><h2>Agent Lab couldn’t start</h2><p>${esc(e.message)}</p></div>`;
  }
})();

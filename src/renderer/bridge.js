// In the browser: the same `window.lab` the app expects, over HTTP to the local engine.
(() => {
  // ?empty: an empty Agent Lab (no agents, workspaces, rules or runs). The reference the native
  // app is matched against, pixel for pixel. Every call answers with nothing; nothing is saved.
  if (new URLSearchParams(location.search).has('empty')) {
    const EMPTY = {
      state: { agents: [], workspaces: [], memory: [], runs: [], approvals: [], operators: {}, codexModels: [], imported: 0, home: '/Users/you' },
      agents: [], approvals: [], 'chats:list': [], 'agent:messages': [], 'git:overlaps': [], 'mavis:scan': [],
    };
    window.lab = { call: async (m) => structuredClone(EMPTY[m] ?? null), on: () => () => {} };
    return;
  }
  const token = document.querySelector('meta[name="lab-token"]')?.content;
  if (!token || window.lab) return;
  const fns = new Set();
  const call = async (method, ...params) => {
    const r = await fetch('/call', { method: 'POST', headers: { 'content-type': 'application/json', 'x-lab-token': token }, body: JSON.stringify({ method, params }) }).then((x) => x.json());
    if (!r.ok) throw new Error(r.error);
    return r.value;
  };
  const es = new EventSource(`/events?t=${token}`);
  es.onmessage = (e) => { let ev; try { ev = JSON.parse(e.data); } catch { return; } for (const fn of fns) fn(ev); };
  // ⌥⌘0 came from the Electron menu; in the browser it is a key.
  document.addEventListener('keydown', (e) => {
    if (e.altKey && (e.metaKey || e.ctrlKey) && e.code === 'Digit0') { e.preventDefault(); for (const fn of fns) fn({ type: 'command', command: 'toggle-now' }); }
  });
  window.lab = { call, on: (fn) => { fns.add(fn); return () => fns.delete(fn); } };
})();

// Design-system auditor. Deliberate exception: the workspace/Messages columns use 10px sides (asked for: between 8 and 12).
// Temporary design-system auditor. Measures what actually renders against the system rules.
// Run in the page: (await import('/audit.js?' + Date.now())).audit()
const TYPE = [12, 14, 16, 20, 24, 28];
const LH = { 12: 16, 14: 20, 16: 24, 20: 28, 24: 32, 28: 36 };
const RADII = [0, 2, 4, 6, 8, 10, 12, 14, 16]; // 2, 4 = nested corners (14 minus padding)
const px = (v) => parseFloat(v) || 0;
const vis = (el) => { const r = el.getBoundingClientRect(); if (r.width < 1 || r.height < 1) return false; const s = getComputedStyle(el); return s.visibility !== 'hidden' && s.display !== 'none' && +s.opacity !== 0; };
const name = (el) => {
  const c = typeof el.className === 'string' ? el.className.trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.') : '';
  return el.tagName.toLowerCase() + (c ? '.' + c : '') + (el.dataset?.act ? `[${el.dataset.act}]` : '');
};
const interactive = (el) => el.matches('button, a[href], input:not([type=hidden]), select, textarea, [role=menuitem], [role=tab], [data-act]');
const off4 = (n) => { const a = Math.abs(Math.round(n * 100) / 100); return a !== 0 && a % 4 !== 0; };

export function audit(root = document.body) {
  const out = { spacing: [], height: [], type: [], lineHeight: [], radius: [], radiusScale: [], target: [] };
  const add = (k, el, v) => { const key = `${name(el)} · ${v}`; if (!out[k].includes(key)) out[k].push(key); };
  for (const el of root.querySelectorAll('*')) {
    if (el.closest('.eg, .wspic, .av, [data-optical]') && !interactive(el)) continue;
    if (el.matches('.backdrop')) continue;
    if (el.closest('svg') || el.tagName === 'svg' || el.tagName === 'SCRIPT' || el.tagName === 'STYLE' || !vis(el)) continue;
    const s = getComputedStyle(el), r = el.getBoundingClientRect();
    // 1. spacing scale: padding, margin, gap on the 4px grid
    for (const p of ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft']) {
      const v = px(s[p]); if (off4(v) && !(p.startsWith('margin') && (Math.abs(v) > 64 || (Math.abs(v) > 16 && v % 1))) && !el.matches('[data-optical]') && !(el.matches('.wsx .pane-list, .msgs .pane-list') && v === 10)) add('spacing', el, `${p} ${v}`);
    }
    if (/flex|grid/.test(s.display)) for (const p of ['rowGap', 'columnGap']) { const v = px(s[p]); if (s[p] !== 'normal' && v > 1 && off4(v)) add('spacing', el, `${p} ${v}`); }
    // heights of controls on the grid
    if (interactive(el) && !el.matches('textarea') && off4(r.height)) add('height', el, `h ${Math.round(r.height * 10) / 10}`);
    // 4. type scale, with paired line heights
    const hasText = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (hasText) {
      const fs = Math.round(px(s.fontSize) * 100) / 100;
      if (!TYPE.includes(fs)) add('type', el, `font ${fs}`);
      else if (s.lineHeight !== 'normal' && Math.abs(px(s.lineHeight) - LH[fs]) > 0.5 && !el.matches('input, textarea')) add('lineHeight', el, `${fs}/${Math.round(px(s.lineHeight) * 10) / 10}`);
    }
    // 3. radius: on the scale, and nested radius = outer - inset
    const rad = px(s.borderTopLeftRadius);
    if (rad > 0 && rad < 100 && Math.min(r.width, r.height) / 2 - rad > 0.5 && !RADII.includes(Math.round(rad))) add('radiusScale', el, `radius ${rad}`);
    if (rad > 0 && rad < 100 && Math.min(r.width, r.height) / 2 - rad > 0.5) {
      let p = el.parentElement;
      while (p && p !== document.body) {
        const ps = getComputedStyle(p), b0 = p.getBoundingClientRect();
        const left = r.left - b0.left < b0.right - r.right, top = r.top - b0.top < b0.bottom - r.bottom;
        const pr = px(ps[`border${top ? 'Top' : 'Bottom'}${left ? 'Left' : 'Right'}Radius`]);
        const painted = ps.backgroundColor !== 'rgba(0, 0, 0, 0)' || ps.boxShadow !== 'none' || px(ps.borderTopWidth) > 0;
        if (painted && (pr > 0 || px(ps.borderTopLeftRadius) > 0)) {
          if (!(pr > 0 && pr < 100)) break;
          const b = p.getBoundingClientRect(), inset = Math.max(left ? r.left - b.left : b.right - r.right, top ? r.top - b.top : b.bottom - r.bottom); // distance into that corner's curve
          const inside = r.left >= b.left - 1 && r.right <= b.right + 1 && r.top >= b.top - 1 && r.bottom <= b.bottom + 1;
          if (inside && inset >= 0 && inset < pr) { const want = Math.max(pr - inset, 0); if (Math.abs(want - rad) > 1) add('radius', el, `${rad} in ${name(p)} ${pr} inset ${Math.round(inset)} → want ${want}`); }
          break;
        }
        p = p.parentElement;
      }
    }
    // 9. targets: 44px hit area (the element or its ::after hit box)
    if (interactive(el) && !el.matches('input, textarea, select')) {
      const a = getComputedStyle(el, '::after'); const hit = a.content !== 'none' && a.position === 'absolute' ? Math.min(px(a.width), px(a.height)) : 0;
      if (Math.max(Math.min(r.width, r.height), hit) < 44 && Math.min(r.width, r.height) < 44) add('target', el, `${Math.round(r.width)}×${Math.round(r.height)}`);
    }
  }
  const counts = Object.fromEntries(Object.entries(out).map(([k, v]) => [k, v.length]));
  return { counts, ...out };
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const esc = () => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
export async function auditAll() {
  const go = async (id) => { (document.querySelector(`#side [data-act=view][data-id=${id}]`) || document.querySelector(`[data-act=view][data-id=${id}]`))?.click(); await wait(500); };
  const steps = {
    home: () => go('agents'), discover: () => go('discover'), review: () => go('reviews'), messages: () => go('messages'),
    playbook: () => go('memory'), usage: () => go('usage'), plugins: () => go('connections'), profile: () => go('profile'),
    settings: async () => { await go('agents'); document.querySelector('[data-act=set-open]').click(); await wait(300); },
    newAgent: async () => { document.querySelector('[data-act=set-open]')?.click(); await wait(200); document.querySelector('.top-tools [data-act=new-agent]').click(); await wait(400); },
    search: async () => { esc(); await wait(300); document.querySelector('.top-tools [data-act=cmd]').click(); await wait(400); },
    chat: async () => { esc(); await wait(300); await go('agents'); document.querySelector('.hx-row, [data-act=dm]')?.click(); await wait(600); },
  };
  const screens = {}, merged = {};
  for (const [n, fn] of Object.entries(steps)) {
    await fn(); const a = audit(); screens[n] = a.counts;
    for (const [k, list] of Object.entries(a)) if (k !== 'counts') for (const e of list) ((merged[k] ||= {})[e] ||= []).push(n);
  }
  esc(); await go('agents');
  return { screens, findings: Object.fromEntries(Object.entries(merged).map(([k, v]) => [k, Object.entries(v).map(([e, s]) => `${e}   [${s.join(', ')}]`)])) };
}

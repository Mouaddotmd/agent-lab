// Agent Lab interface. Every screen draws from real data the engine sends; nothing here is example content.
const lab = window.lab;
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clip = (s, n = 90) => { const t = String(s ?? '').replace(/\s+/g, ' ').trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };
const base = (p) => String(p || '').split('/').filter(Boolean).pop() || p || '';

const OPS = {
  'claude-code': { name: 'Claude Code', ab: 'CC', chats: true, models: [['', 'Claude Code default'], ['claude-opus-5-5', 'Opus 5.5'], ['claude-sonnet-5-5', 'Sonnet 5.5'], ['claude-haiku-5-5', 'Haiku 5.5']] },
  codex: { name: 'Codex', ab: 'Cx', chats: true, models: [['', 'Codex default']] },
  mavis: { name: 'Mavis', ab: 'Mv', chats: true, models: [] },
};
const PERMS = { ask: 'Asks before changes', edits: 'Edits files freely', plan: 'Plans only' };
const STATE = { needs: { label: 'Waiting for you', o: 0 }, working: { label: 'Working', o: 1 }, failed: { label: 'Failed', o: 2 }, done: { label: 'Done', o: 3 }, idle: { label: 'Ready', o: 4 } };

const S = {
  data: null, runs: new Map(), approvals: [], drafts: new Map(), msgs: new Map(), chats: {}, transcripts: new Map(), live: new Map(),
  overlaps: [], tq: '', chatsLimit: 25, mfilter: 'all', mfOpen: false, theme: (() => { try { return localStorage.getItem('theme') === 'light' ? 'light' : 'dark'; } catch { return 'dark'; } })(), wall: (() => { try { const v = localStorage.getItem('wall'); return ['socrates', 'constitution', 'carthage', 'battle'].includes(v) ? v : 'socrates'; } catch { return 'socrates'; } })(), agq: '', mq: '', lastDm: null, preview: false, homeAgent: null, pickOpen: false, space: 'home', view: { kind: 'agents' }, tab: 'all', fold: {}, nowHidden: false, opq: '', cmdSel: 0, quick: [], mavis: null,
};

// ---------------------------------------------------------------- helpers
// Icons: Hugeicons free set (MIT, see hugeicons-LICENSE.md), stroke 1.5 on a 24 grid.
const I = { "code": "<path d=\"M17 8L18.84 9.85C19.61 10.62 20 11.01 20 11.5C20 11.99 19.61 12.38 18.84 13.15L17 15\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M7 8L5.16 9.85C4.39 10.62 4 11.01 4 11.5C4 11.99 4.39 12.38 5.16 13.15L7 15\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M14.5 4L9.5 20\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "mic": "<path d=\"M17 7V11C17 13.76 14.76 16 12 16C9.24 16 7 13.76 7 11V7C7 4.24 9.24 2 12 2C14.76 2 17 4.24 17 7Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M20 11C20 15.42 16.42 19 12 19M12 19C7.58 19 4 15.42 4 11M12 19V22\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "file": "<path d=\"M20 13V10.66C20 9.84 20 9.43 19.85 9.06C19.7 8.7 19.41 8.41 18.83 7.83L14.09 3.09C13.59 2.59 13.34 2.34 13.03 2.2C12.51 1.95 12.16 2 11.46 2C8.21 2 6.59 2 5.49 2.89C5.27 3.07 5.07 3.27 4.89 3.49C4 4.59 4 6.21 4 9.46V14C4 17.77 4 19.66 5.17 20.83C6.34 22 8.23 22 12 22H20\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M13 2.5V3C13 5.83 13 7.24 13.88 8.12C14.76 9 16.17 9 19 9H19.5\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "personAdd": "<path d=\"M12.5 22H6.59C5.04 22 3.81 21.25 2.7 20.19C0.5 18.08 4.1 16.4 5.48 15.58C7.86 14.16 10.75 13.77 13.5 14.42\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M16.5 6.5C16.5 8.99 14.49 11 12 11C9.51 11 7.5 8.99 7.5 6.5C7.5 4.01 9.51 2 12 2C14.49 2 16.5 4.01 16.5 6.5Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M18.5 22V15M15 18.5H22\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "arrowL": "<path d=\"M4 12H20\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M9 17C9 17 4 13.32 4 12C4 10.68 9 7 9 7\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "arrowR": "<path d=\"M20 12H4\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M15 17C15 17 20 13.32 20 12C20 10.68 15 7 15 7\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "clock": "<circle cx=\"12\" cy=\"12\" r=\"10\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M12 8V12L14 14\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "compass": "<circle cx=\"12\" cy=\"12\" r=\"10\" stroke=\"currentColor\" stroke-width=\"1.5\"/><path d=\"M14.9 9.1L13.2 13.2L9.1 14.9L10.8 10.8L14.9 9.1Z\" stroke=\"currentColor\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "chart": "<path d=\"M7 17V13M12 17V7M17 17V10\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-width=\"1.5\"/><path d=\"M2.5 12C2.5 7.52 2.5 5.28 3.89 3.89C5.28 2.5 7.52 2.5 12 2.5C16.48 2.5 18.72 2.5 20.11 3.89C21.5 5.28 21.5 7.52 21.5 12C21.5 16.48 21.5 18.72 20.11 20.11C18.72 21.5 16.48 21.5 12 21.5C7.52 21.5 5.28 21.5 3.89 20.11C2.5 18.72 2.5 16.48 2.5 12Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/>", "shield": "<path d=\"M21 11.18V8.28C21 6.64 21 5.82 20.6 5.29C20.2 4.75 19.28 4.49 17.46 3.97C16.21 3.62 15.12 3.2 14.25 2.81C13.06 2.28 12.46 2.02 12 2.02C11.54 2.02 10.94 2.28 9.75 2.81C8.88 3.2 7.79 3.62 6.54 3.97C4.72 4.49 3.8 4.75 3.4 5.29C3 5.82 3 6.64 3 8.28V11.18C3 16.8 8.06 20.17 10.59 21.51C11.2 21.83 11.5 21.99 12 21.99C12.5 21.99 12.8 21.83 13.41 21.51C15.94 20.17 21 16.8 21 11.18Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-width=\"1.5\"/>", "chip": "<path d=\"M4 12C4 8.23 4 6.34 5.17 5.17C6.34 4 8.23 4 12 4C15.77 4 17.66 4 18.83 5.17C20 6.34 20 8.23 20 12C20 15.77 20 17.66 18.83 18.83C17.66 20 15.77 20 12 20C8.23 20 6.34 20 5.17 18.83C4 17.66 4 15.77 4 12Z\" stroke=\"currentColor\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M8 2V4M16 2V4M12 2V4M8 20V22M12 20V22M16 20V22M22 16H20M22 8H20M4 16H2M4 8H2M4 12H2M22 12H20\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-width=\"1.5\"/><path d=\"M9.5 9.5H14.5V14.5H9.5Z\" stroke=\"currentColor\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "mac": "<path d=\"M14 21H16M10 21H8M10 21V18M14 21V18\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-width=\"1.5\"/><path d=\"M2 10C2 6.23 2 4.34 3.17 3.17C4.34 2 6.23 2 10 2H14C17.77 2 19.66 2 20.83 3.17C22 4.34 22 6.23 22 10C22 13.77 22 15.66 20.83 16.83C19.66 18 17.77 18 14 18H10C6.23 18 4.34 18 3.17 16.83C2 15.66 2 13.77 2 10Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/>", "inbox": "<path d=\"M2 12.5H6.9C7.53 12.5 8.08 12.9 8.27 13.5L8.73 14.5C8.92 15.1 9.47 15.5 10.1 15.5H13.9C14.53 15.5 15.08 15.1 15.27 14.5L15.73 13.5C15.92 12.9 16.47 12.5 17.1 12.5H22\" stroke=\"currentColor\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M2 12C2 7.29 2 4.93 3.46 3.46C4.93 2 7.29 2 12 2C16.71 2 19.07 2 20.54 3.46C22 4.93 22 7.29 22 12C22 16.71 22 19.07 20.54 20.54C19.07 22 16.71 22 12 22C7.29 22 4.93 22 3.46 20.54C2 19.07 2 16.71 2 12Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/>", "gear": "<path d=\"M15.5 12C15.5 13.93 13.93 15.5 12 15.5C10.07 15.5 8.5 13.93 8.5 12C8.5 10.07 10.07 8.5 12 8.5C13.93 8.5 15.5 10.07 15.5 12Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/><path d=\"M21.01 14.1C21.53 13.96 21.79 13.89 21.9 13.75C22 13.62 22 13.4 22 12.97V11.03C22 10.6 22 10.38 21.9 10.25C21.79 10.11 21.53 10.04 21.01 9.9C19.06 9.38 17.84 7.34 18.34 5.4C18.48 4.87 18.55 4.6 18.49 4.44C18.42 4.29 18.23 4.18 17.85 3.96L16.13 2.98C15.75 2.77 15.57 2.67 15.4 2.69C15.23 2.71 15.04 2.9 14.67 3.28C13.21 4.73 10.79 4.73 9.33 3.28C8.96 2.9 8.77 2.71 8.6 2.69C8.43 2.67 8.25 2.77 7.87 2.98L6.15 3.96C5.77 4.18 5.58 4.29 5.51 4.44C5.45 4.6 5.52 4.87 5.66 5.4C6.16 7.34 4.94 9.38 2.99 9.9C2.47 10.04 2.21 10.11 2.1 10.25C2 10.38 2 10.6 2 11.03V12.97C2 13.4 2 13.62 2.1 13.75C2.21 13.89 2.47 13.96 2.99 14.1C4.94 14.62 6.16 16.66 5.66 18.6C5.52 19.13 5.45 19.4 5.51 19.56C5.58 19.71 5.77 19.82 6.15 20.04L7.87 21.02C8.25 21.23 8.43 21.33 8.6 21.31C8.77 21.29 8.96 21.1 9.33 20.72C10.79 19.27 13.21 19.27 14.67 20.72C15.04 21.1 15.23 21.29 15.4 21.31C15.57 21.33 15.75 21.23 16.13 21.02L17.85 20.04C18.23 19.82 18.42 19.71 18.49 19.56C18.55 19.4 18.48 19.13 18.34 18.6C17.84 16.66 19.06 14.62 21.01 14.1Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-width=\"1.5\"/>", "moon": "<path d=\"M21.5 14.0784C20.3003 14.7189 18.9301 15.0821 17.4751 15.0821C12.7491 15.0821 8.91792 11.2509 8.91792 6.52485C8.91792 5.06986 9.28105 3.69968 9.92163 2.5C5.66765 3.49698 2.5 7.31513 2.5 11.8731C2.5 17.1899 6.8101 21.5 12.1269 21.5C16.6849 21.5 20.503 18.3324 21.5 14.0784Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "sun": "<path d=\"M17 12C17 14.7614 14.7614 17 12 17C9.23858 17 7 14.7614 7 12C7 9.23858 9.23858 7 12 7C14.7614 7 17 9.23858 17 12Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/><path d=\"M12 2V3.5M12 20.5V22M19.0708 19.0713L18.0101 18.0106M5.98926 5.98926L4.9286 4.9286M22 12H20.5M3.5 12H2M19.0713 4.92871L18.0106 5.98937M5.98975 18.0107L4.92909 19.0714\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-width=\"1.5\"/>", "hash": "<path d=\"M14 21L18 3\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M6 21L10 3\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M5 8H21\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M3 16H19\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "book": "<path d=\"M15.5 7H8.5M12.499 11H8.49902\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M20 22H6C4.89543 22 4 21.1046 4 20M4 20C4 18.8954 4.89543 18 6 18H20V6C20 4.11438 20 3.17157 19.4142 2.58579C18.8284 2 17.8856 2 16 2H10C7.17157 2 5.75736 2 4.87868 2.87868C4 3.75736 4 5.17157 4 8V20Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M19.5 18C19.5 18 18.5 18.7628 18.5 20C18.5 21.2372 19.5 22 19.5 22\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "agents": "<path d=\"M18.5 7C18.5 9.20914 16.7091 11 14.5 11C12.2909 11 10.5 9.20914 10.5 7C10.5 4.79086 12.2909 3 14.5 3C16.7091 3 18.5 4.79086 18.5 7Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M8 11C6.34315 11 5 9.65685 5 8C5 6.34315 6.34315 5 8 5\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M14.5 14C9.8125 14 7 16.5 7 19C7 20.1046 7.83947 21 8.875 21H20.125C21.1605 21 22 20.1046 22 19C22 16.5 19.1875 14 14.5 14Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M4 19.9992H3.5C2.67157 19.9992 2 19.2317 2 18.2849C2 16.673 3.27307 15.0612 5.5 14.3613\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "memory": "<path d=\"M4.22222 21.9948V18.4451C4.22222 17.1737 3.88927 16.5128 3.23482 15.4078C2.4503 14.0833 2 12.5375 2 10.8866C2 5.97866 5.97969 2 10.8889 2C15.7981 2 19.7778 5.97866 19.7778 10.8866C19.7778 11.4663 19.7778 11.7562 19.802 11.9187C19.8598 12.3072 20.0411 12.6414 20.2194 12.9873L22 16.4407L20.6006 17.1402C20.195 17.3429 19.9923 17.4443 19.851 17.6314C19.7097 17.8184 19.67 18.0296 19.5904 18.4519L19.5826 18.4931C19.4004 19.4606 19.1993 20.5286 18.6329 21.2024C18.4329 21.4403 18.1853 21.6336 17.9059 21.7699C17.4447 21.9948 16.8777 21.9948 15.7437 21.9948C15.219 21.9948 14.6928 22.0069 14.1682 21.9942C12.9247 21.9639 12 20.9184 12 19.7044\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M14.388 10.5315C13.9617 10.5315 13.5729 10.3702 13.2784 10.1048M14.388 10.5315C14.388 11.6774 13.7241 12.7658 12.4461 12.7658C11.1681 12.7658 10.5043 13.8541 10.5043 15M14.388 10.5315C16.5373 10.5315 16.5373 7.18017 14.388 7.18017C14.1927 7.18017 14.0053 7.21403 13.8312 7.27624C13.9362 4.77819 10.3349 4.1 9.51923 6.44018M10.5043 8.29729C10.5043 7.52323 10.1133 6.8411 9.51923 6.44018M9.51923 6.44018C7.66742 5.19034 5.19883 7.4331 6.37324 9.43277C4.40226 9.72827 4.61299 12.7658 6.6205 12.7658C7.18344 12.7658 7.68111 12.4844 7.98234 12.0538\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "plug": "<path d=\"M15.5 2V6M8.5 6V2\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M6.00446 7.61331C5.93719 6.74273 6.63957 6 7.53014 6H16.4699C17.3604 6 18.0628 6.74273 17.9955 7.61331L17.8117 9.99197C17.6796 11.7019 17.1011 13.3498 16.132 14.7773L15.5312 15.6622C14.9638 16.4979 14.0077 17 12.9838 17H11.0162C9.99228 17 9.03617 16.4979 8.46881 15.6622L7.86803 14.7773C6.89885 13.3498 6.32041 11.7019 6.18827 9.99197L6.00446 7.61331Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/><path d=\"M12 17V22\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M11 9H13\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "plus": "<path d=\"M12.001 4.00101V20.001\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M20.001 12.001L4.00098 12.001\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "pen": "<path d=\"M16.4249 4.60509L17.4149 3.6151C18.2351 2.79497 19.5648 2.79497 20.3849 3.6151C21.205 4.43524 21.205 5.76493 20.3849 6.58507L19.3949 7.57506M16.4249 4.60509L9.76558 11.2644C9.25807 11.772 8.89804 12.4078 8.72397 13.1041L8 16L10.8959 15.276C11.5922 15.102 12.228 14.7419 12.7356 14.2344L19.3949 7.57506M16.4249 4.60509L19.3949 7.57506\" stroke=\"currentColor\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M18.9999 13.5C18.9999 16.7875 18.9999 18.4312 18.092 19.5376C17.9258 19.7401 17.7401 19.9258 17.5375 20.092C16.4312 21 14.7874 21 11.4999 21H11C7.22876 21 5.34316 21 4.17159 19.8284C3.00003 18.6569 3 16.7712 3 13V12.5C3 9.21252 3 7.56879 3.90794 6.46244C4.07417 6.2599 4.2599 6.07417 4.46244 5.90794C5.56879 5 7.21252 5 10.5 5\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "home": "<path d=\"M3 11.9896V14.5C3 17.7998 3 19.4497 4.02513 20.4749C5.05025 21.5 6.70017 21.5 10 21.5H14C17.2998 21.5 18.9497 21.5 19.9749 20.4749C21 19.4497 21 17.7998 21 14.5V11.9896C21 10.3083 21 9.46773 20.6441 8.74005C20.2882 8.01237 19.6247 7.49628 18.2976 6.46411L16.2976 4.90855C14.2331 3.30285 13.2009 2.5 12 2.5C10.7991 2.5 9.76689 3.30285 7.70242 4.90855L5.70241 6.46411C4.37533 7.49628 3.71179 8.01237 3.3559 8.74005C3 9.46773 3 10.3083 3 11.9896Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "search": "<path d=\"M17 17L21 21\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M19 11C19 6.58172 15.4183 3 11 3C6.58172 3 3 6.58172 3 11C3 15.4183 6.58172 19 11 19C15.4183 19 19 15.4183 19 11Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "chev": "<path d=\"M18 9.00005C18 9.00005 13.5811 15 12 15C10.4188 15 6 9 6 9\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "more": "<path d=\"M6.00449 12.5V12M18.0045 12.5V12M12.0045 12.5V12M7.00449 12.5C7.00449 11.9477 6.55677 11.5 6.00449 11.5C5.4522 11.5 5.00449 11.9477 5.00449 12.5C5.00449 13.0523 5.4522 13.5 6.00449 13.5C6.55677 13.5 7.00449 13.0523 7.00449 12.5ZM19.0045 12.5C19.0045 11.9477 18.5568 11.5 18.0045 11.5C17.4522 11.5 17.0045 11.9477 17.0045 12.5C17.0045 13.0523 17.4522 13.5 18.0045 13.5C18.5568 13.5 19.0045 13.0523 19.0045 12.5ZM13.0045 12.5C13.0045 11.9477 12.5568 11.5 12.0045 11.5C11.4522 11.5 11.0045 11.9477 11.0045 12.5C11.0045 13.0523 11.4522 13.5 12.0045 13.5C12.5568 13.5 13.0045 13.0523 13.0045 12.5Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "send": "<path d=\"M12 5.5V19\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M18 11C18 11 13.5811 5.00001 12 5C10.4188 4.99999 6 11 6 11\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "stop": "<path d=\"M4 12C4 8.72077 4 7.08116 4.81382 5.91891C5.1149 5.48891 5.48891 5.1149 5.91891 4.81382C7.08116 4 8.72077 4 12 4C15.2792 4 16.9188 4 18.0811 4.81382C18.5111 5.1149 18.8851 5.48891 19.1862 5.91891C20 7.08116 20 8.72077 20 12C20 15.2792 20 16.9188 19.1862 18.0811C18.8851 18.5111 18.5111 18.8851 18.0811 19.1862C16.9188 20 15.2792 20 12 20C8.72077 20 7.08116 20 5.91891 19.1862C5.48891 18.8851 5.1149 18.5111 4.81382 18.0811C4 16.9188 4 15.2792 4 12Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/>", "x": "<path d=\"M18.9991 19L5 5.00098\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M19 5L5.00092 18.999\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "check": "<path d=\"M5 14L8.5 17.5L19 6.5\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "panel": "<path d=\"M2 12C2 8.3109 2 6.46633 2.81382 5.1588C3.1149 4.67505 3.48891 4.2543 3.91891 3.91557C5.08116 3.00003 6.72077 3.00003 10 3.00003H14C17.2792 3.00003 18.9188 3.00003 20.0811 3.91557C20.5111 4.2543 20.8851 4.67505 21.1862 5.1588C22 6.46633 22 8.3109 22 12C22 15.6892 22 17.5337 21.1862 18.8413C20.8851 19.325 20.5111 19.7458 20.0811 20.0845C18.9188 21 17.2792 21 14 21H10C6.72077 21 5.08116 21 3.91891 20.0845C3.48891 19.7458 3.1149 19.325 2.81382 18.8413C2 17.5337 2 15.6892 2 12Z\" stroke=\"currentColor\" stroke-width=\"1.5\"/><path d=\"M14.5 3.00003L14.5 21\" stroke=\"currentColor\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M18 7.00006H19M18 10.0001H19\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "folder": "<path d=\"M13.6656 6.49446H16C18.8284 6.49446 20.2426 6.49446 21.1213 7.37314C22 8.25182 22 9.66603 22 12.4945V14.5C22 17.3284 22 18.7426 21.1213 19.6213C20.2426 20.5 18.8284 20.5 16 20.5H8C5.17157 20.5 3.75736 20.5 2.87868 19.6213C2 18.7426 2 17.3284 2 14.5V8.99183C2 6.65409 2 5.48521 2.61604 4.67881C2.7778 4.46706 2.96706 4.2778 3.17881 4.11604C3.98521 3.5 5.15409 3.5 7.49183 3.5C8.16633 3.5 8.50358 3.5 8.81392 3.60442C8.8976 3.63257 8.97932 3.66623 9.05854 3.70518C9.35239 3.84965 9.59179 4.08719 10.0706 4.56227L10.8483 5.33389C11.4254 5.9066 11.714 6.19295 12.08 6.3437C12.446 6.49446 12.8525 6.49446 13.6656 6.49446Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "trash": "<path d=\"M18.8516 16.3743L19.5 6H4.5L5.14839 16.3743C5.315 19.0401 5.39831 20.373 6.26426 21.1865C7.13021 22 8.46571 22 11.1367 22H12.8633C15.5343 22 16.8698 22 17.7357 21.1865C18.6017 20.373 18.685 19.0401 18.8516 16.3743Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M16 6H21M16 6L15.3778 4.34082C15.0007 3.33524 14.8122 2.83245 14.4402 2.50292C14.3213 2.39765 14.1904 2.3069 14.0501 2.2326C13.6109 2 13.074 2 12 2C10.926 2 10.3891 2 9.9499 2.2326C9.8096 2.3069 9.67865 2.39765 9.55982 2.50292C9.18783 2.83245 8.99928 3.33524 8.62219 4.34082L8 6M16 6H8M3 6H8\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M9.5 11V17M14.5 11V17\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "branch": "<path d=\"M7 19H13C15.8284 19 17.2426 19 18.1213 18.1213C19 17.2426 19 15.8284 19 13V10M19 10C19.7002 10 21.0085 11.9943 21.5 12.5M19 10C18.2998 10 16.9915 11.9943 16.5 12.5\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M5 7L5 17\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><circle cx=\"5\" cy=\"5\" r=\"2\" stroke=\"currentColor\" stroke-width=\"1.5\"/><circle cx=\"19\" cy=\"5\" r=\"2\" stroke=\"currentColor\" stroke-width=\"1.5\"/><circle cx=\"5\" cy=\"19\" r=\"2\" stroke=\"currentColor\" stroke-width=\"1.5\"/>", "chat": "<path d=\"M21.9598 12.9919C21.6856 17.2342 18.3536 20.6134 14.1706 20.8915C13.4574 20.9389 12.7285 21.001 12 21.001C10.4054 21.001 8.95127 20.8637 7.44544 20.2902C7.44544 20.2902 5.56108 21.7589 3.69962 21.4587C3.31009 21.3959 3.11532 21.3644 3.00091 21.1343C2.8865 20.9042 3.00788 20.6756 3.25063 20.2185C3.65964 19.4483 3.92248 18.6737 3.80076 17.8306C3.73703 17.3892 3.50433 16.9974 3.27644 16.6136L3.26529 16.5948C2.62637 15.5188 2.12462 14.2975 2.04024 12.9919C1.98659 12.1617 1.98659 11.3019 2.04024 10.4717C2.31441 6.22935 5.64639 2.85011 9.8294 2.57205C11.2536 2.47738 12.7435 2.47719 14.1706 2.57205C18.3536 2.85011 21.6856 6.22935 21.9598 10.4717C22.0134 11.3019 22.0134 12.1617 21.9598 12.9919Z\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><path d=\"M8.75 14.501H15.25M8.75 9.50098H12.25\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>", "person": "<path d=\"M20 21.0001C19.713 17.269 16.7289 14.3151 12.995 14.0662L12 13.9999C11.6446 14.0096 11.3134 14.0225 11.0008 14.0378C7.3 14.2192 4.28417 17.3057 4 21.0001\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/><circle cx=\"12\" cy=\"6.99988\" r=\"4\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\"/>" };
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
// The hidden lines agents write for the Mac app's chat (to-do card, ticks, report card): never shown as text here.
const stripTags = (t) => String(t ?? '').replace(/\s*⟦\s*report\s*:[^⟧]*⟧[\s\S]*?⟦\s*\/\s*report\s*⟧\s*/gi, '\n\n').replace(/\s*⟦\s*report\s*:[^⟧]*⟧[\s\S]*$/i, '').replace(/\s*⟦\s*(?:plan|done|next)\s*:[^⟧]*⟧/gi, '').replace(/\s*⟦[^⟧]*$/, '');
function md(text) {
  const blocks = stripTags(text).split(/```/);
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
const wsOf = (a) => { const all = S.data?.workspaces || []; return (a.workspace && all.find((w) => w.id === a.workspace)) || all.find((w) => w.path && (inDir(a.cwd, w.path) || a.baseRepo === w.path || inDir(a.baseRepo, w.path))); };
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
const WALLS = [
  { id: 'socrates', name: 'The Death of Socrates · Jacques-Louis David, 1787' },
  { id: 'constitution', name: 'Constitution of 3 May 1791 · Jan Matejko, 1891' },
  { id: 'carthage', name: 'The Decline of the Carthaginian Empire · J. M. W. Turner, 1817' },
  { id: 'battle', name: 'Battle scene' },
];
function applyWall() { document.documentElement.style.setProperty('--wall', `url(walls/${S.wall}.jpg)`); document.documentElement.classList.toggle('light', S.theme === 'light'); }
// ---------------------------------------------------------------- top bar
// Middle: the page you're on, with its icon (like Discord). Right: the toolbox, which acts on the
// agent in focus (the one you're talking to, or the one picked on Home).
const MODELS = { 'claude-code': [['', 'Default', 'What Claude Code would pick'], ['opus', 'Opus', 'Most capable'], ['sonnet', 'Sonnet', 'Fast and capable'], ['haiku', 'Haiku', 'Fastest']], codex: [['', 'Default', 'What Codex would pick']] };
const ACCESS = [['plan', 'Plan only', 'Reads and plans. Changes nothing.'], ['ask', 'Ask first', 'Asks before it edits or runs anything.'], ['edits', 'Edit on its own', 'Edits files without asking. Still asks to run commands.']];
// What a screen is called and its icon: used by the title and by History.
function viewInfo(v, size = 20) {
  const w = S.space !== 'home' ? curWs() : null;
  if (v.kind === 'dm' && ag(v.id)) { const a = ag(v.id); return [avatar(a, size + 2, 'var(--work)', false), a.name]; }
  if (v.kind === 'chat') { const c = (S.chats[v.op] || []).find((x) => x.id === v.id); return [tile(v.op, 'xs'), c?.title || 'Chat']; }
  if (w && WS_VIEWS[v.kind]) return [ic(WS_VIEWS[v.kind][0], size), WS_VIEWS[v.kind][1]];
  if (w && (v.kind === 'channel' || v.kind === 'dm')) return [wsPic(w, size + 2), w.name];
  const P = { agents: ['home', 'Home'], messages: ['chat', 'Messages'], tool: ['chat', 'Messages'], reviews: ['inbox', 'Review'], review: ['inbox', 'Review'], memory: ['book', 'Playbook'], discover: ['compass', 'Discover'], usage: ['chart', 'Usage'], connections: ['plug', 'Plugins'], profile: ['person', 'Profile'] }[v.kind] || ['home', 'Home'];
  return [ic(P[0], size), P[1]];
}
function pageHead() { const [i, l] = viewInfo(S.view); return `${i}<b>${esc(l)}</b>`; }
// Back, forward and History: every screen you open, like a browser.
const H = { stack: [], i: -1 };
const viewKey = (v) => `${v.kind}:${v.id || ''}:${v.op || ''}`;
const histGo = (e, nav) => { if (e.space && (e.space === 'home' || S.data.workspaces.some((w) => w.id === e.space))) S.space = e.space; go(e.view, nav); };
function histMenu() {
  const seen = new Set(), rows = [];
  for (let j = H.stack.length - 1; j >= 0 && rows.length < 8; j--) { const e = H.stack[j], k = `${e.space}|${viewKey(e.view)}`; if (seen.has(k)) continue; seen.add(k); rows.push([j, e]); }
  return `<div class="hist-menu" role="menu" aria-label="Recently viewed"><div class="hist-cap">Recently viewed</div>${rows.map(([j, e]) => { const [i, l] = viewInfo(e.view, 18); const on = j === H.i; return `<button role="menuitem" class="${on ? 'on' : ''}" data-act="hist-go" data-id="${j}">${i}<span>${esc(l)}</span><span class="meta">${on ? 'Now' : ago(e.at)}</span></button>`; }).join('')}</div>`;
}
// Model and access for one agent. Shown where you talk to that agent (Home's ask box, a chat),
// never as a global toolbar, so it's always clear which agent they change.
function agentControls(a, where) {
  if (!a) return '';
  const models = MODELS[a.operator] || MODELS['claude-code'];
  const m = models.find(([id]) => id === (a.model || '')) || [a.model, a.model];
  const acc = ACCESS.find(([id]) => id === (a.permission || 'ask')) || ACCESS[1];
  const open = (k) => S.tbMenu === `${where}:${k}`;
  const menu = (k, items) => open(k) ? `<div class="tb-menu" role="menu">${items}</div>` : '';
  return `<div class="tb-item"><button type="button" class="tb-btn" data-act="tb-menu" data-id="${where}:model" aria-haspopup="menu" aria-expanded="${open('model')}" title="Model ${esc(a.name)} uses">${ic('chip', 15)}<span>${m[0] ? esc(m[1]) : 'Default model'}</span>${ic('chev', 12, 2)}</button>
      ${menu('model', `<div class="tb-cap">Model for ${esc(a.name)}</div>` + models.map(([id, l, d]) => `<button type="button" role="menuitemradio" aria-checked="${(a.model || '') === id}" data-act="tb-model" data-agent="${a.id}" data-id="${id}"><span><b>${l}</b><small>${d}</small></span></button>`).join('') + (a.operator !== 'claude-code' ? '<p class="tb-note">Other models come from this tool’s own settings.</p>' : ''))}</div>
    <div class="tb-item"><button type="button" class="tb-btn" data-act="tb-menu" data-id="${where}:access" aria-haspopup="menu" aria-expanded="${open('access')}" title="What ${esc(a.name)} may do">${ic('shield', 15)}<span>${acc[1]}</span>${ic('chev', 12, 2)}</button>
      ${menu('access', `<div class="tb-cap">What ${esc(a.name)} may do</div>` + ACCESS.map(([id, l, d]) => `<button type="button" role="menuitemradio" aria-checked="${(a.permission || 'ask') === id}" data-act="tb-access" data-agent="${a.id}" data-id="${id}"><span><b>${l}</b><small>${d}</small></span></button>`).join(''))}</div>`;
}
// The page title starts exactly at the content panel's left edge, whatever the sidebar is doing.
function fadeNames() { for (const el of document.querySelectorAll('.ws-name-t')) el.classList.toggle('fade', el.scrollWidth > el.clientWidth + 1); }
new ResizeObserver(() => fadeNames()).observe(document.documentElement);
function alignTitle() {
  fadeNames();
  const top = $('#top'), main = document.querySelector('.main');
  if (!top || !main) return;
  const t = top.getBoundingClientRect(), brand = top.querySelector('.top-brand')?.getBoundingClientRect();
  const x = main.getBoundingClientRect().left - t.left;
  // The nav buttons end exactly where the sidebar's rows end.
  const padL = parseFloat(getComputedStyle(top).paddingLeft) || 0, row = document.querySelector('#side .snav');
  const w = row && row.getBoundingClientRect().width ? row.getBoundingClientRect().right - t.left - padL : x - 20 - padL;
  top.style.setProperty('--brand-w', w > 160 ? `${Math.round(w)}px` : 'auto');
  top.style.setProperty('--title-x', `${Math.round(Math.max(x, brand && x < 200 ? brand.right - t.left + 24 : 0))}px`);
}
addEventListener('resize', alignTitle);
new ResizeObserver(() => alignTitle()).observe(document.documentElement);
function renderTop() {
  $('#top').innerHTML = `
    <div class="top-brand"><span class="lights" aria-hidden="true"><i></i><i></i><i></i></span>
      <div class="top-nav" role="toolbar" aria-label="Navigation"><button class="icon-btn" data-act="nav-back" ${H.i > 0 ? '' : 'disabled'} title="Back (⌘[)" aria-label="Back">${ic('arrowL', 18)}</button><button class="icon-btn" data-act="nav-fwd" ${H.i < H.stack.length - 1 ? '' : 'disabled'} title="Forward (⌘])" aria-label="Forward">${ic('arrowR', 18)}</button><span class="hist-wrap"><button class="icon-btn" data-act="hist-open" aria-haspopup="menu" aria-expanded="${!!S.histOpen}" title="History" aria-label="History">${ic('clock', 18)}</button>${S.histOpen ? histMenu() : ''}</span></div></div>
    <div class="top-page" aria-live="polite">${pageHead()}</div>
    <div class="top-end"><div class="top-tools" data-optical role="toolbar" aria-label="Quick actions"><button class="icon-btn" data-act="new-agent" title="New agent" aria-label="New agent">${ic('pen', 18)}</button><button class="icon-btn" data-act="cmd" title="Find an agent or chat (⌘K)" aria-label="Find an agent or chat">${ic('search', 18)}</button></div></div>`;
  requestAnimationFrame(alignTitle);
}
const PROJ_COLORS = ['#4073d4', '#17866b', '#8b5ade', '#cf4079', '#cc4d29', '#ac6612', '#5f7a4d', '#4a4e57'];
function wsInitials(w) { return (w.name.replace(/[^\p{L}\p{N}]/gu, '').slice(0, 2) || '··').replace(/^./, (c) => c.toUpperCase()); }
function wsPic(w, size = 48, img = w.image, color = w.color) {
  return img ? `<span class="wspic" style="--sz:${size}px"><img src="${img}" alt=""></span>`
    : `<span class="wspic" style="--sz:${size}px;--c:${color || '#5D6B8C'}">${esc(wsInitials(w))}</span>`;
}
function renderRail() {
  const waitIn = (w) => S.approvals.filter((p) => { const a = ag(p.agentId); return a && wsOf(a)?.id === w.id; }).length;
  const dot = (n) => (n ? '<span class="rdot" aria-hidden="true"></span>' : '');
  const tile = (id, inner, label, n) => `<button class="rt2 ${S.space === id ? 'on' : ''}" data-act="space" data-id="${id}" title="${esc(label)}" aria-label="${esc(label)}${n ? `, ${n} waiting for you` : ''}">${inner}${S.space === id ? '' : dot(n)}</button>`;
  $('#rail').innerHTML = tile('home', ic('person', 22), 'Personal', S.approvals.length)
    + '<div class="rsep"></div>'
    + (S.data?.workspaces || []).map((w) => tile(w.id, wsPic(w, 48), w.name, waitIn(w))).join('')
    + `<button class="rt2 add" data-act="ws-add" title="Add a project folder" aria-label="Add a project folder">${ic('plus', 22)}</button>`;
}

function renderSide() {
  renderHomeSide();
}
function renderProjectSide(w) {
  const v = S.view;
  const list = agents().filter(agentIn).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || lastAt(b) - lastAt(a));
  const row = (a) => { const st = stateOf(a), sel = v.kind === 'dm' && v.id === a.id; return `<button class="dm ${sel ? 'on' : ''}" data-act="dm" data-id="${a.id}">${avatar(a, 32, sel ? 'var(--i3)' : 'var(--ground)')}<span class="grow"><span class="t">${esc(a.name)}</span><span class="s ${st === 'needs' ? 'wait' : st === 'failed' ? 'fail' : ''}">${esc(statusLine(a))}</span></span></button>`; };
  const waiting = S.approvals.filter((p) => { const a = ag(p.agentId); return a && agentIn(a); }).length;
  $('#side').innerHTML = `
    <div class="proj-banner" style="--c:${w.color || '#5D6B8C'}">
      <div class="proj-cover">${w.image ? `<img src="${w.image}" alt="">` : ''}</div>
      <div class="proj-id">${wsPic(w, 64)}<button class="icon-btn proj-edit" data-act="proj-edit" title="Edit project" aria-label="Edit ${esc(w.name)}">${ic('pen', 18)}</button></div>
      <div class="proj-name">${esc(w.name)}</div>
      <div class="proj-meta">${list.length} ${list.length === 1 ? 'agent' : 'agents'} · ${list.filter((a) => stateOf(a) === 'working').length} working · <button class="link-like" data-act="open-folder" data-path="${esc(w.path)}" title="${esc(w.path)}">Open folder</button></div>
    </div>
    <nav class="side-body scroll" aria-label="${esc(w.name)}">
      <div class="side-ws">Channels</div>
      <button class="snav ${v.kind === 'channel' ? 'on' : ''}" data-act="channel">${ic('hash', 20)}<span class="t">general</span>${waiting ? `<span class="count">${waiting}</span>` : ''}</button>
      <div class="side-ws with-add">Agents<button data-act="new-agent" title="New agent in ${esc(w.name)}" aria-label="New agent in ${esc(w.name)}">${ic('plus', 16)}</button></div>
      ${list.map(row).join('') || '<p class="meta side-empty">No agents here yet. Agents you make in this project work in its folder.</p>'}
    </nav>`;
}
function openCreateWs() { S.projDraft = { id: null, name: `${base(S.data.home)}’s workspace`, image: null, color: PROJ_COLORS[Math.floor(Math.random() * PROJ_COLORS.length)], path: null }; drawCreateWs(); }
function drawCreateWs() {
  const d = S.projDraft;
  layer(modal('Create a workspace', `<div class="m-head"><h3 class="big">Make your workspace</h3><p>Give it a name and a picture. Agents you add here live in it. You can change both later.</p>
      <label class="pic-drop ${d.image ? 'has' : ''}">${d.image ? `<img src="${d.image}" alt="">` : `${ic('plus', 22)}<span>Upload</span>`}<input type="file" id="projPic" accept="image/png,image/jpeg,image/webp" hidden></label></div>
    <form class="m-body" id="projForm">
      <div class="field"><label for="pjName">Workspace name</label><input id="pjName" value="${esc(d.name)}" maxlength="40" autofocus></div>
      <div class="field"><label for="pjAbout">Description <span class="meta">optional</span></label><input id="pjAbout" value="${esc(d.about || '')}" maxlength="140" placeholder="What this team of agents works on"></div>
      <div class="field"><span class="lbl">Folder <span class="meta">optional</span></span><button type="button" class="path-btn" data-act="ws-link-folder">${ic('folder')}<span>${esc(d.path || 'None. Agents choose their own folders.')}</span></button></div>
    </form>`, '<button class="btn ghost-link" data-act="close-layer-btn">Back</button><span style="flex:1"></span><button class="btn primary" data-act="proj-save">Create</button>'));
}
function openProjectForm(w) { S.projDraft = { id: w.id, about: w.about || '', name: w.name, image: w.image || null, color: w.color || PROJ_COLORS[2], path: w.path }; drawProjectForm(); }
function drawProjectForm() {
  const d = S.projDraft;
  layer(modal('Edit workspace', `<div class="m-head">${wsPic({ name: d.name || '?' }, 88, d.image, d.color)}<div class="pic-acts"><label class="btn second">Upload picture<input type="file" id="projPic" accept="image/png,image/jpeg,image/webp" hidden></label>${d.image ? '<button class="btn second" data-act="proj-pic-clear">Remove</button>' : ''}</div><h3>Edit workspace</h3></div>
    <form class="m-body" id="projForm">
      <div class="field"><label for="pjName">Name</label><input id="pjName" value="${esc(d.name)}" maxlength="40" autofocus></div>
      <div class="field"><label for="pjAbout">Description <span class="meta">optional</span></label><input id="pjAbout" value="${esc(d.about || '')}" maxlength="140" placeholder="What this team of agents works on"></div>
      ${d.image ? '' : `<div class="field"><span class="lbl">Colour</span><div class="swatches">${PROJ_COLORS.map((c) => `<button type="button" class="swatch ${c === d.color ? 'on' : ''}" style="--c:${c}" data-act="proj-color" data-id="${c}" aria-label="Colour ${c}"></button>`).join('')}</div></div>`}
      <div class="field"><span class="lbl">Folder <span class="meta">optional</span></span><span class="meta">${esc(d.path || 'None. Agents choose their own folders.')}</span></div>
    </form>`, '<button class="btn danger" data-act="ws-remove-proj">Remove workspace</button><span style="flex:1"></span><button class="btn second" data-act="close-layer-btn">Cancel</button><button class="btn primary" data-act="proj-save">Save</button>'));
}
async function saveProject() {
  const d = S.projDraft; if (!d) return;
  d.name = $('#pjName')?.value.trim() || d.name;
  if ($('#pjAbout')) d.about = $('#pjAbout').value.trim();
  if (!d.id) {
    const w = await run(() => lab.call('workspace:create', { name: d.name, about: d.about || '', image: d.image, color: d.color, path: d.path }));
    if (w) { S.data.workspaces.push(w); closeLayer(); S.projDraft = null; S.space = w.id; go({ kind: 'channel' }); toast(`${w.name} is ready`); }
    return;
  }
  const w = await run(() => lab.call('workspace:update', d.id, { name: d.name, about: d.about || '', color: d.color, image: d.image }));
  if (w) { const i = S.data.workspaces.findIndex((x) => x.id === w.id); if (i >= 0) S.data.workspaces[i] = w; closeLayer(); S.projDraft = null; render(true); toast('Saved'); }
}
function wsSection(w) {
  const open = S.space === w.id;
  const pool = agents().filter((a) => wsOf(a)?.id === w.id).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || lastAt(b) - lastAt(a));
  const waiting = S.approvals.filter((p) => pool.some((a) => a.id === p.agentId)).length;
  const working = pool.filter((a) => stateOf(a) === 'working').length;
  const about = w.about || (w.path ? w.path.replace(/^\/Users\/[^/]+/, '~') : '');
  const team = pool.length ? `<span class="wsrow-team"><span class="ws-faces">${pool.slice(0, 4).map((a) => avatar(a, 24, 'var(--wsrow-bg)', false)).join('')}${pool.length > 4 ? `<span class="ws-more">+${pool.length - 4}</span>` : ''}</span><span>${pool.length} ${pool.length === 1 ? 'agent' : 'agents'}${working ? ` · ${working} working` : ''}</span></span>` : '';
  return `<button class="wsrow ${open ? 'on' : ''}" data-act="space" data-id="${w.id}" aria-current="${open}">
    ${wsPic(w, 48)}
    <span class="wsrow-main">
      <span class="wsrow-top"><span class="t">${esc(w.name)}</span>${waiting ? `<span class="count" title="${waiting} waiting for you">${waiting}</span>` : ''}</span>
      ${about ? `<span class="wsrow-about">${esc(about)}</span>` : ''}
      ${team}
    </span>
  </button>`;
}
function renderHomeSide() {
  const v = S.view;
  const on = (k, id) => (v.kind === k && (id === undefined || v.id === id) ? 'on' : '');
  const list = agents().filter(agentIn).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || b.createdAt - a.createdAt);
  S.quick = list.slice(0, 9).map((a) => a.id);
  const waiting = waitingCount();
  const row = (a, i) => {
    const st = stateOf(a), sel = on('dm', a.id);
    const sub = statusLine(a);
    return `<button class="dm ${sel}" data-act="dm" data-id="${a.id}">${avatar(a, 32, sel ? 'var(--i4)' : 'var(--side)')}<span class="grow"><span class="t">${esc(a.name)}</span><span class="s ${st === 'needs' ? 'wait' : st === 'failed' ? 'fail' : ''}">${esc(sub)}</span></span>${i < 9 ? `<kbd class="quick">⌘${i + 1}</kbd>` : ''}</button>`;
  };
  const inMsgs = v.kind === 'dm' || v.kind === 'messages' || v.kind === 'chat' || v.kind === 'tool';
  const navRow = (kind, icon, label, extra = '', act = 'view') => {
    const sel = S.space === 'home' && (kind === 'messages' ? inMsgs : kind === 'reviews' ? v.kind === 'reviews' || v.kind === 'review' : v.kind === kind);
    return `<button class="snav ${sel ? 'on' : ''}" data-act="${act}" data-id="${kind}">${ic(icon, 20)}<span class="t">${label}</span>${extra}</button>`;
  };
  const waitIn = (w) => S.approvals.filter((p) => { const x = ag(p.agentId); return x && wsOf(x)?.id === w.id; }).length;
  const dot = (n) => (n ? '<span class="rdot" aria-hidden="true"></span>' : '');
  $('#side').innerHTML = `
    <div class="side-ws">Personal</div>
    <nav class="side-body scroll" aria-label="Agent Lab">
      ${navRow('agents', 'home', 'Home')}
      ${navRow('discover', 'compass', 'Discover')}
      ${(() => { const n = reviewQueue().count; return navRow('reviews', 'inbox', 'Review', n ? `<span class="count">${n}</span>` : ''); })()}
      ${navRow('messages', 'chat', 'Messages')}
      ${navRow('memory', 'book', 'Playbook')}
      <div class="side-ws with-add">Workspaces<button data-act="ws-create" title="Create a workspace" aria-label="Create a workspace">${ic('plus', 16)}</button></div>
      ${(S.data?.workspaces || []).map(wsSection).join('') || '<p class="meta side-empty">Create a workspace to give a team of agents its own place.</p>'}
    </nav>
    <div class="upanel"><button class="upanel-me" data-act="view" data-id="profile" title="Your profile">${meAvatar()}<span class="grow"><b>${esc(base(S.data.home))}</b><span>${agents().length} ${agents().length === 1 ? 'agent' : 'agents'}${S.runs.size ? ` · ${S.runs.size} working` : ''}</span></span></button><button class="icon-btn" data-act="set-open" aria-haspopup="menu" aria-expanded="${!!S.setOpen}" aria-label="Plugins and settings" title="Plugins and settings">${ic('gear', 18)}</button>
      ${S.setOpen ? `<div class="set-menu" role="menu"><button role="menuitem" data-act="view" data-id="connections">${ic('plug', 18)}<span>Plugins</span><span class="meta">${['claude-code', 'codex'].filter((k) => S.data.operators?.[k]?.path).length} connected</span></button><button role="menuitem" data-act="view" data-id="profile">${ic('person', 18)}<span>Profile</span></button><button role="menuitem" data-act="view" data-id="usage">${ic('chart', 18)}<span>Usage</span><span class="meta">${(() => { const u = usageOf(weekStart()); return u.cost ? `${money(u.cost)} this week` : `${u.runs} runs this week`; })()}</span></button><hr><div class="set-walls" role="group" aria-label="Wallpaper"><span>Wallpaper</span>${WALLS.map((w) => `<button type="button" data-act="wall" data-id="${w.id}" aria-pressed="${S.wall === w.id}" style="background-image:url(walls/${w.id}.jpg)" title="${w.name}" aria-label="Wallpaper: ${w.name}"></button>`).join('')}</div><button role="menuitem" data-act="theme">${ic(S.theme === 'light' ? 'moon' : 'sun', 18)}<span>${S.theme === 'light' ? 'Dark theme' : 'Light theme'}</span></button></div>` : ''}</div>`;
}

// ---------------------------------------------------------------- top bar
function renderStrip() {
  const v = S.view;
  const toggle = `<button class="icon-btn only-wide ${S.nowHidden ? '' : 'on'}" data-act="now-toggle" aria-pressed="${!S.nowHidden}" aria-label="${S.nowHidden ? 'Show' : 'Hide'} Right now" title="${S.nowHidden ? 'Show' : 'Hide'} Right now  ⌥⌘0">${ic('panel')}</button>`;
  let title = '', extra = '';
  if (v.kind === 'agents') {
    const n = waitingCount();
    const tabs = [['all', 'All'], ['working', 'Working'], ['needs', 'Waiting for you'], ['done', 'Done']];
    title = `Home</div><div class="tabs" role="tablist">${tabs.map(([k, l]) => `<button class="tab ${S.tab === k ? 'on' : ''}" data-act="tab" data-id="${k}" role="tab" aria-selected="${S.tab === k}">${l}${k === 'needs' && n ? `<span class="count">${n}</span>` : ''}</button>`).join('')}`;
    extra = `<button class="btn primary" data-act="new-agent">New agent</button>`;
  } else if (v.kind === 'messages' || v.kind === 'dm') {
  } else if (v.kind === 'review') {
    const a = ag(v.id);
    title = `${a ? avatar(a, 24, 'var(--work)') : ''}Review changes<span class="meta">${esc(a?.branch || '')}</span>`;
    extra = `<button class="btn danger" data-act="discard">Discard</button><button class="btn second" data-act="ask-changes">Ask for changes</button><button class="btn primary" data-act="merge">Merge into ${esc(a?.baseBranch || 'main')}</button>`;
  } else title = { memory: `${ic('memory', 20)}Memory`, connections: `${ic('plug', 20)}Connections` }[v.kind] || '';
  $('#strip').hidden = v.kind !== 'review';
  $('#strip').innerHTML = `<div class="title">${title}</div><div class="end">${extra}</div>`;
}

// ---------------------------------------------------------------- views
function renderView(keep) {
  renderTop();
  const el = $('#view'), top = el.scrollTop, v = S.view;
  const pl = $('#paneList'), plTop = pl ? pl.scrollTop : 0, pd = $('#paneDetail'), pdTop = pd ? pd.scrollTop : 0;
  const pdAtEnd = pd ? pd.scrollHeight - pd.scrollTop - pd.clientHeight < 40 : true;
  const atEnd = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
  const focus = document.activeElement?.id, selStart = document.activeElement?.selectionStart;
  const draftVal = $('#cmpInput')?.value;
  el.innerHTML = S.space !== 'home' && curWs() && (v.kind === 'dm' || v.kind === 'channel' || WS_VIEWS[v.kind]) ? projectView() : v.kind === 'dm' || v.kind === 'messages' || v.kind === 'chat' || v.kind === 'tool' ? messagesView() : v.kind === 'review' ? reviewView() : v.kind === 'reviews' ? '<div class="blank" aria-hidden="true"></div>' : v.kind === 'discover' ? discoverView() : v.kind === 'usage' ? usageView() : v.kind === 'memory' ? '<div class="blank" aria-hidden="true"></div>' : v.kind === 'connections' ? connectionsView() : v.kind === 'profile' ? profileView() : homeView();
  if (draftVal && $('#cmpInput') && !$('#cmpInput').value) $('#cmpInput').value = draftVal;
  el.scrollTop = keep ? top : 0;
  const npl = $('#paneList'); if (npl) npl.scrollTop = plTop;
  const npd = $('#paneDetail'); if (npd) npd.scrollTop = keep && !pdAtEnd ? pdTop : npd.scrollHeight;
  if (focus) { const f = document.getElementById(focus); if (f) { f.focus(); try { if (selStart != null) f.setSelectionRange(selStart, selStart); } catch {} } }
  autoGrow();
}

const TABS_FILTER = { all: () => true, working: (a) => stateOf(a) === 'working', needs: (a) => stateOf(a) === 'needs', done: (a) => ['done', 'failed', 'idle'].includes(stateOf(a)) };
// Home is a command centre: one call to action, quick starts, then every agent and what it's doing.
const QUICK = [
  ['plus', 'New agent', null],
  ['branch', 'Fix a bug', 'Find and fix the bug where '],
  ['check', 'Review changes', 'Review the uncommitted changes in this folder and tell me what you would change.'],
  ['search', 'Research', 'Research '],
  ['pen', 'Write tests', 'Write tests for '],
  ['book', 'Plan', 'Make a step-by-step plan for '],
];
// What an agent has to show for itself, in one line: the outcome, not its last chat message.
function outcomeLine(a) {
  const st = stateOf(a), r = S.runs.get(`agent:${a.id}`);
  if (st === 'working') return `${esc(r?.activity || 'Working')} · <span data-since="${r?.startedAt}">${elapsed(r?.startedAt || Date.now())}</span>`;
  if (st === 'needs') { const p = approvalsFor(a.id)[0]; return `<span class="wait">Asks to ${esc(String(p?.verb || 'continue').toLowerCase())} ${esc(clip(p?.line || '', 60))}</span>`; }
  const rc = reviewCache.get(a.id);
  if (rc?.files?.length) { const add = rc.files.reduce((n, f) => n + f.add, 0), del = rc.files.reduce((n, f) => n + f.del, 0); return `Changed ${rc.files.length} ${rc.files.length === 1 ? 'file' : 'files'} <span class="c-add">+${add}</span> <span class="c-del">−${del}</span> · ready to review`; }
  if (st === 'failed') return `<span class="fail">Stopped with an error ${ago(a.last?.at || lastAt(a))}</span>`;
  if (st === 'done') return `Finished ${ago(a.last?.at || lastAt(a))} · reply waiting`;
  const t = a.last?.at || lastAt(a);
  return t ? `Idle · last worked ${ago(t)}` : 'Ready for its first task';
}
// Usage from the engine's run ledger. Claude Code reports cost; Codex reports time only.
function usageOf(since) {
  const rows = agents().map((a) => { const l = (a.ledger || []).filter((x) => x.at >= since); return { a, runs: l.length, ms: l.reduce((n, x) => n + (x.ms || 0), 0), cost: l.reduce((n, x) => n + (x.cost || 0), 0), priced: l.some((x) => x.cost != null) }; });
  return { rows: rows.filter((r) => r.runs).sort((x, y) => y.cost - x.cost || y.ms - x.ms), runs: rows.reduce((n, r) => n + r.runs, 0), ms: rows.reduce((n, r) => n + r.ms, 0), cost: rows.reduce((n, r) => n + r.cost, 0) };
}
const weekStart = () => { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return d.getTime(); };
const money = (n) => n >= 100 ? `$${Math.round(n)}` : `$${n.toFixed(2)}`;
const dur = (ms) => { const m = Math.round(ms / 60000); return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`; };

// Home: greet, ask, then your agents (filter by state or tool, like Discord's Friends tabs),
// with Right now beside it. Ideas only show while you're getting started.
function homePick(scope) { return ag(S.homeAgent) && agentIn(ag(S.homeAgent)) ? ag(S.homeAgent) : scope[0]; }
function homeView() {
  // Same Home with or without agents (like Discord's empty Friends page): every section shows its own empty state.
  const scope = agents().filter(agentIn).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || lastAt(b) - lastAt(a));
  const pick = homePick(scope);
  const aps = S.approvals.filter((p) => { const a = ag(p.agentId); return a && agentIn(a); });
  const ovs = S.overlaps.filter((o) => o.agents.some((id) => ag(id) && agentIn(ag(id))));
  const w = aps.length + ovs.length, k = scope.filter((a) => stateOf(a) === 'working').length;
  const hr = new Date().getHours();
  const hello = hr < 5 ? 'Good evening' : hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening';
  const q = reviewQueue(), wk = usageOf(weekStart());
  const pulse = [
    q.aps.length + q.ovs.length ? `<button class="pulse-i wait" data-act="view" data-id="reviews"><i></i>${q.aps.length + q.ovs.length} waiting for you</button>` : '',
    q.ready.length ? `<button class="pulse-i" data-act="view" data-id="reviews">${q.ready.length} ready to review</button>` : '',
    k ? `<button class="pulse-i busy" data-act="hf" data-id="working"><i></i>${k} working</button>` : '',
    wk.runs ? `<button class="pulse-i" data-act="view" data-id="usage">${wk.cost ? `${money(wk.cost)} · ` : ''}${wk.runs} ${wk.runs === 1 ? 'run' : 'runs'} this week</button>` : '',
  ].filter(Boolean);
  const summary = pulse.length ? pulse.join('<span class="pulse-dot" aria-hidden="true"></span>') : '<span>All quiet. Your agents are ready when you are.</span>';
  const op = (a) => OPS[a.operator]?.name || a.operator;
  const line = outcomeLine;
  const badge = (a) => { const st = stateOf(a); return `<span class="hb st-${st}">${STATE[st].label}</span>`; };

  // Ask box
  const menu = S.pickOpen ? `<div class="pick-menu" role="listbox">${scope.map((a) => `<button type="button" role="option" aria-selected="${a.id === pick?.id}" data-act="home-pick" data-id="${a.id}">${avatar(a, 24, 'var(--i3)', false)}<span>${esc(a.name)}</span><span class="meta">${op(a)}</span></button>`).join('')}</div>` : '';
  const ask = `<div class="sx">
    <form class="sx-box" id="homeForm" autocomplete="off">
      <textarea id="homeInput" rows="2" placeholder="Ask ${esc(pick?.name || 'an agent')} to fix, build, review or research something…" aria-label="Message ${esc(pick?.name || 'an agent')}"></textarea>
      <div class="sx-bar">
        ${pick ? `<button type="button" class="sx-who" data-act="home-pick-open" aria-haspopup="listbox" aria-expanded="${!!S.pickOpen}" title="Choose an agent">${pick ? avatar(pick, 22, 'var(--hx-card)', false) : ''}<span>${esc(pick?.name || '')}</span>${ic('chev', 12, 2)}</button>` : `<button type="button" class="sx-who" data-act="new-agent" title="Make your first agent">${ic('plus', 16)}<span>Make an agent</span></button>`}
        ${pick ? `<div class="tb-item"><button type="button" class="tb-btn" data-act="tb-menu" data-id="home:folder" aria-haspopup="menu" aria-expanded="${S.tbMenu === 'home:folder'}" title="Where ${esc(pick.name)} works">${ic(pick.worktree ? 'branch' : 'folder', 15)}<span>${esc(base(pick.worktree ? pick.cwd : pick.cwd) || 'Home folder')}${pick.worktree ? ` · ${esc(pick.branch || 'own branch')}` : ''}</span>${ic('chev', 12, 2)}</button>
          ${S.tbMenu === 'home:folder' ? `<div class="tb-menu" role="menu"><div class="tb-cap">${esc(pick.name)} works in</div><button type="button" data-act="open-folder" data-path="${esc(pick.worktree || pick.cwd || '')}"><span><b>${esc(pick.worktree || pick.cwd || S.data.home)}</b><small>${pick.worktree ? `Its own branch, ${esc(pick.branch || '')}. Your main copy stays untouched.` : pick.cwd === S.data.home ? 'Your home folder. It can reach any project in it.' : 'It edits this folder directly.'}</small></span>${ic('folder', 16)}</button><button type="button" data-act="new-agent"><span><b>Use another folder</b><small>Make an agent for that project, so each one keeps its own context.</small></span>${ic('plus', 16)}</button></div>` : ''}</div>` : ''}
        ${agentControls(pick, 'home')}
        <span class="sx-grow"></span>
        <button class="sx-send" type="submit" aria-label="Send" title="Send  ↵">${ic('send', 16, 2)}</button>
      </div>${menu}</form>
    <div class="sx-tray">${QUICK.filter(([, , p]) => p !== null).map(([icon, label]) => `<button type="button" data-act="quick" data-id="${QUICK.findIndex((q) => q[1] === label)}">${ic(icon, 15)}<span>${label}</span></button>`).join('')}</div>
  </div>`;

  // Agents, filtered like Discord's Friends tabs
  const f = ['all', 'working', 'needs'].includes(S.hf) ? S.hf : 'all';
  const ops = [...new Set(scope.map((a) => a.operator))];
  const fo = ops.includes(S.hop) ? S.hop : 'any';
  const list = scope.filter((a) => (f === 'all' || stateOf(a) === f) && (fo === 'any' || a.operator === fo));
  const tab = (id, label, n) => `<button class="htab2 ${f === id ? 'on' : ''}" data-act="hf" data-id="${id}" aria-pressed="${f === id}">${label}${n ? `<span class="n">${n}</span>` : ''}</button>`;
  const opTab = (id, label) => `<button class="htab2 op ${fo === id ? 'on' : ''}" data-act="hop" data-id="${id}" aria-pressed="${fo === id}">${id === 'any' ? '' : tile(id, 'xs')}${label}</button>`;
  const head = `<div class="agbar">${ic('agents', 18)}<h2>Agents</h2><span class="dsep"></span>
      ${tab('all', 'All')}${tab('working', 'Working', k)}${tab('needs', 'Waiting for you', scope.filter((a) => stateOf(a) === 'needs').length)}
      ${ops.length > 1 ? `<span class="agbar-div"></span>${opTab('any', 'Any tool')}${ops.map((o) => opTab(o, op({ operator: o }))).join('')}` : ''}
      <span class="sx-grow"></span><button class="btn second sm" data-act="new-agent">New agent</button></div>`;
  // A Discord member row, quietly: name with the tool as a small tag, what it's doing under it,
  // and on hover the two things you'd do (open the chat, more) where the status badge sits.
  const row = (a) => `<div class="hx-row dr" data-act="dm" data-id="${a.id}" role="button" tabindex="0" aria-label="Open ${esc(a.name)}">${avatar(a, 36, 'var(--hx-card)')}<span class="hx-main"><span class="hx-name">${esc(a.name)}<span class="dr-tag">${op(a)}</span><span class="hx-op">${esc(wsOf(a)?.name || base(a.cwd))}</span></span><span class="hx-line">${line(a)}</span></span><span class="dr-end">${badge(a)}<span class="dr-acts"><button class="dr-act" data-act="dm" data-id="${a.id}" aria-label="Open the chat with ${esc(a.name)}" title="Open chat">${ic('chat', 18)}</button><button class="dr-act" data-act="agent-edit" data-id="${a.id}" aria-label="More for ${esc(a.name)}" title="More">${ic('more', 18)}</button></span></span></div>`;
  const empty = f === 'working' ? 'Nobody is working right now.' : f === 'needs' ? 'Nobody is waiting for you.' : scope.length ? 'No agents match.' : 'No agents yet. Make one, or add a ready-made one from Discover.';

  // Ideas: only while you're getting started, and you can hide them
  const IDEAS = [
    { title: 'Your first week in Agent Lab', body: 'A few things that make your agents more useful. Do them in any order.', items: [['plug', 'Connect GitHub', 'view', 'connections'], ['book', 'Add a rule to your Playbook', 'view', 'memory'], ['folder', 'Create a workspace for a project', 'ws-create', ''], ['compass', 'Add a ready-made agent from Discover', 'view', 'discover']] },
    { title: 'Run agents side by side', body: 'Give each agent its own job and folder. Agent Lab tells you when two of them touch the same files.', items: [['branch', 'Fix a bug in one folder', 'quick', '1'], ['check', 'Review the changes in another', 'quick', '2'], ['chat', 'Bring in your Claude Code chats', 'view', 'messages'], ['inbox', 'See what needs you in Review', 'view', 'reviews']] },
  ];
  let hideIdeas = false; try { hideIdeas = localStorage.getItem('ideas:hidden') === '1'; } catch {}
  const idea = IDEAS[(S.ideaAt || 0) % IDEAS.length];
  const ideas = hideIdeas || scope.length > 3 ? '' : `<section class="sx-ideas" aria-label="Getting started">
    <div class="sx-ideas-head"><h2>Getting started</h2><span class="sx-grow"></span><button class="nav-btn sm" data-act="idea" data-id="-1" aria-label="Previous">${ic('chev', 14, 2)}</button><button class="nav-btn sm fwd" data-act="idea" data-id="1" aria-label="Next">${ic('chev', 14, 2)}</button><button class="nav-btn sm" data-act="ideas-hide" aria-label="Hide" title="Hide">${ic('x', 12, 2)}</button></div>
    <div class="sx-idea"><div class="sx-idea-l"><b>${idea.title}</b><p>${idea.body}</p></div><ul>${idea.items.map(([icon, label, act, id]) => `<li><button data-act="${act}" data-id="${id}">${ic(icon, 20)}<span>${label}</span><svg class="sx-go" width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M9 6C9 6 15 10.42 15 12C15 13.58 9 18 9 18" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button></li>`).join('')}</ul></div></section>`;

  // Right now (Discord's Active Now)
  const runs = [...S.runs.values()].filter((r) => r.agentId && ag(r.agentId) && agentIn(ag(r.agentId))).sort((x, y) => x.startedAt - y.startedAt);
  // Discord's Active Now card, for agents: who and which tool on top; under it, full width, what it's
  // doing, where (folder and branch), its latest output, and the two things you'd do: open it or stop it.
  const nowCard = ({ a, doing, since, preview, o, where, branch, key }) => `<article class="ac" ${key ? `data-act="dm" data-id="${a.id}" role="button" tabindex="0" aria-label="Open ${esc(a.name)}"` : ''}>
      <header class="ac-head"><span class="ac-av">${avatar({ ...a, last: null }, 40, 'var(--hx-raise)', false)}<i class="ac-dot" aria-hidden="true"></i></span><div class="ac-who"><b>${esc(a.name)}</b><span>Working · ${since}</span></div><span class="ac-tool" title="${OPS[o]?.name || o}">${tile(o, 'sm')}</span></header>
      <div class="ac-body">
        <div class="ac-doing">${esc(doing)}</div>
        ${where ? `<div class="ac-where">${ic('folder', 14)}<span>${esc(where)}</span>${branch ? `${ic('branch', 14)}<span>${esc(branch)}</span>` : ''}</div>` : ''}
        ${preview ? `<p class="ac-out">${esc(clip(preview, 220))}</p>` : ''}
        ${key ? `<div class="ac-acts"><button class="btn ghost sm" data-act="stop" data-id="${esc(key)}">Stop</button><button class="btn second sm" data-act="dm" data-id="${a.id}">Open chat</button></div>` : ''}
      </div></article>`;
  const live = runs.map((r) => { const a = ag(r.agentId); return nowCard({ a, doing: r.activity || 'Working', since: `<span data-since="${r.startedAt}">${elapsed(r.startedAt)}</span>`, preview: r.preview, o: r.operator || a.operator, where: base(a.cwd), branch: a.worktree ? a.branch : '', key: r.key || `agent:${a.id}` }); }).join('');
  const sample = S.preview ? nowCard({ a: SAMPLE[2], doing: 'Reading the Stripe v2 docs', since: '4 min', preview: 'The v2 API moves idempotency keys into headers and drops the old charge object. I am mapping every call site in checkout/ before changing anything.', o: 'claude-code', where: 'checkout-service', branch: 'stripe-v2' })
    + nowCard({ a: SAMPLE[3], doing: 'Running the test suite', since: '1 min', preview: '212 passed, 3 failing in auth/session.test.ts. Looking at the first failure now.', o: 'codex', where: 'web-app', branch: 'fix-session-expiry' })
    + nowCard({ a: SAMPLE[0], doing: 'Writing the migration plan', since: '12 s', preview: '', o: 'claude-code', where: 'api' }) : '';
  const recent = scope.filter((a) => stateOf(a) !== 'working' && (a.last?.at || 0)).sort((x, y) => (y.last?.at || 0) - (x.last?.at || 0)).slice(0, 5);
  const nowCol = `<aside class="now-col" aria-label="Right now">
      <h2>Right now${runs.length ? '<i class="live-dot on"></i>' : ''}${S.preview ? '<span class="sample">Example</span>' : ''}</h2>
      ${live || sample || `<p class="now-quiet">Nothing is running. <button class="link-like" data-act="preview">See an example</button></p>`}
      ${S.preview && !live ? '<button class="sample-off" data-act="preview">Hide the example</button>' : ''}
      ${recent.length ? `<h2 class="now-sub">Recently</h2><div class="now-recent">${recent.map((a) => `<button class="now-r" data-act="dm" data-id="${a.id}">${avatar(a, 28, 'var(--work)')}<span class="hx-main"><span class="hx-name">${esc(a.name)}</span><span class="hx-line">${outcomeLine(a)}</span></span></button>`).join('')}</div>` : ''}
    </aside>`;

  return `<div class="cc-wrap"><div class="hx-wrap"><div class="hx hx-refined">
    <header class="hx-head" data-optical><h1>${hello}</h1><p>${summary}</p></header>
    ${ask}
    ${w ? `<section class="hx-sec"><h2>Waiting for you</h2><div class="inbox">${aps.map((p, i) => approvalCard(p, i === 0, true)).join('')}${ovs.map(overlapCard).join('')}</div></section>` : ''}
    <section class="hx-sec ag-sec">${head}<div class="hx-list">${list.map(row).join('') || `<p class="hx-none">${empty}</p>`}</div></section>
    ${ideas}
  </div></div>${nowCol}</div>`;
}
// Clearly labelled example rows, only when you ask to see how the cards look busy.
const SAMPLE = [{ id: 's-juno', name: 'Juno' }, { id: 's-rook', name: 'Rook' }, { id: 's-wren', name: 'Wren' }, { id: 's-echo', name: 'Echo' }];
function sampleRow(a, sub, cls = '') { return `<div class="wrow is-sample">${avatar({ ...a, last: null }, 40, 'var(--work)', false)}<span class="wrow-main"><span class="wrow-name">${a.name}</span><span class="wrow-sub ${cls}">${sub}</span></span>${ic('chev', 16, 2)}</div>`; }
function sampleWait() { return sampleRow(SAMPLE[0], 'Wants to run npm test in checkout/', 'wait') + sampleRow(SAMPLE[1], 'Wants to edit src/auth/session.ts', 'wait'); }
function sampleRuns() { return sampleRow(SAMPLE[2], 'Reading the Stripe v2 docs · 4 min') + sampleRow(SAMPLE[3], 'Running the test suite · 1 min') + sampleRow(SAMPLE[0], 'Writing the migration plan · 12 s'); }
function profileView() {
  const all = agents(), sent = [], DAY = 864e5;
  let replies = 0;
  for (const a of all) for (const m of S.msgs.get(a.id) || []) { if (m.role === 'user' && m.at) sent.push(m.at); if (m.role === 'assistant') replies++; }
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const weeks = 26, end = today.getTime(), start = end - ((weeks - 1) * 7 + today.getDay()) * DAY;
  const counts = new Map();
  for (const t of sent) { const d = new Date(t); d.setHours(0, 0, 0, 0); counts.set(d.getTime(), (counts.get(d.getTime()) || 0) + 1); }
  let cells = '';
  for (let w = 0; w < weeks; w++) { cells += '<div class="hm-col">'; for (let d = 0; d < 7; d++) { const t = start + (w * 7 + d) * DAY; if (t > end) { cells += '<i class="hm-cell none"></i>'; continue; } const n = counts.get(t) || 0; cells += `<i class="hm-cell l${n === 0 ? 0 : n < 3 ? 1 : n < 6 ? 2 : n < 10 ? 3 : 4}" title="${n} ${n === 1 ? 'message' : 'messages'} on ${new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}"></i>`; } cells += '</div>'; }
  const handle = base(S.data.home);
  const card = (a) => `<button class="pcard" data-act="dm" data-id="${a.id}"><span class="pcard-top">${avatar(a, 32, 'var(--work)')}<span class="pcard-name">${esc(a.name)}</span><span class="pcard-state">${STATE[stateOf(a)].label}</span></span><span class="pcard-job">${esc(a.job || statusLine(a))}</span><span class="pcard-meta">${OPS[a.operator]?.name || a.operator} · ${esc(wsOf(a)?.name || base(a.cwd))}${lastAt(a) ? ` · ${shortAgo(lastAt(a))}` : ''}</span></button>`;
  return `<div class="col page profile">
    <div class="prof-head"><span class="prof-av">${ic('person', 40, 1.5)}</span><div><h2>You</h2><p class="meta">@${esc(handle)} · ${all.length} ${all.length === 1 ? 'agent' : 'agents'} · ${S.data.memory.length} ${S.data.memory.length === 1 ? 'rule' : 'rules'} in your Playbook</p></div></div>
    <div class="prof-stats"><div><b>${sent.length}</b><span>Messages sent</span></div><div><b>${replies}</b><span>Replies</span></div><div><b>${all.filter((a) => a.worktree).length}</b><span>Agents on a branch</span></div></div>
    <section class="section"><h3>Activity</h3><div class="hm">${cells}</div><p class="meta hm-legend">Your messages to agents over the last six months.</p></section>
    <section class="section"><h3>Your agents</h3><div class="pgrid">${all.map(card).join('') || '<p class="meta">No agents yet.</p>'}</div></section>
  </div>`;
}
function agentsView() {
  if (!agents().length) return emptyHero();
  const scope = agents().filter(agentIn);
  const empty = (a, b) => `<div class="empty"><div>${a}</div><div>${b}</div></div>`;
  if (S.tab === 'needs') {
    const aps = S.approvals.filter((p) => { const a = ag(p.agentId); return a && agentIn(a); });
    const ovs = S.overlaps.filter((o) => o.agents.some((id) => ag(id) && agentIn(ag(id))));
    return `<div class="col list-page"><div class="ag-count" style="margin-top:0">Waiting for you<span class="n">${aps.length + ovs.length}</span></div>
      <div class="inbox">${aps.map((p, i) => approvalCard(p, i === 0, true)).join('')}${ovs.map(overlapCard).join('')}</div>
      ${!aps.length && !ovs.length ? empty('Nothing is waiting for you', 'When an agent wants to change something, it asks here first.') : ''}</div>`;
  }
  const q = S.agq.trim().toLowerCase();
  const list = scope.filter(TABS_FILTER[S.tab]).filter((a) => !q || `${a.name} ${a.job || ''}`.toLowerCase().includes(q))
    .sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || b.createdAt - a.createdAt);
  const label = { all: 'All agents', working: 'Working', done: 'Done' }[S.tab];
  return `<div class="col list-page">
    <label class="ag-search">${ic('search')}<input id="agq" type="search" placeholder="Search" value="${esc(S.agq)}" aria-label="Search agents" autocomplete="off"></label>
    <div class="ag-count">${label}<span class="n">${list.length}</span></div>
    ${list.map(arow).join('')}
    ${list.length ? '' : q ? empty(`No agent matches “${esc(S.agq)}”`, 'Try another name.') : S.tab === 'working' ? empty('Nobody is working right now', 'Message an agent and it shows up here.') : scope.length ? empty('Nothing here yet', 'Agents show up here when they finish.') : empty('No agents in this workspace yet', 'New agents made here work in this folder.')}
  </div>`;
}

function emptyHero() {
  return `<div class="col"><div class="empty-hero">
    <h2>No agents yet</h2>
    <p>An agent is Claude Code or Codex with a name, a folder and a job of your choosing. It answers exactly as that tool does, and asks you before it changes anything.</p>
    <div class="row"><button class="btn primary" data-act="new-agent">New agent</button><button class="btn second" data-act="mavis-start">Bring in from Mavis</button></div>
  </div></div>`;
}

function arow(a) {
  const st = stateOf(a);
  const where = wsOf(a)?.name || (a.cwd && a.cwd !== S.data.home ? base(a.cwd) : '');
  return `<div class="arow" data-act="dm" data-id="${a.id}" role="button" tabindex="0">${avatar(a, 40, 'var(--work)')}
    <div class="arow-main"><div class="arow-name">${esc(a.name)}</div>
    <div class="arow-sub ellipsis ${st === 'needs' ? 'wait' : st === 'failed' ? 'fail' : ''}">${esc(statusLine(a))}${S.space === 'home' && where ? ` <span class="where">· ${esc(where)}</span>` : ''}</div></div>
    <div class="acts">${st === 'needs' ? `<button class="btn second" data-act="dm" data-id="${a.id}">Review</button>` : `<span class="row-state">${STATE[st].label}</span>`}<button class="icon-btn row-more" data-act="agent-edit" data-id="${a.id}" aria-label="Edit ${esc(a.name)}" title="Edit">${ic('more', 18)}</button></div></div>`;
}

function approvalCard(p, primary, withWho) {
  const a = ag(p.agentId);
  const detail = p.detail && p.detail !== p.line ? String(p.detail).slice(0, 600) : '';
  return `<div class="ask"><div class="ask-kicker"><i></i>Waiting for you</div>
    ${withWho && a ? `<button class="ask-who" data-act="dm" data-id="${a.id}">${avatar(a, 20, 'var(--i2)', false)}<span><b>${esc(a.name)}</b> wants to</span></button>` : ''}
    <div class="ask-title">${esc(p.verb)} ${esc(p.line)}</div>
    ${detail ? `<code class="cmd">${esc(detail)}</code>` : ''}
    <div class="ask-acts"><button class="btn ${primary ? 'primary' : 'second'}" data-act="approve" data-id="${p.id}" data-decision="allow">Allow</button>${p.canAlways ? `<button class="btn second" data-act="approve" data-id="${p.id}" data-decision="always">Always allow</button>` : ''}<button class="btn danger" data-act="approve" data-id="${p.id}" data-decision="deny">Don’t allow</button></div></div>`;
}

function overlapCard(o) {
  const [a, b] = o.agents.map(ag);
  if (!a || !b) return '';
  return `<div class="ask"><div class="ask-kicker"><i></i>Same files changed</div>
    <div class="ask-title">${esc(a.name)} and ${esc(b.name)} both changed ${esc(o.files.slice(0, 3).map(base).join(', '))}${o.files.length > 3 ? ` and ${o.files.length - 3} more` : ''}.</div>
    <p class="meta" style="margin:4px 0 0">Merge one first; the other then updates from it instead of conflicting.</p>
    <div class="ask-acts"><button class="btn second" data-act="review" data-id="${a.id}">Review ${esc(a.name)}</button><button class="btn second" data-act="review" data-id="${b.id}">Review ${esc(b.name)}</button></div></div>`;
}

// ---- agent conversation
const clock = (t) => new Date(t).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
function stamp(t) {
  if (!t) return '';
  const d = new Date(t), now = new Date(), y = new Date(now); y.setDate(now.getDate() - 1);
  return clock(t);
}
const dayLabel = (t) => { const d = new Date(t), now = new Date(), y = new Date(now); y.setDate(now.getDate() - 1); return d.toDateString() === now.toDateString() ? 'Today' : d.toDateString() === y.toDateString() ? 'Yesterday' : d.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }); };
const meAvatar = () => `<span class="me-av" aria-hidden="true">${ic('person', 20)}</span>`;
function convRow(a, sel) {
  const st = stateOf(a), t = lastAt(a), on = a.id === sel;
  const model = a.model ? (OPS[a.operator]?.models.find((m) => m[0] === a.model) || [0, a.model])[1] : '';
  const where = wsOf(a)?.name || base(a.cwd) || 'Home folder';
  const facts = [model, where, a.worktree ? `on ${a.branch}` : '', PERMS[a.permission] || PERMS.ask].filter(Boolean).map(esc).join(' · ');
  return `<div class="conv ${on ? 'on' : ''} st-${st}" data-act="dm" data-id="${a.id}" role="button" tabindex="0" aria-current="${on}">
    ${avatar(a, 40, 'var(--conv-bg)')}
    <span class="conv-main">
      <span class="conv-top"><span class="conv-name">${esc(a.name)}</span><span class="conv-op" title="Runs on ${OPS[a.operator]?.name || a.operator}">${OPS[a.operator]?.name || a.operator}</span></span>
      <span class="conv-sub ${st === 'needs' ? 'wait' : st === 'failed' ? 'fail' : ''}">${esc(statusLine(a))}</span>
      <span class="conv-facts">${facts}</span>
    </span>
    <span class="conv-end">${t ? `<span class="conv-time">${shortAgo(t)}</span>` : ''}${st === 'needs' ? '<i class="conv-dot" aria-label="Waiting for you"></i>' : st === 'working' ? '<i class="conv-dot busy" aria-label="Working"></i>' : ''}</span>
    <button class="conv-more" data-act="agent-edit" data-id="${a.id}" aria-label="More for ${esc(a.name)}" title="More">${ic('more', 18)}</button>
  </div>`;
}
// A workspace works like a Slack workspace or Discord server for one project: shortcuts to what
// needs you (Activity, Changes, Runs, Rules), one channel everyone posts in, and a DM row per agent.
const WS_VIEWS = { 'ws-activity': ['inbox', 'Activity'], 'ws-changes': ['branch', 'Changes'], 'ws-runs': ['chart', 'Runs'], 'ws-rules': ['book', 'Rules'] };
// Categories of text channels, like a Discord server. A workspace without any starts with one.
const wsCats = (w) => (w.categories?.length ? w.categories : [{ id: 'text', name: 'Text channels', open: true, channels: [{ id: 'general', name: 'general' }] }]);
const wsChannel = (w, id) => wsCats(w).flatMap((c) => c.channels).find((x) => x.id === id) || wsCats(w).flatMap((c) => c.channels)[0] || null;
const cid = () => `c${Math.random().toString(36).slice(2, 10)}`;
async function saveCats(w, cats) {
  const out = await run(() => lab.call('workspace:update', w.id, { categories: cats }));
  if (out) { Object.assign(w, out); renderView(true); renderTop(); }
  return out;
}
// One small dialog for every channel and category edit: make, rename, delete.
function openChanForm(spec) {
  S.chanDraft = spec;
  const { kind, mode, name = '' } = spec, isCh = kind === 'channel';
  const title = mode === 'new' ? (isCh ? 'Create a text channel' : 'Create a category') : (isCh ? 'Edit channel' : 'Edit category');
  layer(modal(title, `<div class="m-head"><h3>${title}</h3><p>${isCh ? 'Agents in this workspace can be messaged here. Lowercase, with dashes instead of spaces.' : 'A group of channels, like a section of a server.'}</p></div>
    <form class="m-body" id="chanForm"><div class="field"><label for="chName">${isCh ? 'Channel name' : 'Category name'}</label>${isCh ? `<div class="ch-input">${ic('hash', 16)}<input id="chName" value="${esc(name)}" maxlength="40" placeholder="new-channel" autofocus autocomplete="off"></div>` : `<input id="chName" value="${esc(name)}" maxlength="40" placeholder="Category" autofocus autocomplete="off">`}</div></form>`,
    `${mode === 'edit' && spec.canDelete ? `<button class="btn danger" data-act="chan-del">Delete ${isCh ? 'channel' : 'category'}</button>` : '<button class="btn second" data-act="close-layer-btn">Cancel</button>'}<span style="flex:1"></span><button class="btn primary" data-act="chan-save">${mode === 'new' ? 'Create' : 'Save'}</button>`));
}
async function saveChanForm() {
  const d = S.chanDraft, w = curWs(); if (!d || !w) return;
  const name = $('#chName')?.value.trim(); if (!name) { $('#chName')?.focus(); return; }
  const cats = structuredClone(wsCats(w));
  if (d.kind === 'category') {
    if (d.mode === 'new') cats.push({ id: cid(), name, open: true, channels: [] });
    else { const c = cats.find((x) => x.id === d.id); if (c) c.name = name; }
  } else {
    const c = cats.find((x) => x.id === d.cat);
    if (d.mode === 'new') { const id = cid(); c?.channels.push({ id, name }); closeLayer(); if (await saveCats(w, cats)) go({ kind: 'channel', id }); return; }
    const ch = c?.channels.find((x) => x.id === d.id); if (ch) ch.name = name;
  }
  closeLayer(); await saveCats(w, cats);
}
function wsChanges(pool) {
  const out = [];
  for (const a of pool) { if (!a.worktree) continue; const r = reviewCache.get(a.id); if (r?.files?.length) out.push([a, r.files]); }
  return out;
}
function wsRuns(pool) { return pool.flatMap((a) => (a.ledger || []).map((x) => ({ a, ...x }))).sort((x, y) => y.at - x.at); }
function projectView() {
  const w = curWs(), v = S.view;
  const pool = agents().filter(agentIn);
  const list = pool.slice().sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || lastAt(b) - lastAt(a));
  const short = (k) => { const [icon, label] = WS_VIEWS[k], n = 0; return `<button class="snav ${v.kind === k ? 'on' : ''}" data-act="ws-view" data-id="${k}">${ic(icon, 20)}<span class="t">${label}</span>${n ? `<span class="${k === 'ws-activity' ? 'count' : 'ws-n'}">${n}</span>` : ''}</button>`; };
  const agentRow = (a) => { const st = stateOf(a), n = approvalsFor(a.id).length; return `<button class="snav ws-agent ${v.kind === 'dm' && v.id === a.id ? 'on' : ''}" data-act="dm" data-id="${a.id}" title="${esc(statusLine(a))}">${avatar(a, 20, 'var(--work)', false)}<span class="t">${esc(a.name)}</span>${n ? `<span class="count">${n}</span>` : st === 'working' ? '<i class="ws-dot busy" aria-label="Working"></i>' : st === 'failed' ? '<i class="ws-dot fail" aria-label="Failed"></i>' : ''}</button>`; };
  const detail = v.kind === 'dm' ? dmView() : WS_VIEWS[v.kind] ? '<div class="blank" aria-hidden="true"></div>' : channelView(w, pool, wsChannel(w, v.id || 'general'));
  requestAnimationFrame(fadeNames);
  return `<div class="split msgs wsx">
    <div class="pane-list scroll" id="paneList">
      <div class="ws-bar"><button class="ws-name" data-act="proj-edit" title="${esc(w.name)} settings" aria-label="${esc(w.name)} settings"><span class="ws-name-t">${esc(w.name)}</span>${ic('chev', 16, 2)}</button><button class="mf-new" data-act="new-agent" aria-label="New agent in ${esc(w.name)}" title="New agent  ⌘N">${ic('pen', 18)}</button></div>
      <nav class="ws-nav" aria-label="${esc(w.name)}">
        ${Object.keys(WS_VIEWS).map(short).join('')}
        <div class="side-ws ws-cat"><span>Channels</span></div>
        <button class="snav chan-row ${v.kind === 'channel' ? 'on' : ''}" data-act="channel" data-id="general" title="Everything the agents here say">${ic('hash', 20)}<span class="t">general</span></button>
        <div class="side-ws with-add ws-cat"><span>Agents</span><button data-act="new-agent" aria-label="New agent in ${esc(w.name)}" title="New agent">${ic('plus', 16)}</button></div>
        ${list.map(agentRow).join('') || '<p class="meta side-empty">No agents here yet. Press + to add one.</p>'}
      </nav>
    </div>
    <div class="pane-detail scroll" id="paneDetail">${detail}</div>
  </div>`;
}
function wsActivityView(w) {
  return `<div class="ws-page">${reviewsView('Activity', `What the agents in ${esc(w.name)} need from you, most urgent first: requests to run something, and finished work to look at.`)}</div>`;
}
function wsChangesView(w, pool) {
  const own = pool.filter((a) => a.worktree), list = wsChanges(pool), loading = own.some((a) => reviewCache.get(a.id)?.loading);
  const sum = (f, k) => f.reduce((n, x) => n + x[k], 0);
  const card = ([a, files]) => `<article class="chg">
      <header class="chg-head">${avatar(a, 28, 'var(--hx-card)', false)}<div class="chg-who"><b>${esc(a.name)}</b><span>${esc(a.branch || 'its own branch')} · ${files.length} ${files.length === 1 ? 'file' : 'files'} <span class="c-add">+${sum(files, 'add')}</span> <span class="c-del">−${sum(files, 'del')}</span></span></div><button class="btn primary sm" data-act="review" data-id="${a.id}">Review changes</button></header>
      <ul class="chg-files">${files.slice(0, 6).map((f) => `<li><span class="chg-path ellipsis" title="${esc(f.path)}">${esc(f.path)}</span><span class="c-add">+${f.add}</span><span class="c-del">−${f.del}</span></li>`).join('')}${files.length > 6 ? `<li class="meta">and ${files.length - 6} more</li>` : ''}</ul>
    </article>`;
  return `<div class="ws-page"><div class="pg">
    <header class="pg-head"><h1>Changes</h1><p>Uncommitted work from the agents in ${esc(w.name)} that run on their own branch, so nothing touches your copy until you review it.</p></header>
    ${list.length ? list.map(card).join('') : `<p class="rv-empty">${loading ? 'Reading each agent’s branch…' : own.length ? 'No changes yet. When an agent edits files on its branch, they show up here.' : 'No agent here runs on its own branch. Turn on “Its own branch and folder” when you make one, and its work collects here.'}</p>`}
  </div></div>`;
}
function wsRunsView(w, pool) {
  const runs = wsRuns(pool), wk = runs.filter((x) => x.at >= weekStart());
  const cost = wk.reduce((n, x) => n + (x.cost || 0), 0), ms = wk.reduce((n, x) => n + (x.ms || 0), 0);
  return `<div class="ws-page"><div class="pg">
    <header class="pg-head"><h1>Runs</h1><p>Every run in ${esc(w.name)}, newest first. Claude Code reports cost; Codex reports time only.</p></header>
    <div class="use-stats"><div><b>${wk.length}</b><span>Runs this week</span></div><div><b>${ms ? dur(ms) : '–'}</b><span>Time working</span></div><div><b>${cost ? money(cost) : '–'}</b><span>Cost reported</span></div></div>
    <section class="pg-sec"><h2>Recent runs</h2>${runs.length ? `<div class="use-table runs" role="table"><div class="use-tr head" role="row"><span role="columnheader">Agent</span><span role="columnheader">When</span><span role="columnheader">Took</span><span role="columnheader">Cost</span><span role="columnheader">Result</span></div>${runs.slice(0, 50).map((x) => `<button class="use-tr" role="row" data-act="dm" data-id="${x.a.id}"><span role="cell" class="use-who">${avatar(x.a, 24, 'var(--work)', false)}${esc(x.a.name)}</span><span role="cell">${ago(x.at)}</span><span role="cell">${x.ms ? dur(x.ms) : '–'}</span><span role="cell">${x.cost != null ? money(x.cost) : '–'}</span><span role="cell" class="${x.ok ? 'run-ok' : 'run-fail'}">${x.ok ? 'Finished' : 'Failed'}</span></button>`).join('')}</div>` : '<p class="rv-empty">No runs yet. Runs are counted from your agents’ next one.</p>'}</section>
  </div></div>`;
}
function channelView(w, pool, ch = { id: 'general', name: 'general' }) {
  const items = [], isGen = ch.id === 'general';
  for (const a of pool) for (const m of S.msgs.get(a.id) || []) if ((m.role === 'user' || m.role === 'assistant') && m.at && (m.ch ? m.ch === ch.id : isGen)) items.push({ a, m });
  items.sort((x, y) => x.m.at - y.m.at);
  let prevKey = null, prevAt = 0, day = '';
  const lines = items.slice(-300).map(({ a, m }) => {
    let out = '';
    const d = new Date(m.at).toDateString();
    if (d !== day) { out += `<div class="day">${dayLabel(m.at)}</div>`; day = d; prevKey = null; }
    const mine = m.role === 'user', k = `${mine ? 'me' : a.id}:${a.id}`;
    const cont = prevKey === k && m.at - prevAt < 7 * 60e3;
    out += `<div class="ln ${cont ? 'cont' : ''} ${mine ? 'mine' : ''}"><div class="ln-av">${cont ? `<span class="ln-hover-time">${clock(m.at)}</span>` : mine ? meAvatar() : avatar(a, 40, null, false)}</div><div class="ln-body">${cont ? '' : `<div class="ln-head"><span class="ln-name">${mine ? `You <span class="to">to ${esc(a.name)}</span>` : `<button class="name-link" data-act="dm" data-id="${a.id}">${esc(a.name)}</button>`}</span><span class="ln-time">${stamp(m.at)}</span></div>`}<div class="ln-text">${md(mine && m.text.length > 1500 ? `${m.text.slice(0, 1200)}…` : m.text)}</div></div></div>`;
    prevKey = k; prevAt = m.at;
    return out;
  }).join('');
  const aps = S.approvals.filter((p) => pool.some((a) => a.id === p.agentId)).map((p, i) => approvalCard(p, i === 0, true)).join('');
  const working = pool.filter((a) => S.runs.has(`agent:${a.id}`));
  const typing = working.length ? `<div class="typing"><i></i><i></i><i></i>&nbsp;<b>${working.map((a) => esc(a.name)).join(', ')}</b>&nbsp;${working.length === 1 ? 'is' : 'are'} working</div>` : '';
  const intro = isGen ? '' : `<div class="ch-intro"><span class="ch-intro-ic">${ic('hash', 32)}</span><h2>Welcome to #${esc(ch.name)}</h2><p>This is the start of #${esc(ch.name)}. Start a message with @ and an agent’s name to ask it something here; its reply stays in this channel.</p></div>`;
  if (!isGen) return `<div class="convo"><div class="chat-head">${ic('hash', 20)}<span class="chat-name">${esc(ch.name)}</span></div><div class="thread">${intro}${lines}${aps}</div>${composer(pool.length ? `Message #${ch.name} — start with @${pool[0].name}` : `Message #${ch.name}`, `chan:${w.id}:${ch.id}`, false, typing)}</div>`;
  return `<div class="convo"><div class="chat-head">${ic('hash', 20)}<span class="chat-name">general</span><span class="meta">Everything the agents in ${esc(w.name)} say</span></div><div class="thread">
    ${lines}
    ${aps}
  </div>${composer(pool.length ? `Message #general — start with @${pool[0].name}` : 'Message #general', `chan:${w.id}`, false, typing)}</div>`;
}
const MFILTERS = [['all', 'All'], ['needs', 'Waiting for you'], ['working', 'Working'], ['failed', 'Failed'], ['claude-code', 'Claude Code'], ['codex', 'Codex']];
const CFILTERS = [['all', 'All'], ['claude-code', 'Claude Code'], ['codex', 'Codex']];
const CHAT_DAYS = 30;
const mfPass = (a) => { const f = S.mfilter; return f === 'all' || (OPS[f] ? a.operator === f : stateOf(a) === f); };
const SRC = [['agents', 'Agents'], ['claude-code', 'Claude Code'], ['codex', 'Codex']];
function srcCount(k) { if (k === 'agents') return agents().filter(agentIn).length || ''; return S.chats[k] ? visibleChats(k).filter(chatIn).length : ''; }
function chatList(q, src) {
  if (!S.data.operators[src]?.path) return `<div class="src-empty"><b>${OPS[src].name} isn’t on this Mac</b><span>Install it and its chats show up here.</span></div>`;
  const ops = [src];
  const missing = ops.filter((op) => !S.chats[op]);
  if (missing.length) { Promise.all(missing.map((op) => loadChats(op))).then(() => renderView(true), () => {}); return '<p class="meta side-empty">Reading your chats…</p>'; }
  const all = ops.flatMap((op) => visibleChats(op).filter(chatIn)).filter((c) => !q || `${c.title} ${c.cwd || ''}`.toLowerCase().includes(q)).sort((a, b) => b.updated - a.updated);
  const recent = q ? all.slice(0, 60) : all.slice(0, S.chatsLimit);
  const older = q ? 0 : all.length - recent.length;
  const sel = S.view.kind === 'chat' ? `${S.view.op}:${S.view.id}` : null;
  const row = (c) => `<div class="conv chatrow ${sel === `${c.operator}:${c.id}` ? 'on' : ''}" data-act="chat-open" data-op="${c.operator}" data-id="${esc(c.id)}" role="button" tabindex="0">
      <span class="chat-tile">${tile(c.operator, 'lg')}</span>
      <span class="conv-main"><span class="conv-top"><span class="conv-name">${esc(c.title)}</span></span>
      <span class="conv-facts">${OPS[c.operator]?.name} · ${esc(base(c.cwd) || 'No folder')}</span></span>
      <span class="conv-end"><span class="conv-time">${shortAgo(c.updated)}</span></span></div>`;
  return (recent.map(row).join('') || `<p class="meta side-empty">${q ? 'No chat matches.' : 'No chats yet.'}</p>`)
    + (older > 0 ? `<button class="show-older" data-act="chats-older">Show ${Math.min(25, older)} more</button>` : '');
}
function chatView() {
  const { op, id } = S.view, c = (S.chats[op] || []).find((x) => x.id === id);
  if (!c) return '<div class="empty"><div>This chat is gone</div></div>';
  const tkey = `${op}:${id}`, rkey = `chat:${op}:${id}`;
  const items = S.transcripts.get(tkey);
  if (!items) {
    lab.call('chat:transcript', op, id).then((t) => { S.transcripts.set(tkey, t); renderView(false); }, (e) => { S.transcripts.set(tkey, []); toast(e.message, true); });
    return `<div class="convo"><div class="chat-head">${tile(op, 'sm')}<span class="chat-name ellipsis">${esc(c.title)}</span></div><div class="thread"><p class="meta" style="padding:8px">Opening this chat…</p></div></div>`;
  }
  const all = [...items.slice(-300), ...(S.live.get(rkey) || [])];
  let prev = null;
  const lines = all.map((m) => {
    if (m.role === 'tool') return `<div class="step"><b>${esc(m.verb || '')}</b> <span>${esc(m.text)}</span></div>`;
    if (m.role !== 'user' && m.role !== 'assistant') return '';
    const mine = m.role === 'user', cont = prev === m.role;
    prev = m.role;
    return `<div class="ln ${cont ? 'cont' : ''} ${mine ? 'mine' : ''}"><div class="ln-av">${cont ? '' : mine ? meAvatar() : `<span class="chat-tile">${tile(op, 'lg')}</span>`}</div><div class="ln-body">${cont ? '' : `<div class="ln-head"><span class="ln-name">${mine ? 'You' : OPS[op].name}</span></div>`}<div class="ln-text">${md(mine && m.text.length > 4000 ? `${m.text.slice(0, 3999)}…` : m.text)}</div></div></div>`;
  }).join('');
  const r = S.runs.get(rkey), draft = S.drafts.get(rkey);
  const aps = S.approvals.filter((p) => p.key === rkey).map((p, i) => approvalCard(p, i === 0, false)).join('');
  const working = r && !draft && !aps ? `<div class="typing"><i></i><i></i><i></i>&nbsp;<b>${OPS[op].name}</b>&nbsp;is working · ${esc(r.activity || 'Working')}</div>` : '';
  return `<div class="convo"><div class="chat-head">${tile(op, 'sm')}<span class="chat-name ellipsis">${esc(c.title)}</span><span class="meta">${OPS[op].name} · ${esc(base(c.cwd) || 'No folder')}</span></div><div class="thread">
    ${items.length > 300 ? `<p class="meta" style="padding:0 8px">Showing the latest 300 of ${items.length} messages.</p>` : ''}
    ${lines || '<p class="meta" style="padding:8px">This chat has no messages to show.</p>'}
    ${draft ? `<div class="ln"><div class="ln-av"><span class="chat-tile">${tile(op, 'lg')}</span></div><div class="ln-body"><div class="ln-text draft" data-draft="${rkey}">${md(draft)}</div></div></div>` : ''}
    ${aps}
  </div>${composer(`Continue in ${OPS[op].name}`, rkey, r, working)}</div>`;
}
const MF = [['all', 'All'], ['needs', 'Waiting for you'], ['agents', 'Agents'], ['tools', 'Claude Code and Codex'], ['claude-code', 'Claude Code'], ['codex', 'Codex']];
// Claude Code and Codex sit in Messages as contacts: one row each, their chats inside.
function toolRow(op, sel) {
  const list = visibleChats(op).filter(chatIn).sort((a, b) => b.updated - a.updated);
  const last = list[0];
  return `<div class="conv toolrow ${sel ? 'on' : ''}" data-act="tool-open" data-id="${op}" role="button" tabindex="0">
    <span class="chat-tile">${tile(op, 'lg')}</span>
    <span class="conv-main">
      <span class="conv-top"><span class="conv-name">${OPS[op].name}</span><span class="conv-op">${list.length} ${list.length === 1 ? 'chat' : 'chats'}</span></span>
      <span class="conv-sub">${last ? esc(last.title) : 'No chats yet'}</span>
      <span class="conv-facts">${last ? `Latest in ${esc(base(last.cwd) || 'no folder')}` : 'Your own chats with it, outside Agent Lab'}</span>
    </span>
    <span class="conv-end">${last ? `<span class="conv-time">${shortAgo(last.updated)}</span>` : ''}</span>
  </div>`;
}
function people(list, q) {
  const f = S.mfilter, v = S.view;
  const sel = v.kind === 'dm' ? v.id : null, tsel = v.kind === 'tool' || v.kind === 'chat' ? v.op : null;
  const items = [];
  if (f === 'all' || f === 'agents' || f === 'needs') for (const a of list) if (f !== 'needs' || stateOf(a) === 'needs') items.push([lastAt(a), convRow(a, sel)]);
  for (const op of ['claude-code', 'codex']) {
    if (!(f === 'all' || f === 'tools' || f === op) || !S.data.operators[op]?.path) continue;
    if (q && !OPS[op].name.toLowerCase().includes(q)) continue;
    if (!S.chats[op]) { loadChats(op).then(() => renderView(true), () => {}); continue; }
    items.push([visibleChats(op).filter(chatIn).reduce((m, c) => Math.max(m, c.updated), 0), toolRow(op, tsel === op)]);
  }
  items.sort((x, y) => y[0] - x[0]);
  return items.length ? items.map((x) => x[1]) : [`<p class="meta side-empty">${f === 'needs' ? 'Nothing is waiting for you.' : 'Nothing matches.'}</p>`];
}
function toolView(op) {
  const v = S.view;
  return `<div class="toolsplit">
    <div class="threads scroll" id="paneThreads">
      <div class="threads-head">${tile(op, 'sm')}<b>${OPS[op].name}</b><span class="meta">${visibleChats(op).filter(chatIn).length} chats</span></div>
      <label class="ag-search threads-search">${ic('search', 14)}<input id="tq" type="search" placeholder="Search ${OPS[op].name} chats" value="${esc(S.tq)}" aria-label="Search ${OPS[op].name} chats" autocomplete="off"></label>
      ${chatList(S.tq.trim().toLowerCase(), op)}
    </div>
    <div class="threadview scroll" id="paneDetail">${v.kind === 'chat' ? chatView() : `<div class="msg-empty"><div class="msg-empty-art">${tile(op, 'xl')}</div><h2>${OPS[op].name}</h2><p>Pick one of your ${OPS[op].name} chats to read it or keep it going.</p></div>`}</div>
  </div>`;
}
function messagesView() {
  const q = S.mq.trim().toLowerCase();
  const list = agents().filter(agentIn).filter((a) => !q || `${a.name} ${a.job || ''}`.toLowerCase().includes(q)).sort((a, b) => {
    const la = lastAt(a), lb = lastAt(b);
    return STATE[stateOf(a)].o - STATE[stateOf(b)].o || lb - la;
  });
  const sel = S.view.kind === 'dm' ? S.view.id : null;
  const row = (a) => convRow(a, sel);
  const empty = `<div class="msg-empty"><div class="msg-empty-art">${ic('chat', 48, 1.4)}</div><h2>Your messages</h2><p>Pick an agent on the left to pick up where you left off, or make a new one.</p><button class="btn primary" data-act="new-agent">New agent</button></div>`;
  return `<div class="split msgs">
    <div class="pane-list scroll" id="paneList">
      <div class="msgs-head x"><span>Messages</span>
        <div class="mf"><button class="mf-pill" data-act="mf-open" aria-haspopup="menu" aria-expanded="${!!S.mfOpen}">${MF.find((f) => f[0] === S.mfilter)?.[1] || 'All'}${ic('chev', 14, 2)}</button>
          ${S.mfOpen ? `<div class="mf-menu" role="menu">${MF.map(([k, l], i) => `${i === 2 || i === 4 ? '<div class="mf-sep"></div>' : ''}<button role="menuitemradio" aria-checked="${S.mfilter === k}" data-act="mf-set" data-id="${k}"><span>${l}</span>${S.mfilter === k ? ic('check', 16, 2) : ''}</button>`).join('')}</div>` : ''}
          <button class="mf-new" data-act="new-agent" aria-label="New agent" title="New agent  ⌘N">${ic('pen', 18)}</button></div></div>
      <label class="ag-search msgs-search x">${ic('search')}<input id="mq" type="search" placeholder="Search" value="${esc(S.mq)}" aria-label="Search agents and tools" autocomplete="off"></label>
      <div class="conv-list">${people(list, q).join('') || `<p class="meta side-empty">${agents().length ? 'No agent matches.' : 'No agents yet.'}</p>`}</div>
    </div>
    ${S.view.kind === 'tool' || S.view.kind === 'chat' ? `<div class="pane-detail">${toolView(S.view.op)}</div>` : `<div class="pane-detail scroll" id="paneDetail">${sel ? dmView() : empty}</div>`}
  </div>`;
}
function lastAt(a) { const m = S.msgs.get(a.id); return (m && m.length && m[m.length - 1].at) || a.last?.at || a.createdAt || 0; }
function shortAgo(t) { const s = Math.max(1, (Date.now() - t) / 1000); if (s < 60) return 'now'; const m = s / 60; if (m < 60) return `${Math.round(m)}m`; const h = m / 60; if (h < 24) return `${Math.round(h)}h`; const d = h / 24; if (d < 7) return `${Math.round(d)}d`; return new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); }
function dmView() {
  const a = ag(S.view.id);
  if (!a) return '<div class="col"><div class="empty"><div>This agent was removed</div></div></div>';
  const key = `agent:${a.id}`, r = S.runs.get(key), msgs = S.msgs.get(a.id) || [];
  const ws = wsOf(a);
  const model = a.model ? (OPS[a.operator]?.models.find((m) => m[0] === a.model) || [0, a.model])[1] : '';
  const facts = [
    `<span>${OPS[a.operator]?.name || a.operator}${model ? `, ${esc(model)}` : ''}</span>`,
    `<button data-act="open-folder" data-path="${esc(a.cwd)}" title="${esc(a.cwd)}">${esc(ws?.name || base(a.cwd))}</button>`,
    a.worktree ? `<button data-act="review" data-id="${a.id}">Review ${esc(a.branch)}</button>` : '',
    `<span>${PERMS[a.permission] || PERMS.ask}</span>`,
  ].filter(Boolean).join('');
  let prev = null, prevAt = 0, day = '';
  const lines = msgs.map((m) => {
    if (m.role === 'tool') return `<div class="step"><b>${esc(m.verb)}</b> <span>${esc(m.text)}</span></div>`;
    if (m.role === 'error') return `<div class="step err"><b>${m.text === 'Stopped.' ? 'Stopped' : 'Error'}</b> <span>${esc(m.text === 'Stopped.' ? 'You stopped this run.' : m.text)}</span></div>`;
    let out = '';
    const d = m.at ? new Date(m.at).toDateString() : day;
    if (d !== day && m.at) { out += `<div class="day">${dayLabel(m.at)}</div>`; day = d; prev = null; }
    const cont = prev === m.role && m.at - prevAt < 7 * 60e3;
    const mine = m.role === 'user';
    const text = mine && m.text.length > 1500 ? `${m.text.slice(0, 1200)}\n\n…${m.text.length - 1200} more characters of context` : m.text;
    out += `<div class="ln ${cont ? 'cont' : ''} ${mine ? 'mine' : ''}"><div class="ln-av">${cont ? `<span class="ln-hover-time">${clock(m.at)}</span>` : mine ? meAvatar() : avatar(a, 40, null, false)}</div><div class="ln-body">${cont ? '' : `<div class="ln-head"><span class="ln-name">${mine ? 'You' : esc(a.name)}</span><span class="ln-time">${stamp(m.at)}</span></div>`}<div class="ln-text">${md(text)}</div></div></div>`;
    prev = m.role; prevAt = m.at || prevAt;
    return out;
  }).join('');
  const draft = S.drafts.get(key);
  const aps = approvalsFor(a.id).map((p, i) => approvalCard(p, i === 0, false)).join('');
  const draftCont = prev === 'assistant';
  const working = r && !draft && !aps ? `<div class="typing"><i></i><i></i><i></i>&nbsp;<b>${esc(a.name)}</b>&nbsp;is working · ${esc(r.activity || 'Working')}</div>` : '';
  return `<div class="convo"><div class="chat-head">${avatar(a, 24, 'var(--work)')}<span class="chat-name">${esc(a.name)}</span><span class="meta">${STATE[stateOf(a)].label}</span><span class="chat-end">${a.worktree ? `<button class="btn second" data-act="review" data-id="${a.id}">Review changes</button>` : ''}<button class="icon-btn" data-act="agent-edit" data-id="${a.id}" aria-label="Edit ${esc(a.name)}" title="Edit">${ic('more')}</button></span></div><div class="thread">
    <div class="intro">${avatar(a, 80, 'var(--work)')}<h2>${esc(a.name)}</h2><p class="selectable">${a.job ? esc(a.job) : `This is the start of your conversation with ${esc(a.name)}. It answers exactly the way ${OPS[a.operator]?.name || 'its tool'} does, and asks before it changes anything.`}</p><div class="facts">${facts}</div></div>
    ${lines}
    ${draft ? `<div class="ln ${draftCont ? 'cont' : ''}"><div class="ln-av">${draftCont ? '' : avatar(a, 40, null, false)}</div><div class="ln-body">${draftCont ? '' : `<div class="ln-head"><span class="ln-name">${esc(a.name)}</span><span class="ln-time">now</span></div>`}<div class="ln-text draft" data-draft="${key}">${md(draft)}</div></div></div>` : ''}
    ${aps}
  </div>${composer(`Message @${a.name}`, key, r, working)}</div>`;
}

// One message box everywhere (workspaces, Messages, chats), laid out like Claude's:
// + on the left, the message, send or stop on the right, and one quiet line under it with
// the agent's model and access, and what it's doing right now.
function composer(placeholder, key, running, above = '') {
  const k = String(key), a = k.startsWith('agent:') ? ag(k.slice(6)) : null;
  const chan = k.startsWith('chan:') ? agents().filter(agentIn) : null;
  const r = running ? S.runs.get(k) : null;
  const plus = S.plusOpen === k ? `<div class="cmp-menu" role="menu">${chan?.length ? `<div class="tb-cap">Mention an agent</div>${chan.slice(0, 6).map((x) => `<button type="button" role="menuitem" data-act="cmp-mention" data-id="${esc(x.name)}">${avatar(x, 20, 'var(--work)', false)}<span>${esc(x.name)}</span></button>`).join('')}<div class="mf-sep"></div>` : ''}<button type="button" role="menuitem" data-act="cmp-file">${ic('file', 18)}<span>Add a file’s path</span></button><button type="button" role="menuitem" data-act="cmp-folder">${ic('folder', 18)}<span>Add a folder’s path</span></button></div>` : '';
  const status = running ? `<span class="cmp-status"><i class="cmp-spin" aria-hidden="true"></i>${esc(r?.activity || 'Working')}</span>` : '';
  const foot = a || status ? `<div class="cmp-foot">${status}<span class="cmp-grow"></span>${a ? agentControls(a, 'chat') : ''}</div>` : '';
  return `<form class="composer cbox" id="cmpForm" data-key="${esc(key)}" autocomplete="off">${above || '<div class="typing"></div>'}<div class="cmp"><span class="cmp-plus-wrap"><button type="button" class="cmp-plus" data-act="cmp-plus" data-id="${esc(key)}" aria-haspopup="menu" aria-expanded="${S.plusOpen === k}" aria-label="Add to message" title="Add">${ic('plus', 22)}</button>${plus}</span><textarea id="cmpInput" rows="1" placeholder="${esc(placeholder)}" aria-label="${esc(placeholder)}"></textarea><span class="cmp-tools">${SPEECH ? `<button type="button" class="cmp-tool cmp-mic ${S.listening ? 'on' : ''}" data-act="cmp-mic" aria-pressed="${!!S.listening}" aria-label="${S.listening ? 'Stop dictating' : 'Dictate'}" title="${S.listening ? 'Stop dictating' : 'Dictate'}">${ic('mic', 22)}</button>` : ''}${running ? `<button class="send stop" type="button" data-act="stop" data-id="${esc(key)}" aria-label="Stop" title="Stop">${ic('stop', 22)}</button>` : ''}</span><button type="submit" class="cmp-submit" tabindex="-1" aria-hidden="true"></button></div>${foot}</form>`;
}
// Dictation with the browser's own speech recognition, where it has one.
const SPEECH = window.SpeechRecognition || window.webkitSpeechRecognition || null;
let rec = null;
function toggleDictation() {
  if (rec) { rec.stop(); return; }
  const i = $('#cmpInput'); if (!i || !SPEECH) return;
  const start = i.value ? `${i.value.replace(/\s*$/, '')} ` : '';
  rec = new SPEECH(); rec.continuous = true; rec.interimResults = true; rec.lang = navigator.language || 'en-US';
  rec.onresult = (e) => { const t = [...e.results].map((r) => r[0].transcript).join(''); const box = $('#cmpInput'); if (box) { box.value = start + t; autoGrow(); } };
  rec.onerror = (e) => { if (e.error !== 'aborted' && e.error !== 'no-speech') toast(e.error === 'not-allowed' ? 'Allow the microphone to dictate.' : 'Dictation isn’t available here.', true); };
  rec.onend = () => { rec = null; S.listening = false; $('.cmp-mic')?.classList.remove('on'); $('.cmp-mic')?.setAttribute('aria-pressed', 'false'); $('#cmpInput')?.focus(); };
  rec.start(); S.listening = true; $('.cmp-mic')?.classList.add('on'); $('.cmp-mic')?.setAttribute('aria-pressed', 'true');
}
// Put text into the message box where the cursor is.
function cmpInsert(text) {
  const i = $('#cmpInput'); if (!i) return;
  const at = i.selectionStart ?? i.value.length, before = i.value.slice(0, at), after = i.value.slice(i.selectionEnd ?? at);
  const pad = before && !/\s$/.test(before) ? ' ' : '';
  i.value = `${before}${pad}${text} ${after}`; i.focus(); const pos = (before + pad + text).length + 1; i.setSelectionRange(pos, pos); autoGrow();
}

// ---- operator: chat list beside the open chat
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

// ---- review queue: everything your agents need from you, most urgent first. Quiet by design:
// nothing pings you; you come here when you choose to.
// What you've already marked as reviewed: the agent's changes as they were then. New edits bring it back.
const changeSig = (files) => files.map((f) => `${f.path}:${f.add}:${f.del}`).join('|');
function reviewedSig() { try { return JSON.parse(localStorage.getItem('reviewed') || '{}'); } catch { return {}; } }
function briefOf(a) { const m = S.msgs.get(a.id) || []; const u = [...m].reverse().find((x) => x.role === 'user' && x.text); return u?.text || a.job || ''; }
function reviewQueue() {
  const scope = agents().filter(agentIn);
  const aps = S.approvals.filter((p) => { const a = ag(p.agentId); return a && agentIn(a); });
  const ovs = S.overlaps.filter((o) => o.agents.some((id) => ag(id) && agentIn(ag(id))));
  // Load the changes of every agent on its own branch, once, so we can tell what's waiting to be reviewed.
  for (const a of scope) if (a.worktree && !S.runs.has(`agent:${a.id}`) && !reviewCache.has(a.id)) {
    reviewCache.set(a.id, { loading: true });
    lab.call('git:changes', a.id).then((c) => { reviewCache.set(a.id, { files: c.files, open: c.files[0]?.path || null, diffs: new Map() }); renderSide(); if (S.view.kind === 'reviews') renderView(true); }, (e) => { reviewCache.set(a.id, { error: e.message }); });
  }
  const changes = (a) => { const r = reviewCache.get(a.id); return r?.files?.length && reviewedSig()[a.id] !== changeSig(r.files) ? r.files : null; };
  const ready = scope.filter((a) => stateOf(a) !== 'working' && stateOf(a) !== 'needs' && ((a.last?.state === 'done' && !a.last.seen) || a.last?.state === 'failed' && !a.last.seen || changes(a)))
    .sort((x, y) => lastAt(y) - lastAt(x));
  const running = scope.filter((a) => stateOf(a) === 'working');
  return { aps, ovs, ready, running, changes, count: aps.length + ovs.length + ready.length };
}
function reviewsView(title = 'Review', lede = 'What your agents need from you, most urgent first. Nothing here pings you; check in when you’re ready.') {
  const { aps, ovs, ready, running, changes } = reviewQueue();
  const block = aps.length + ovs.length;
  const card = (a) => {
    const f = changes(a), add = f ? f.reduce((n, x) => n + x.add, 0) : 0, del = f ? f.reduce((n, x) => n + x.del, 0) : 0;
    const ov = S.overlaps.find((o) => o.agents.includes(a.id));
    const failed = a.last?.state === 'failed';
    const brief = briefOf(a);
    return `<article class="rv-card ${failed ? 'fail' : ''}">
      <header class="rv-head">${avatar(a, 36, 'var(--hx-card)')}<div class="rv-who"><b>${esc(a.name)}</b><span>${failed ? 'Stopped with an error' : 'Finished'} · ${ago(lastAt(a))} · ${OPS[a.operator]?.name || a.operator}</span></div>
        ${f ? `<span class="rv-diff">${f.length} ${f.length === 1 ? 'file' : 'files'} <span class="c-add">+${add}</span> <span class="c-del">−${del}</span></span>` : ''}</header>
      <div class="rv-pair">
        <div class="rv-q"><span class="rv-label">You asked</span><p>${brief ? esc(clip(brief, 260)) : '<span class="meta">No brief. It worked from its job description.</span>'}</p></div>
        <div class="rv-a"><span class="rv-label">It says</span><p>${esc(clip(statusLine(a), 320))}</p></div>
      </div>
      ${ov ? `<div class="rv-warn">${ic('agents', 16)}<span>${esc(ag(ov.agents.find((x) => x !== a.id))?.name || 'Another agent')} also changed ${esc(ov.files.slice(0, 2).map(base).join(', '))}${ov.files.length > 2 ? ` and ${ov.files.length - 2} more` : ''}. Merge one first.</span></div>` : ''}
      <footer class="rv-acts">${f ? `<button class="btn primary" data-act="review" data-id="${a.id}">Review changes</button>` : ''}<button class="btn second" data-act="dm" data-id="${a.id}">${f ? 'Open chat' : 'Read the reply'}</button><span class="sx-grow"></span><button class="btn ghost" data-act="rv-done" data-id="${a.id}">Mark as reviewed</button></footer>
    </article>`;
  };
  return `<div class="rv">
    <header class="rv-top"><h1>${title}</h1><p>${lede}</p>
      <div class="rv-stats"><span class="${block ? 'wait' : ''}"><b>${block}</b> blocked on you</span><span><b>${ready.length}</b> ready to review</span><span><b>${running.length}</b> running</span></div></header>
    <section class="rv-sec"><h2>Blocked on you</h2>${block ? `<div class="inbox">${aps.map((p, i) => approvalCard(p, i === 0, true)).join('')}${ovs.map(overlapCard).join('')}</div>` : `<div class="hx-clear">${ic('check', 18)}<span><b>Nothing is blocked on you</b><span>When an agent asks to run something, or two agents touch the same files, it shows up here first.</span></span></div>`}</section>
    <section class="rv-sec"><h2>Ready to review</h2>${ready.length ? ready.map(card).join('') : '<p class="rv-empty">Nothing to review yet. When an agent finishes, its work lands here next to what you asked for.</p>'}</section>
    ${running.length ? `<section class="rv-sec"><h2>Still running</h2><div class="hx-list">${running.map((a) => { const r = S.runs.get(`agent:${a.id}`); return `<button class="hx-row" data-act="dm" data-id="${a.id}">${avatar(a, 32, 'var(--hx-card)')}<span class="hx-main"><span class="hx-name">${esc(a.name)}<span class="hx-op">${OPS[a.operator]?.name || a.operator}</span></span><span class="hx-line">${esc(r?.activity || 'Working')}</span></span><span class="rv-time" data-since="${r?.startedAt}">${elapsed(r?.startedAt || Date.now())}</span></button>`; }).join('')}</div></section>` : ''}
  </div>`;
}

// ---- discover: ready-made agents with one clear job each. Adding one opens the normal form,
// filled in, so you still choose its folder.
const TEMPLATES = [
  ['Build', [
    ['branch', 'Bug fixer', 'Finds the cause of a bug you describe, fixes it with the smallest change, and adds a test that failed before the fix.', { permission: 'ask', ownBranch: true }],
    ['pen', 'Test writer', 'Writes tests for the code you point at, runs them, and stops when they pass. Never changes the code under test.', { permission: 'edits', ownBranch: true }],
    ['agents', 'Refactorer', 'Cleans up one module at a time without changing behaviour, running the tests after every step.', { permission: 'ask', ownBranch: true }],
  ]],
  ['Review', [
    ['check', 'Reviewer', 'Reads your uncommitted changes or a branch and points out bugs, risky changes and missing tests. Never edits.', { permission: 'plan' }],
    ['search', 'Explainer', 'Answers questions about a codebase you don’t know yet: where things live, how a request flows, what to read first.', { permission: 'plan' }],
  ]],
  ['Maintain', [
    ['plug', 'Dependency keeper', 'Checks for outdated or vulnerable packages, updates one at a time, and runs the tests after each.', { permission: 'ask', ownBranch: true }],
    ['book', 'Docs writer', 'Keeps the README and docs in step with the code, and writes what changed in plain language.', { permission: 'edits', ownBranch: true }],
    ['inbox', 'Release notes', 'Summarises what changed since the last tag for people who don’t read diffs.', { permission: 'plan' }],
  ]],
];
const ACCESS_LABEL = { plan: 'Plan only', ask: 'Ask first', edits: 'Edit on its own' };
function discoverView() {
  return `<div class="pg">
    <header class="pg-head"><h1>Discover</h1><p>Ready-made agents with one clear job each. Add one, choose its folder, and it’s on your team.</p></header>
    ${TEMPLATES.map(([group, list]) => `<section class="pg-sec"><h2>${group}</h2><div class="tpl-grid">${list.map(([icon, name, job, o], i) => `<article class="tpl">
      <div class="tpl-ic">${ic(icon, 20)}</div><h3>${name}</h3><p>${job}</p>
      <div class="tpl-meta"><span>${ACCESS_LABEL[o.permission]}</span>${o.ownBranch ? '<span>Own branch</span>' : ''}</div>
      <button class="btn second sm" data-act="tpl-add" data-id="${group}:${i}">Add to your agents</button></article>`).join('')}</div></section>`).join('')}
  </div>`;
}
// ---- usage: what your agents ran this week, from the engine's own ledger.
function usageView() {
  const since = weekStart(), u = usageOf(since), DAY = 864e5;
  const days = Array.from({ length: 7 }, (_, i) => { const from = since + i * DAY; const l = agents().flatMap((a) => (a.ledger || []).filter((x) => x.at >= from && x.at < from + DAY)); return { label: new Date(from).toLocaleDateString(undefined, { weekday: 'short' }), runs: l.length, ms: l.reduce((n, x) => n + (x.ms || 0), 0) }; });
  const max = Math.max(1, ...days.map((d) => d.ms));
  const today = Math.floor((Date.now() - since) / DAY);
  return `<div class="pg">
    <header class="pg-head"><h1>Usage</h1><p>What your agents ran this week. Claude Code reports what each run cost; Codex reports time only, so their cost shows as a dash.</p></header>
    <div class="use-stats"><div><b>${u.cost ? money(u.cost) : '–'}</b><span>Cost reported</span></div><div><b>${u.runs}</b><span>Runs</span></div><div><b>${u.ms ? dur(u.ms) : '–'}</b><span>Time working</span></div></div>
    <section class="pg-sec"><h2>This week</h2><div class="use-days">${days.map((d, i) => `<div class="use-day ${i === today ? 'today' : ''} ${i > today ? 'future' : ''}" title="${d.runs} runs · ${dur(d.ms)}"><i style="height:${Math.round((d.ms / max) * 100)}%"></i><span>${d.label}</span></div>`).join('')}</div></section>
    <section class="pg-sec"><h2>By agent</h2>${u.rows.length ? `<div class="use-table" role="table"><div class="use-tr head" role="row"><span role="columnheader">Agent</span><span role="columnheader">Runs</span><span role="columnheader">Time</span><span role="columnheader">Cost</span></div>${u.rows.map((r) => `<button class="use-tr" role="row" data-act="dm" data-id="${r.a.id}"><span role="cell" class="use-who">${avatar(r.a, 24, 'var(--work)', false)}${esc(r.a.name)}<small>${OPS[r.a.operator]?.name || r.a.operator}</small></span><span role="cell">${r.runs}</span><span role="cell">${dur(r.ms)}</span><span role="cell">${r.priced ? money(r.cost) : '–'}</span></button>`).join('')}</div>` : '<p class="rv-empty">No runs yet this week. Usage starts counting with your agents’ next run.</p>'}</section>
  </div>`;
}

// ---- memory
function memoryView() {
  const ws = S.data.workspaces;
  const list = S.data.memory.filter((d) => S.space === 'home' || !d.workspace || d.workspace === S.space).sort((a, b) => b.n - a.n);
  const inWs = S.space !== 'home' && curWs();
  return `<div class="col page"><h2>${inWs ? 'Rules' : 'Playbook'}</h2><p class="lede">${inWs ? `The rules every agent in ${esc(curWs().name)} follows: the ones set for this workspace, plus your rules for everywhere. Claude Code agents are told them before they start.` : 'The rules your agents follow. Every Claude Code agent is told them before it starts, alongside Claude Code’s own instructions. Nothing else is added.'}</p>
    <form class="add-row" id="memForm"><input id="memInput" placeholder="A decision, like “Never merge to main without tests passing”" aria-label="New decision"><select id="memScope" aria-label="Where it applies"><option value="">Everywhere</option>${ws.map((w) => `<option value="${w.id}" ${S.space === w.id ? 'selected' : ''}>${esc(w.name)}</option>`).join('')}</select><button class="btn primary" type="submit">Add</button></form>
    <div class="list">${list.map((d) => `<div class="tile mem-row"><span class="mid">#${d.n}</span><div class="tile-main"><div class="selectable">${esc(d.text)}</div><div class="meta">${d.workspace ? esc(ws.find((w) => w.id === d.workspace)?.name || 'A removed workspace') : 'Everywhere'} · ${esc(d.by)}${d.source ? ` · from ${esc(d.source)}` : ''} · ${ago(d.at)}</div></div><button class="icon-btn" data-act="mem-remove" data-id="${d.id}" aria-label="Remove decision ${d.n}" title="Remove">${ic('trash')}</button></div>`).join('')}</div>
    ${!list.length ? '<div class="empty"><div>No decisions yet</div><div>Add one above, or save them from a chat when you make it an agent</div></div>' : ''}</div>`;
}

// ---- connections
function connectionsView() {
  const ops = S.data.operators;
  const opRow = (id) => { const o = ops[id]; return `<div class="tile mid-align">${tile(id, 'lg')}<div class="tile-main"><div>${OPS[id].name}</div><div class="meta">${o?.path ? `${esc(o.version || 'Installed')} · ${esc(o.path)}` : 'Not found on this Mac'}</div></div><span class="op-status ${o?.path ? 'ok' : ''}"><i></i>${o?.path ? 'Connected' : 'Not installed'}</span></div>`; };
  const m = S.mavis;
  return `<div class="col page"><h2>Plugins</h2><p class="lede">Agents run through the tools already on this Mac, with your own logins and settings. Agent Lab never sees your passwords.</p>
    <div class="list">${['claude-code', 'codex'].map(opRow).join('')}</div>
    <section class="section"><h3>Mavis</h3><p class="lede">Brings Mavis’s agents in by name. Mavis’s own prompts and rules stay behind: agents here answer the way Claude Code does.</p>
      <div class="tile mid-align">${tile('mavis', 'lg')}<div class="tile-main"><div>Mavis on this Mac</div><div class="meta">${!m ? 'Not checked yet' : !m.found ? 'No Mavis data found' : `${m.bots} ${m.bots === 1 ? 'agent' : 'agents'}`}</div></div>
      ${!m ? '<button class="btn second" data-act="mavis-scan">Check</button>' : m.found && m.newAgents ? '<button class="btn primary" data-act="mavis-import">Bring them in</button>' : m.found ? '<span class="mavis-ok">Everything is here</span>' : ''}</div></section>
    <section class="section"><h3>Workspaces</h3><p class="lede">A workspace is a folder. Agents made in it work there, and it gets its own space on the left.</p>
      <div class="list">${S.data.workspaces.map((w) => `<div class="tile mid-align"><span class="ws-dot" style="background:var(--i9)"></span><div class="tile-main"><div>${esc(w.name)}</div><div class="meta">${esc(w.path)}</div></div><button class="icon-btn" data-act="ws-remove" data-id="${w.id}" aria-label="Remove ${esc(w.name)}" title="Remove from the sidebar">${ic('x')}</button></div>`).join('')}
      <button class="btn second" data-act="ws-add" style="align-self:flex-start">${ic('folder', 14)}Add a folder</button></div>
    </section></div>`;
}

// ---------------------------------------------------------------- Right now
function renderNow() {
  const runs = [...S.runs.values()].filter((r) => r.agentId && ag(r.agentId) && agentIn(ag(r.agentId)));
  $('#now').innerHTML = `<div class="now-card"><div class="now-title">Right now${runs.length ? '<i class="live-dot"></i>' : ''}</div>
    <div class="now-body">${runs.map((r) => {
      const a = ag(r.agentId);
      return `<div class="live" data-act="dm" data-id="${a.id}"><div class="live-top">${avatar(a, 40, 'var(--i2)')}<div class="live-who"><div>${esc(a.name)}</div><div class="live-doing">${esc(r.activity || 'Working')} · <span data-since="${r.startedAt}">${elapsed(r.startedAt)}</span></div></div></div>${r.preview ? `<div class="live-body"><div class="pad"><div class="preview">${esc(r.preview)}</div></div></div>` : ''}</div>`;
    }).join('')}
    ${!runs.length ? '<p class="now-empty">Nothing is running. Agents show up here while they work.</p>' : ''}</div></div>`;
}

function render(keep = true) { applyWall(); renderTop(); renderRail(); renderSide(); renderView(keep); renderStrip(); renderNow(); $('#sheet').classList.add('no-now'); }

// ---------------------------------------------------------------- navigation
function go(view, nav = false) {
  if (window.__trace) console.log('[go]', JSON.stringify(view), new Error().stack.split('\n').slice(2, 5).join(' | '));
  if (view.kind === 'dm') S.lastDm = view.id;
  if (view.kind === 'dm') {
    const a = ag(view.id);
    if (a && S.space !== 'home' && wsOf(a)?.id !== S.space) S.space = 'home';
    if (a?.last?.state && !a.last.seen) { a.last.seen = true; lab.call('agent:update', a.id, { last: a.last }).catch(() => {}); }
  }
  if (view.kind === 'review') reviewCache.delete(view.id);
  if (!nav) {
    if (H.i < 0 && S.view) { H.stack.push({ view: S.view, at: Date.now(), space: 'home' }); H.i = 0; }
    if (viewKey(view) !== viewKey(H.stack[H.i]?.view || {}) || S.space !== H.stack[H.i]?.space) { H.stack = H.stack.slice(0, H.i + 1); H.stack.push({ view, at: Date.now(), space: S.space }); if (H.stack.length > 100) H.stack.shift(); H.i = H.stack.length - 1; }
  } else if (H.stack[H.i]) H.stack[H.i].at = Date.now();
  S.histOpen = false;
  S.view = view;
  closeDrawers();
  render(false);
}
function navStep(d) { const j = H.i + d; if (j < 0 || j >= H.stack.length) return; H.i = j; histGo(H.stack[j], true); }
function closeDrawers() { $('#now').classList.remove('open'); $('#scrim').classList.remove('show'); }

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
  draft = { name: '', job: '', look: randLook(), operator: Object.keys(OPS).find((k) => k !== 'mavis' && S.data.operators[k]?.path) || 'claude-code', model: '', permission: 'ask', cwd: base0, ownBranch: false, repo: null, workspace: S.space !== 'home' ? S.space : null, ...spec };
  draft.repo = (await lab.call('folder:info', draft.cwd).catch(() => null))?.repo || null;
  drawAgentForm();
}
function drawAgentForm() {
  const d = draft, editing = !!d.id, op = OPS[d.operator];
  const models = d.operator === 'codex' ? [['', 'Codex default'], ...(S.data.codexModels || []).map((m) => [m, m])] : op.models;
  const ops = ['claude-code', 'codex'];
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
  const a = await run(() => lab.call('agent:create', { workspace: d.workspace || null, name: d.name.trim(), job: d.job, look: d.look, operator: d.operator, model: d.model || null, permission: d.permission, cwd: d.cwd, ownBranch: d.ownBranch, sessionId: d.sessionId || null, origin: d.origin || null }));
  if (!a) { if (btn) { btn.disabled = false; btn.textContent = 'Add agent'; } return; }
  S.data.agents.push(a); S.msgs.set(a.id, []);
  closeLayer(); draft = null; toast(`${a.name} joined`); go({ kind: 'dm', id: a.id });
}

// Make a chat an agent: it continues that very session, with decisions saved to Memory if you want.
function openCmd() {
  layer(`<div class="backdrop" data-act="close-layer"><div class="overlay" role="dialog" aria-modal="true" aria-label="Search">
    <form class="cmd-in" id="cmdForm">${ic('search', 18)}<input id="cmdInput" placeholder="Find an agent or a chat, or type what you need" aria-label="Search agents and chats" autocomplete="off" autofocus></form>
    <div class="cmd-list scroll" id="cmdList"></div>
    <div class="cmd-foot"><span><kbd>↵</kbd> open or hand off</span><span><kbd>↑</kbd> <kbd>↓</kbd> choose</span><span><kbd>esc</kbd> close</span></div></div></div>`);
  S.cmdSel = 0; cmdList();
  Promise.all(['claude-code', 'codex'].filter((k) => S.data.operators[k]?.path && !S.chats[k]).map((k) => loadChats(k))).then(() => { if ($('#cmdList')) cmdList(); }, () => {});
}
function cmdRows() {
  const q = ($('#cmdInput')?.value || '').trim(), t = q.toLowerCase();
  const as = agents().filter((a) => !t || `${a.name} ${a.job}`.toLowerCase().includes(t) || q.length > 12).slice(0, 6);
  const own = ownedSessions();
  const chats = t ? ['claude-code', 'codex'].flatMap((k) => (S.chats[k] || []).filter((c) => !own.has(c.id) && `${c.title} ${c.cwd || ''}`.toLowerCase().includes(t)).slice(0, 6)).sort((a, b) => b.updated - a.updated).slice(0, 8) : [];
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
  if (row.dataset.act === 'open-chat') { closeLayer(); go({ kind: 'chat', op: row.dataset.op, id: row.dataset.id }); return; }
  const q = ($('#cmdInput')?.value || '').trim();
  const a = ag(row.dataset.id); closeLayer();
  go({ kind: 'dm', id: a.id });
  if (q.length > 12) sendTo(a.id, q);
}

// ---------------------------------------------------------------- sending
async function sendTo(agentId, text, ch = null) {
  const key = await run(() => lab.call('agent:send', agentId, text, ch));
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
    // The Mac app (or another window) saved agents or workspaces: show them.
    case 'state': { const d = await lab.call('state'); if (d && S.data) { S.data.agents = d.agents; S.data.workspaces = d.workspaces; S.data.memory = d.memory; scheduleRender(); } break; }
    case 'command':
      if (ev.command === 'search') openCmd();
      if (ev.command === 'new-agent') openAgentForm();
      if (ev.command === 'toggle-now') { S.nowHidden = !S.nowHidden; render(true); }
      break;
  }
});

// ---------------------------------------------------------------- input
document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-act]');
  if (S.wsMenu && t?.dataset.act !== 'ws-menu') { S.wsMenu = false; renderSide(); }
  if (S.setOpen && !['set-open', 'wall'].includes(t?.dataset.act)) { S.setOpen = false; renderSide(); }
  if (S.histOpen && !['hist-open', 'hist-go'].includes(t?.dataset.act)) { S.histOpen = false; renderTop(); }
  if (S.tbMenu && t?.dataset.act !== 'tb-menu' && !t?.closest?.('.tb-menu')) { S.tbMenu = null; renderView(true); }
  if (S.plusOpen && !['cmp-plus', 'cmp-mention', 'cmp-file', 'cmp-folder'].includes(t?.dataset.act)) { S.plusOpen = null; renderView(true); }
  if (S.pickOpen && !['home-pick-open', 'home-pick'].includes(t?.dataset.act)) { S.pickOpen = false; renderView(true); }
  if (S.mfOpen && !['mf-open', 'mf-set'].includes(t?.dataset.act)) { S.mfOpen = false; renderView(true); }
  if (!t || t.disabled) return;
  const act = t.dataset.act, id = t.dataset.id;
  if (act === 'close-layer' && e.target !== t) return;
  switch (act) {
    case 'tpl-add': { const [g, i] = id.split(':'); const t = TEMPLATES.find(([x]) => x === g)?.[1][+i]; if (t) openAgentForm({ name: t[1], job: t[2], ...t[3] }); break; }
    case 'hf': S.hf = id; if (S.view.kind !== 'agents') go({ kind: 'agents' }); else renderView(true); break;
    case 'hop': S.hop = id; renderView(true); break;
    case 'ideas-hide': try { localStorage.setItem('ideas:hidden', '1'); } catch {} renderView(true); break;
    case 'idea': S.ideaAt = ((S.ideaAt || 0) + +id + 2) % 2; renderView(true); break;
    case 'home-pick-open': S.pickOpen = !S.pickOpen; renderView(true); break;
    case 'home-pick': S.homeAgent = id; S.pickOpen = false; renderView(true); $('#homeInput')?.focus(); break;
    case 'quick': { const q = QUICK[+id]; const i = $('#homeInput'); if (i) { i.value = q[2]; i.focus(); i.setSelectionRange(i.value.length, i.value.length); } break; }
    case 'src-set': S.msrc = id; S.mfOpen = false; S.mq = ''; S.chatsLimit = 25; if (OPS[id]?.chats) loadChats(id).then(() => renderView(true), () => {}); renderView(false); break;
    case 'chats-older': S.chatsLimit += 25; renderView(true); break;
    case 'open-chat': closeLayer(); go({ kind: 'chat', op: t.dataset.op, id }); break;
    case 'tool-open': S.tq = ''; S.chatsLimit = 25; go({ kind: 'tool', op: id }); break;
    case 'chat-open': go({ kind: 'chat', op: t.dataset.op, id }); break;
    case 'mf-open': S.mfOpen = !S.mfOpen; renderView(true); if (S.mfOpen) ['claude-code', 'codex'].filter((k) => S.data.operators[k]?.path && !S.chats[k]).forEach((k) => loadChats(k).then(() => S.mfOpen && renderView(true), () => {})); break;
    case 'mf-set': S.mfilter = id; S.mfOpen = false; renderView(true); break;
    case 'theme': S.theme = S.theme === 'light' ? 'dark' : 'light'; try { localStorage.setItem('theme', S.theme); } catch {} render(true); break;
    case 'wall': S.wall = id; try { localStorage.setItem('wall', id); } catch {} applyWall(); renderTop(); renderSide(); break;
    case 'preview': S.preview = !S.preview; renderView(true); break;
    case 'ws-menu': S.wsMenu = !S.wsMenu; renderSide(); break;
    case 'space': S.space = id; S.tab = 'all'; S.agq = ''; go(id === 'home' ? { kind: 'agents' } : { kind: 'channel' }); break;
    case 'channel': go({ kind: 'channel', id: id || 'general' }); break;
    case 'cat-toggle': { const w = curWs(); if (!w) break; const cats = structuredClone(wsCats(w)); const c = cats.find((x) => x.id === id); if (c) { c.open = c.open === false; await saveCats(w, cats); } break; }
    case 'cat-add': openChanForm({ kind: 'category', mode: 'new' }); break;
    case 'cat-edit': { const c = wsCats(curWs()).find((x) => x.id === id); if (c) openChanForm({ kind: 'category', mode: 'edit', id, name: c.name, canDelete: wsCats(curWs()).length > 1 }); break; }
    case 'chan-add': openChanForm({ kind: 'channel', mode: 'new', cat: id }); break;
    case 'chan-edit': { const ch = wsChannel(curWs(), id); if (ch) openChanForm({ kind: 'channel', mode: 'edit', id, cat: t.dataset.cat, name: ch.name, canDelete: ch.id !== 'general' }); break; }
    case 'chan-save': saveChanForm(); break;
    case 'chan-del': {
      const d = S.chanDraft, w = curWs(); if (!d || !w) break;
      const cats = structuredClone(wsCats(w));
      const label = d.kind === 'channel' ? `#${d.name}` : d.name;
      const ok = await confirmBox({ title: `Delete ${label}?`, body: d.kind === 'channel' ? 'The channel goes away. Messages sent in it stay in each agent’s own chat.' : 'The category and its channels go away. Messages stay in each agent’s own chat.', ok: 'Delete', danger: true });
      if (!ok) break;
      if (d.kind === 'channel') { const c = cats.find((x) => x.id === d.cat); if (c) c.channels = c.channels.filter((x) => x.id !== d.id); }
      else { const gone = cats.find((x) => x.id === d.id); const keepGen = gone?.channels.find((x) => x.id === 'general'); const rest = cats.filter((x) => x.id !== d.id); if (keepGen && rest[0]) rest[0].channels.unshift(keepGen); cats.length = 0; cats.push(...rest); }
      if (await saveCats(w, cats)) go({ kind: 'channel', id: 'general' });
      break;
    }
    case 'ws-view': go({ kind: id }); break;
    case 'ws-create': openCreateWs(); break;
    case 'ws-link-folder': { S.projDraft.name = $('#pjName')?.value || S.projDraft.name; if ($('#pjAbout')) S.projDraft.about = $('#pjAbout').value; const p = await run(() => lab.call('folder:pick', 'Link a folder to this workspace')); if (p) S.projDraft.path = p; (S.projDraft.id ? drawProjectForm : drawCreateWs)(); break; }
    case 'proj-edit': if (curWs()) openProjectForm(curWs()); break;
    case 'proj-color': S.projDraft.name = $('#pjName')?.value || S.projDraft.name; if ($('#pjAbout')) S.projDraft.about = $('#pjAbout').value; S.projDraft.color = id; drawProjectForm(); break;
    case 'proj-pic-clear': S.projDraft.name = $('#pjName')?.value || S.projDraft.name; if ($('#pjAbout')) S.projDraft.about = $('#pjAbout').value; S.projDraft.image = null; drawProjectForm(); break;
    case 'proj-save': saveProject(); break;
    case 'ws-remove-proj': { const id2 = S.projDraft?.id; closeLayer(); if (id2 && (await run(() => lab.call('workspace:remove', id2)))) { S.data.workspaces = S.data.workspaces.filter((w) => w.id !== id2); S.space = 'home'; go({ kind: 'agents' }); toast('Workspace removed. Its folder and agents are untouched.'); } break; }
    case 'view': S.space = 'home'; go(id === 'messages' && S.lastDm && ag(S.lastDm) ? { kind: 'dm', id: S.lastDm } : { kind: id }); break;
    case 'tab': S.tab = id; go({ kind: 'agents' }); break;
    case 'dm': e.stopPropagation(); go({ kind: 'dm', id }); break;
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
    case 'close-layer': case 'close-layer-btn': closeLayer(); draft = null; break;
    case 'confirm-yes': confirmBox.resolve?.(true); break;
    case 'confirm-no': confirmBox.resolve?.(false); break;
    case 'approve': { S.approvals = S.approvals.filter((p) => p.id !== id); scheduleRender(); await run(() => lab.call('approval:answer', id, t.dataset.decision)); break; }
    case 'stop': run(() => lab.call('run:stop', id)); break;
    case 'review': go({ kind: 'review', id }); break;
    case 'set-open': S.setOpen = !S.setOpen; renderSide(); break;
    case 'nav-back': navStep(-1); break;
    case 'nav-fwd': navStep(1); break;
    case 'hist-open': S.histOpen = !S.histOpen; renderTop(); break;
    case 'hist-go': { const e = H.stack[+id]; if (e) histGo(e); break; }
    case 'tb-menu': S.tbMenu = S.tbMenu === id ? null : id; renderView(true); break;
    case 'cmp-mic': toggleDictation(); break;
    case 'cmp-plus': S.plusOpen = S.plusOpen === id ? null : id; renderView(true); break;
    case 'cmp-mention': S.plusOpen = null; renderView(true); { const i = $('#cmpInput'); if (i) { i.value = `@${id} ${i.value.replace(/^@\S+\s*/, '')}`; i.focus(); i.setSelectionRange(i.value.length, i.value.length); autoGrow(); } } break;
    case 'cmp-file': case 'cmp-folder': { S.plusOpen = null; renderView(true); const p = await run(() => lab.call(act === 'cmp-file' ? 'file:pick' : 'folder:pick', act === 'cmp-file' ? 'Choose a file to mention' : 'Choose a folder to mention')); if (p) cmpInsert(p); break; }
    case 'tb-model': case 'tb-access': { const a = ag(t.dataset.agent); if (!a) break; const key = act === 'tb-model' ? 'model' : 'permission'; const val = act === 'tb-model' ? (id || null) : id; S.tbMenu = null; try { await lab.call('agent:update', a.id, { [key]: val }); a[key] = val; toast(act === 'tb-model' ? `${a.name} now uses ${val ? val[0].toUpperCase() + val.slice(1) : 'the default model'}` : `${a.name}: ${ACCESS.find(([x]) => x === val)[1]}`); } catch (err) { toast(err.message, true); } renderView(true); break; }
    case 'rv-done': { const a = ag(id); if (!a) break; a.last = { ...(a.last || { state: 'done', at: Date.now() }), seen: true }; lab.call('agent:update', a.id, { last: a.last }).catch(() => {}); const r = reviewCache.get(a.id); if (r?.files) { const m = reviewedSig(); m[a.id] = changeSig(r.files); try { localStorage.setItem('reviewed', JSON.stringify(m)); } catch {} } renderSide(); renderView(true); toast(`${a.name} marked as reviewed`); break; }
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
    if (key.startsWith('chan:')) {
      const m = text.match(/^@(\S+)\s+([\s\S]+)/), pool = agents().filter(agentIn);
      const a = m && pool.find((x) => x.name.toLowerCase() === m[1].toLowerCase());
      if (!a) { i.value = text; autoGrow(); toast(pool.length ? `Start with @${pool[0].name} (or another agent’s name) to choose who you’re talking to.` : 'This project has no agents yet.', true); return; }
      sendTo(a.id, m[2].trim(), key.split(':')[2] || 'general');
    } else if (key.startsWith('agent:')) sendTo(key.slice(6), text); else sendChat(key, text);
  } else if (f.id === 'cmdForm') cmdGo(document.querySelectorAll('.cmd-row')[S.cmdSel]);
  else if (f.id === 'agentForm') saveAgentForm();
  else if (f.id === 'promoForm') savePromote();
  else if (f.id === 'homeForm') {
    const text = $('#homeInput').value.trim(); if (!text) return;
    const scope = agents().filter(agentIn).sort((a, b) => STATE[stateOf(a)].o - STATE[stateOf(b)].o || lastAt(b) - lastAt(a));
    const a = ag(S.homeAgent) && agentIn(ag(S.homeAgent)) ? ag(S.homeAgent) : scope[0];
    if (!a) { openAgentForm({ job: text }); return; }
    if (S.runs.has(`agent:${a.id}`)) { toast(`${a.name} is still working. Pick another agent or wait.`, true); return; }
    go({ kind: 'dm', id: a.id }); sendTo(a.id, text);
  }
  else if (f.id === 'projForm') saveProject();
  else if (f.id === 'chanForm') saveChanForm();
  else if (f.id === 'memForm') {
    const text = $('#memInput').value.trim(); if (!text) return;
    const d = await run(() => lab.call('memory:add', text, $('#memScope').value || null, null));
    if (d) { S.data.memory.push(d); renderView(true); $('#memInput')?.focus(); toast(`Saved as decision #${d.n}`); }
  }
});

document.addEventListener('keydown', (e) => {
  const inField = /INPUT|TEXTAREA|SELECT/.test(e.target.tagName);
  if (e.target.id === 'homeInput' && e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); $('#homeForm')?.requestSubmit(); return; }
  if (e.target.id === 'cmpInput' && e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); $('#cmpForm')?.requestSubmit(); return; }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openCmd(); return; }
  if ((e.metaKey || e.ctrlKey) && !inField && (e.key === '[' || e.key === ']')) { e.preventDefault(); navStep(e.key === '[' ? -1 : 1); return; }
  if (S.histOpen && e.key === 'Escape') { S.histOpen = false; renderTop(); return; }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'n') { e.preventDefault(); openAgentForm(); return; }
  if (e.key === 'Escape') { if ($('#layer').innerHTML) { confirmBox.resolve ? confirmBox.resolve(false) : closeLayer(); confirmBox.resolve = null; draft = null; } else closeDrawers(); return; }
  if ((e.metaKey || e.ctrlKey) && !e.altKey && /^[1-9]$/.test(e.key) && S.quick[+e.key - 1]) { e.preventDefault(); go({ kind: 'dm', id: S.quick[+e.key - 1] }); return; }
  if (e.target.id === 'cmdInput') {
    const n = document.querySelectorAll('.cmd-row').length;
    if (n && e.key === 'ArrowDown') { e.preventDefault(); S.cmdSel = (S.cmdSel + 1) % n; cmdList(); }
    if (n && e.key === 'ArrowUp') { e.preventDefault(); S.cmdSel = (S.cmdSel - 1 + n) % n; cmdList(); }
    return;
  }
  if ((e.key === 'Enter' || e.key === ' ') && (e.target.classList?.contains('arow') || e.target.classList?.contains('conv') || e.target.classList?.contains('hx-row'))) { e.preventDefault(); e.target.click(); }
});
document.addEventListener('change', (e) => {
  if (e.target.id !== 'projPic' || !e.target.files?.[0]) return;
  const f = e.target.files[0], img = new Image(), url = URL.createObjectURL(f);
  img.onload = () => {
    const c = document.createElement('canvas'), n = 256, k = Math.min(img.width, img.height);
    c.width = c.height = n;
    c.getContext('2d').drawImage(img, (img.width - k) / 2, (img.height - k) / 2, k, k, 0, 0, n, n);
    S.projDraft.name = $('#pjName')?.value || S.projDraft.name; if ($('#pjAbout')) S.projDraft.about = $('#pjAbout').value;
    S.projDraft.image = c.toDataURL('image/jpeg', 0.86); URL.revokeObjectURL(url); (S.projDraft.id ? drawProjectForm : drawCreateWs)();
  };
  img.src = url;
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'cmdInput') { S.cmdSel = 0; cmdList(); }
  if (e.target.id === 'agq') { S.agq = e.target.value; renderView(true); }
  if (e.target.id === 'mq') { S.mq = e.target.value; renderView(true); }
  if (e.target.id === 'tq') { S.tq = e.target.value; renderView(true); }
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
    // ?empty&view=discover opens on a page (used for the native app's pixel references).
    const startView = new URLSearchParams(location.search).get('view');
    if (startView) S.view = { kind: startView };
    render(false);
    // ?empty&open=settings|history|search|newagent opens an overlay (native pixel references).
    const open = new URLSearchParams(location.search).get('open');
    if (open === 'settings') { S.setOpen = true; renderSide(); }
    if (open === 'history') { go({ kind: 'discover' }); go({ kind: 'agents' }); S.histOpen = true; renderTop(); }
    if (open === 'search') openCmd();
    if (open === 'newagent') openAgentForm();
  } catch (e) {
    document.body.innerHTML = `<div class="empty-hero"><h2>Agent Lab couldn’t start</h2><p>${esc(e.message)}</p></div>`;
  }
})();

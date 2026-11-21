// Agent Lab as a local web app: serves the interface and bridges it to the engine (server.js).
// Listens on 127.0.0.1 only. Every request needs a token that is written into the page it serves,
// so other websites open in your browser can't drive your agents.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const ui = path.join(here, '..', 'src', 'renderer');
const port = Number(process.env.PORT || 4300);
const token = crypto.randomBytes(24).toString('hex');

// The engine runs as its own process, one JSON line per message, exactly as the Swift app uses it.
const engine = spawn(process.execPath, [path.join(here, 'server.js')], { stdio: ['pipe', 'pipe', 'inherit'] });
engine.stdin.on('error', () => {});
const waiting = new Map();
const listeners = new Set();
let nextId = 1, buf = '';
engine.stdout.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    let m; try { m = JSON.parse(line); } catch { continue; }
    if (m.event) { for (const res of listeners) res.write(`data: ${JSON.stringify(m.event)}\n\n`); continue; }
    const w = waiting.get(m.id); if (w) { waiting.delete(m.id); w(m); }
  }
});
engine.on('exit', (code) => { console.error(`engine stopped (${code})`); process.exit(1); });
const call = (method, params) => new Promise((resolve) => {
  const id = nextId++;
  waiting.set(id, resolve);
  engine.stdin.write(`${JSON.stringify({ id, method, params })}\n`);
});

// The things a browser page can't do itself: pick a folder or a file, and open a folder.
const local = {
  'folder:pick': (title = 'Choose a folder') => new Promise((resolve) => {
    execFile('/usr/bin/osascript', ['-e', `POSIX path of (choose folder with prompt ${JSON.stringify(String(title))})`], (err, out) => resolve(err ? null : out.trim().replace(/\/$/, '')));
  }),
  'file:pick': (title = 'Choose a file') => new Promise((resolve) => {
    execFile('/usr/bin/osascript', ['-e', `POSIX path of (choose file with prompt ${JSON.stringify(String(title))})`], (err, out) => resolve(err ? null : out.trim()));
  }),
  'open:folder': (dir) => new Promise((resolve) => execFile('/usr/bin/open', [String(dir)], () => resolve(true))),
};

const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.otf': 'font/otf', '.jpg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const json = (res, code, v) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(v)); };

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const authed = req.headers['x-lab-token'] === token || url.searchParams.get('t') === token;

  if (req.method === 'POST' && url.pathname === '/call') {
    if (req.headers['x-lab-token'] !== token) return json(res, 403, { ok: false, error: 'Not allowed' });
    let body = '';
    for await (const c of req) body += c;
    try {
      const { method, params = [] } = JSON.parse(body);
      if (local[method]) return json(res, 200, { ok: true, value: await local[method](...params) });
      const r = await call(method, params);
      return json(res, 200, r.ok ? { ok: true, value: r.value } : { ok: false, error: r.error });
    } catch (e) { return json(res, 200, { ok: false, error: e.message }); }
  }

  if (url.pathname === '/events') {
    if (!authed) { res.writeHead(403); return res.end(); }
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
    res.write(': hi\n\n');
    listeners.add(res);
    req.on('close', () => listeners.delete(res));
    return;
  }

  // Static interface. index.html gets the token and the bridge.
  const file = path.join(ui, url.pathname === '/' ? 'index.html' : path.normalize(url.pathname).replace(/^(\.\.[/\\])+/, ''));
  if (!file.startsWith(ui) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end('Not found'); }
  let out = fs.readFileSync(file);
  if (file.endsWith('index.html')) {
    out = out.toString('utf8').replace("connect-src 'none'", "connect-src 'self'")
      .replace('<script type="module" src="app.js"></script>', `<meta name="lab-token" content="${token}"><link rel="stylesheet" href="web.css"><script src="bridge.js"></script>\n<script type="module" src="app.js"></script>`);
  }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
  res.end(out);
})
  .on('error', (e) => {
    // Already running (another terminal, or the preview pane): open that one instead of starting a second.
    if (e.code === 'EADDRINUSE') {
      console.log(`Agent Lab is already running: http://localhost:${port}`);
    } else console.error(e.message);
    engine.removeAllListeners('exit'); engine.kill(); setTimeout(() => process.exit(e.code === 'EADDRINUSE' ? 0 : 1), 200);
  })
  .listen(port, '127.0.0.1', () => {
    console.log(`Agent Lab: http://localhost:${port}  (Ctrl-C to stop)`);
  });

process.on('SIGINT', () => { engine.stdin.end(); setTimeout(() => process.exit(0), 300); });
process.on('SIGTERM', () => { engine.stdin.end(); setTimeout(() => process.exit(0), 300); });

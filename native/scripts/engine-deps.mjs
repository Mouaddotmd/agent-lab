// Prints the node_modules folders the engine needs (the agent SDK and everything it pulls in, nothing else), one per
// line, relative to the project folder. Used by build.sh to put the engine inside the app.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const seen = new Set();
function find(name, from) {
  for (let dir = from; dir.startsWith(root); dir = path.dirname(dir)) {
    const p = path.join(dir, 'node_modules', name);
    if (fs.existsSync(path.join(p, 'package.json'))) return p;
    if (dir === root) break;
  }
  return null;
}
function add(name, from) {
  const p = find(name, from);
  if (!p || seen.has(p)) return;
  seen.add(p);
  const pkg = JSON.parse(fs.readFileSync(path.join(p, 'package.json'), 'utf8'));
  for (const d of Object.keys({ ...pkg.dependencies, ...pkg.peerDependencies, ...pkg.optionalDependencies })) add(d, p);
}
add('@anthropic-ai/claude-agent-sdk', root);
for (const p of [...seen].sort()) console.log(path.relative(root, p));

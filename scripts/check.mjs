// Syntax-checks every source file. Run with `npm run check`.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const files = [];
const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (/\.(m?js|cjs)$/.test(e.name)) files.push(p); } };
walk('src'); walk('scripts');
let bad = 0;
for (const f of files) { try { execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' }); } catch (e) { bad++; console.error(`✗ ${f}\n${e.stderr}`); } }
console.log(bad ? `${bad} file(s) failed` : `✓ ${files.length} files OK`);
process.exit(bad ? 1 : 0);

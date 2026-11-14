// Runs the end-to-end test in the real app with a throwaway data folder. Screenshots land in a temp folder.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import electron from 'electron';
const data = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-data-'));
const out = process.env.AGENT_LAB_E2E_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'agent-lab-shots-'));
const child = spawn(electron, ['.'], { stdio: 'inherit', env: { ...process.env, AGENT_LAB_E2E: '1', AGENT_LAB_DATA: data, AGENT_LAB_E2E_OUT: out } });
child.on('exit', (code) => { fs.rmSync(data, { recursive: true, force: true }); console.log(code === 0 ? `E2E passed. Screenshots: ${out}` : `E2E failed (${code}). Screenshots: ${out}`); process.exit(code ?? 1); });

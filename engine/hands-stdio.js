// The agent's hands for Codex: an MCP server Codex starts itself (stdio), with the same tools as Claude's (hands.js).
// Each call goes to the engine over its socket (LAB_HANDS_SOCK), for agent LAB_AGENT; the engine applies the agent's
// mode and the app does the step on the real pane.
import net from 'node:net';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { specs, SERVER } from './hands.js';

const sock = process.env.LAB_HANDS_SOCK;
const agentId = process.env.LAB_AGENT;
let conn = null, buf = '', seq = 0;
const waiting = new Map();

function connection() {
  if (conn) return conn;
  conn = new Promise((resolve, reject) => {
    const c = net.createConnection(sock, () => resolve(c));
    c.setEncoding('utf8');
    c.on('data', (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 1);
        let m; try { m = JSON.parse(line); } catch { continue; }
        waiting.get(m.id)?.(m.result); waiting.delete(m.id);
      }
    });
    const lost = (e) => { conn = null; for (const w of waiting.values()) w({ content: [{ type: 'text', text: 'Agent Lab closed.' }], isError: true }); waiting.clear(); reject(e); };
    c.on('error', lost); c.on('close', lost);
  });
  return conn;
}

async function call(tool, args) {
  try {
    const c = await connection();
    const id = ++seq;
    return await new Promise((resolve) => { waiting.set(id, resolve); c.write(`${JSON.stringify({ id, agentId, tool, args })}\n`); });
  } catch {
    return { content: [{ type: 'text', text: 'Agent Lab is not open, so its panes can\'t be reached.' }], isError: true };
  }
}

const server = new McpServer({ name: SERVER, version: '1.0.0' });
for (const t of specs()) server.registerTool(t.name, { description: t.description, inputSchema: t.shape }, (args) => call(t.name, args));
await server.connect(new StdioServerTransport());

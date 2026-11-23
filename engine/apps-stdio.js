// Connected apps for Codex: an MCP server Codex starts itself (stdio). The tools and every call go to the engine over its
// socket (LAB_HANDS_SOCK), for agent LAB_AGENT; the engine applies the agent's mode and makes the call (apps.js).
import net from 'node:net';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';

let conn = null, buf = '', seq = 0;
const waiting = new Map();
function connection() {
  if (conn) return conn;
  conn = new Promise((resolve, reject) => {
    const c = net.createConnection(process.env.LAB_HANDS_SOCK, () => resolve(c));
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
    const lost = (e) => { conn = null; for (const w of waiting.values()) w(null); waiting.clear(); reject(e); };
    c.on('error', lost); c.on('close', lost);
  });
  return conn;
}
async function ask(body) {
  try {
    const c = await connection(), id = ++seq;
    return await new Promise((resolve) => { waiting.set(id, resolve); c.write(`${JSON.stringify({ id, apps: true, agentId: process.env.LAB_AGENT, ...body })}\n`); });
  } catch { return null; }
}
const mcp = new McpServer({ name: 'apps', version: '1.0.0' }, { capabilities: { tools: {} } });
mcp.server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: (await ask({ list: true }))?.tools || [] }));
mcp.server.setRequestHandler(CallToolRequestSchema, async (r) => (await ask({ tool: r.params.name, args: r.params.arguments }))
  || { content: [{ type: 'text', text: 'Agent Lab is not open, so your apps can\'t be reached.' }], isError: true });
await mcp.connect(new StdioServerTransport());

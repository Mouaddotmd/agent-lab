// Connected apps: the client for Composio's tool router, ported from Mavis final launch (Engine/runtime/index.cjs,
// ComposioClient) method for method. What Agent Lab does with it is in apps.js.
import crypto from 'node:crypto';
import fs from 'node:fs';

const DEFAULT_API = "https://backend.composio.dev/api/v3.1";
const TOOL_CACHE_TTL_MS = 6e4;
const SLUG = /^[a-z0-9][a-z0-9_-]{0,79}$/;
const ACCOUNT_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
function validSlug(value) {
  const slug = value.trim().toLowerCase();
  if (!SLUG.test(slug)) throw new Error("Invalid connected-app name");
  return slug;
}
function validAlias(value) {
  const alias2 = value?.trim();
  if (!alias2) return void 0;
  if (alias2.length > 64 || [...alias2].some((character) => {
    const point = character.codePointAt(0);
    return point < 32 || point === 127;
  })) throw new Error("Account alias must be 1-64 printable characters");
  return alias2;
}
function trustedComposioUrl(value, api) {
  const url2 = new URL(value);
  // Through the apps server (AGENTLAB_COMPOSIO_API), its tool addresses point back to it.
  const relay = api && api !== DEFAULT_API ? new URL(api).hostname : null;
  if (url2.protocol === "https:" && relay && url2.hostname === relay) return url2.toString();
  if (url2.protocol !== "https:" || url2.hostname !== "composio.dev" && !url2.hostname.endsWith(".composio.dev")) throw new Error("Composio returned an untrusted URL");
  return url2.toString();
}
function trustedAssetUrl(value) {
  try {
    const url2 = new URL(value);
    return url2.protocol === "https:" ? url2.toString() : null;
  } catch {
    return null;
  }
}
function serviceState(accounts) {
  const active = accounts.find(({ status }) => /^active$/i.test(status));
  const pending = accounts.find(({ status }) => /^(initiated|initializing|pending)$/i.test(status));
  return { connected: Boolean(active), pending: Boolean(pending), status: (active ?? pending ?? accounts[0])?.status ?? "not_connected", accounts };
}
function parseMcpBody(raw, contentType) {
  if (contentType.includes("text/event-stream")) {
    const data = raw.split(/\r?\n/).filter((line) => line.startsWith("data:")).map((line) => line.slice(5).trim()).filter((line) => line && line !== "[DONE]").at(-1);
    if (!data) throw new Error("Connected app returned an empty MCP stream");
    return JSON.parse(data);
  }
  return JSON.parse(raw);
}
export class ComposioClient {
  constructor(environment, statePath, fetcher = fetch) {
    this.statePath = statePath;
    this.fetcher = fetcher;
    this.key = environment.AGENTLAB_COMPOSIO_API_KEY?.trim() || null;
    this.apiBase = (environment.AGENTLAB_COMPOSIO_API ?? DEFAULT_API).replace(/\/$/, "");
    const api = new URL(this.apiBase);
    if (api.protocol !== "https:" && !["127.0.0.1", "localhost"].includes(api.hostname)) throw new Error("Composio API must use HTTPS");
  }
  statePath;
  fetcher;
  key;
  apiBase;
  session = null;
  initialized = false;
  names = new Map();
  toolCache = null;
  toolCacheExpiresAt = 0;
  toolCachePromise = null;
  toolCacheVersion = 0;
  configured() {
    return Boolean(this.key);
  }
  // Set (or clear) the project key live, from the app's Connectors card.
  setKey(value) {
    const next = typeof value === "string" && value.trim() ? value.trim() : null;
    if (next && !/^(?:ak|ck)_[A-Za-z0-9_-]{8,200}$/.test(next)) throw new Error("A Composio key starts with ak_ (project) or ck_ (Composio Connect)");
    this.key = next;
    this.session = null;
    this.initialized = false;
    this.connectedSlugs = new Set();
    this.consumerApps = null;
    this.rawTools = null;
    this.invalidateTools();
  }
  // A Composio Connect key (ck_): your own Composio account's hosted MCP server, where the
  // apps you connected on composio.dev live. No project API: connections are managed there (or by its own tools).
  get consumer() {
    return Boolean(this.key?.startsWith("ck_"));
  }
  // Apps with a live connection, refreshed whenever the services are listed: a request naming one gets its tools.
  connectedSlugs = new Set();
  async tools() {
    if (!this.key) return [];
    if (this.toolCache && Date.now() < this.toolCacheExpiresAt) return this.toolCache.map((tool) => ({ ...tool }));
    if (this.toolCachePromise) return (await this.toolCachePromise).map((tool) => ({ ...tool }));
    const version2 = this.toolCacheVersion;
    let pending;
    pending = this.loadTools().then((tools) => {
      if (version2 === this.toolCacheVersion) {
        this.toolCache = tools;
        this.toolCacheExpiresAt = Date.now() + TOOL_CACHE_TTL_MS;
      }
      return tools;
    }).finally(() => {
      if (this.toolCachePromise === pending) this.toolCachePromise = null;
    });
    this.toolCachePromise = pending;
    return (await pending).map((tool) => ({ ...tool }));
  }
  async loadTools() {
    if (!this.initialized) {
      const initialized = await this.rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "agent-lab", version: "1.0.0" } });
      // Any dated MCP version the server picks (Composio Connect answers with its own).
      if (!/^\d{4}-\d{2}-\d{2}$/.test(String(initialized?.protocolVersion ?? ""))) throw new Error("Connected-app MCP protocol is incompatible");
      await this.notify("notifications/initialized", {});
      this.initialized = true;
    }
    const listed = await this.rpc("tools/list", {});
    const raw = listed.tools;
    this.rawTools = Array.isArray(raw) ? raw : [];
    if (!Array.isArray(raw) || raw.length > 500) throw new Error("Connected app returned an invalid tool catalog");
    this.names.clear();
    return raw.map((value, index) => {
      if (!value || typeof value !== "object") throw new Error("Connected app returned an invalid tool");
      const tool = value;
      if (!tool.name || tool.name.length > 160) throw new Error("Connected app returned an invalid tool name");
      let safe = `connector_${tool.name.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 110)}`;
      while (this.names.has(safe)) safe = `${safe.slice(0, 116)}_${index}`;
      this.names.set(safe, { original: tool.name, readOnly: tool.annotations?.readOnlyHint === true });
      return { name: safe, description: `Connected app: ${tool.description?.slice(0, 900) || tool.name}`, inputSchema: tool.inputSchema && typeof tool.inputSchema === "object" ? tool.inputSchema : { type: "object", properties: {}, additionalProperties: true } };
    });
  }
  risk(name) {
    const tool = this.names.get(name);
    if (!tool) throw new Error("Connected-app tool is unavailable");
    return tool.readOnly ? "read" : "send";
  }
  async call(name, input) {
    const tool = this.names.get(name);
    if (!tool) throw new Error("Connected-app tool is unavailable");
    return await this.rpc("tools/call", { name: tool.original, arguments: input });
  }
  async catalog() {
    if (this.consumer) return { cards: [] };
    this.requireKey();
    const endpoint = new URL(this.apiBase.replace(/\/api\/v3\.1$/, "/api/v3") + "/toolkits");
    endpoint.searchParams.set("limit", "500");
    endpoint.searchParams.set("sort_by", "usage");
    const body = await this.projectJson(endpoint.toString());
    if (!Array.isArray(body.items) || body.items.length > 1e3) throw new Error("Composio returned an invalid app catalog");
    const cards = [];
    for (const raw of body.items) {
      if (!raw || typeof raw !== "object") continue;
      const item = raw;
      const slugValue = String(item.slug ?? "").toLowerCase();
      if (!SLUG.test(slugValue)) continue;
      const meta3 = item.meta && typeof item.meta === "object" ? item.meta : {};
      cards.push({ slug: slugValue, label: String(item.name ?? item.display_name ?? slugValue).slice(0, 100), description: String(item.description ?? meta3.description ?? "Connect this app to your agents.").slice(0, 300), categories: (Array.isArray(meta3.categories) ? meta3.categories : []).map((c) => String(c?.name ?? '').toLowerCase()).filter(Boolean).slice(0, 6), noAuth: item.no_auth === true, tools: Number(meta3.tools_count) || 0, site: typeof meta3.app_url === 'string' ? trustedAssetUrl(meta3.app_url) : null, logo: typeof item.logo === "string" ? trustedAssetUrl(item.logo) : typeof meta3.logo === "string" ? trustedAssetUrl(meta3.logo) : null });
    }
    return { cards };
  }
  async connectedServices() {
    if (this.consumer) return { services: await this.consumerServices(), consumer: true };
    const session = await this.ensureSession();
    // Your accounts say what's connected. (Mavis also paged through every toolkit of the session, 1,800 of them by 50s:
    // 21 seconds. The apps that need no sign-in come from the catalogue instead: `noAuth`.)
    const accounts = await this.connectedAccounts(session.userId);
    const services = {};
    for (const account of accounts) {
      const list2 = services[account.slug]?.accounts ?? [];
      list2.push({ id: account.id, ...account.alias ? { alias: account.alias } : {}, status: account.status });
      services[account.slug] = serviceState(list2);
    }
    this.connectedSlugs = new Set(Object.entries(services).filter(([, service]) => service.connected).map(([slug]) => slug));
    return { services };
  }
  async authorizeService(value, requestedAlias) {
    if (this.consumer) return await this.consumerAuthorize(validSlug(value));
    const slug = validSlug(value);
    const alias2 = validAlias(requestedAlias);
    const session = await this.ensureSession();
    const accounts = (await this.connectedAccounts(session.userId, [slug]).catch(() => [])).filter((account) => account.slug === slug);
    // A sign-in you left unfinished (and nothing connected): it's dropped, and a fresh one opens. (Mavis refused it.)
    if (!alias2 && !accounts.some(({ status }) => /^active$/i.test(status))) {
      for (const old of accounts.filter(({ status }) => /^(initiated|initializing|pending)$/i.test(status))) await this.projectJson(`${this.apiBase}/connected_accounts/${encodeURIComponent(old.id)}`, { method: "DELETE" }, true).catch(() => {});
      accounts.splice(0, accounts.length);
    }
    const usable = accounts.filter(({ status }) => /^(active|initiated|initializing|pending)$/i.test(status));
    if (usable.length >= 5) throw new Error(`${slug} already has the maximum of 5 accounts`);
    if (usable.length > 0 && !alias2) throw new Error("Add an account alias so the existing connection is not replaced");
    if (alias2 && accounts.some((account) => account.alias?.toLowerCase() === alias2.toLowerCase())) throw new Error(`Account alias \u201C${alias2}\u201D is already in use`);
    const body = await this.projectJson(`${this.apiBase}/tool_router/session/${encodeURIComponent(session.id)}/link`, { method: "POST", body: JSON.stringify({ toolkit: slug, ...alias2 ? { alias: alias2 } : {} }) });
    if (typeof body.redirect_url !== "string") throw new Error("Composio returned no authorization link");
    this.invalidateTools();
    return { url: trustedComposioUrl(body.redirect_url, this.apiBase) };
  }
  async removeAccount(value, accountId) {
    const slug = validSlug(value);
    if (!ACCOUNT_ID.test(accountId)) throw new Error("Invalid connected-account ID");
    const session = await this.ensureSession();
    const accounts = await this.connectedAccounts(session.userId, [slug]);
    const toolkits = accounts.length ? [] : await this.sessionToolkits(session.id);
    const owned = accounts.some((account) => account.slug === slug && account.id === accountId) || toolkits.some((toolkit) => toolkit.slug === slug && toolkit.accountId === accountId);
    if (!owned) return { removed: 0 };
    await this.projectJson(`${this.apiBase}/connected_accounts/${encodeURIComponent(accountId)}?revoke_on_delete=true`, { method: "DELETE" }, true);
    this.invalidateTools();
    return { removed: 1 };
  }
  async removeService(value) {
    if (this.consumer) return await this.consumerRemove(validSlug(value));
    const slug = validSlug(value);
    const session = await this.ensureSession();
    const accounts = await this.connectedAccounts(session.userId, [slug]);
    const toolkits = accounts.length ? [] : await this.sessionToolkits(session.id);
    const ids = new Set(accounts.filter((account) => account.slug === slug).map(({ id }) => id));
    for (const toolkit of toolkits) if (toolkit.slug === slug && toolkit.accountId) ids.add(toolkit.accountId);
    for (const id of ids) await this.projectJson(`${this.apiBase}/connected_accounts/${encodeURIComponent(id)}?revoke_on_delete=true`, { method: "DELETE" }, true);
    if (ids.size > 0) this.invalidateTools();
    return { removed: ids.size };
  }
  // Apps connected with a Composio Connect key (ck_), as Codex and Claude do with the same
  // key: the key's MCP server has its own connection tool (COMPOSIO_MANAGE_CONNECTIONS or the like). Asked for an app,
  // it answers with the app's sign-in link, or says the app is already active. Which apps are connected is kept in a
  // small file beside the session state, and pending ones are asked again until they're active.
  consumerState() {
    if (this.consumerApps) return this.consumerApps;
    let saved = {};
    try { if (this.statePath) saved = JSON.parse(fs.readFileSync(`${this.statePath}.apps.json`, "utf8")); } catch {}
    this.consumerApps = { fingerprint: this.fingerprint(), connected: saved.fingerprint === this.fingerprint() && Array.isArray(saved.connected) ? saved.connected : [], pending: [] };
    return this.consumerApps;
  }
  saveConsumerState() {
    if (!this.statePath || !this.consumerApps) return;
    const { fingerprint, connected } = this.consumerApps;
    try { fs.writeFileSync(`${this.statePath}.apps.json`, JSON.stringify({ fingerprint, connected }), { encoding: "utf8", mode: 384 }); } catch {}
  }
  async connectionTool() {
    if (!this.rawTools) await this.tools();
    const tools = this.rawTools ?? [];
    return tools.find((tool) => /MANAGE_CONNECTIONS/i.test(tool.name)) ?? tools.find((tool) => /(INITIATE|CREATE|START)_CONNECTION|CONNECT_(APP|TOOLKIT)/i.test(tool.name)) ?? null;
  }
  // The tool's own inputs decide how the app is named: a list of toolkits, or one toolkit or app.
  connectionArguments(tool, slug) {
    const props = tool.inputSchema?.properties ?? {};
    const key = Object.keys(props).find((name) => /^toolkits?$/i.test(name)) ?? Object.keys(props).find((name) => /toolkit|app|integration/i.test(name)) ?? "toolkits";
    return { [key]: props[key]?.type === "string" ? slug : [slug] };
  }
  // What the tool said: its text parts read as JSON when they are.
  connectionAnswer(result) {
    const parts = Array.isArray(result?.content) ? result.content : [];
    const values = [result?.structuredContent];
    for (const part of parts) {
      if (typeof part?.text !== "string") continue;
      try { values.push(JSON.parse(part.text)); } catch { values.push(part.text); }
    }
    return values.filter((value) => value !== void 0 && value !== null);
  }
  // The sign-in link in an answer: a field named for one, or else the first https link in it.
  connectionLink(answer) {
    let found = null;
    const visit = (value, name = "") => {
      if (found) return;
      if (typeof value === "string") {
        if (/^https:\/\//.test(value) && /redirect|auth|connect|link|url/i.test(name)) found = value;
        return;
      }
      if (Array.isArray(value)) { for (const item of value) visit(item, name); return; }
      if (value && typeof value === "object") for (const [key, item] of Object.entries(value)) visit(item, key);
    };
    visit(answer);
    if (!found) found = JSON.stringify(answer).match(/https:\/\/[^\s"'\\)]+/)?.[0] ?? null;
    return found;
  }
  async askConnection(slug) {
    const tool = await this.connectionTool();
    if (!tool) throw new Error("Composio offers no way to connect apps with this key");
    const answer = this.connectionAnswer(await this.rpc("tools/call", { name: tool.name, arguments: this.connectionArguments(tool, slug) }));
    const text = JSON.stringify(answer);
    const link = this.connectionLink(answer);
    const active = !link && /\b(active|connected|already)\b/i.test(text) && !/not[ _]connected|inactive|no active/i.test(text);
    return { link, active };
  }
  async consumerAuthorize(slug) {
    const state = this.consumerState();
    const { link, active } = await this.askConnection(slug);
    if (active) {
      if (!state.connected.includes(slug)) state.connected.push(slug);
      state.pending = state.pending.filter((item) => item !== slug);
      this.saveConsumerState();
      this.invalidateTools();
      return { url: null, connected: true };
    }
    if (!link) throw new Error("Composio returned no sign-in link");
    if (!state.pending.includes(slug)) state.pending.push(slug);
    return { url: link };
  }
  async consumerServices() {
    const state = this.consumerState();
    for (const slug of [...state.pending]) {
      const { active } = await this.askConnection(slug).catch(() => ({ active: false }));
      if (active) {
        state.pending = state.pending.filter((item) => item !== slug);
        if (!state.connected.includes(slug)) state.connected.push(slug);
        this.saveConsumerState();
        this.invalidateTools();
      }
    }
    const services = {};
    for (const slug of state.connected) services[slug] = { connected: true, pending: false, status: "ACTIVE", accounts: [] };
    for (const slug of state.pending) services[slug] = { connected: false, pending: true, status: "INITIATED", accounts: [] };
    this.connectedSlugs = new Set(state.connected);
    return services;
  }
  async consumerRemove(slug) {
    const state = this.consumerState();
    state.connected = state.connected.filter((item) => item !== slug);
    state.pending = state.pending.filter((item) => item !== slug);
    this.saveConsumerState();
    return { removed: 1 };
  }
  invalidateTools() {
    this.toolCacheVersion += 1;
    this.toolCache = null;
    this.toolCacheExpiresAt = 0;
    this.toolCachePromise = null;
  }
  fingerprint() {
    return crypto.createHash("sha256").update(this.key).digest("hex");
  }
  loadState() {
    if (!this.statePath || !fs.existsSync(this.statePath)) return null;
    try {
      const value = JSON.parse(fs.readFileSync(this.statePath, "utf8"));
      return value.fingerprint === this.fingerprint() && value.userId && value.sessionId ? value : null;
    } catch {
      return null;
    }
  }
  saveState(value) {
    if (!this.statePath) return;
    const temporary = `${this.statePath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(value), { encoding: "utf8", mode: 384 });
    fs.renameSync(temporary, this.statePath);
  }
  requireKey() {
    if (!this.key || !this.key.startsWith("ak_")) throw new Error("A valid Composio project key is required");
    return this.key;
  }
  async ensureSession() {
    if (this.session) return this.session;
    if (this.consumer) return this.session = { id: null, userId: null, url: "https://connect.composio.dev/mcp", transportId: null };
    if (!this.key || !this.key.startsWith("ak_")) throw new Error("A valid Composio project key is required");
    const saved = this.loadState();
    if (saved) {
      const response2 = await this.fetcher(`${this.apiBase}/tool_router/session/${encodeURIComponent(saved.sessionId)}`, { headers: { "x-api-key": this.key }, signal: AbortSignal.timeout(15e3) });
      if (response2.ok) {
        const body2 = await response2.json();
        if (typeof body2.session_id === "string" && typeof body2.mcp?.url === "string") return this.session = { id: body2.session_id, userId: typeof body2.config?.user_id === "string" ? body2.config.user_id : saved.userId, url: trustedComposioUrl(body2.mcp.url, this.apiBase), transportId: null };
      }
      if (response2.status !== 404) throw new Error(`Connected-app session check failed (${response2.status})`);
    }
    const userId = saved?.userId ?? `agentlab_${crypto.randomUUID()}`;
    const response = await this.fetcher(`${this.apiBase}/tool_router/session`, { method: "POST", headers: { "x-api-key": this.key, "content-type": "application/json" }, body: JSON.stringify({ user_id: userId, manage_connections: { enable: true, enable_wait_for_connections: true, enable_connection_removal: true }, multi_account: { enable: true, max_accounts_per_toolkit: 5, require_explicit_selection: true } }), signal: AbortSignal.timeout(3e4) });
    if (!response.ok) throw new Error(`Composio rejected the project key (${response.status})`);
    const body = await response.json();
    if (typeof body.session_id !== "string" || typeof body.mcp?.url !== "string") throw new Error("Composio returned an invalid session");
    this.saveState({ fingerprint: this.fingerprint(), userId, sessionId: body.session_id });
    return this.session = { id: body.session_id, userId, url: trustedComposioUrl(body.mcp.url, this.apiBase), transportId: null };
  }
  async projectJson(url2, init = {}, allowEmpty = false) {
    const headers = new Headers(init.headers);
    headers.set("x-api-key", this.requireKey());
    if (init.body) headers.set("content-type", "application/json");
    const response = await this.fetcher(url2, { ...init, headers, signal: AbortSignal.timeout(3e4) });
    if (!response.ok) throw new Error(`Connected-app request failed (${response.status})`);
    const raw = await response.text();
    if (!raw && allowEmpty) return {};
    if (Buffer.byteLength(raw) > 20 * 1024 * 1024) throw new Error("Connected-app response exceeded 20 MB");
    return JSON.parse(raw);
  }
  async connectedAccounts(userId, slugs = []) {
    const output = [];
    let cursor;
    const seen = new Set();
    for (let page = 0; page < 100; page += 1) {
      const url2 = new URL(`${this.apiBase}/connected_accounts`);
      url2.searchParams.set("limit", "50");
      url2.searchParams.set("user_ids", userId);
      if (slugs.length) url2.searchParams.set("toolkit_slugs", slugs.join(","));
      if (cursor) url2.searchParams.set("cursor", cursor);
      const body = await this.projectJson(url2.toString());
      if (!Array.isArray(body.items)) throw new Error("Composio returned an invalid account inventory");
      for (const raw of body.items) {
        if (!raw || typeof raw !== "object") continue;
        const item = raw;
        const toolkit = item.toolkit && typeof item.toolkit === "object" ? item.toolkit : {};
        const id = String(item.id ?? "");
        const slug = String(toolkit.slug ?? "").toLowerCase();
        if (!ACCOUNT_ID.test(id) || !SLUG.test(slug)) continue;
        const alias2 = validAlias(typeof item.alias === "string" ? item.alias : null);
        output.push({ id, slug, ...alias2 ? { alias: alias2 } : {}, status: String(item.status ?? "UNKNOWN") });
      }
      const next = typeof body.next_cursor === "string" && body.next_cursor ? body.next_cursor : void 0;
      if (!next || seen.has(next)) return output;
      seen.add(next);
      cursor = next;
    }
    throw new Error("Composio account inventory exceeded the safety limit");
  }
  async sessionToolkits(sessionId) {
    const output = [];
    let cursor;
    const seen = new Set();
    for (let page = 0; page < 100; page += 1) {
      const url2 = new URL(`${this.apiBase}/tool_router/session/${encodeURIComponent(sessionId)}/toolkits`);
      url2.searchParams.set("limit", "50");
      if (cursor) url2.searchParams.set("cursor", cursor);
      const body = await this.projectJson(url2.toString());
      if (!Array.isArray(body.items)) throw new Error("Composio returned an invalid toolkit inventory");
      for (const raw of body.items) {
        if (!raw || typeof raw !== "object") continue;
        const item = raw;
        const slug = String(item.slug ?? "").toLowerCase();
        if (!SLUG.test(slug)) continue;
        const selected = item.connected_account && typeof item.connected_account === "object" ? item.connected_account : {};
        const accountId = typeof selected.id === "string" && ACCOUNT_ID.test(selected.id) ? selected.id : void 0;
        output.push({ slug, noAuth: item.is_no_auth === true, ...accountId ? { accountId } : {}, status: String(selected.status ?? (item.is_no_auth ? "ACTIVE" : "not_connected")) });
      }
      const next = typeof body.next_cursor === "string" && body.next_cursor ? body.next_cursor : void 0;
      if (!next || seen.has(next)) return output;
      seen.add(next);
      cursor = next;
    }
    throw new Error("Composio toolkit inventory exceeded the safety limit");
  }
  async rpc(method, params) {
    const session = await this.ensureSession();
    const headers = { [this.consumer ? "x-consumer-api-key" : "x-api-key"]: this.key, "content-type": "application/json", accept: "application/json, text/event-stream" };
    if (session.transportId) headers["mcp-session-id"] = session.transportId;
    const response = await this.fetcher(session.url, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: crypto.randomUUID(), method, params }), signal: AbortSignal.timeout(method === "tools/call" ? 10 * 6e4 : 3e4) });
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (declared > 20 * 1024 * 1024) throw new Error("Connected-app response exceeded 20 MB");
    const raw = await response.text();
    if (Buffer.byteLength(raw) > 20 * 1024 * 1024) throw new Error("Connected-app response exceeded 20 MB");
    if (!response.ok) throw new Error(`Connected-app MCP request failed (${response.status})`);
    session.transportId = response.headers.get("mcp-session-id") ?? session.transportId;
    const body = parseMcpBody(raw, response.headers.get("content-type") ?? "application/json");
    if (body.error) throw new Error(String(body.error.message ?? "Connected-app tool failed"));
    return body.result;
  }
  async notify(method, params) {
    const session = await this.ensureSession();
    const headers = { [this.consumer ? "x-consumer-api-key" : "x-api-key"]: this.key, "content-type": "application/json", accept: "application/json, text/event-stream" };
    if (session.transportId) headers["mcp-session-id"] = session.transportId;
    const response = await this.fetcher(session.url, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", method, params }), signal: AbortSignal.timeout(3e4) });
    if (!response.ok && response.status !== 202) throw new Error(`Connected-app MCP notification failed (${response.status})`);
    session.transportId = response.headers.get("mcp-session-id") ?? session.transportId;
    await response.arrayBuffer();
  }
};

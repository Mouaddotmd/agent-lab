// The conversation around a DM: its helpers (Claude's sub-agents) and the commands running above the box, side chats,
// forking a chat, handing it to another agent, and its context (tokens, cost, how full it is, compacting).
// The work itself runs in engine.js (Engine: side, compact, liveContext, stopHelper, stopCommand); this file is the calls.
import os from 'node:os';
import { forkSession } from '@anthropic-ai/claude-agent-sdk';
import { newId } from './store.js';
import { codexRpc } from './engine.js';

const clip = (s, n = 80) => { const t = String(s ?? '').replace(/\s+/g, ' ').trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };
// The hidden lines agents write (plans, ticks, reports' tags, notes to remember), out of words meant for reading.
const plain = (t) => String(t || '').replace(/⟦\s*remember\s*:[^⟧]*⟧/gi, '').replace(/⟦\s*\/?\s*(plan|done|report|next)[^⟧]*⟧/gi, '').trim();

/// A helper as the capsule and the list need it: everything but its transcript.
const brief = ({ messages, prompt, ...h }) => ({ ...h, steps: (messages || []).filter((m) => m.role === 'tool').length });

/// A DM as plain text for a summary: what you said, what it said, what it did (newest kept when it's long).
export function asText(messages, limit = 60_000) {
  const lines = [];
  for (const m of messages) {
    if (m.role === 'user') lines.push(`User: ${m.text}`);
    else if (m.role === 'assistant') { const t = plain(m.text); if (t) lines.push(`Agent: ${t}`); }
    else if (m.role === 'tool') lines.push(`  (${m.verb || 'Step'} ${m.text || ''}${m.failed ? ', failed' : ''})`);
    else if (m.role === 'error' && m.text !== 'Stopped.') lines.push(`  (Error: ${m.text})`);
  }
  const all = lines.join('\n');
  return all.length > limit ? `…${all.slice(-limit)}` : all;
}

export default function calls({ store, engine, out }) {
  const agentOf = (id) => { const a = store.agent(id); if (!a) throw new Error('That agent no longer exists.'); return a; };
  const emitSide = (agentId, side) => out({ event: { type: 'side', agentId, sideId: side.id, side } });

  // A copy of an agent for a fork: the same job, look, model, mode, folder, notes and workspaces.
  function copyAgent(a, name, sessionId) {
    const names = new Set(store.state.agents.map((x) => x.name));
    let n = name;
    for (let i = 2; names.has(n); i++) n = `${name} ${i}`;
    const copy = store.addAgent({ name: n, job: a.job || '', color: a.color ?? null, look: a.look || null, operator: a.operator, model: a.model || null,
      permission: a.permission || 'ask', cwd: a.cwd || os.homedir(), pinned: false, sessionId: sessionId || null, origin: { type: 'fork', ref: a.id, title: `Forked from ${a.name}` },
      workspace: null, claudeSetup: !!a.claudeSetup, alwaysEdits: !!a.alwaysEdits });
    if (a.memory?.length) store.updateAgent(copy.id, { memory: a.memory.map((m) => ({ ...m })) });
    for (const w of store.state.workspaces || []) if ((w.members || []).includes(a.id)) store.setMember(w.id, copy.id, true);
    return store.agent(copy.id);
  }

  async function sideAsk(agentId, sideId, text, images = []) {
    const agent = agentOf(agentId);
    const q = String(text || '').trim();
    if (!q && !images.length) throw new Error('Ask something first.');
    const list = store.sides(agentId);
    let side = sideId ? list.find((x) => x.id === sideId) : null;
    if (sideId && !side) throw new Error('That side chat was closed.');
    if (!side) side = { id: newId('s'), title: clip(q, 60), at: Date.now(), sessionId: null, operator: agent.operator, messages: [] };
    if (side.running) throw new Error('It’s still answering. Stop it first, or wait.');
    if (!side.messages.length) side.title = clip(q, 60);
    side.messages.push({ id: newId('m'), role: 'user', text: q, at: Date.now(), ...(images.length ? { images } : {}) });
    side.running = true;
    store.put(`sides_${agentId}`, side);
    emitSide(agentId, side);
    const reply = { id: newId('m'), role: 'assistant', text: '', at: Date.now(), steps: [] };
    const save = () => emitSide(agentId, { ...side, reply });
    let deltaAt = 0;
    engine.side(agent, { key: `side:${side.id}`, sessionId: side.sessionId || agent.sessionId || null, fork: !side.sessionId, rewindAt: side.sessionId ? null : agent.rewindAt || null, prompt: q, images }, {
      // Words as they're written, at most 20 times a second.
      onDelta: (t) => { const now = Date.now(); if (now - deltaAt < 50) return; deltaAt = now; out({ event: { type: 'side-delta', agentId, sideId: side.id, text: `${reply.text ? `${reply.text}\n\n` : ''}${plain(t)}` } }); },
      onText: (t) => { const w = plain(t); if (!w) return; reply.text = reply.text ? `${reply.text}\n\n${w}` : w; save(); },
      onTool: (d) => { reply.steps.push({ id: d.id, verb: d.verb, line: d.line, ...(d.detail ? { detail: String(d.detail).slice(0, 2000) } : {}), done: false, failed: false }); save(); },
      onToolDone: (id, failed, extra = {}) => {
        const st = reply.steps.find((x) => x.id === id); if (!st) return;
        Object.assign(st, { done: true, failed: !!failed, ...(extra.output ? { output: String(extra.output).slice(-8000) } : {}) });
        save();
      },
      onEnd: (o, sid) => {
        side.running = false;
        if (sid) side.sessionId = sid;
        for (const st of reply.steps) if (!st.done) st.done = true;
        if (reply.text || reply.steps.length) side.messages.push(reply);
        if (o.error) side.messages.push({ id: newId('m'), role: o.error === 'Stopped.' ? 'stopped' : 'error', text: o.error, at: Date.now() });
        side.at = Date.now();
        store.put(`sides_${agentId}`, side);
        emitSide(agentId, side);
      },
    });
    return { id: side.id, title: side.title };
  }

  return {
    // ---- helpers and running commands ----
    /// A conversation's helpers (without their transcripts).
    'convo:helpers': (conv) => store.helpers(conv).map(brief),
    /// One helper, with its transcript.
    'convo:helper': (conv, id) => store.helpers(conv).find((h) => h.id === id) || null,
    /// What a DM's run has going now: helpers still at work and commands running long enough to show.
    'convo:work': (agentId) => {
      const run = engine.runs.get(`agent:${agentId}`);
      return {
        helpers: [...(run?.helpers?.values() || [])].filter((h) => h.status === 'running').map(brief),
        commands: [...(run?.commands?.values() || [])].map(({ output, ...c }) => c),
      };
    },
    'convo:commandOutput': (agentId, id) => engine.commandOutput(agentId, String(id)),
    'convo:stopCommand': (agentId, id) => engine.stopCommand(agentId, String(id)),
    'convo:stopHelper': (agentId, id) => engine.stopHelper(agentId, String(id)),

    // ---- side chats ----
    'convo:sides': (agentId) => store.sides(agentId).map(({ messages, ...s }) => ({ ...s, count: messages.length })).sort((a, b) => b.at - a.at),
    'convo:side': (agentId, id) => store.sides(agentId).find((s) => s.id === id) || null,
    /// An empty side chat, for the + menus (you ask in its tab).
    'convo:sideNew': (agentId) => {
      const a = agentOf(agentId);
      const side = { id: newId('s'), title: 'Side chat', at: Date.now(), sessionId: null, operator: a.operator, messages: [] };
      store.put(`sides_${agentId}`, side);
      return side;
    },
    'convo:sideAsk': (agentId, sideId, text, images) => sideAsk(agentId, sideId || null, text, Array.isArray(images) ? images : []),
    'convo:sideStop': (sideId) => engine.stopSide(`side:${sideId}`),
    'convo:sideRemove': (agentId, sideId) => { engine.stopSide(`side:${sideId}`); store.drop(`sides_${agentId}`, (s) => s.id !== sideId); return true; },

    // ---- fork and hand off ----
    /// A new agent like this one whose chat is everything before one of your messages; that message comes back to
    /// put in its box. Claude: its session forked at that point; Codex: its thread forked and rolled back.
    /// `through`: branch from an answer instead: the new chat keeps that message's whole turn (up to your next
    /// message, or the end), and its box starts empty.
    async 'convo:fork'(agentId, messageId, through = false) {
      const a = agentOf(agentId);
      if (engine.runs.has(`agent:${agentId}`)) throw new Error(`${a.name} is still working. Branch when it's done.`);
      const all = store.messages(agentId);
      const found = all.findIndex((m) => m.id === messageId);
      if (found < 0 || all[found].role !== 'user') throw new Error('That message is no longer in this chat.');
      const next = through ? all.findIndex((m, i) => i > found && m.role === 'user') : found;
      const at = through ? (next < 0 ? all.length : next) : found;
      const before = all.slice(0, at);
      let sessionId = null;
      if (a.sessionId && before.some((m) => m.role !== 'user')) {
        if (a.operator === 'codex') {
          const cwd = a.cwd || os.homedir();
          const turns = all.slice(at).filter((m) => m.role === 'user').length;
          const [forked] = await codexRpc(cwd, [['thread/fork', { threadId: a.sessionId, cwd }]]);
          sessionId = forked?.thread?.id || null;
          if (!sessionId) throw new Error('Codex couldn’t fork this chat.');
          if (turns) {
            const [, rolled] = await codexRpc(cwd, [['thread/resume', { threadId: sessionId, cwd }], ['thread/rollback', { threadId: sessionId, numTurns: turns }]]);
            if (!rolled) throw new Error('Codex couldn’t go back to that message in the fork.');
          }
        } else {
          const keep = [...before].reverse().find((m) => m.sdk)?.sdk || null;
          if (keep) sessionId = (await forkSession(a.sessionId, { upToMessageId: keep, title: `${a.name} (fork)` })).sessionId;
        }
      }
      const copy = copyAgent(a, `${a.name} (branch)`, sessionId);
      const list = store.messages(copy.id);
      list.push(...before.map((m) => structuredClone(m)));
      list.dirty = true;
      const tools = new Set(before.map((m) => m.toolId).filter(Boolean));
      for (const h of store.helpers(agentId)) if (tools.has(h.id)) store.putHelper(copy.id, structuredClone(h));
      store.save();
      return { agent: store.agent(copy.id), text: through ? '' : all[at].text, images: through ? [] : all[at].images || [] };
    },

    /// Passes a DM to another agent: it gets a note on the goal, what was done and what's left as your first message
    /// in its own DM, and starts on it. The chat it came from says where it went.
    async 'convo:handoff'(fromId, toId) {
      const from = agentOf(fromId), to = agentOf(toId);
      if (fromId === toId) throw new Error('Pick another agent.');
      if (engine.runs.has(`agent:${toId}`)) throw new Error(`${to.name} is still working. Hand it over when it's done.`);
      const text = asText(store.messages(fromId));
      if (!text.trim()) throw new Error('There’s nothing in this chat to hand over yet.');
      const note = await engine.ask(`Here is a conversation between a user and an AI agent called ${from.name}, working in ${from.cwd || os.homedir()}.\n\n<conversation>\n${text}\n</conversation>\n\nAnother agent, ${to.name}, is taking this over. Write the hand-over note it will read first, addressed to it: the goal, what was done and decided (files and commands by name), and what is left to do, in that order. At most 12 short lines of plain words, no headings, no preamble.`);
      if (!note.trim()) throw new Error('Couldn’t write the hand-over note.');
      if (engine.runs.has(`agent:${toId}`)) throw new Error(`${to.name} started working meanwhile. Hand it over when it's done.`);
      const message = `${from.name} handed this over to you.\n\n${note.trim()}\n\nIts folder: ${from.cwd || os.homedir()}\n\nCarry on with what's left.`;
      engine.sendToAgent(toId, message);
      store.addMessage(fromId, { role: 'note', text: `Handed to ${to.name}.`, ref: toId });
      out({ event: { type: 'messages', agentId: fromId } });
      return { to: toId };
    },

    // ---- context ----
    /// What the DM has used: tokens, cost, how full its context was at the end of the last run, and the model.
    'convo:context': (agentId) => {
      const a = agentOf(agentId);
      return { operator: a.operator || 'claude-code', model: a.model || null, usage: a.usage || null, session: !!a.sessionId,
        running: engine.runs.has(`agent:${agentId}`), compacting: !!engine.compacting?.has(agentId) };
    },
    /// Claude Code's own count of the context right now, by part (null when it can't be asked: Codex, working, no chat).
    'convo:contextLive': (agentId) => engine.liveContext(agentId),
    'convo:compact': (agentId) => engine.compact(agentId),
  };
}

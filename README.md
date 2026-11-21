# Agent Lab

A home for your AI agents. An agent is Claude Code or Codex with a name, a face, a folder and (optionally) a
job. It runs as that tool runs on its own, with your login and settings, and asks you before it changes anything.

## Run

```sh
npm install
npm start
```

Needs the tools you want to use, signed in as usual: `claude` (Claude Code), and optionally `codex`.
Agent Lab finds them in your `PATH`, `~/.local/bin`, `/usr/local/bin` and `/opt/homebrew/bin`.

## What it does

- **Agents** run through the real tools: Claude Code through the Claude Agent SDK (your `claude` login), Codex through
  `codex exec --json`. Replies stream in as they're written.
- **Nothing is added to how they behave.** Claude Code agents keep Claude Code's own system prompt and your own settings.
  The only extra text is a job you write yourself and the decisions you saved to Memory. Leave both empty and the agent
  answers exactly as the tool does.
- **Approvals** pause the agent for real. With "Asks before changes", every edit or command shows a card (Allow, Always
  allow, Don't allow) and the agent waits. Codex can't pause, so it works inside its own sandbox.
- **Stop** ends a run at any point.
- **Own branch.** An agent can work on `agent/<name>` in its own folder (a git worktree). Review shows its changes
  against the branch it started from; Merge brings them in; Discard throws them away. If two agents change the same file,
  Waiting for you says so before you merge.
- **Your chats** from Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`) are listed per tool, beside the
  open chat. Continue any of them, hand one to an agent (Claude writes a short hand-off note), or make it an agent: the
  agent continues that exact session, and Claude can list the decisions in it for you to keep in Memory.
- **Mavis.** Connections brings in Mavis's agents and conversations by name. Mavis's prompts, rules and injected context
  are left behind.
- **Workspaces** are folders. Each gets a tile on the left with its own agents and chats.
- **Keyboard:** ⌘K search everything or hand off, ⌘N new agent, ⌘1–9 jump to an agent, ↑↓ move through chats,
  ⌥⌘0 show or hide Right now.

Data lives in `~/Library/Application Support/Agent Lab/` (`state.json`, one file per agent conversation, and agent
worktrees). Chats are read where each tool keeps them; nothing is uploaded.

## Layout

| Path | What it is |
| --- | --- |
| `src/main/main.js` | Window, menu, and every call the interface can make |
| `src/main/engine.js` | Runs agents (Claude Agent SDK, Codex), streaming, approvals, stop |
| `src/main/history.js` | Reads Claude Code and Codex chats, and Mavis names and conversations |
| `src/main/git.js` | Agent branches and folders, review, merge, discard, overlaps |
| `src/main/store.js` | Saved state, written atomically |
| `src/preload.cjs` | The only bridge between the page and the engine |
| `src/renderer/` | The interface: `styles.css` (the design system tokens), `app.js` |
| `scripts/` | `check.mjs` (syntax), `e2e.mjs` + `e2e-driver.mjs` (end-to-end test) |

## Checks

```sh
npm run check   # syntax of every source file
npm run e2e     # drives the real app on a throwaway data folder and repository, with real Claude Code, Codex and git
```

The end-to-end test makes a few small real requests (Claude Haiku and one Codex reply) and saves a screenshot per step.

## Design rules

Every value comes from the tokens at the top of `src/renderer/styles.css`: a 4px spacing scale, a 1.25 type scale from
14px, radii of 4/8/12/16 nested by inset, one primary action per screen, 44px touch targets, and a palette where each
colour has one job (clay is waiting for you, red is failed).

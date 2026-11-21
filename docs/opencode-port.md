# Bringing OpenCode's chat into Agent Lab

Agent Lab keeps its own look, layout and product model (agents are people with their own memory; workspaces are
channels). OpenCode's features are rebuilt into it, not copied. The source of truth for behaviour is OpenCode's code at
`~/Desktop/Agent Hub/Extras/reference/opencode` (map: `~/Desktop/Agent Hub/research_notes/opencode-reference.md`).

## Done (17 Nov)

- **Message box:** + menu (files or photos ⌘U, folder, slash commands, plugins with "Use my Claude Code setup"), `/` and
  `@` with full keyboard control, attachments, history, drafts.
- **Turns:** steps open to their command, output or diff; "Changed N files" after a turn; messages sent while it works
  go in; go back to an earlier message (files put back for Claude); approval notes, question cards, edit diffs;
  thinking; Codex on `app-server` (live words, output, diffs, approvals, mid-turn messages, clean stop).

## To build, in order

Each phase ends built, tested and relaunched.

### 1. The side panel (everything else plugs into it)
A panel to the right of a chat with tabs and a + menu (OpenCode: `app/src/runtime/plugin/side-region.tsx`). Resizable,
remembers its width, ⌘\ to show or hide. Tabs: Files, Changes, Terminal, Browser, Side chat, Helper, Context.

### 2. Files
The agent's folder as a tree with git change marks; a file opens in a tab: syntax colours, Markdown and image preview,
find in file (⌘F). Select lines → "Add to message" (puts them in the box as context). **Editing (new, OpenCode is
read-only):** edit and save with ⌘S, with a warning if the agent changed the file meanwhile. ⌘P: open a file by name.

### 3. Changes
Uncommitted changes, changes against the base branch, and this chat's changes (OpenCode: `gui-plugins/src/review`).
File list with +/−, each file's diff; a line can be added to the message. **Commit (new):** message and Commit, for
when you want to keep what the agent did.

### 4. Sub-agents
Claude's helpers (Task tool) get their own transcript: the step "Asked a helper to …" opens it (in the side panel),
with its own steps, words, and a status bar (Running / Done / Failed). Above the box, a live capsule: "2 helpers
working · 1 command running", each opening its helper or showing the command's output with Stop.

### 5. Side chats, fork, handoff
- **Side chat (`/btw` or the + menu):** ask the agent something about the chat without adding to it; the answer opens in
  a side tab.
- **Fork (new for Agent Lab's model):** from any of your messages, a new chat with the same agent that keeps everything
  before it; opens with that message in the box to change.
- **Hand off (new):** pass the chat to another agent: it gets a summary of the conversation and what's left, and carries
  on in its own DM (fits "agents are people").

### 6. Terminal
A real terminal in a side tab (a pseudo-terminal running your shell in the agent's folder), xterm.js in a web view for
the screen. Commands the agent leaves running show their live output there with Stop.

### 7. Browser
A web view in a side tab: address bar, back, forward, reload, zoom. "Add page to message" (the page's address and
text into the box) and "Point at something" (click an element, it goes in as context).

### 8. Command palette and finding
⌘K: every command, agent, chat, file and setting. ⌘F in a chat: find, with next/previous. Jump to a message.

### 9. Context
Tokens, cost and how full the context is, for the open chat; compact from there.

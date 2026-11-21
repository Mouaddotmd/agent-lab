# Preview, Undo, Publish

Three features that turn Agent Lab from a place where agents write code into a place where anyone builds things: **see it**,
**never be afraid of breaking it**, **put it out into the world**. Every serious coding tool has some version of each
(Claude Code `/rewind`, OpenCode `/undo`, Cursor checkpoints and its browser, T3 Code's one-click PR). Without them,
builders uninstall, and everyone else never gets started.

Build them in **Agent Lab Native** (`native/`) on top of the existing engine (`engine/`). Keep the Whop system
(`docs/whop-system.md`), the current palette and the corner scale. These features add surfaces; they don't restyle
existing ones.

---

## What exists today (the starting point)

| Piece | Where | What it gives us |
|---|---|---|
| A run's lifecycle | `engine/engine.js`: `#converse` → `#start` → `#finish`, which emits `run`, `run-end` | One clean before and after for every turn |
| Where an agent works | `cwd`: the agent's own folder, its worktree (`agent/<name>`), the workspace folder in a channel, or `HOME` when it has none | The folder to snapshot, preview and publish |
| Branch tools | `engine/git.js`: `changes`, `fileDiff`, `merge`, `discard`, `overlaps`, wired as `git:*` in `server.js` | Review and Merge exist in the engine, but the native app doesn't use them yet |
| Turns in the chat | `native/Sources/ChatTurns.swift`: `Turn.id` is the id of the message you sent | A stable place to hang a restore point |
| The Review page | `Kind.reviews` in `Store.swift`, rendered as `Color.clear` in `Pages.swift` ("parked") | An empty home, ready for "what changed, go back, publish" |
| Panes | `native/Sources/Panes.swift`: `sidebar`, `list`, `now` | A resizable pane model the preview can join |
| Claude Agent SDK | `resumeSessionAt`, `forkSession`, `enableFileCheckpointing` in `sdk.d.ts` | Rewinding a Claude conversation, not only its files |

What the three features share: **the folder an agent works in**, and **the moment a turn starts and ends**.

---

## 1. Undo: every turn is a restore point

### What the person sees
- Under each of your messages in a chat, once the agent has answered and changed something: a small
  **"↶ Go back to here"** on hover, plus the count of files changed in that turn ("3 files").
- Clicking it opens a small card:
  - **Files only**: the folder goes back to how it was before this message. The chat stays.
  - **Files and chat** (Claude Code agents only): the agent also forgets everything after this point.
  - One line in plain words: "Undoes 2 turns: 5 files, 1 new file removed." Nothing is said about git.
  - One primary button: **Go back**.
- After going back, a toast says **"Went back. Redo"**. Redo works because going back is itself a restore point.
- On the Review page, each agent has a **timeline** of its restore points (time, your message, files changed). Clicking
  any one shows what changed in it and offers **Go back to here**.

### Rules
- **Works for every agent, in any folder, whether it's a git repository or not.** Undo can't depend on the person
  knowing git.
- **Never touches the person's own git history.** No commits, stashes or resets in their repository.
- Covers everything the agent did: Claude edits, Codex edits, and files changed by shell commands. That's why
  this can't use the SDK's `enableFileCheckpointing` alone, which only tracks Claude's own edit tools.
- An agent with no folder (`cwd` is `HOME`) gets no restore points. Its "Go back" is replaced by one line: "Give this agent
  a folder to be able to go back." Never snapshot the home folder.
- While an agent is running, Go back is disabled for that folder ("Stop Mira first").

### How it works
**A shadow store per folder.** This is the same approach as OpenCode's snapshots: a separate git object store that only
Agent Lab uses.

```
~/Library/Application Support/Agent Lab/snapshots/<sha1(realpath(folder))>/   # bare git dir
git --git-dir=<that> --work-tree=<folder> add -A          # respects the folder's .gitignore
git --git-dir=<that> --work-tree=<folder> write-tree      # → tree id = the restore point
```

- New module `engine/snapshots.js`: `take(folder) → treeId`, `diff(folder, fromTree, toTree) → files`,
  `restore(folder, treeId)`.
- `restore`:
  1. Take a snapshot first, so Redo works.
  2. `read-tree <tree>`, then `checkout-index -a -f`.
  3. Delete files that exist now but not in the target tree: `diff --name-only --diff-filter=A <tree>`.
- Limits:
  - Always exclude `node_modules`, `.git`, `dist`, `build`, `.next` and the folder's `.gitignore`.
  - Skip any single file over 20 MB.
  - If a snapshot would be over 500 MB, skip it and say so once in the chat.
  - Prune trees older than 30 days, plus every tree not referenced by a message.
- **Hooks in `engine.js`:**
  - In `#converse`, before `#start`: `checkpoint = snapshots.take(cwd)`. Store it on the sent message:
    `store.updateMessage(conv, sent.id, { checkpoint, folder: cwd })`.
  - In `#finish`: `after = snapshots.take(cwd)`. Store `{ after, changed: diff(checkpoint, after).length }` on the same
    message. If `changed` is 0, the chat shows no undo affordance for that turn.
- **New calls in `server.js`:**
  - `checkpoint:list(conv)`
  - `checkpoint:diff(conv, messageId)`
  - `checkpoint:restore(conv, messageId, { chat })`
- **Chat rewind (Claude only).** `restore` with `chat: true` also stores `resumeAt: <SDK message uuid before that turn>`
  on the agent. The next `#claude` call passes `resumeSessionAt` and `forkSession: true`, so the old session is kept. In the
  app, messages after the point are hidden (marked `rewound: true` and kept on disk, not deleted). Codex shows
  **Files only**.
- **Channels:** several agents can work in one workspace folder. If going back to a point would also undo another agent's
  later turn, the card says so by name: "This also undoes what Kai did after it."

### Done when
- [ ] Ask an agent to create, edit and delete files across 3 turns, then go back to turn 1: the folder matches byte for
      byte, new files are gone, deleted files are back.
- [ ] Redo returns exactly to the state before going back.
- [ ] Works the same in a non-git folder, a git repository and an agent worktree. The person's `git log` and `git status`
      are unchanged by any undo.
- [ ] A shell command's changes (`npm init -y`, `mv a b`) are undone too.
- [ ] Files and chat on a Claude agent: the next reply doesn't remember the rewound turns.

---

## 2. Preview: see the thing you're building

### What the person sees
- When the agent's folder is something that can be shown, a **Preview** button appears in the chat's title bar.
- Preview opens a pane on the right of the chat, beside or instead of Right now. It holds a real web view with a slim bar:
  page path, reload, "Open in browser", and a status dot (starting, live, crashed).
- **It updates on its own.** When an agent's turn ends, the preview reloads, unless the dev server already hot-reloads.
- **Errors come back as a question, not noise.** If the page throws or the server crashes, the pane shows one line ("The
  page has an error") and a **"Ask Mira to fix it"** chip. The chip sends the error text and the last 40 lines of server
  output as a normal message. It never sends anything automatically.
- When there's nothing to show, the button doesn't appear. The person never sees "no dev server configured".

### What can be previewed (detection, in order)
1. `package.json` with a `dev` script, or else `start`. Run it with the person's package manager (`pnpm-lock` → pnpm,
   `bun.lock` → bun, `yarn.lock` → yarn, else npm). If `node_modules` is missing, run install first and show "Setting it
   up…" in the pane.
2. `index.html` at the root, or in `public/`: serve the folder statically from the engine (a small built-in static server).
3. A single `.html`, `.svg`, `.md` or image file the agent just wrote: show the file.
4. Anything else: no preview, for now. Native apps, Python and so on come later.

### How it works
- New module `engine/preview.js`. At most **one preview process per folder**, shared by every agent working there.
  - `start(folder)` picks a free port and passes `PORT=<p>`. It adds `-- --port <p>` for Vite and `-p <p>` for Next,
    reads stdout until it sees a URL or the port answers (timeout 60 s), and emits
    `{ type: 'preview', folder, url, status }`.
  - It keeps the last 400 lines of output in memory for the "fix it" chip.
  - `stop(folder)`: on closing the pane, on the agent going idle for 15 minutes, and on app quit (`engine.stopAll`).
- On `run-end`, emit `preview-reload` for that folder. The native side reloads only if no hot-reload websocket was seen.
- **Native:**
  - A new `PaneID.preview` in `Panes.swift` (standard 520, min 360, max 900, grows left).
  - A `PreviewPane` wrapping `WKWebView`.
  - A `WKScriptMessageHandler` that forwards `window.onerror` and `unhandledrejection` to the pane's error line.
- **Agents with their own branch** preview their own worktree, not the main folder. That makes it possible to compare
  two agents' versions side by side later.
- **Safety:** only `localhost` and `file://` load in the pane. Clicking an outside link opens the person's browser.

### Done when
- [ ] "Make me a landing page for a bakery" in an empty folder ends with the page visible in the pane, with no terminal
      and no URL typed by the person.
- [ ] A Vite app and a Next app each start on a free port, and two agents' worktrees can preview at once.
- [ ] Breaking the page shows the error line. The chip sends one message containing the error, and the fix reloads the
      pane.
- [ ] Quitting Agent Lab leaves no dev server running (`lsof -i` is clean).

---

## 3. Publish: put it out into the world

### What the person sees
- A **Publish** button sits beside Preview. It is the screen's one primary action once there are changes, and it's never
  shown when there's nothing new.
- Publish opens a card that always says where the work goes, in plain words, before anything happens:
  - **"Put it online"**: "Your site will be live at a link anyone can open." Then the link appears, with **Copy** and
    **Open**.
  - **"Send it for review"**: "Opens a pull request on github.com/you/bakery for you to merge." Then the PR link appears.
  - **"Save to main"**: "Adds Mira's work to `main` on this Mac." This is today's Merge, renamed.
- Only the options that are possible for this folder are shown. If one needs an account the person hasn't connected, it
  shows **"Connect GitHub"** or **"Connect Vercel"** instead, which starts the tool's own sign-in in their browser.
  Agent Lab never stores their passwords or tokens.
- Each publish becomes a marked point on the Undo timeline ("Published · 14:02 · bakery.vercel.app").

### Rules
- **The person's own accounts and tools, like the agents themselves.** Use their `gh` and `vercel` command-line tools and
  sign-ins. Agent Lab doesn't host anything and adds no data path.
- **Always a person's click.** Agents can suggest publishing ("Ready to put it online?" as a chip), but publishing never
  happens inside an agent's turn or from an approval card.
- **Going live is a separate, second step.** "Put it online" first makes a preview deployment (its own link). A
  **"Make this the main link"** button promotes it (`vercel --prod`). The person always sees what goes live first.

### How it works
- New module `engine/publish.js`:
  - `options(folder)` returns the available targets:
    - `save`: the agent has its own branch, which reuses `git.merge`.
    - `pr`: the repository has a `github.com` remote and `gh auth status` succeeds.
    - `online`: Preview found something web-shaped (rule 1 or 2 above) and `vercel` is installed. When it isn't signed
      in, offer "Connect".
  - `pr`: commit the worktree (`commitAll`, but with a message Claude writes from the turns since the last publish), then
    `git push -u origin agent/<name>`, then `gh pr create --fill --head agent/<name>`. Return the URL.
  - `online`: run `vercel deploy --yes` in the folder and return the URL. Promote with `vercel promote <url>` or
    `vercel --prod`.
  - Every step streams progress events (`{ type: 'publish', folder, step, url?, error? }`), so the card shows "Uploading…",
    "Building…", "Live".
- **Errors in plain words:**
  - Build failed: show the last 20 lines and offer the same "Ask Mira to fix it" chip.
  - Push rejected: "GitHub has newer changes. Ask Mira to update first."
- **Native:**
  - A `PublishCard` sheet.
  - Publish history on the Review page, which finally gets content: per agent, the changes (from `git:changes` and
    snapshot diffs), the timeline, and the publish history.

### Done when
- [ ] The bakery page from Preview goes from "Publish" to a working public link in one card, on an account connected
      once.
- [ ] A repository with a GitHub remote gets a PR whose title and body describe the agent's work, with no terminal.
- [ ] Nothing is ever pushed or deployed without a click on the card. Searching the engine for `push`, `deploy` and `gh pr`
      finds them only in `publish.js`.
- [ ] Missing `gh` or `vercel` shows "Connect…", never a raw error.

---

## Build order

1. **Undo** first. It has no outside dependencies, everything else leans on it (a publish is a restore point), and it
   makes the other two safe to try.
2. **Preview**. It's what makes the product make sense to someone who doesn't read code.
3. **Publish**, starting with "Save to main" (Merge, which already exists in the engine) and "Send for review", then
   "Put it online".

Each step: engine module, then `server.js` calls, then native UI. Then add an end-to-end step in `scripts/e2e.mjs`,
`native/build.sh`, and relaunch `~/Applications/Agent Lab Native.app`.

## Not in this round
- Previewing native apps, mobile apps and Python apps.
- Hosting anything ourselves, or custom domains.
- Undo for conversations with Codex (it has no resume-at-point).
- Agents publishing on their own.

## Open questions for Mouad
1. **Where Preview lives.** Should Preview take Right now's place on the right while it's open, or sit between the chat
   and Right now? This spec assumes it replaces Right now while open.
2. **Hosting.** Vercel first for "Put it online"? Netlify and Cloudflare Pages would work the same way through their own
   command-line tools.
3. **What the Review page is called.** It becomes "what changed, go back, publish". Keep the name Review, or rename it
   (e.g. "Changes")?

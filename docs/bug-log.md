# Agent Lab Native: bug log (MAVIS port)

Every bug reported and worked on during the MAVIS redesign of Agent Lab Native, from the port onward. The cause is
what was actually wrong; the fix is what shipped. "Open" means not fixed or not confirmed.

## Layout and look

| Bug | Cause | Fix |
|---|---|---|
| Chat bubbles far too wide | The AppKit text view fills any width it's offered | Bubble hugs its words (measured width) |
| Bubble words off-centre (more room on the right, sat low) | A doubled 5 pt text inset, +4 slack, and AppKit sets words low in a fixed 23 pt line | Measure exactly, lift the words by the line's spare height |
| Chat and box too wide with no panel open | No max width | 720 pt reading column, centred |
| Composer placeholder and typed text misaligned | Field 16 pt vs placeholder 15 pt, words low in their line | Same size, baseline lifted |
| Profile bar slid under the surface when the list narrowed | Fixed 355 pt width | Follows the list's width |
| Jump-to-latest arrow in a random spot | Pinned to the window edge | On the chatbox's right edge |
| Extra space above a channel's header (~20 pt) | Kept chat views took the title bar's safe-area inset | Safe area off for kept chats |
| Workspace sidebar ran over the rail when narrow | Workspace name had a fixed width | Name gives way; column clipped |
| Workspace name always faded / "ate" itself on resize | Fade applied without measuring | Fades only when it truly doesn't fit, measured live |
| List column missing the prototype's outline | Never drawn | 1 pt 3% outline, 12 pt top corners |
| "Jump back in" labels not flush with cards | 10 pt inset | 0 |
| Browser tabs overlapped, ✕ outside the tab, + vanished | Title wouldn't shrink; widths unbounded | Tabs with set widths, clipped; Chrome-style narrowing; + always visible |
| Take-over and collapse buttons not aligned | 6 vs 8 pt edges | Both 8 |
| Omnibox changed shape while typing | Editing swapped to a classic field | Same pill geometry, rows joined under it |
| Omnibox selected row invisible | Selected tone = dropdown tone | Pill in the selection blue |
| Omnibox rows not aligned under the field | No shared lead | Icons and words line up with the field's |
| Approval card wide, showed full URLs, off-system | Old card | System card, hugs words, "Open YouTube?" |
| Step/plan cards looked inset, weak check | 1 pt edge, small tick | Flat cards, bold tick in a circle |
| Attachments small, ✕ always shown, off the box's spacing | Old strip | 96 pt tiles, 6 pt rule, concentric radius, ✕ on hover like Discord's status dot |
| Chip pills: square fills, text overlapping, half-cut at line start, sat high | Fill per colour run; no room; AppKit clipped the pill to the text area; centred on the line not the words | One rounded pill per chip, kerned room, room inside the text area, centred on the words (verified offscreen: tools/chiptest) |
| One-word command wrapped to two lines in its bubble | Width measured without the chip's weight and room | Measured as drawn |
| "Text channels" as the default category name | Engine default | "Main" |
| Agents group looked like a category | Coloured tag | Plain label |
| Side chats still in the old look | Never ported | Same bubbles, words, shimmer and box as the chat |
| "Interrupted" with a square icon, grey | Old line | No icon, soft red |

## Behaviour

| Bug | Cause | Fix |
|---|---|---|
| Browser split stuck while dragging | The width lived in a setting the view never watched | Width in view state, saved on release |
| Default browser column far too narrow | Old fixed default | 50/50 with the chat |
| New tab opened twice / launcher over a blank tab | Launcher shown even with a new tab in front | Launcher only over a real page; + toggles it; + closes the address bar while typing |
| Max tabs | None | 15 |
| Chat row hover existed though the design has none | Classic behaviour left on | Off in MAVIS |
| Row highlight vanished on reaching ⋯ | The row's own button hover ended at the ⋯ | Row hover covers the whole row |
| ⋯ hover hard to see / square | Grey on blue, small radius | Row's blue on selected rows, rounder, lights only under the pointer |
| Hover on workspace channels/categories wrong | Not ported | Prototype's: tag brightens, + on hover, bare icons |
| Clicking outside a text box didn't release it | No such behaviour | App-wide: any editable box lets go on an outside click |
| Text selection left bright blue highlights behind, two at once | Each text block kept its own selection | One selection at a time, cleared on leaving, app's selection tone |
| I-beam cursor everywhere | A chat kept drawn under another page kept its cursor zones | Away chats move out of the visible area |
| Leaving a workspace closed your open Messages chat | Opening a workspace cleared the selection | Messages keeps its chat |
| Black flash / 1 s pause going back to Messages (mavis v2) | Messages and workspace shared one cached chat view; the cache evicted long chats; the browser slept while hidden | Separate cached views, Messages chats kept first, chat stays drawn while away |
| Browser pane blanked or "animated" on page switches | Web view taken out of the window and repainted | Web view parked in the window, never removed |
| Snapshot cover showed video as white | Video can't be snapshotted | Removed |
| Shimmer invisible / frozen | Animation switched off by its parent; too faint | Clock-driven, white band over dark words |
| Hover/press shadows on popups | Default shadows | None in MAVIS |
| Tooltips on buttons too quick | Shared the rail's delay | 0.9 s for buttons; rail unchanged |
| Expand/collapse animation on steps | Animated reveal | Instant |
| "Show earlier messages" button | Discord-style paging | Gone: earlier messages load as you scroll up |

## Agents, channels, engine

| Bug | Cause | Fix |
|---|---|---|
| Channels needed an @tag for every answer | Engine only answered tags | A channel's agents (or its assistant) answer untagged |
| New workspace still needed tags | Default only for one-agent workspaces | First agent / assistant always answers |
| Channels shared the agent's DM (its DM showed busy) | Channel runs used the DM's run key | Channel runs have their own key and session |
| Agents' browser steps went to the wrong panel | Hands calls carried only the agent | Tagged with the channel; app routes to that channel's panes |
| Codex agent said "browser unavailable" | It used the user's own ChatGPT tools instead | App runs switch off node_repl / computer-use (cua_repl named off-limits; it can't be switched off) |
| Agents said they couldn't open the browser | Not told to act in the app | Told to open panes and show finished work, Claude Code-style |
| Engine wouldn't start ("no agents") | A stray apostrophe in the agents' instructions broke the JS | Fixed; engine loads |
| 5-minute "Extract still frames" | Its approval card was filtered out in channels, so it waited forever | Channel turns show their approvals |
| Sent videos/files showed as "@/path" text | Files were appended as text and shown raw | Tiles above the bubble with Quick Look previews |
| Slash commands absent in channels | Commands only offered with a DM agent | Channel box offers its answering agent's commands |
| No permission (Mode) pill in channels with no agent | The assistant was hidden from the app | Assistant's mode shown |
| Category colours / channel agents lost | Engine dropped unknown fields | Engine keeps color and agents |

## Speed (tools/chatperf, real mavis v2 chat)

| Issue | Cause | Fix |
|---|---|---|
| Trackpad scrolling felt choppy | Every trackpad event hit-tested the whole window; hover tracker ran every scroll frame | Skipped unless needed: event cost 0.4 → 0 ms |
| Long chat open slow, resize slower after removing paging | Every message laid out | Pages of 40, earlier ones join as you scroll up: open 365 → 119 ms, Messages resize 31 → 12.5 ms/frame |

## Before the MAVIS port (Nov 14–19), from the notes left in the code and the tests written for them

### Chat scrolling and following
| Bug | When | Fix |
|---|---|---|
| A view held to the bottom edge fought the follower: two things scrolled the chat | 15 Nov | One scroll writer (the follower) |
| After a stall the follow glide lurched | 15 Nov | At most one 60 Hz frame per step |
| Rows showed twice, offset, for a frame | 16 Nov | Moves that aren't ours are put back before they're drawn |
| History arriving above (+905 pt) yanked the view | 16 Nov | Big moves from history are let through |
| Opening a long chat at its end showed black until you scrolled (lazy list guessed heights) | 17 Nov | Transcript built for real, not lazy |
| A new width rewrapped every message and the same offset showed something else | 17 Nov | The message you're reading kept in place on resize |
| First frame of a panel opening drawn scrolled up, then jumped back | 17 Nov | Pinned in the same layout pass |
| The chat scrolled back and forth while the panel opened | 17 Nov | Follow paused while the panel moves |
| The end left behind for one frame on a width change (3,812 pt) | 19 Nov | Content width read before the visible area |
| Scroll twitched when the message you were reading was the one changing | 19 Nov | That move no longer moves the view |
| The follow glide pulled against your first scroll (phase arrives late) | 19 Nov | Your wheel counts at once |
| Your send glided to the end and read as a glitch | 19 Nov | Lands in one frame, as Claude Code |
| "Buggy for the first split second" at the bottom of a chat | — | Opening rules for the first frames |
| A mouse wheel lagged and stuttered with driver-smoothed mice | — | Fractional (already smoothed) wheels left as they come |
| Mouse-wheel scrolling not smooth | — | mouad.work's eased curve, 40 pt a line (tools/scrolltest) |

### Chat rendering and streaming
| Bug | When | Fix |
|---|---|---|
| A 2,000-character backlog came out as several lines at once, then a crawl | 16 Nov | Words revealed at an even, eased pace |
| Words vanished and retyped when a block was saved | 17 Nov | Never wipe and retype; the draft holds its place |
| Checklists written as text instead of the to-do card | 17 Nov | Plans are the card only |
| The status line dropped out and the chat shrank and grew back | 15 Nov | Line reads the turn's real steps |
| A cross-fade drew old and new words over each other when a turn ended | 15 Nov | One still swap |
| The old plan card shown until the new one arrived read as the wrong plan | 19 Nov | Card swaps at once |
| A confirmed send remounted its row and flickered | — | Pending row kept, same id |
| Opening a chat ~120 ms, resizing 15–25 ms a frame (a SwiftUI view per paragraph) | 17 Nov | One attributed string per message: ~20 ms open, under 10 ms resize |
| A sent "/skill" looked different right after launch than when sent | — | Known commands remembered on disk; consistencytest |
| The agent's name and face over its own replies in its own chat | 19 Nov | Just the reply |

### Window, panes and switching
| Bug | When | Fix |
|---|---|---|
| Switching chats / Review → Messages: ~45 ms, three dropped frames | 17 Nov | Kept chat views (ChatHost pool) |
| A chat built before its slot was sized drew one frame squeezed into a corner | 19 Nov | Shown only once sized |
| Resizing fell to 20–30 fps (whole app redrew on pane changes) | 17 Nov | Views redraw only for what they show |
| Home's cost: four versions of a row on every resize frame | 17 Nov | Row built once |
| Any motion on the side panel read as a glitch | 17 Nov | Shown and gone at once |
| Panel stuck half-shown after quick clicks; chat black mid-slide | — | paneltest guards it every frame |
| Chat went blank while resizing | — | resizetest guards it |
| The agent's browser lost its tabs when the pane closed or the app quit | 19 Nov | Tabs saved and restored |
| Content cropped as the window got smaller | — | Rail and "Right now" step aside |

### Menus, tips and focus
| Bug | When | Fix |
|---|---|---|
| A menu over a scrolling list showed but nothing in it lit or clicked | 17 Nov | Menus in a window of their own (menuclick test) |
| Menu pop too quiet to notice, then too slow | 18 Nov | 2.5× quicker spring |
| A clicked-open menu popped and faded | 19 Nov | There at once, full size |
| A 20 pt shadow blur cut off square over light pages | 19 Nov | Short, crisp shadows |
| Tooltips in the wrong place, wrong words, lingering | — | tiptest checks side, centring, words, dismissal |
| A long label pushed its row instead of truncating | — | Ends in "…" in tight spaces |

### Agents, engine, Mac
| Bug | When | Fix |
|---|---|---|
| The agent's cursor made the whole Mac feel laggy | 19 Nov | Cursor parked between steps |
| Each kept chat answered every mouse event (half the main thread while scrolling) | 19 Nov trace | One hover tracker; kept chats hear nothing |
| The whole app froze on Stop while dictating (permission prompt on the main thread) | — | Prompt off the main thread |
| A half-written save could corrupt the data file | — | Atomic writes |
| A second engine started when one was already running | — | Reuses the running one |
| Links opening new windows (target=_blank) went nowhere | — | Open in the same pane |
| A terminal flood queued up in the web view | — | Fed at the screen's pace |
| A failed message load left a chat blank for good | — | Opens empty, never blank |

## Open / not confirmed

- Slash-command menu in a DM: couldn't reproduce from code; needs a screenshot if it still fails.
- The mavis v2 pause with its browser open: fixed in code, not measured live (the test can't open a browser pane).
- Scroll smoothness in the live window: ~/Library/Logs/Agent Lab/scroll.log records real frames (median 8.3 ms at 120 Hz, some late frames).
- An old engine from Nov 17 (Desktop/Agent Lab/engine) still runs and shares the app's data.

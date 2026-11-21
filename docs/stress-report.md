# Stress test: 21 Nov 2026

Everything the app's test tools could exercise, real-window screenshots in the MAVIS theme, timings on the real mavis v2
chat, and an independent read of the code changed this week. Nothing here is fixed yet unless it says so.

Severity: **A** wrong answer / wrong chat / data, **B** visible glitch or flicker, **C** slow (frames dropped),
**D** minor or polish, **T** test gap (not an app bug, but it hid bugs).

## Passed

- Side panel open/close/quick clicks: no blank frames, never stuck half open (paneltest).
- Window resize with the panel open: 0 blank frames of 138 (resizetest).
- Wheel and trackpad scrolling (scrolltest), menus clicking and closing (menuclick), back/forward (navtest).
- Engine: agents, workspaces, channels, members (enginetest). Message look identical cold, warm and across launches.
- Scrolling a long chat: 0 frames over 16.7 ms.

## Wrong behaviour (A)

| # | Bug | Where it shows | Found by |
|---|---|---|---|
| 1 | An approval to edit a file read as a website: "Edit Refund?" for refund.js | Approval cards | chattest (**fixed, in the next build**) |
| 2 | fn+1 / fn+2 can answer an approval card you can't see (hidden or other chats keep their key listener) | Any chat with an ask pending | code |
| 3 | An agent working in its DM and a channel at once shows both asks in both places | Chats, channels | code |
| 4 | A channel turn's status line can show the agent's DM activity | Channels | code |
| 5 | A Codex agent's approval can land in the wrong chat when it runs in a DM and a channel together | Codex agents | code |
| 6 | "Open chat" from a workspace (or the palette) opens your previous Messages chat instead | Workspaces, palette | code |
| 7 | The same agent's chat exists twice (Messages and workspace): a dropped file or "Add page to chat" lands in both boxes, drafts overwrite each other | Messages + workspace | code |
| 8 | Those two copies fight over one browser page: the browser you're looking at can go blank | Side panel browser | code |
| 9 | Keyboard shortcuts (⌘. stop, ⌘T, ⌘⇧M…) still act on a chat you've left | Everywhere | code (likely) |
| 10 | With only a file attached, the box shows the mic instead of Send | Chatbox | code |
| 11 | The @ file list doesn't fill in once files are listed (only the newest box gets it) | Chatbox @ | code |
| 12 | Building a hidden box steals the keyboard from the one you're typing in | Chats, side chats, omnibox | code |
| 13 | A DM read inside a workspace keeps its red count | Messages list | code |
| 14 | A workspace's red count includes its agents' DM asks and other workspaces' asks | Rail | code |
| 15 | @-tagging a workspace member not given the channel does nothing (the default answers) | Channels | code |
| 16 | An agent removed from a workspace keeps answering in its channels; the picker offers all agents, not members | Channels | code |
| 17 | Old channels with a single `agent` are answered by it while the header says "Assistant"; any rename or recolour silently drops it | Channels | code |
| 18 | A channel run changes the agent's DM status ("done", "stopped with an error") | Messages list | code |
| 19 | After changing who answers, "/" still lists the previous agent's commands | Channels | code |
| 20 | Clicking Send or the mic drops the keyboard from the box | Chatbox | code |
| 21 | A tab can keep the previous site's icon | Browser tabs | code |
| 22 | /model, /btw and /handoff throw away attached files | Chatbox | code |
| 23 | Two agents with the same name break the @ list | Chatbox @ | code |
| 24 | Everything typed in the omnibox, questions to the agent included, is sent to Google for suggestions | Omnibox | code (privacy) |

## Glitches and flicker (B)

| # | Bug | Where | Found by |
|---|---|---|---|
| 25 | When the box grows (attachments, long text) the chat doesn't stay at its end: the last message is left half under the box | Chats | screenshot |
| 26 | Older messages joining as you scroll up jump the view by up to ~400 pt, with one shifted frame | Long chats | code |
| 27 | The side-panel width is per chat: other chats jump to an old width when you switch | Side panel | code |
| 28 | With 10+ tabs the strip overflows: + and the last tabs are cut off (the 15-tab limit is higher than fits) | Browser tabs | code |
| 29 | Hiding a browser tab takes its page out of the window: blank frames when you come back, agent screenshots of background tabs can fail | Browser | code |
| 30 | Hidden tabs keep their cursor zones (an I-beam over the front tab) | Side panel | code (likely) |
| 31 | The new-channel dialog runs off the window with many agents (no scroll) | New channel | code |
| 32 | Selecting text across a chip draws a rounded, widened selection | Chips | code |
| 33 | Slash and @ menus are still the old look (grey, 40 pt rows, `</>` icons), not the system's | Chatbox | screenshot |
| 34 | A restored tab builds its whole web page while being drawn (state changes mid-draw) | Browser tabs | code |

## Slow (C), measured on the real chat

| # | Issue | Number | Budget |
|---|---|---|---|
| 35 | Opening a chat | first 164 ms, then ~100 ms each | 16.7 ms a frame: a visible hitch |
| 36 | Switching chat to chat, worst case | 112 ms | " |
| 37 | Window resize on Messages | median 15 ms, worst 25 ms | some frames dropped |
| 38 | Home redraws on any unrelated change | 13 ms each (while an agent streams) | jank on Home |
| 39 | Switching theme | ~40 ms | one hitch |
| 40 | Every saved chat is read and decoded at launch, on the main thread, during the first draw | launch stall | code |
| 41 | A file check per sent message, full-size images decoded, on every redraw | per row | code |
| 42 | A new date formatter for every time label, twice per message | per row | code |
| 43 | @ file search scores up to 20,000 paths on every keystroke, on the main thread | typing @ | code |
| 44 | Shimmers keep animating at display rate even in chats you've left | always | code |
| 45 | The scroll meter (a debug tool) runs for everyone and writes a log on every scroll | always | code |

## Minor (D)

| # | Bug |
|---|---|
| 46 | The chat's scroll follower leaks three observers and holds its scroll view when a chat is dropped |

## Test gaps (T): fixed or to fix

| # | Gap | Status |
|---|---|---|
| T1 | boxtest, tiptest, handstest, menuclick, navtest, chattest, consistencytest and scrolltest ran in the old classic theme, so they never checked MAVIS | **fixed** (set to MAVIS) |
| T2 | tiptest looked for labels the redesign renamed, and waited less than the 0.9 s tooltip delay | **fixed** |
| T3 | chattest still expected the long URL wording | **fixed** |
| T4 | handstest can't reach the terminal outside the app bundle (its 5 terminal failures are this, not the app) | to fix |
| T5 | No test covers: channels, approvals in channels, the chip pills, attachments, the omnibox, the 15-tab strip, page switches with a browser open | to add |

## Still open from the bug log

- The mavis v2 pause with its browser open: fixed in code, not measured live.
- An old engine from Nov 17 still runs from Desktop/Agent Lab/engine and shares the app's data.

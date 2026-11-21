# MAVIS window system

The reference for building the new MAVIS look in Agent Lab Native. Every value in sections 1–10 was measured from the working prototype at `~/Desktop/Agent Hub/mavis-window/mavis-window.html` (open it with `?1x` to see it at true size). Where this file and `whop-system.md` disagree, this file wins for the new look; the Whop doc stays as the history of the earlier direction.

**How to use it**
- Building one of the shipped screens (Home, Messages, workspace chat, side panes): use sections 1–10. The prototype is the spec; if Swift and the prototype differ, Swift is wrong.
- Designing a new screen later: start from the MAVIS tokens (section 2), then fall back to the Chrome foundations (section 12) for anything MAVIS doesn't define yet. Look at the boards in section 13 for a layout that already solved something close.
- Moving the native app over: follow section 14 in order.

## 1. The rules in one screen

- **Two tones.** The page tone `#1a1a1a` and the card tone `#2a2a2a`. Anything that sits *inside* a card (an agent tile, a send button at rest, a pill) takes the page tone.
- **Colour means something.** Neutral greys carry the structure. Colour appears only as a category tag, a live status dot or the one accent blue `#789aff`.
- **Flat.** No shadows. The only strokes are the 0.5px hairline around the big surfaces and the chatbox outline.
- **One inset.** Cards are 12px in from every edge.
- **Instant states.** Hover and press change at once, with no fade.
- **One typeface.** Anthropic Sans everywhere. Monospace only in the terminal and file preview.
- **Icons are Hugeicons** (stroke rounded, 1.5 stroke).

## 2. Tokens

| Token | Value | Use |
|---|---|---|
| `frame` | `#141414` | Window background behind the surfaces |
| `page` | `#1a1a1a` | Main surfaces (Home, chat, pane headers); things inside cards |
| `omni` / `raise` | `#222222` | Address bar, profile bar |
| `box` | `#2a2a2a` | Cards and chatboxes |
| `toolbar` | `#2b2b2b` | Browser toolbar and pane bodies |
| `sel` | `#2f2f2f` | Selected row |
| `box2` | `#333333` | Card hover; neutral chips; browser tab |
| `line` | `#3a3a3a` | Dividers inside panes |
| `t1` | `#e6e6e6` | Primary text |
| `t2` | `#bdbdbd` | Secondary text, idle icons |
| `t3` | `#9e9e9e` | Meta text. Raised from `#8f8f8f` so it passes 4.5:1 on `box` (5.4:1) and on the `box2` hover (4.7:1) |
| `blue` | `#789aff` | The accent: unread dots, context ring, selected workspace ring, focus rings, your message bubble (at 22%) |
| `hover` | white 7% | Small control hover (agent chip) |
| `st-hover` / `st-press` | white 10% / 16% | Icon button and rail hover / press |
| Status on / idle | `#34a853` / `#80868b` | Live status dots only |
| Done chip | `green-bg` with `#8fdcb4` text | Finished state |
| Category tags | Design `#c58af9`, Launch `#fdd663`, Backend `#81c995` | Solid fill, `#1f1f1f` text |

**Open:** the browser's Take over button still uses Google's `#1a73e8`. Decide whether it moves to `blue`.

### Mapping onto the native theme (`Sources/Themes.swift`)

The native app already draws every colour from one live `ThemePalette`, so the MAVIS colours become one new preset, `mavis.dark`. These are the slots by what their comments say they do:

| Native slot | Its job in Swift | MAVIS value |
|---|---|---|
| `v0` | frame | `#141414` |
| `v1` | panel (chat, menus) | `#1a1a1a` |
| `v2` | raised (chat box, cards) | `#2a2a2a` |
| `v3` | hover on buttons | `#333333` |
| `v4` | lines | `#3a3a3a` |
| `v5` | control outlines | `#2e2e2e` (the surface hairline) |
| `v6` | strong lines | `#474747` |
| `i9` | quiet text | `#9e9e9e` |
| `i10` | faint text, icons | `#bdbdbd` |
| `i12` | strong text | `#e6e6e6` |
| `ink` | what hairlines and soft fills are made of | `#ffffff` |
| `blue` | links and highlights | `#789aff` |
| `primaryHover` | primary button hover | decide: the white button has no hover in the prototype |

Two native tokens are close but not equal: `C.edge` is ink 3.5% where the chatbox outline is 4%, and `C.rowHover` is ink 6% where MAVIS uses `box2` (a solid `#333`) on cards. Change them in the preset step, not per screen.

## 3. Type

Anthropic Sans, weights 400 and 500 (600 is embedded but unused).

| Role | Size / line height | Weight | Colour |
|---|---|---|---|
| Home greeting, two lines | 30/38, tracking −0.3px | 500 | line 1 `t1`, line 2 `t2` |
| Messages list title | 24/32 | 500 | `t1` |
| Today title | 18/24 | 500 | `t1` |
| Chat header name, list row name | 15 (rows 15/22) | 500 | `t1` |
| Chat messages | 14.5/23 | 400 | `t1` |
| Card title, ask | 14/20 | 500 | `t1` |
| List row preview | 14/21 | 400 | `t2` |
| Body inside cards, section labels | 12.5/18 (labels 12.5/20) | 400 | `t3` |
| Chips and pills | 12.5 (header chip 12) | 500 | varies |
| Meta (dates, stamps) | 12 | 400 | `t3` |
| Category tag | 11.5, 20 tall | 500 | `#1f1f1f` |
| Terminal and preview | 12/18 mono | 400 | `t2` |

## 4. Layout

| Part | Value |
|---|---|
| Window | 1280 × 800, radius 16 |
| Rail | 72 wide; buttons and workspace tiles 48 × 48, radius 16 |
| Gutter | 8px between surfaces and from the window edge (no gutter on the rail side) |
| Surfaces | radius 14, `0.5px #2e2e2e` hairline, on every main surface (Home, Today, chat, panes). The Messages list and workspace sidebar sit straight on the frame with no surface |
| Messages list | 304 wide, padding 4 12 0; rows 66 tall, radius 12, padding 10 12 |
| Agent tile | 44 × 44, radius 12, icon 22–24; the same size in lists, cards and Messages |
| Status dot | 12px with a 3px ring in the colour of whatever it sits on, so the ring changes with hover |
| Profile | avatar 36px inside a 48 × 48 hover button (radius 16) that lines up with the rail column. It never moves or resizes: on Home only the avatar shows, elsewhere the bar opens to 355 wide with name, status, bell and settings |

## 5. Headers and icon buttons

- Every header is **44 tall**: chat, browser tab strip, browser toolbar, Terminal and Files.
- Icon buttons in headers: **28 × 28**, fully round, **18px icon**, last one **8px** from the right edge. The chat header icons and the browser's collapse button share one centre line.
- Header padding: chat `0 8 0 16`, pane headers `0 8 0 14`.
- Close controls: **Browser** uses the Hugeicons sidebar-right icon (collapse); **Terminal and Files** use a plain ✕.

## 6. Cards (Home)

| Card | Spec |
|---|---|
| All cards | `box` fill, radius 16, padding 12 |
| Hover | fill steps to `box2` `#333`, instantly. Press and selection keep it |
| Jump back in | 3 across, 10 apart; tag + meta on top, title 14/20, two lines of 12.5/18 |
| Brief | padding 12, 12.5/18 text, sparkle icon |
| Waiting for you | cards 12 apart. Icon left; agent name in `t3` on the first line with the tag top-right; the ask in `t1` under it. Only the first card has actions: Later (ghost) and Review (white pill), bottom-right, 28 tall |
| Your agents | one card, padding 4 12; rows 60 tall, radius 12, hover per row; Assign pill 28 tall on `page` |
| Section labels | 20 tall, 8 above the content, 24 between sections |
| Count badge | `box` fill, `t1` text |

## 7. Chatboxes

| Part | Home | Messages and workspace |
|---|---|---|
| Box | radius 24, padding 16 10 8 20 | 52 tall, radius 26, padding 0 6 |
| Text | 15.5, one 24 line, 12 above the controls | 15 |
| Agent chip | 36 tall, radius 18, 10 from the edge, tile inset 7 | none |
| Send | 36 round; play icon (nudged 1px right). At rest `page`, white `#fff` with `#141414` icon once there's text | 40 round; mic at rest, up-arrow send in white `#fff` once there's text |
| Spacing | n/a | the last button always keeps 2px on its left, so nothing shifts when send appears |

**Outline (all chatboxes):** inset 1px white 4% at rest, 1px 8% on hover, **2px 12%** while typing. Instant.

**Under the box (Messages and workspace):** pills 28 tall, radius 14, `#1f1f1f` fill, 12.5 text. Mode pill (Auto / Builder) is the label plus a down arrow, padding 0 8 0 12, gap 4. Context pill shows a ring whose used part is `blue`.

## 8. Side panes

- A **392 wide** column on the right. Browser, Terminal and Files **stack vertically and can all be open at once**, 8 apart. Opening one never closes another. Browser takes 1.6 shares of the height, the others 1 each.
- **Browser:** tab 30 tall, radius 25, `box2`; address bar 34 tall, radius 17, `omni`.
- **Terminal:** body `#161616`, padding 10 14 12, mono 12/18. Prompt user in green, path in purple. No focus box on the input.
- **Files:** one surface (header and body the same `page`). Rows 32 tall, fully round, 2 apart, 20px indent per level. Hover `hover`; selected white 10% with `t1` text. Modified / added badges: 18 tall, round, yellow / green fill with dark text. Preview: a `box` card, radius 12, at most 40% of the pane; the tree keeps at least 45%.
- Panes open and close instantly.

## 9. Messages

- Your bubble: `blue` at 22%, radius 20, padding 10 16, max 76% wide.
- Agent replies: plain text, no bubble, optional step line above in `t3` 13px with a right arrow.
- Thinking: three dots, 6px, pulsing (static when reduced motion is on).
- Time stamps centred, 12px `t3`.
- Header chip: Done is green; other states (Free) use `box2` with `t2` text; 24 tall, radius 12.

## 10. Focus and keyboard

- Every card and row on Home, and the profile avatar, can be reached with Tab and opened with Enter or Space.
- Focus ring: 2px `blue`, 2px out from the element (the avatar uses a 2px ring on its 48px button).

## 11. What ships as it is today

**Menus keep their current items, layout and behaviour** (Auto / Builder, the agent switcher, the workspace menu, new chat, attach, the @ picker, voice). What changes is only their values, through the one shared menu part, so they match the new surfaces:

| Menu part | Value |
|---|---|
| Surface | `page` fill, radius 14, 0.5px hairline, Material level-2 shadow (`0 4 8 3` black 15% + `0 1 3` black 30%); menus are the one thing allowed a shadow |
| Padding | 8 above the first item and below the last |
| Item | 36 tall, padding 0 16, 13.5 text in `t1`, 18 icon in `t2`, shortcut on the right in 12 `t3` |
| Hover / chosen | `st-hover` (white 10%), no tick for the chosen item, `t1` text |
| Section heading | 12 `t3`, padding 10 16 4 |
| Divider | `line`, 6 above and below |
| Width | 240 by default; content can widen it |

Still not designed (keep the current native behaviour, or decide before building):
- Empty and error states: an agent stopped with an error, a failed reply, no workspaces, an empty Waiting for you.
- Smaller window sizes: what collapses first below 1280 (Today panel, then side panes down to one).
- Light theme (`mavis.light`).
- Explore, Settings, Notifications, Add workspace, and the Changes pane.
- Long chat titles: the header truncates them when all three panes are open.

## 11b. Rules for cases nobody designed

When a screen or state isn't in the prototype, don't invent a look: build it from these rules and the parts in `Sources/MavisSystem.swift` (`MV`). If none of them fits, stop and add the new part to this spec first, then build it.

| Situation | Answer |
|---|---|
| A new main area (a page, a second chat, a workspace view) | A surface: `page` fill, radius 14, 0.5px hairline, 8 from its neighbours. Title row is a 44 header (15/500 name, icons at the right, 28 buttons, 8 from the edge). |
| Something you open beside a chat (any tool, preview, log) | A side pane in the right column: 392 wide, stacks with the others, never closes them. 44 header with an 18px icon, a title, a quiet meta line and a close ✕ (only the browser collapses). |
| A list of agents, chats or people | Rows: 44 agent tile (radius 12) + status dot, name 15/22 `t1`, line under it 14/21 `t2`, time 13 `t3`. Rows 66 tall in lists, radius 12, selected `sel`, hover `st-hover`. |
| A list of things (files, settings, results) | 32 rows, fully round, 13px text, 18 icon, 2 apart; hover `hover`, selected white 10%. |
| A group of facts or a summary | A card: `box`, radius 16, padding 12, title 14/20, body 12.5/18 `t3`, tags top-right. Hover steps to `box2` if it opens something. |
| A section inside a panel | Label 12.5/20 `t3`, 8 above its content, 24 between sections, count badge on `box`. |
| A place to type | A chatbox: outline 1px 4% → 8% hover → 2px 12% typing. Send turns white with text. Search fields use the same outline on a 36 pill. |
| A button | The main action is a white pill (`#fff` on `#141414`), one per surface. Others are ghost text (`t2`) or a `page` pill on a card. All 28 tall, radius 14, 12.5/500. Icon-only buttons are 28 round with an 18 icon. |
| A status | A dot (`#34a853` on, `#80868b` idle) with a 3px ring in the colour under it; or a 24 chip (green Done, `box2` neutral). Errors use `red` text. |
| Nothing to show yet | An empty state inside the surface: centred 44 agent tile or 24 icon in `t3`, a 15/500 line, one 13 `t3` line, at most one white pill. |
| Waiting (loading) | Keep the layout; draw the real rows with their text replaced by `box` bars at the text's height. No spinners on whole screens. For an agent reply, the three-dot "thinking" line. |
| Something went wrong | Inline where it happened, `red` text plus one action ("Try again"). No full-screen errors. |
| Opening, closing, moving | Hover and press are instant. Things that move use Material 3 curves: emphasized decelerate in 250–350ms, emphasized accelerate out in about 200ms. Reduced motion becomes a cut. |
| Not enough room | Drop in this order: the Today panel, then side panes down to one (the most recent), then the list collapses to its icons. Text truncates with an ellipsis, never wraps in a header. |
| A menu | Keeps today's native menu (section 11), coloured by the theme. |

## 12. Chrome foundations

The MAVIS look grew out of the Chrome system used on every board of the **Agent Lab × Chrome** canvas (claude.ai/artifact/Syq6oFgj98xLn6wKyUSqpT). Two boards hold it: *The Chrome system used on every board* (`Chrome-System`) and *Official Chrome values* (`Chrome-Official`, copied from Chromium source and Material 3). Use this section for anything MAVIS hasn't defined yet. Where a MAVIS value exists (sections 2–10), MAVIS wins.

### Principles (Chrome-System)
- Layers by tone, not lines: frame darkest, content one step lighter, controls one step lighter again.
- Flat in dark: separation comes from tone steps; shadows only on things that float (menus, bubbles).
- Pills for input, rounded rectangles for things: anything you type into or toggle is fully round; surfaces, tabs and tiles use 8–16 corners.
- Tonal, not saturated: blue is pale and desaturated; fills are tonal.
- One place to type per job: the address bar is for pages, the composer is for the agent.

### Chrome colour roles, dark (Chromium `sys_color_mixer`)

| Chrome role | Used for | Chrome | MAVIS |
|---|---|---|---|
| `sys.header` | Window frame | `#1f2020` | `frame #141414` (darker on purpose) |
| `sys.surface` | Pages, dialogs, menus | `#1f1f1f` | `page #1a1a1a` |
| `sys.base-container`, `omnibox-container` | Side panel, address bar | `#282828` | `omni #222222` |
| `sys.surface-container-high` | Cards, inputs | `#2a2a2a` | `box #2a2a2a` (match) |
| `sys.surface-container-highest` | Highest raised fill | `#343535` | `box2 #333333` |
| `sys.base` / `header-container` | Toolbar, active tab | `#3c3c3c` | not used |
| `sys.on-surface` | Primary text | `#e3e3e3` | `t1 #e6e6e6` |
| `sys.on-surface-subtle` | Secondary text, icons | `#c7c7c7` | `t2 #bdbdbd` |
| `sys.on-surface-variant` | Tertiary text | `#c4c7c5` | `t3 #9e9e9e` |
| `sys.divider` | Separators | `#5e5e5e` | `line #3a3a3a` |
| `sys.neutral-outline` | Outlined controls | `#757575` | not used |
| `sys.primary` / on | Links, focus, filled buttons | `#a8c7fa` / `#062e6f` | `blue #789aff` (own accent) |
| `sys.tonal-container` / on | Tonal buttons | `#004a77` / `#c2e7ff` | not used (white send instead) |
| `sys.error` / container | Errors | `#f2b8b5` / `#8c1d18` | `red #f2b8b5` |
| `ref.tertiary` (positive) | Success | `#6dd58c` | status `#34a853`, Done text `#8fdcb4` |

Light theme (Chrome): header `#d3e3fd`, surface and toolbar `#ffffff`, omnibox `≈#e9eef6`, primary `#0b57d0`, on-surface `#1f1f1f`, subtle `#474747`. A future `mavis.light` should start here.

### Interaction states (Chromium)

| State | Dark | Light |
|---|---|---|
| Hover on subtle surfaces | white 10% | `#1f1f1f` 6% |
| Hover on prominent fills | `#1f1f1f` 6% | white 10% |
| Pressed | white 16% | `#1f1f1f` 8% |
| Focus ring | 2px, 2px gap, keyboard only | same |
| Disabled content / container | on-surface 38% / 12% | same |

MAVIS uses these as `st-hover` (10%) and `st-press` (16%) on icon buttons and the rail, and replaces the card hover with a solid tone step (`box2`).

### Layout constants (Chromium `layout_constants.cc`)

| Item | Chrome |
|---|---|
| Tab | 34 tall, padding 8 × 6, close 16 |
| Toolbar button | 34 tall, icon 20, gap 4 |
| Address bar | 34 tall, full pill, icons 16 / 20 |
| Side panel inset | 8 (MAVIS gutter is the same 8) |
| Toolbar / content corner | 8 |
| Vertical tab | 30 tall, radius 8 |

### Shape (Material 3)
None 0 · extra small 4 · small 8 · medium 12 · large 16 · extra large 28 · full. MAVIS lands on these: tiles 12, cards and rail buttons 16, home chatbox 24, pills full. Its surfaces use 14 (from the Chrome-System board). Inner radius = outer radius minus the gap.

### Spacing (Chrome-System)
2px steps inside controls, a 4px grid everywhere else: 2, 4, 6, 8, 10, 12, 16, 20, 24, 28. Panes float 8 apart.

### Type (Material 3, set in Anthropic Sans for MAVIS)
Headline small 24/32 · title large 22/28 · title medium 16/24 500 · title small 14/20 500 · body large 16/24 · body medium 14/20 · body small 12/16 · label large 14/20 500 · label medium 12/16 500 · label small 11/16 500. Weights 400 and 500 only.

### Motion (Material 3)
Short 50–200ms (hover, chip, icon swap) · medium 250–400ms (menus, side panel, tabs) · long 450–600ms (page transitions). Curves: standard `(0.2, 0, 0, 1)`, decelerate `(0, 0, 0, 1)`, accelerate `(0.3, 0, 1, 1)`, emphasized decelerate `(0.05, 0.7, 0.1, 1)` for panels opening, emphasized accelerate `(0.3, 0, 0.8, 0.15)` for closing. MAVIS rule on top: hover and press are instant; anything that moves (a pane opening) uses these curves; reduced motion swaps movement for a cut.

### Elevation (Chrome-System)
Dark panes: a 0.5px hairline, no drop shadow. Chips and pills: flat fill one tone above. Menus and bubbles: `0 4px 8px 3px rgba(0,0,0,.15), 0 1px 3px rgba(0,0,0,.3)` (Material level 2).

### Accessibility
Text 4.5:1, icons and outlines 3:1, click targets at least 24 × 24 (MAVIS uses 28–48).

## 13. Board index (Agent Lab × Chrome canvas)

**Final, build these:**
- *Workspace · #general (FINAL MAIN foundation)* (`Workspace-General`): the main workspace layout.
- *Workspace · project model* (`Workspace-Project`): chats in folders, agents with roles.
- *Home · your structure, Google look* (`Home-Main`): the Home screen.
- *test design system board copy* (`Test-Design-System-1iv2`): the Messages list and avatar spec (44 tile, radius 12, 12px status dot).
- The prototype (`mavis-window.html`) puts these together and is the source for sections 1–10.

**Foundations:** `Chrome-System`, `Chrome-Official` (section 12), and *MAVIS palettes: Chrome vibe, own identity* (`MAVIS-Palettes`).

**Explored, use for ideas only:**
- Layout studies 01–10 (`Main`, `V02`–`V10b`): floating panes, toolbar omnibox, labelled rail, side-panel switcher, list popover, @ and / suggestions, header pill, DevTools-docked terminal, light and dark themes.
- First concepts CC01–CC05: sessions as tabs, New Tab page, omnibox suggestions, chat in the side panel, vertical tabs.
- Audit A, B, C: refine, recompose (Chrome model) and rethink.
- Chat layouts 01–10: Gemini, AI Mode, Google Messages (chosen), activity timeline, cards, Docs gutter, working doc, assistant, Gmail thread, omnibox prompts.
- Home layouts 01–10: New Tab, Today dashboard, tab groups, Gemini (closest to Home-Main), search page, navigation drawer, history, day view, agent cards, side panel.
- *dechromed* (`Test-Design-System-own`): the same board without Chrome's look.

## 14. Moving the native app over

The goal is that the new look reads as if the app was always built this way. The risk isn't the new values, it's a half-moved app: some screens new, some old, and layouts breaking while they change. So the move is done the way large teams re-skin an app, in layers, behind a switch, and checked by pixels rather than by eye.

1. **Freeze behaviour.** This release changes how things look, not what they do. No logic, data or navigation changes ride along, so any bug that appears is a drawing bug.
2. **Colours first, as a theme.** Add `mavis.dark` to `Palettes.all` with the values in the mapping table (section 2). The app recolours everywhere at once, menus included, with no layout touched. Because themes switch live, this is also the on/off switch for the whole project: the new look stays a theme you can turn off until every screen is done.
3. **Measurements as shared constants.** Put the MAVIS sizes into the existing scales (`R`, `Box`, and a header or button scale), read only when `mavis.dark` is on: header 44, icon button 28 with 18 icon, surface radius 14, card radius 16, card inset 12, pills 28, agent tile 44, chatbox 52 / radius 26. Screens read the constants, never their own numbers, so one change can't drift one screen.
4. **Rebuild the shared pieces once:** pane header, icon button, card, pill, agent tile with status dot, chatbox, profile button. Every screen then uses the same parts, which is what makes it feel designed rather than patched.
5. **Screens, smallest blast radius first:** the chat and Messages list, then the side panes (browser, terminal and files share the pane header), then the workspace, then Home (new, so nothing old can break).
6. **Check each screen against the prototype by pixels.** `tools/snapshot` renders a native screen to PNG with no window, and `tools/diff` compares it with a reference: screenshot the prototype at `?1x` on the same screen and diff. A screen is done when the diff is clean, not when it looks close.
7. **Keep the existing gates green on every step:** `chatperf` (smoothness is non-negotiable), and `resizetest`, `paneltest`, `navtest`, `scrolltest`, `consistencytest`. Rebuild with `build.sh` and relaunch the installed app after each change.
8. **Ship it whole.** Use it yourself with `mavis.dark` on until every screen in step 5 passes, then make it the default in one release. Never ship a mixture of old and new screens.

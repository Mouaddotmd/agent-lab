# Whop system: Agent Lab's interface reference

Agent Lab's layout copies Whop's. The values below were measured from whop.com/home
in CSS px with the window 2560 wide. They're also in `src/renderer/discord.css`, in the comments
marked "WHOP'S SYSTEM" (around line 248).

## Measured from Whop

**Surface**
- One flat `#111` surface.
- Dividers are 1px at 10.6% white (`rgb(255 255 255/.106)`).
- Card outlines are 1px at 13.3% white.

**Top bar**
- 56 tall, laid out as a three-column grid: brand on the left, search in the middle, buttons on the right.
- Search: 300×36, radius 12, 7% white fill. Placeholder `#7b7b7b`, with a keyboard hint on the right.
- Round 40×40 buttons with a 7% white hover.

**Sidebar**
- 280 wide, 8 padding, with a 1px divider on its right edge.
- Workspace tiles: 60×60, radius 14, 7% white fill, 8 apart. Hover is 10%. The selected tile gets a 2px inset ring in `#eee`.
- Section label (for example "Personal"): 14/20, weight 500, 45% white, 24 tall, padding 2 12.
- Nav rows:
  - 40 tall, radius 14, padding 0 9, 4 apart.
  - The icon sits in a 30px box.
  - Text is 16/26, weight 500.
  - Idle rows are 69% white, hover is a 5% white fill, and the selected row is `#2a2a2a` with `#eee` text.

**Main area (Home)**
- Two columns: 740, then a 40 gap, then 416. Centred, starting 44 from the top.
- Under 1240 wide it becomes one column with the cards first.
- The big figure is 40/48, weight 500, tracking -0.02em, with tabular numbers. Its label is 16/24 weight 500, and the line under it is 14/20 at 45% white.

**Cards**
- Radius 24, with a 1px inset outline at 13.3% white and no fill. Padding 24 12 12.
- Card title: 20/28, weight 600, padded 0 12 12.
- Rows inside a card: at least 64 tall, radius 12, padding 12, gap 12. Name is 16/24 weight 500; the line under it is in the meta size at 45% white.

**Pages and Messages**
- Pages title themselves: no header bar, and content starts 44 from the top.
- Messages: a 320 list column next to the chat.
  - Conversation rows are 64 tall.
  - The chat header is 48 tall and stays pinned at the top.
  - An empty state has a 128px tile, a title and one line of text.

**Colour tokens (as Whop uses them)**
- `--i2 #1c1c1c` · `--i3 #242424` · `--i4 #2a2a2a`
- `--i10` 44.7% white · `--i11` 68.6% white · `--i12 #eee`
- `--hover` 5% white

## Rules Mouad set on top of it

1. **Keep Whop's measurements.** When asked for a small change, make only that change. Don't redesign.
2. Additions on top of Whop:
   - The page sits as one inset panel on a slightly darker frame, at radius 14 (the same as Whop's rows).
   - Whop's 60px tiles move into a rail on the left, 84 wide, with labels under each tile.
3. Nav order: Home, Create, Messages, Playbook, Plugins, Profile. The workspace label is called "Personal".
4. The top bar holds the search only. Profile is reached from the nav, not a top-bar button.
5. A workspace opens the way Messages does:
   - its own column with the workspace's picture and name, then Search, then Channels (#general) and Agents (+)
   - the item you pick opens on the right

## Changes since the copy (Whop's values were overridden here)

- **Colours:** Whop's flat `#111` made the app read as one dark slab, so the warm dark palette came back:
  - frame `#080807`
  - sidebar `#0e0e0d`
  - content `#151514`, a step lighter than the sidebar
- **Top bar:** the hairline under it was removed.
- **Home:** the early layout came back:
  - a greeting and a line saying how many things are waiting
  - agent faces with status rings, like stories
  - text tabs: All · Working · Waiting for you · Done
  - the agent list grouped by state
  - "Right now" as an outlined card on the right
- **Corners:** Whop's 14 radius on 40-tall rows made selected rows read as pills.
  - The first replacement was one nested scale: window 24, page 16, cards 12, controls 8, rows 6, tiny 4.
  - That was followed by a second pass, "rounder inside, calmer window", which is what's live now:
    - window 16, page 14, cards 14, menus 12, controls 10, rows 10, tiny 6, and menu items 8
  - Avatars, status dots and counts stay fully round.

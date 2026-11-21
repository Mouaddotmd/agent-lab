# Agent Lab Native: how to change anything you can see

The app is moving to the MAVIS look. Every visual change follows one system, so the app reads as if it was always designed this way.

## Read first
- `../docs/mavis-system.md`: the spec. Sections 1–10 are measured from the prototype, 11b covers cases nobody designed, 12 holds the Chrome foundations, 13 indexes the design boards and 14 is the migration order.
- `Sources/MavisSystem.swift` (`MV`): every colour, size, gap, corner, stroke, type size and curve, by name.
- The prototype is the spec for shipped screens: `~/Desktop/Agent Hub/mavis-window/mavis-window.html` (open with `?1x`). If Swift and the prototype differ, Swift is wrong.

## Rules
1. **No raw values in views.** Use `MV.*` (or the live theme tokens in `Theme.swift` and `Themes.swift`). Never write a colour, padding, size, corner, font size or stroke as a number in a view. `tools/systemlint.py` runs at the start of `build.sh` and fails the build if any file gains a raw value.
2. **A missing value goes into the spec first.** If `MV` doesn't have what you need, add it to `docs/mavis-system.md`, then to `MavisSystem.swift`, then use it. Never pick a number by eye.
3. **Undesigned screens and states follow spec section 11b.** A new pane, list, card, empty state, loading state, error or narrow window is built from those rules and the shared parts. Don't invent a new look.
4. **Change the look, not the behaviour.** A redesign step doesn't change logic, data or navigation in the same change.
5. **Menus keep their current design.** They only take their colours from the theme.
6. **Hover and press are instant.** Movement uses `MV.Motion`; respect reduced motion.
7. **Smoothness is non-negotiable.** Nothing may stutter when switching chats or resizing.

## Before you call a visual change done
1. `./build.sh` (runs the drift check, builds and installs).
2. When you moved a file onto the system: `python3 tools/systemlint.py --update` to lock in the lower count.
3. Compare with the prototype: `build/snapshot out.png <view>` and `build/diff ref.png out.png diff.png <x> <y>` against a `?1x` screenshot of the same screen.
4. `tools/shotall.sh <label>` and look through every screen in the gallery, not just the one you changed.
5. Keep the existing checks passing: `build/chatperf`, `build/resizetest`, `build/paneltest`, `build/navtest`, plus `build/consistencytest`, which needs its own compile (it isn't built by `build.sh`).
6. Relaunch the installed app so the user sees it: `pkill -x AgentLabNative; open ~/Applications/Agent\ Lab\ Native.app`. Never run it from the Desktop.

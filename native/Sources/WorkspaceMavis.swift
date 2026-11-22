// A workspace in the MAVIS look (prototype: the mavis workspace). The sidebar sits on the frame (304, padding 4 12 0):
// the workspace head, then each category as a coloured tag with its chats under a 2 pt line in its colour, then its
// agents. The channel's header is a crumb (folder / name) with the agents pill; an empty channel opens on a start
// screen. Same data and actions as the classic WorkspacePage. Every value is MV's.
import SwiftUI

struct MavisWorkspaceSidebar: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    let w: Workspace; let members: [Agent]; let open: Agent?; let channel: Workspace.Channel?
    @Binding var headMenu: Bool
    @Binding var inviting: Bool
    let newChannel: (String) -> Void
    let rename: (String, Workspace.Channel) -> Void
    let delete: (String) -> Void
    let newCategory: () -> Void
    let renameCategory: (Workspace.Category) -> Void
    let recolor: (String, String) -> Void
    let deleteCategory: (String) -> Void
    @State private var folded: Set<String> = []

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: 0) {
            head.padding(.bottom, MV.Space.gridGap)
            ForEach(Array((w.categories ?? []).enumerated()), id: \.element.id) { i, c in
                let color = MV.Workspace.color(c, at: i)
                category(c.name, color: color, folded: folded.contains(c.id), add: { newChannel(c.id) }, menu: {
                    Menu("Colour") {
                        ForEach(MV.Workspace.tagColors, id: \.hex) { t in
                            Button { recolor(c.id, t.hex) } label: {
                                Label { Text(t.name) } icon: { Image(nsImage: Self.swatch(t.hex)) }
                            }
                        }
                    }
                    Button("Rename \(c.name)…") { renameCategory(c) }
                    if (w.categories ?? []).count > 1 && c.channels.isEmpty { Button("Delete \(c.name)", role: .destructive) { deleteCategory(c.id) } }
                }) { toggle(c.id) } rows: {
                    ForEach(c.channels) { ch in
                        let on = open == nil && channel?.id == ch.id
                        MVSideRow(icon: "hash", name: ch.name, selected: on, unread: false,
                                  working: s.runs.values.contains { $0.conv == w.conv(ch.id) },
                                  menu: {
                                      var items: [ActionMenu.Item] = [.init(symbol: "pencil", title: "Rename #\(ch.name)") { rename(c.id, ch) }]
                                      if w.channels.count > 1 { items += [.divider, .init(symbol: "trash", title: "Delete #\(ch.name)", danger: true) { delete(ch.id) }] }
                                      return items
                                  }) {
                            s.openAgent = nil; s.openChannel = ch.id; Task { await s.loadMessages(w.conv(ch.id)) }
                        }
                    }
                }
            }
            // The agents here: one more group in the same look (invite with +, right-click to remove).
            category("Agents", color: MV.Workspace.agentsColor, folded: folded.contains("agents"), plain: true,
                     add: { if Date().timeIntervalSince(PickMenu.closedAt) > 0.3 { inviting.toggle() } }) { toggle("agents") } rows: {
                ForEach(members) { a in
                    MVSideRow(icon: (a.operator ?? "claude-code").hasPrefix("claude") ? "mvBot" : "mvPrompt", name: a.name,
                              selected: open?.id == a.id, unread: s.state(of: a) == "needs", working: s.state(of: a) == "working",
                              menu: {
                                  [.init(symbol: "bubble.left", title: "Open chat") { s.openChat(a.id) },
                                   .init(symbol: "pencil", title: "Edit agent") { s.editingAgent = a.id },
                                   .divider,
                                   .init(symbol: "person.badge.minus", title: "Remove from \(w.name)", danger: true) {
                                       if s.openAgent == a.id { s.openAgent = nil }; Task { await s.setMember(a.id, w.id, false) }
                                   }]
                              }) {
                        s.openChat(a.id)          // its one chat, in Messages (a second copy here split drafts and the browser)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if inviting {
                    PickMenu(scope: s.agents.filter { !(w.members ?? []).contains($0.id) }, chosen: "", open: $inviting,
                             extra: ("plus", "New agent", { s.newAgentOpen = true })) { id in Task { await s.setMember(id, w.id, true) } }
                        .offset(y: MV.Workspace.catHeader)
                }
            }
            .zIndex(1)
        }
        Group {
            if SnapshotMode.on { VStack(spacing: 0) { rows; Spacer(minLength: 0) } }
            else { ScrollView { rows.padding(.bottom, MV.Size.profileBar.height + MV.Space.section) }.scrollIndicators(.never) }
        }
        .padding(.top, MV.Space.xs).padding(.horizontal, MV.Space.inset)
        .frame(width: MVListGap.width(panes), alignment: .leading)
        .clipped()
        .mvListPanel()
    }

    /// A 12 pt colour dot for the Colour menu (menus draw images, not SwiftUI shapes).
    static func swatch(_ hex: String) -> NSImage {
        let d = MV.Workspace.swatch
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            NSColor(Color(cssHex: hex) ?? MV.Workspace.agentsColor).setFill(); NSBezierPath(ovalIn: r).fill(); return true
        }
        return img
    }
    private func toggle(_ id: String) { if folded.contains(id) { folded.remove(id) } else { folded.insert(id) } }

    /// The workspace head (prototype .ws-h): 52 tall; its 26 picture, the name with an arrow (the menu: no fill on
    /// hover, the arrow lights with the words), its folder under it; then search and a new chat, 32 round.
    var head: some View {
        HStack(spacing: MV.Space.xs) {
            // The picture spans both lines (name and folder), its corners the rail tiles'.
            WsPic(name: w.name, color: w.color, image: w.image, size: MV.Workspace.headTile, radius: MV.Radius.tile)
                .padding(.trailing, MV.Space.xs)
            VStack(alignment: .leading, spacing: MV.Space.rowGap) {
                Hover { h in
                    Button { headMenu.toggle() } label: {
                        HStack(spacing: MV.Space.xs) {
                            // A long name fades out at its end (as a tab's title), never "…": only when it doesn't fit.
                            MVFadeText(text: w.name, font: F.font(MV.Text.panelTitle, .medium), color: MV.Ink.t1)
                                .layoutPriority(1)
                            Icon("mvChevDown", MV.Size.icon).fixedSize().foregroundStyle(h || headMenu ? MV.Ink.t1 : MV.Ink.t3)
                        }
                        .padding(.horizontal, MV.Space.sm).padding(.vertical, MV.Space.rowGap).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                // Hugs the name, but gives way when the list is narrow (a fixed name pushed the whole column over the rail).
                .fixedSize(horizontal: false, vertical: true)
                .unlessSnapshot { $0.floatingMenu($headMenu, placement: .below(trailing: false, gap: MV.Space.sm)) { WorkspaceActions(w: w, open: $headMenu) } }
                HStack(spacing: MV.Workspace.pathGap) {
                    Icon("mvFolder", MV.Workspace.pathIcon).foregroundStyle(MV.Ink.t3)
                    Text(((w.path ?? s.home) as NSString).abbreviatingWithTildeInPath).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.leading, MV.Space.sm)
            }
            Spacer(minLength: 0)
            MVHeadButton(icon: "mvSearch", label: "Search this workspace (⌘K)") { s.closeMenus(); s.searchOpen.toggle() }
            MVHeadButton(icon: "mvFolderAdd", label: "New category", action: newCategory)
        }
        .padding(.leading, MV.Space.gridGap).padding(.trailing, MV.Space.rowGap)
        .frame(height: MV.List.header)
        .zIndex(2)
    }

    /// A category (prototype .cat + .cat-body): a 30 header (2 above, padding 0 8 0 2) with its tag (22 tall, radius 6,
    /// padding 0 8, 12.5 medium on its colour), then + and the fold arrow (24 round, t3). Its rows sit 10 in, 8 past a
    /// 2 pt line in its colour at 70%, 4 below the header, 2 apart.
    @ViewBuilder func category<Rows: View, M: View>(_ name: String, color: Color, folded: Bool, plain: Bool = false, add: @escaping () -> Void,
                                          @ViewBuilder menu: () -> M = { EmptyView() },
                                          toggle: @escaping () -> Void, @ViewBuilder rows: () -> Rows) -> some View {
        let m = menu()
        VStack(alignment: .leading, spacing: 0) {
            MVCategoryHead(name: name, color: color, folded: folded, add: add, toggle: toggle, plain: plain)
                .unlessSnapshot { $0.contextMenu { m } }
            if !folded {
                VStack(spacing: MV.Space.rowGap) { rows() }
                    .padding(.leading, MV.Space.labelGap)
                    .overlay(alignment: .leading) { Rectangle().fill(color.opacity(MV.Workspace.lineOpacity)).frame(width: MV.Space.rowGap) }
                    .padding(.leading, MV.Space.gridGap)
                    .padding(.top, MV.Space.xs)
            }
        }
    }
}

/// A sidebar chat (prototype .sb-row): 36 tall, radius 12, padding 0 10, 12 apart; an 18 icon and 14/20 words; selected
/// the 16% blue wash with white words and a pale-blue icon; unread: an 8 blue dot at the end.
struct MVSideRow: View {
    let icon: String; let name: String; let selected: Bool; let unread: Bool
    /// An agent is working here: the name shimmers.
    var working = false
    /// Its ⋯ menu (on hover, and on right-click).
    var menu: (() -> [ActionMenu.Item])? = nil
    let action: () -> Void
    @State private var hover = false
    @State private var open = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
        Button(action: action) {
            HStack(spacing: MV.Space.inset) {
                // Prototype: words t2 (t1 when unread, white when selected), icon t3 (pale blue when selected).
                TabIcon(name: icon, size: MV.Size.icon).foregroundStyle(selected ? MV.Workspace.selectedIcon : MV.Ink.t3)
                if working {
                    Shimmer(text: name, font: F.font(MV.Text.title, .regular), base: selected ? MV.Ink.t2 : MV.Ink.t3, band: Color.white)
                } else {
                    // A long name fades out at its end (as the workspace's title), never "…"; while ⋯ shows it stops
                    // before it, so the button never sits on the words.
                    MVFadeText(text: name, font: F.font(MV.Text.title, .regular), color: selected ? Color.white : unread ? MV.Ink.t1 : MV.Ink.t2)
                        .padding(.trailing, menu != nil && (hover || open) ? MV.Size.iconButton : 0)
                }
                Spacer(minLength: 0)
                if unread { Circle().fill(MV.Accent.blue).frame(width: MV.Space.labelGap, height: MV.Space.labelGap) }
            }
            .padding(.horizontal, MV.Space.gridGap).frame(height: MV.Workspace.row)
            .background(shape.fill(selected ? MV.Accent.selected : .clear))
            .overlay(shape.fill(hover || open ? MV.Wash.stHover : .clear).allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(MVStates(shape: shape, hoverable: false))
        // On hover, ⋯ at the end, 4 in from the row's edges (36 row, 28 button), concentric with its corner.
        .overlay(alignment: .trailing) {
            if let menu {
                ZStack {
                    if hover || open { MVMoreButton(open: open, corner: MV.Radius.tile, inset: MV.Space.xs, selected: selected) { open.toggle() } }
                }
                .frame(width: MV.Size.iconButton, height: MV.Size.iconButton)
                .unlessSnapshot { $0.floatingMenu($open, pop: true) { ActionMenu(open: $open, width: MV.Menu.width, items: menu()) } }
                .padding(.trailing, MV.Space.xs)
            }
        }
        .containerShape(shape)
        .onHover { hover = $0 }
        .unlessSnapshot { $0.onRightClick { if menu != nil { open = true } } }
    }
}

/// A category's header (prototype .cat): on hover its tag brightens (CSS brightness 1.3, saturate 1.3) and its + shows;
/// + and the arrow are bare icons (no fill), t3, white under the pointer, 70% while pressed. Clicking the row folds it.
struct MVCategoryHead: View {
    let name: String; let color: Color; let folded: Bool; let add: () -> Void; let toggle: () -> Void
    /// The agents' group: a plain label, not a coloured tag (it isn't a category of chats).
    var plain = false
    @State private var hover = false
    var body: some View {
        HStack(spacing: MV.Space.labelGap) {
            if plain {
                MVFadeText(text: name, font: F.font(MV.Text.control, .medium), color: hover ? MV.Ink.t2 : MV.Ink.t3)
                    .padding(.leading, MV.Space.labelGap).frame(height: MV.Workspace.tag)
            } else {
                MVFadeText(text: name, font: F.font(MV.Text.control, .medium), color: MV.Accent.onTag)
                    .padding(.horizontal, MV.Space.labelGap).frame(height: MV.Workspace.tag)
                    .background(RoundedRectangle(cornerRadius: MV.Space.sm, style: .continuous).fill(hover ? MV.Workspace.lit(color) : color))
            }
            Spacer(minLength: 0)
            MVBareIcon(icon: "mvPlus", label: "New chat in \(name)", action: add)
                .opacity(hover ? 1 : 0).allowsHitTesting(hover)
            MVBareIcon(icon: "mvChevDown", label: folded ? "Show" : "Hide", turned: folded, action: toggle)
        }
        .padding(.leading, MV.Space.rowGap).padding(.trailing, MV.Space.labelGap)
        .frame(height: MV.Workspace.catHeader)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
        .padding(.top, MV.Space.rowGap)
    }
}

/// A bare 24 pt icon button (no fill on hover): t3, white under the pointer, 70% while pressed.
struct MVBareIcon: View {
    let icon: String; let label: String; var turned = false; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Icon(icon, MV.Size.iconSmall).foregroundStyle(hover ? Color.white : MV.Ink.t3).rotationEffect(.degrees(turned ? -90 : 0))
                .frame(width: MV.Workspace.smallButton, height: MV.Workspace.smallButton).contentShape(Circle())
        }
        .buttonStyle(MVPressFade())
        .onHover { hover = $0 }
        .tip(label).accessibilityLabel(label)
    }
}
struct MVPressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? MV.Workspace.pressed : 1)
    }
}

/// A 24 pt round button with a 16 pt icon in t3 (a category's + and fold arrow); the arrow turns over when folded.
struct MVSmallRound: View {
    let icon: String; let label: String; var turned = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(icon, MV.Size.iconSmall).foregroundStyle(MV.Ink.t3).rotationEffect(.degrees(turned ? -90 : 0))
                .frame(width: MV.Workspace.smallButton, height: MV.Workspace.smallButton).contentShape(Circle())
        }
        .buttonStyle(MVStates(shape: Circle()))
        .tip(label).accessibilityLabel(label)
    }
}

/// A 32 pt round header button with an 18 pt icon in t2 (the workspace head's search and new chat).
struct MVHeadButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(icon, MV.Size.icon).foregroundStyle(MV.Ink.t2)
                .frame(width: MV.Workspace.headButton, height: MV.Workspace.headButton).contentShape(Circle())
        }
        .buttonStyle(MVStates(shape: Circle()))
        .tip(label).accessibilityLabel(label)
    }
}

/// A channel's header (prototype .ch in a workspace): the crumb (folder icon and category in its colour, then the
/// channel's name 15 medium), then the agents pill (their faces, 22 radius 7 ringed in box, and how many).
struct MavisChannelHead: View {
    let category: String; let color: Color; let name: String; let members: [Agent]
    let panel: SidePanel
    /// The agents given this channel; the pill shows and changes them (none: the assistant).
    let given: [Agent]
    /// The channel's state (Store.channelState), shown as a chat's is beside its name.
    var state = "idle"
    let set: ([String]) -> Void
    @State private var picking = false
    var body: some View {
        HStack(spacing: MV.Space.gridGap) {
            HStack(spacing: MV.Space.sm) {
                Icon("mvFolder", MV.Size.iconSmall).foregroundStyle(color)
                Text(category + " /").font(F.font(MV.Text.name, .regular)).foregroundStyle(color)
                Text(name).font(F.font(MV.Text.name, .medium)).foregroundStyle(MV.Ink.t1)
            }
            .lineLimit(1).truncationMode(.tail)
            MVChip(text: MavisToday.stateWord(state), done: state == "done")
            .layoutPriority(-1)                 // the crumb gives way first: the agent pill and tools always show
            Spacer(minLength: 0)
            MVAccessPill(given: given, open: $picking, set: set)
            PanelTools(panel: panel, changes: true)
        }
        .padding(.leading, MV.Space.headerLead).padding(.trailing, MV.Space.headerEdge).frame(height: MV.Size.header)
    }
}

/// An empty channel (prototype .start): at the foot of the chat, its name 28/36, a 15/23 line (600 wide), then its
/// context chips (30 tall, outlined 8% white, 13 in t2).
struct MavisChannelStart: View {
    let title: String; let lede: String; let chips: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(title).font(F.font(MV.Workspace.startTitle, .medium)).tracking(MV.Workspace.startTracking).foregroundStyle(MV.Ink.t1)
            Text(lede).font(F.font(MV.Text.chatInput, .regular)).foregroundStyle(MV.Ink.t2).lineSpacing(MV.Workspace.ledeSpacing)
                .frame(maxWidth: MV.Workspace.ledeWidth, alignment: .leading).padding(.top, MV.Space.sm)
            HStack(spacing: MV.Space.labelGap) {
                ForEach(chips, id: \.1) { icon, text in
                    HStack(spacing: MV.Space.sm) {
                        Icon(icon, MV.Size.iconSmall).foregroundStyle(MV.Ink.t2)
                        Text(text).font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Ink.t2)
                    }
                    .padding(.leading, MV.Workspace.chipLead).padding(.trailing, MV.Space.inset).frame(height: MV.Workspace.crew)
                    .overlay(Capsule().strokeBorder(MV.Stroke.boxHover, lineWidth: MV.Stroke.boxRestWidth))
                }
            }
            .padding(.top, MV.Workspace.chipsTop)
        }
        .padding(.horizontal, MV.Chat.sides).padding(.bottom, MV.Workspace.startBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}


/// Who answers in a channel, as the box's Mode pill (28 tall, capsule, the quiet outline): the assistant's spark, or the
/// agents' faces, and their name. Its menu has two parts: Assistant (a plain session on your operator: the default),
/// then your agents, each bringing its own setup into the session; ticking one leaves the assistant, unticking them all
/// comes back to it.
struct MVAccessPill: View {
    @EnvironmentObject var s: Store
    let given: [Agent]
    @Binding var open: Bool
    let set: ([String]) -> Void
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: MV.Space.sm) {
                if given.isEmpty {
                    Icon("mvSparkle", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2)
                    Text("Assistant").font(F.font(MV.Text.control, .medium)).foregroundStyle(MV.Ink.t1)
                } else {
                    HStack(spacing: -MV.Space.sm) { ForEach(given.prefix(3)) { a in MVCrewFace(agent: a) } }
                    Text(given.count == 1 ? given[0].name : "\(given.count) agents").font(F.font(MV.Text.control, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1)
                }
                Icon("mvChevDown", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2)
            }
            .padding(.leading, given.isEmpty ? MV.Space.gridGap : MV.Space.xs).padding(.trailing, MV.Space.labelGap)
            .frame(height: MV.Size.pill)
            .background(Capsule().fill(open ? MV.Tone.box2 : MV.Tone.pill))
            .overlay(Capsule().strokeBorder(MV.Chat.pillEdge, lineWidth: MV.Chat.pillEdgeWidth))
            .contentShape(Capsule())
        }
        .buttonStyle(MVStates(shape: Capsule()))
        .tip("Who answers here", edge: .bottom)
        .unlessSnapshot { $0.floatingMenu($open, placement: .below(trailing: true, gap: MV.Space.sm)) { MVAccessMenu(given: given.map(\.id), set: set) } }
    }
}

/// The two-part menu: Assistant, then your agents (ticks). Rows 36, radius 12, the selection tone when chosen.
struct MVAccessMenu: View {
    @EnvironmentObject var s: Store
    let given: [String]
    let set: ([String]) -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Menu.radius, style: .continuous)
        VStack(alignment: .leading, spacing: MV.Space.rowGap) {
            row(icon: AnyView(Icon("mvSparkle", MV.Size.icon).foregroundStyle(MV.Ink.t2).frame(width: MV.Workspace.crewFace, height: MV.Workspace.crewFace)),
                name: "Assistant", detail: "A plain session", on: given.isEmpty, radio: true) { set([]) }
            Rectangle().fill(MV.Menu.divider).frame(height: MV.Stroke.list).padding(.vertical, MV.Space.xs)
            Text("Agents").font(F.font(MV.Menu.headerText, .medium)).foregroundStyle(MV.Ink.t3)
                .padding(.horizontal, MV.Space.labelGap).frame(height: MV.Home.labelLine)
            if s.agents.isEmpty {
                Text("No agents yet").font(F.font(MV.Menu.itemText, .regular)).foregroundStyle(MV.Ink.t3).padding(.horizontal, MV.Space.labelGap)
            }
            ForEach(s.agents) { a in
                let on = given.contains(a.id)
                row(icon: AnyView(MVCrewFace(agent: a)), name: a.name, detail: nil, on: on, radio: false) {
                    set(on ? given.filter { $0 != a.id } : given + [a.id])
                }
            }
        }
        .padding(MV.Menu.padding)
        .frame(width: MV.Menu.width + MV.Space.section + MV.Space.headerLead)
        .background(shape.fill(MV.Menu.fill))
        .overlay(shape.strokeBorder(MV.Tone.hairline, lineWidth: MV.Stroke.boxRestWidth))
    }
    private func row(icon: AnyView, name: String, detail: String?, on: Bool, radio: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
        return Button(action: action) {
            HStack(spacing: MV.Space.inset) {
                icon
                Text(name).font(F.font(MV.Menu.itemText, .regular)).foregroundStyle(on ? Color.white : MV.Ink.t1).lineLimit(1)
                if let detail { Text(detail).font(F.font(MV.Text.meta, .regular)).foregroundStyle(on ? MV.Accent.selectedText : MV.Ink.t3).lineLimit(1) }
                Spacer(minLength: 0)
                MVTick(on: on, radio: radio)
            }
            .padding(.horizontal, MV.Space.labelGap).frame(height: MV.Menu.item)
            .background(shape.fill(on ? MV.Accent.selected : .clear))
            .contentShape(shape)
        }
        .buttonStyle(MVStates(shape: shape))
    }
}

/// An 18 pt choice mark: a ring when not chosen; chosen, a blue disc with a white tick (or a white dot for one-of).
struct MVTick: View {
    let on: Bool; var radio = false
    var body: some View {
        ZStack {
            if on {
                Circle().fill(MV.Accent.blue)
                if radio { Circle().fill(Color.white).frame(width: MV.Space.sm, height: MV.Space.sm) }
                else { Icon("check", MV.Size.iconSmall - MV.Space.xs).fontWeight(.bold).foregroundStyle(Color.white) }
            } else {
                Circle().strokeBorder(MV.Ink.t3, lineWidth: MV.Chat.markLine)
            }
        }
        .frame(width: MV.Chat.mark, height: MV.Chat.mark)
    }
}

/// A 22 pt agent face (the crew's): radius 7, the agent's icon.
struct MVCrewFace: View {
    let agent: Agent
    var body: some View {
        let claude = (agent.operator ?? "claude-code").hasPrefix("claude")
        RoundedRectangle(cornerRadius: MV.Workspace.crewRadius, style: .continuous)
            .fill(claude ? MV.Accent.clayTile : MV.Tone.box2)
            .frame(width: MV.Workspace.crewFace, height: MV.Workspace.crewFace)
            .overlay(Icon(claude ? "mvBot" : "mvPrompt", MV.Size.iconSmall - MV.Space.rowGap).foregroundStyle(claude ? MV.Accent.clay : MV.Ink.t2))
            .background(RoundedRectangle(cornerRadius: MV.Workspace.crewRadius + MV.Space.rowGap, style: .continuous).fill(MV.Tone.box).padding(-MV.Space.rowGap))
    }
}


/// One line of words that fits its room: as wide as the words when there's room, and only when there isn't, cut at the
/// room's edge with the last 30% fading out (never "…"). Follows a resize as it happens.
struct MVFadeText: View {
    let text: String; let font: Font; let color: Color
    @State private var full: CGFloat = 0
    @State private var room: CGFloat = 0
    var body: some View {
        let words = Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
        let fades = full > room + MV.Stroke.list
        words
            .frame(minWidth: 0, maxWidth: full > 0 ? full : nil, alignment: .leading)
            .clipped()
            .mask {
                if fades {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: MV.Browser.fadeFrom), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                } else { Rectangle() }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .background { words.hidden().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { full = $0 } }
            .accessibilityLabel(text)
    }
}


/// A new channel (Discord's, in MAVIS's look): its name with the # before it, the category it goes in, and who answers:
/// the assistant (a plain session, the default) or agents you pick. Esc or a click outside cancels; ↵ creates.
struct MVChannelDialog: View {
    @EnvironmentObject var s: Store
    let title: String; let category: String; let confirm: String
    @Binding var name: String
    @Binding var agents: [String]
    var asksAgents = true
    let cancel: () -> Void; let create: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        let card = RoundedRectangle(cornerRadius: MV.Radius.homeBox, style: .continuous)
        let field = RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
        ZStack {
            Color.black.opacity(MV.Launcher.dim).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: cancel)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(F.font(MV.Text.panelTitle, .medium)).foregroundStyle(MV.Ink.t1)
                Text("in \(category)").font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Ink.t3).padding(.top, MV.Space.xs)
                Text("Name").font(F.font(MV.Text.control, .medium)).foregroundStyle(MV.Ink.t2).padding(.top, MV.Space.section).padding(.bottom, MV.Space.labelGap)
                HStack(spacing: MV.Space.labelGap) {
                    TabIcon(name: "hash", size: MV.Size.icon).foregroundStyle(MV.Ink.t3)
                    TextField("new-channel", text: $name).textFieldStyle(.plain).font(F.font(MV.Text.chatInput, .regular)).foregroundStyle(MV.Ink.t1)
                        .focused($focused).onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { create() } }
                }
                .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.chatBox - MV.Space.labelGap)
                .background(field.fill(MV.Tone.page))
                .overlay(field.strokeBorder(focused ? MV.Chat.talking : MV.Stroke.boxRest, lineWidth: focused ? MV.Stroke.boxTypingWidth : MV.Stroke.boxRestWidth))
                if asksAgents {
                    Text("Who answers").font(F.font(MV.Text.control, .medium)).foregroundStyle(MV.Ink.t2).padding(.top, MV.Space.section).padding(.bottom, MV.Space.labelGap)
                    ScrollView { VStack(spacing: MV.Space.rowGap) {
                        choice(icon: AnyView(Icon("mvSparkle", MV.Size.icon).foregroundStyle(MV.Ink.t2).frame(width: MV.Workspace.crewFace, height: MV.Workspace.crewFace)),
                               name: "Assistant", detail: "A plain session", on: agents.isEmpty, radio: true) { agents = [] }
                        ForEach(s.agents) { a in
                            let on = agents.contains(a.id)
                            choice(icon: AnyView(MVCrewFace(agent: a)), name: a.name, detail: nil, on: on, radio: false) {
                                agents = on ? agents.filter { $0 != a.id } : agents + [a.id]
                            }
                        }
                    }
                    .padding(MV.Space.xs) }
                    .scrollIndicators(.never)
                    .frame(maxHeight: MV.Launcher.width / 2)            // many agents scroll; the dialog stays on screen
                    .background(field.fill(MV.Tone.page))
                }
                HStack(spacing: MV.Space.labelGap) {
                    Spacer(minLength: 0)
                    Button(action: cancel) {
                        Text("Cancel").font(F.font(MV.Text.footer, .medium)).foregroundStyle(MV.Ink.t1)
                            .padding(.horizontal, MV.Space.headerLead).frame(height: MV.Size.chatButton - MV.Space.xs)
                            .background(Capsule().fill(MV.Tone.box2)).contentShape(Capsule())
                    }
                    .buttonStyle(MVStates(shape: Capsule())).keyboardShortcut(.cancelAction)
                    let ready = !name.trimmingCharacters(in: .whitespaces).isEmpty
                    Button(action: create) {
                        Text(confirm).font(F.font(MV.Text.footer, .medium)).foregroundStyle(MV.Ink.onWhite)
                            .padding(.horizontal, MV.Space.headerLead).frame(height: MV.Size.chatButton - MV.Space.xs)
                            .background(Capsule().fill(Color.white)).contentShape(Capsule())
                    }
                    .buttonStyle(MVStates(shape: Capsule())).disabled(!ready).opacity(ready ? 1 : MV.Browser.disabled)
                }
                .padding(.top, MV.Space.section)
            }
            .padding(MV.Space.section)
            .frame(width: MV.Launcher.width - MV.Space.section * 4)
            .background(card.fill(MV.Tone.box))
            .overlay(card.strokeBorder(MV.Stroke.boxRest, lineWidth: MV.Stroke.boxRestWidth))
        }
        .onAppear { focused = true }
    }
    private func choice(icon: AnyView, name: String, detail: String?, on: Bool, radio: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.tile - MV.Space.xs, style: .continuous)
        return Button(action: action) {
            HStack(spacing: MV.Space.inset) {
                icon
                Text(name).font(F.font(MV.Menu.itemText, .regular)).foregroundStyle(on ? Color.white : MV.Ink.t1).lineLimit(1)
                if let detail { Text(detail).font(F.font(MV.Text.meta, .regular)).foregroundStyle(on ? MV.Accent.selectedText : MV.Ink.t3) }
                Spacer(minLength: 0)
                MVTick(on: on, radio: radio)
            }
            .padding(.horizontal, MV.Space.labelGap).frame(height: MV.Menu.item)
            .background(shape.fill(on ? MV.Accent.selected : .clear))
            .contentShape(shape)
        }
        .buttonStyle(MVStates(shape: shape))
    }
}

// The pages, matching the web app's empty state (?empty).
import SwiftUI

struct Page: View {
    @EnvironmentObject var s: Store
    /// Messages, once opened, stays built behind the other pages, so coming back to it is instant (its chats, their
    /// scroll and their rows all kept: ChatHost.swift). Hidden, it takes no clicks and nothing reads it aloud.
    @State private var messagesBuilt = false
    var body: some View {
        ZStack {
            if messagesBuilt || s.view == .messages {
                let on = s.view == .messages
                MessagesPage().environment(\.chatActive, on).opacity(on ? 1 : 0).allowsHitTesting(on).accessibilityHidden(!on)
                    .onAppear { messagesBuilt = true }
            }
            if s.view != .messages {
                if MV.on && s.view != .agents { other.mvSurface() } else { other }   // MAVIS Home draws its own surfaces
            }
        }
    }
    @ViewBuilder var other: some View {
        switch s.view {
        case .agents: if MV.on { MavisHome() } else { HomePage() }
        case .discover: DiscoverPage()
        case .messages: EmptyView()
        case .usage: UsagePage()
        case .connections: PluginsPage()
        case .profile: ProfilePage()
        case .reviews, .memory, .team: Color.clear     // parked: intentionally blank
        default: Color.clear                            // built in the next pass
        }
    }
}

/// The web app's pages scroll in a view that keeps room for a scrollbar (scrollbar-gutter: stable),
/// so centred columns sit 11px left of the panel's true centre. Kept so the pixels match.
let gutter: CGFloat = 11

/// Set by the snapshot tool (offscreen rendering for the pixel diff).
enum SnapshotMode { nonisolated(unsafe) static var on = false }

/// Home with no agents yet (web: .empty-hero inside .col).
struct HomeEmpty: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(spacing: 12) {
            Line("No agents yet", 24, .semibold, C.i12, tracking: -0.36)
            Para(text: "An agent is Claude Code or Codex with a name, a folder and a job of your choosing. It answers exactly as that tool does, and asks you before it changes anything.", size: 14, weight: .regular, color: C.i10, align: .center)
                .frame(maxWidth: 507.4)
            HStack(spacing: 8) {
                PrimaryButton(title: "New agent") { s.newAgentOpen = true }
                SecondaryButton(title: "Bring in from Mavis") {}
            }
            .padding(.top, 8)
        }
        .padding(.top, 48 + 32)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.trailing, gutter)
    }
}

/// White fill, #0a0a0a text, 32 tall, 16 sides, 10 corners (web: .btn.primary).
struct PrimaryButton: View {
    let title: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Line(title, 14, .medium, C.v1).padding(.horizontal, 16).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.primaryHover : C.i12)).contentShape(Rectangle())
            }.buttonStyle(Press(scale: 0.97))
        }
    }
}
/// #0a0a0a fill, 1px #2e2e2e outline (web: .btn.second).
struct SecondaryButton: View {
    let title: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Line(title, 14, .medium, C.i12).padding(.horizontal, 16).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : C.v1))
                    .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Rectangle())
            }.buttonStyle(Press(scale: 0.97))
        }
    }
}

// MARK: Menus (web: .set-menu, .hist-menu)

/// #0a0a0a, 14 corners, 4 inside, 1px #2e2e2e inside, plus the menu's own drop.
struct MenuSurface<Content: View>: View {
    var width: CGFloat; var softDrop = false; @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(4).frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
            .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edgeControl, lineWidth: 1))
            .modifier(MenuDrop(soft: softDrop))
    }
}
/// History: 0 4 8 −4 / 0 1 2 (crisp). Settings: 0 8 24 (soft). Both black at 50%.
struct MenuDrop: ViewModifier {
    let soft: Bool
    func body(content: Content) -> some View {
        if MV.on { content }                         // MAVIS: no shadow on anything that pops up
        else if soft { content.shadow(color: .black.opacity(0.5), radius: 12, y: 8) }
        else { content.shadow(color: .black.opacity(0.5), radius: 4, y: 2).shadow(color: .black.opacity(0.5), radius: 1, y: 1) }
    }
}
/// 40 tall, 10 corners, 18 icon at 12, label 14/20 medium 12 after it, meta 12/16 medium on the right.
struct MenuRow: View {
    let icon: String; let title: String; var meta: String? = nil
    var on = false; var dimWhenOff = false; var metaColor: Color = C.i9
    let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 12) {
                    Icon(icon, 18).foregroundStyle(C.i10)
                    Line(title, 14, .medium, !dimWhenOff || on || h ? C.i12 : C.i10)
                    Spacer(minLength: 0)
                    if let meta { Line(meta, 12, .medium, metaColor) }
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: R.ctl).fill(on ? C.sel : h ? C.v3 : .clear)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// History: "Recently viewed", newest first; the current screen says "Now".
struct HistoryMenu: View {
    @EnvironmentObject var s: Store
    var body: some View {
        MenuSurface(width: 288) {
            Line("Recently viewed", 12, .medium, C.i10).padding(.horizontal, 12).frame(height: 28)
            VStack(spacing: 4) {
                ForEach(s.recent, id: \.1.id) { j, e in
                    MenuRow(icon: e.kind.info.icon, title: e.kind.info.title, meta: j == s.index ? "Now" : ago(e.at), on: j == s.index, dimWhenOff: true, metaColor: C.i10) { s.jump(j) }
                }
            }
        }
    }
}

/// From the gear: Plugins, Profile, Usage, then the theme. (The web version also has a Wallpaper row:
/// it changes the picture behind its drawn window. A real Mac window sits on your own desktop, so it's left out.)
struct SettingsMenu: View {
    @EnvironmentObject var s: Store
    var body: some View {
        MenuSurface(width: 264, softDrop: true) {
            VStack(spacing: 4) {
                MenuRow(icon: "plug", title: "Plugins", meta: "0 connected") { s.go(.connections) }
                MenuRow(icon: "person", title: "Profile") { s.go(.profile) }
                MenuRow(icon: "chart", title: "Usage", meta: "0 runs this week") { s.go(.usage) }
            }
            .onHover { if $0 { ThemePicker.shared.close() } }      // another row: the theme submenu folds away
            Rectangle().fill(C.divider).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
            ThemeRows()
        }
    }
}

// MARK: Search
// The search (⌘K, the top bar's search button) is the command palette: PaletteView.swift.

// MARK: Page column (web: .pg / .col.page): 800 wide, centred (minus the scrollbar gutter), title 40 from the top.

struct PageColumn<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        let column = VStack(alignment: .leading, spacing: 0) { content }
            .frame(width: 800, alignment: .leading)
            .padding(.top, 40).padding(.bottom, 64)
            .frame(maxWidth: .infinity)
            .padding(.trailing, gutter)
        if SnapshotMode.on {
            // The offscreen renderer can't draw scroll views; same column, unscrolled, clipped.
            GeometryReader { g in column.frame(width: g.size.width).fixedSize(horizontal: false, vertical: true).frame(height: g.size.height, alignment: .top).clipped() }
        } else {
            ScrollView(.vertical) { column }.scrollIndicators(.never)
        }
    }
}
struct PageHead: View {
    let title: String; let lede: String
    @ViewBuilder var body: some View {
        if MV.on {
            // MAVIS: the page's title as Messages' (24/32 medium), its line 14/21 in t2, 4 under it.
            VStack(alignment: .leading, spacing: MV.Space.xs) {
                Text(title).font(F.font(MV.Text.listTitle, .medium)).foregroundStyle(MV.Ink.t1)
                Text(lede).font(F.font(MV.Text.preview, .regular)).foregroundStyle(MV.Ink.t2).lineSpacing(MV.Text.previewLine - MV.Text.preview)
                    .frame(maxWidth: MV.Workspace.ledeWidth, alignment: .leading)
            }
        } else { classic }
    }
    var classic: some View {
        VStack(alignment: .leading, spacing: 8) {
            Line(title, 28, .semibold, C.i12, tracking: -0.56)
            Para(text: lede, size: 14, weight: .regular, color: C.i10).frame(width: 507.4, alignment: .leading)
        }
    }
}
struct SectionTitle: View {
    let text: String
    @ViewBuilder var body: some View {
        // MAVIS: a section label (spec 11b): 12.5/20 in t3.
        if MV.on { Text(text).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3).frame(height: MV.Home.labelLine) }
        else { Line(text, 16, .semibold) }
    }
}

// MARK: Discover (web: discoverView)

struct Template { let icon: String; let name: String; let job: String; let access: String; let ownBranch: Bool }
let TEMPLATES: [(String, [Template])] = [
    ("Build", [
        .init(icon: "branch", name: "Bug fixer", job: "Finds the cause of a bug you describe, fixes it with the smallest change, and adds a test that failed before the fix.", access: "Ask first", ownBranch: true),
        .init(icon: "pen", name: "Test writer", job: "Writes tests for the code you point at, runs them, and stops when they pass. Never changes the code under test.", access: "Auto", ownBranch: true),
        .init(icon: "agents", name: "Refactorer", job: "Cleans up one module at a time without changing behaviour, running the tests after every step.", access: "Ask first", ownBranch: true),
    ]),
    ("Review", [
        .init(icon: "check", name: "Reviewer", job: "Reads your uncommitted changes or a branch and points out bugs, risky changes and missing tests. Never edits.", access: "Read only", ownBranch: false),
        .init(icon: "search", name: "Explainer", job: "Answers questions about a codebase you don’t know yet: where things live, how a request flows, what to read first.", access: "Read only", ownBranch: false),
    ]),
    ("Maintain", [
        .init(icon: "plug", name: "Dependency keeper", job: "Checks for outdated or vulnerable packages, updates one at a time, and runs the tests after each.", access: "Ask first", ownBranch: true),
        .init(icon: "book", name: "Docs writer", job: "Keeps the README and docs in step with the code, and writes what changed in plain language.", access: "Auto", ownBranch: true),
        .init(icon: "inbox", name: "Release notes", job: "Summarises what changed since the last tag for people who don’t read diffs.", access: "Read only", ownBranch: false),
    ]),
]

struct DiscoverPage: View {
    @EnvironmentObject var s: Store
    var body: some View {
        PageColumn {
            PageHead(title: "Discover", lede: "Ready-made agents with one clear job each. Add one, choose its folder, and it’s on your team.")
            ForEach(TEMPLATES, id: \.0) { group, list in
                VStack(alignment: .leading, spacing: MV.on ? MV.Space.labelGap : 12) {
                    SectionTitle(text: group)
                    Grid(horizontalSpacing: MV.on ? MV.Space.gridGap : 12, verticalSpacing: MV.on ? MV.Space.gridGap : 12) {
                        GridRow(alignment: .top) {
                            ForEach(0..<3, id: \.self) { i in
                                if i < list.count { TemplateCard(t: list[i]) } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                            }
                        }
                    }
                }
                .padding(.top, MV.on ? MV.Space.section : 32)
            }
        }
    }
}

/// #111, 1px #1f1f1f, 14 corners, 16 inside; icon tile 36 / 10; name 16 semibold; job 14; meta 12 #878787; button 28.
struct TemplateCard: View {
    @EnvironmentObject var s: Store
    let t: Template
    @ViewBuilder var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS (spec 11b, a card): box, radius 16, padding 12, no outline, box2 on hover; a 36 page-tone tile with the
    /// icon, the name 14/20, its job 12.5/18 in t3, the access line 12, then a page-tone pill.
    var mavis: some View {
        Hover { h in
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous).fill(MV.Tone.page)
                    .frame(width: MV.Pages.cardIcon, height: MV.Pages.cardIcon)
                    .overlay(Icon(t.icon, MV.Size.icon).foregroundStyle(MV.Ink.t2))
                Text(t.name).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).padding(.top, MV.Space.inset)
                Text(t.job).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3).lineSpacing(MV.Text.bodyLine - MV.Text.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, MV.Space.xs)
                Text(t.ownBranch ? "\(t.access) · Own branch" : t.access).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3)
                    .padding(.top, MV.Space.labelGap)
                MVPill(title: "Add to your agents", primary: false, filled: true) { s.newAgentOpen = true }.padding(.top, MV.Space.inset)
            }
            .padding(MV.Space.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(h ? MV.Tone.box2 : MV.Tone.box))
        }
    }
    var classic: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: R.ctl).fill(C.v4).frame(width: 36, height: 36).overlay(Icon(t.icon, 20).foregroundStyle(C.i12))
            Line(t.name, 16, .semibold).padding(.top, 12)
            // The description grows (flex: 1) so every card's access line and button sit on one line.
            Para(text: t.job, size: 14, weight: .regular, color: C.i10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 8)
            HStack(spacing: 8) {
                Line(t.access, 12, .regular, C.i9)
                if t.ownBranch { HStack(spacing: 8) { Line("·", 12, .regular, C.i9); Line("Own branch", 12, .regular, C.i9) } }
            }.padding(.top, 8)
            SmallSecondaryButton(title: "Add to your agents") { s.newAgentOpen = true }.padding(.top, 12)
        }
        .padding(17)
        .frame(width: 258.7, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1))
    }
}

/// .btn.second.sm: 28 tall, 12 sides.
struct SmallSecondaryButton: View {
    let title: String; let action: () -> Void
    @ViewBuilder var body: some View {
        if MV.on { MVPill(title: title, primary: false, filled: true, action: action) } else { classic }
    }
    var classic: some View {
        Hover { h in
            Button(action: action) {
                Line(title, 14, .medium, C.i12).padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : C.v1))
                    .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Rectangle())
            }.buttonStyle(Press(scale: 0.97))
        }
    }
}

// MARK: Shared pieces

/// .tile: #0a0a0a, 1px #1f1f1f inside, 14 corners, 12/16 padding, 64 tall with a 40px tile.
struct Tile<Trailing: View>: View {
    let ab: String; var op: String? = nil; let title: String; let meta: String; @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: R.ctl).fill(C.v4).frame(width: 40, height: 40)
                .overlay { if op != nil { OpLogo(op: op, size: 24) } else { Line(ab, 12, .regular, C.i10) } }
            VStack(alignment: .leading, spacing: 4) { Line(title, 14, .regular); Line(meta, 12, .regular, C.i10) }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16).frame(height: 64)
        .background(RoundedRectangle(cornerRadius: MV.on ? MV.Radius.card : R.card, style: .continuous).fill(MV.on ? MV.Tone.box : C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(MV.on ? .clear : C.edge, lineWidth: 1))
    }
}
struct Lede: View {
    let text: String
    var body: some View { Para(text: text, size: 14, weight: .regular, color: C.i10).frame(width: 507.4, alignment: .leading) }
}
/// 28/36 title with −0.015em (Plugins, Profile use h2: −0.42).
struct PageTitle: View {
    let text: String; var tracking: CGFloat = -0.42
    var body: some View { Line(text, 28, .semibold, C.i12, tracking: tracking) }
}
/// Bordered card used for stats and the week chart: #111, 1px #1f1f1f, 14 corners.
extension View {
    @ViewBuilder func card(_ fill: Color = C.v2, line: Color = C.v4) -> some View {
        if MV.on { background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(MV.Tone.box)) }   // MAVIS: flat, no outline
        else { background(RoundedRectangle(cornerRadius: R.card).fill(fill)).overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(line, lineWidth: 1)) }
    }
}

// MARK: Messages (empty: no agents, no tools found)

struct MessagesPage: View {
    /// The Messages filter (All ▾): hidden until it filters something.
    static let showsFilter = false
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    @State private var query = ""
    /// The row whose ⋯ menu is open.
    @State private var menuFor: String? = ProcessInfo.processInfo.environment["AL_TEST_MENU"].flatMap { $0.hasPrefix("conv:") ? String($0.dropFirst(5)) : nil }
    func menuBinding(_ id: String) -> Binding<Bool> { Binding(get: { menuFor == id }, set: { menuFor = $0 ? id : (menuFor == id ? nil : menuFor) }) }
    var body: some View {
        HStack(spacing: 0) {
            if MV.on { mavisList; MVListGap() } else { classicList }
            // The chat draws its own surface (and its panel's, beside it: ChatWithPanel); the empty side needs one.
            if MV.on && (s.openWorkspace == nil ? s.openAgent : (s.messagesAgent ?? s.openAgent)) == nil { conversation.mvSurface() } else { conversation }
        }
    }
    /// MAVIS (prototype Messages list): on the frame, 304 wide, padding 4 12 0. The title row is 52 (padding 0 4 0 12,
    /// 24/32 medium), 4 above the rows; rows 66, 4 apart. No search and no pen (⌘K and ⌘N do those); room at the foot
    /// for the profile bar.
    var mavisList: some View {
        let list = s.agents.sorted { ($0.pinned == true) != ($1.pinned == true) ? $0.pinned == true : lastAt($0) > lastAt($1) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Messages").font(F.font(MV.Text.listTitle, .medium)).foregroundStyle(MV.Ink.t1)
                Spacer(minLength: 0)
                // A new agent: the head's round button (the workspace head's), ⌘N.
                MVHeadButton(icon: "mvPlus", label: "New agent (\u{2318}N)") { s.newAgentOpen = true }
            }
            .padding(.leading, MV.Space.inset).padding(.trailing, MV.Space.rowGap).frame(height: MV.List.header, alignment: .leading)
            .padding(.bottom, MV.Space.xs)
            let rows = VStack(spacing: MV.Space.xs) {
                ForEach(list) { a in ConvRow(agent: a, menuOpen: menuBinding(a.id)).zIndex(menuFor == a.id ? 1 : 0) }
            }
            if SnapshotMode.on { rows; Spacer(minLength: 0) }      // offscreen renders can't draw a scroll view
            else {
                ScrollView { rows.padding(.bottom, MV.Size.profileBar.height + MV.Space.section) }
                    .scrollIndicators(.never).scrollClipDisabled()
            }
        }
        .padding(.top, MV.Space.xs).padding(.horizontal, MV.Space.inset)
        .frame(width: MVListGap.width(panes))
        .mvListPanel()
        .zIndex(1)
    }
    var classicList: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Line("Messages", 24, .semibold, C.i12, tracking: -0.36).padding(.leading, 4).layoutPriority(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        // The filter steps aside before the title would be cut. Hidden for the launch (it does
                        // nothing yet): flip `showsFilter` to bring it back.
                        if Self.showsFilter { FirstFit { Hover { h in
                            Button {} label: {
                                HStack(spacing: 8) { Line("All", 14, .semibold); Icon("chev", 14).foregroundStyle(C.i12) }
                                    .padding(.leading, 16).padding(.trailing, 12).frame(height: 32)
                                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear))
                                    .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Rectangle())
                            }.buttonStyle(Press(scale: 0.97))
                        }; Color.clear.frame(width: 0) } }
                        Hover { h in
                            Button { s.newAgentOpen = true } label: {
                                Icon("pen", 18).foregroundStyle(C.i12).frame(width: 32, height: 32)
                                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v4 : C.v3)).contentShape(Rectangle())
                            }.buttonStyle(Press())
                        }.tip("New agent", "⌘N")
                    }
                }
                .frame(height: 44)
                SearchField(text: $query, placeholder: "Search").padding(.top, 12)
                let q = query.trimmingCharacters(in: .whitespaces).lowercased()
                // Pinned first, then the most recent.
                let list = s.agents.filter { q.isEmpty || "\($0.name) \($0.job ?? "")".lowercased().contains(q) }
                    .sorted { ($0.pinned == true) != ($1.pinned == true) ? $0.pinned == true : lastAt($0) > lastAt($1) }
                if list.isEmpty {
                    Para(text: s.agents.isEmpty ? "Nothing matches." : "No agent matches.", size: 14, weight: .regular, color: C.i10).padding(.horizontal, 12).padding(.vertical, 8).padding(.top, 22)
                    Spacer(minLength: 0)
                } else if SnapshotMode.on {
                    VStack(spacing: 4) { ForEach(list) { a in ConvRow(agent: a, menuOpen: menuBinding(a.id)).zIndex(menuFor == a.id ? 1 : 0) } }.padding(.top, 12)
                    Spacer(minLength: 0)
                } else {
                    // An open ⋯ menu draws over the rows under it, and past the list's edge.
                    ScrollView { VStack(spacing: 4) { ForEach(list) { a in ConvRow(agent: a, menuOpen: menuBinding(a.id)).zIndex(menuFor == a.id ? 1 : 0) } }.padding(.top, 12).padding(.bottom, 12) }
                        .scrollIndicators(.never).scrollClipDisabled()
                }
            }
            .padding(.top, 8).padding(.horizontal, 10)
            .frame(width: panes.list)
            .overlay(alignment: .trailing) { SplitHandle(pane: PaneID.list).offset(x: 5.5) }
            .padding(.trailing, 1)
            .zIndex(1)
    }
    @ViewBuilder var conversation: some View {
            // In a workspace, Messages (kept underneath) holds on to its own chat, so coming back shows it at once.
            if let id = s.openWorkspace == nil ? s.openAgent : (s.messagesAgent ?? s.openAgent), let a = s.agents.first(where: { $0.id == id }) {
                ChatHost(key: "dm:\(a.id)", token: a) { ChatPane(agent: a) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            // Empty conversation side, centred.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: R.card).fill(C.v1).frame(width: 128, height: 128).overlay(Icon("chat", 48).foregroundStyle(C.i9))
                Line("Your messages", 20, .semibold).padding(.top, 20)
                Para(text: "Pick an agent on the left to pick up where you left off, or make a new one.", size: 14, weight: .regular, color: C.i10, align: .center)
                    .frame(maxWidth: 338.2).padding(.top, 12)
                PrimaryButton(title: "New agent") { s.newAgentOpen = true }.padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, gutter)
            }
    }
}

/// The gap between a list (Messages, a workspace's sidebar) and its chat: drag to resize the list (kept), double-click
/// for 304.
struct MVListGap: View {
    @EnvironmentObject var panes: Panes
    @State private var from: CGFloat?
    static func width(_ panes: Panes) -> CGFloat {
        min(max(MV.Resize.listMin, panes.width(PaneID.list)), MV.Resize.listMax)
    }
    var body: some View {
        MVResizeGap(axis: .horizontal) { dx in
            if from == nil { from = Self.width(panes) }
            panes.drag(PaneID.list, to: (from ?? MV.Size.listWidth) + dx)
        } end: {
            from = nil; panes.dragEnd(PaneID.list)
        } reset: {
            panes.set(PaneID.list, MV.Size.listWidth)
        }
    }
}

/// A MAVIS surface only while MAVIS is on (the classic layout keeps its one panel).
struct MVSurfaceIfOn: ViewModifier {
    func body(content: Content) -> some View {
        if MV.on { content.mvSurface() } else { content }
    }
}

/// 44 tall, #0a0a0a, 1px #2e2e2e, 10 corners; 16px icon, 16px text (web: .ag-search).
struct SearchField: View {
    @Binding var text: String; let placeholder: String
    var body: some View {
        HStack(spacing: 8) {
            Icon("search", 16).foregroundStyle(C.i10)
            ZStack(alignment: .leading) {
                if text.isEmpty { Line(placeholder, 16, .regular, C.i10) }
                if !SnapshotMode.on { TextField("", text: $text).textFieldStyle(.plain).font(F.font(16, .regular)).foregroundStyle(C.i12) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
    }
}

// MARK: Usage (web: usageView, no runs)

struct UsagePage: View {
    var body: some View {
        PageColumn {
            PageHead(title: "Usage", lede: "What your agents ran this week. Claude Code reports what each run cost; Codex reports time only, so their cost shows as a dash.")
            HStack(spacing: 12) {
                stat("–", "Cost reported"); stat("0", "Runs"); stat("–", "Time working")
            }.padding(.top, 24)
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "This week")
                WeekBars()
            }.padding(.top, 32)
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "By agent")
                Para(text: "No runs yet this week. Usage starts counting with your agents’ next run.", size: 14, weight: .regular, color: C.i10)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edgeControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }.padding(.top, 32)
        }
    }
    func stat(_ big: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Line(big, 24, .semibold).monospacedDigit()
            Line(label, 12, .regular, C.i10).padding(.top, 2).frame(height: 20, alignment: .top)
        }
        .padding(17).frame(width: 258.7, alignment: .leading).card()
    }
}

/// Seven days from Monday; today's bar white, past bars grey, future bars hidden (web: .use-days).
struct WeekBars: View {
    var body: some View {
        let cal = Calendar(identifier: .gregorian), now = Date()
        let todayIndex = (cal.component(.weekday, from: now) + 5) % 7   // Monday = 0
        let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
        let monday = cal.date(byAdding: .day, value: -todayIndex, to: cal.startOfDay(for: now))!
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: R.xs).fill(i == todayIndex ? C.i12 : C.v6).frame(width: 40, height: 2).opacity(i > todayIndex ? 0 : 1)
                    Line(fmt.string(from: cal.date(byAdding: .day, value: i, to: monday)!), 12, .regular, i == todayIndex ? C.i12 : C.i9)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(17).frame(height: 140).card()
    }
}

// MARK: Plugins (web: connectionsView, nothing installed)

struct PluginsPage: View {
    var body: some View {
        PageColumn {
            PageTitle(text: "Plugins")
            Lede(text: "Agents run through the tools already on this Mac, with your own logins and settings. Agent Lab never sees your passwords.").padding(.top, 4)
            VStack(spacing: 8) {
                ForEach([("claude-code", "Claude Code"), ("codex", "Codex")], id: \.0) { op, name in
                    Tile(ab: "", op: op, title: name, meta: "Not found on this Mac") {
                        HStack(spacing: 8) { Circle().fill(C.v6).frame(width: 8, height: 8); Line("Not installed", 12, .regular, C.i10) }
                    }
                }
            }.padding(.top, 24)
            VStack(alignment: .leading, spacing: 0) {
                Line("Mavis", 16, .semibold)
                Lede(text: "Brings Mavis’s agents in by name. Mavis’s own prompts and rules stay behind: agents here answer the way Claude Code does.").padding(.top, 12)
                Tile(ab: "Mv", title: "Mavis on this Mac", meta: "Not checked yet") { SecondaryButton(title: "Check") {} }.padding(.top, 24)
            }.padding(.top, 32)
            VStack(alignment: .leading, spacing: 0) {
                Line("Workspaces", 16, .semibold)
                Lede(text: "A workspace is a folder. Agents made in it work there, and it gets its own space on the left.").padding(.top, 12)
                Hover { h in
                    Button {} label: {
                        HStack(spacing: 4) { Icon("folder", 14).foregroundStyle(C.i12); Line("Add a folder", 14, .medium) }
                            .padding(.horizontal, 16).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : C.v1))
                            .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Rectangle())
                    }.buttonStyle(Press(scale: 0.97))
                }.padding(.top, 24)
            }.padding(.top, 32)
        }
    }
}

// MARK: Profile (web: profileView, no agents)

struct ProfilePage: View {
    @EnvironmentObject var s: Store
    var body: some View {
        PageColumn {
            HStack(alignment: .top, spacing: 16) {
                Circle().fill(C.v3).frame(width: 88, height: 88).overlay(Icon("person", 40).foregroundStyle(C.i10))
                VStack(alignment: .leading, spacing: 4) {
                    PageTitle(text: "You")
                    Line("@\(s.handle) · 0 agents", 14, .regular, C.i10)
                }
            }
            HStack(alignment: .top, spacing: 32) {
                stat("0", "Messages sent"); stat("0", "Replies"); stat("0", "Agents on a branch")
            }.padding(.top, 24)
            VStack(alignment: .leading, spacing: 0) {
                Line("Activity", 16, .semibold)
                Heatmap().padding(.top, 12)
                Line("Your messages to agents over the last six months.", 12, .regular, C.i10).padding(.top, 8)
            }.padding(.top, 32)
            VStack(alignment: .leading, spacing: 0) {
                Line("Your agents", 16, .semibold)
                Line("No agents yet.", 12, .regular, C.i10).padding(.top, 24)
            }.padding(.top, 32)
            SignIns().padding(.top, 32)
        }
    }
    func stat(_ big: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) { Line(big, 24, .semibold).monospacedDigit(); Line(label, 12, .regular, C.i10) }
    }
}

/// 26 weeks × 7 days, Sunday first; days after today are left empty (web: .hm).
struct Heatmap: View {
    var body: some View {
        let cal = Calendar(identifier: .gregorian), today = cal.startOfDay(for: Date())
        let dow = cal.component(.weekday, from: today) - 1           // Sunday = 0, like getDay()
        let start = cal.date(byAdding: .day, value: -(25 * 7 + dow), to: today)!
        HStack(spacing: 4) {
            ForEach(0..<26, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let t = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                        RoundedRectangle(cornerRadius: R.xs).fill(t > today ? .clear : C.v4).frame(width: 12, height: 12)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(height: 140)
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1))
    }
}

/// Both sign-ins (Mavis final launch's Settings › Account and Claude): your Agent Lab account, and Claude on this Mac.
struct SignIns: View {
    @ObservedObject private var account = Account.shared
    @State private var claudeIn = ClaudeAccount.signedIn
    @State private var claudeThere = ClaudeAccount.installed
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Line("Sign-ins", 16, .semibold)
            if Account.configured {
                row(account.session.map { $0.name ?? $0.email } ?? "Agent Lab account",
                    account.session.map { s in [s.name == nil ? nil : s.email, s.status == "approved" ? "Signed in" : s.status == "waitlist" ? "On the waitlist" : nil].compactMap { $0 }.joined(separator: " · ") } ?? "Not signed in") {
                    if account.session != nil {
                        SmallSecondaryButton(title: "Sign out") { account.signOut(); Welcome.shared.reopen() }
                        SmallSecondaryButton(title: "Delete account") { deleting = true }
                    }
                }
            }
            row("Claude", claudeThere ? (claudeIn ? "Signed in on this Mac · agents use your Claude plan" : "Installed, not signed in") : "Claude Code isn't installed") {
                if !claudeThere { SmallSecondaryButton(title: "Install") { ClaudeAccount.install() } }
                else if !claudeIn { SmallSecondaryButton(title: "Sign in") { ClaudeAccount.signIn() } }
            }
        }
        .onAppear { claudeIn = ClaudeAccount.signedIn; claudeThere = ClaudeAccount.installed }
        .confirmationDialog("Delete your Agent Lab account?", isPresented: $deleting) {
            Button("Delete account", role: .destructive) { Task { try? await account.deleteAccount(); Welcome.shared.reopen() } }
        } message: { Text("Your sign-in and profile are removed from Agent Lab's account service. Your agents and chats on this Mac stay.") }
    }
    func row<T: View>(_ title: String, _ detail: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { Line(title, 14, .medium); Line(detail, 12, .regular, C.i10) }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).frame(height: 60)
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1))
    }
}


// MARK: Theme

/// The theme row: it says which theme is on. Pointing at it opens every theme, Dark and Light, beside the menu, as a
/// submenu does (pointing at another row of the menu closes it).
struct ThemeRows: View {
    @ObservedObject private var themes = Themes.shared
    @State private var frame: CGRect = .zero
    var body: some View {
        let t = themes.chosen
        MenuRow(icon: t.dark ? "moon" : "sun", title: "Theme", meta: t.name + " · " + t.mode) { open() }
            .background(GeometryReader { g in Color.clear.onAppear { frame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, f in frame = f } })
            .onHover { if $0 { open() } }
    }
    /// The panel, where this row is on screen (the menu's own window holds it).
    private func open() {
        guard let menu = NSApp.windows.first(where: { $0.isVisible && $0 is NSPanel && $0.frame.contains(NSEvent.mouseLocation) }) ?? NSApp.keyWindow,
              let parent = menu.parent ?? NSApp.mainWindow else { return }
        let content = menu.contentView?.frame ?? menu.frame
        let onScreen = NSRect(x: menu.frame.minX + frame.minX, y: menu.frame.minY + content.height - frame.maxY, width: frame.width, height: frame.height)
        ThemePicker.shared.open(at: onScreen, menu: menu.frame, parent: parent)
    }
}

/// Every theme in a panel by itself: pointing at one shows the whole app in it, leaving puts yours back, a click keeps
/// it. Its own window, so the app can redraw underneath without closing it.
@MainActor final class ThemePicker {
    static let shared = ThemePicker()
    private var panel: NSPanel?
    private var monitor: Any?
    func open(at row: NSRect, menu: NSRect, parent: NSWindow) {
        if panel != nil { return }
        let m = MenuWindow.margin
        let host = NSHostingView(rootView: AnyView(ThemePickerView { [weak self] in self?.close() }.padding(m)))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        // Beside the menu, as a submenu: its edge 6 pt from the menu's card, its last row level with the Theme row (the
        // menu sits above the gear, so the list reaches upward), kept on screen.
        var f = NSRect(x: menu.maxX - m + 6 - m, y: row.minY - m - 8, width: size.width, height: size.height)
        if let vis = parent.screen?.visibleFrame {
            f.origin.y = min(max(f.minY, vis.minY - m), vis.maxY + m - f.height)
            f.origin.x = min(max(f.minX, vis.minX - m), vis.maxX + m - f.width)
        }
        let p = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.isReleasedWhenClosed = false
        p.appearance = NSAppearance(named: themeNow.dark ? .darkAqua : .aqua)
        p.contentView = host
        parent.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self, let p = self.panel else { return e }
            if e.type == .keyDown { if e.keyCode == 53 { self.close(); return nil }; return e }
            if e.window !== p { self.close() }
            return e
        }
    }
    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let p = panel { p.parent?.removeChildWindow(p); p.orderOut(nil) }
        panel = nil
        Themes.shared.preview(nil)
    }
}

private struct ThemePickerView: View {
    let close: () -> Void
    @ObservedObject private var themes = Themes.shared
    var body: some View {
        // Drawn again in each theme as you point (it's part of the app too).
        MenuSurface(width: 264, softDrop: true) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach([true, false], id: \.self) { dark in
                    Line(dark ? "Dark" : "Light", 12, .medium, C.i9).padding(.horizontal, 12).frame(height: 26, alignment: .bottom)
                    ForEach(Palettes.all.filter { $0.dark == dark }) { p in
                        ThemeOption(palette: p, on: p.id == themes.chosen.id) { themes.choose(p.id); close() }
                    }
                }
            }
            .padding(.bottom, 2)
            .onHover { if !$0 { themes.preview(nil) } }
        }
        // It opens on hover, so it pops (a click-opened menu doesn't): from the menu's side, quick, no bounce.
        .scaleEffect(shown ? 1 : 0.97, anchor: .bottomLeading).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)) { shown = true } }
    }
    @State private var shown = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

/// One theme: its colours in a small swatch (its frame, panel and ink) and its name; yours sits on the selected fill.
private struct ThemeOption: View {
    let palette: ThemePalette; let on: Bool; let pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(palette.v0))
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(palette.v1)).padding(.top, 5).padding(.leading, 5)
                    Circle().fill(Color(palette.i12)).frame(width: 5, height: 5).offset(x: 9, y: 9)
                }
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.ink(0.12), lineWidth: 1))
                Line(palette.name, 14, .medium, on || hover ? C.i12 : C.i10)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: R.ctl).fill(on ? C.sel : hover ? C.v3 : .clear)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hover = h
            // A moment's rest before the app redraws in it, so sweeping across the list doesn't redraw for every row.
            guard h else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { if hover { Themes.shared.preview(palette.id) } }
        }
        .accessibilityLabel("\(palette.name), \(palette.mode)")
    }
}

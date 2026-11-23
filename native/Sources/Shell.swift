// The window: top bar, sidebar, main panel. Positions are the web app's measured layout (window 1392 wide).
import SwiftUI

/// Buttons don't shrink when pressed; hover fills are their only feedback.
struct Press: ButtonStyle {
    var scale: CGFloat = 1
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// Hover tracking for a view (mouse only), used for the CSS :hover fills.
struct Hover<Content: View>: View {
    @State private var on = false
    @ViewBuilder let content: (Bool) -> Content
    var body: some View { content(on).onHover { on = $0 } }
}

struct RootView: View {
    @EnvironmentObject var s: Store
    @ObservedObject private var welcome = Welcome.shared
    var drawLights = false
    var body: some View {
        // Until the welcome is finished (signed in, Claude connected) nothing else of Agent Lab runs: the engine starts
        // with the app itself.
        if welcome.showing && !SnapshotMode.on {
            WelcomeView()
        } else {
            Shell(drawLights: drawLights).environmentObject(s.panes).environmentObject(s.railTip)
                // Every link in the app's own text opens inside it: a page in the chat's Browser pane, a file in Files.
                .environment(\.openURL, OpenURLAction { url in ProseView.open(url); return .handled })
                .task { if !SnapshotMode.on { s.connect() } }
        }
    }
}

/// The window's layout. Every width comes from Panes; the window's own width is read here, so the sidebar folds into
/// its rail and Right now steps aside as the window gets smaller, instead of the content being cropped.
struct Shell: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    @EnvironmentObject var railTip: RailTip
    var drawLights = false
    /// The theme decides the layout (MAVIS or the classic one), so a switch redraws the shell.
    @ObservedObject private var themes = Themes.shared
    var body: some View {
        Group {
            if MV.on {
                // MAVIS: no top bar. The rail runs the full height with the lights on it; the surfaces float 12 down,
                // 8 from the right and bottom (Back, Forward, History, Search and New agent live in the Go menu).
                HStack(spacing: 0) {
                    RailSidebar().frame(width: MV.Size.rail).padding(.top, MV.Shell.railTop)
                    MainPanel().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .padding(.top, MV.Shell.surfaceTop).padding(.trailing, MV.Space.gutter).padding(.bottom, MV.Space.gutter)
                }
                .overlay(alignment: .topLeading) { if drawLights { MavisLights() } }
            } else {
                VStack(spacing: 0) {
                    TopBar(drawLights: drawLights)
                    HStack(spacing: 0) {
                        SidebarStack(width: panes.sidebar)
                        // The panel takes what's left and clips its own content: whatever happens inside it, it never
                        // pushes the sidebar or the window's edge out of view.
                        MainPanel().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
                            // The handle starts below the panel's rounded corner, so its lit line never runs through the curve.
                            .overlay(alignment: .leading) { SplitHandle(pane: PaneID.sidebar, showsLine: false).offset(x: -5.5).padding(.top, R.card + 4) }
                    }
                }
            }
        }
        .frame(minWidth: Panes.windowMin, minHeight: 560)
        .background(C.v0)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            // Only Right now responds to the window's size (it steps aside); crossing that size springs.
            panes.resized(w)
        }
        .overlay(alignment: .topLeading) {
            if s.historyOpen { HistoryMenu().offset(x: MV.on ? MV.Size.rail : TopBar.leftWidth(panes) - 12, y: MV.on ? MV.Shell.surfaceTop : 52) }
        }
        // The rail's label floats over everything, 10 to the right of its tile and centred on it, placed from the tile's
        // own bounds (an anchor), so it's right wherever the tile is, scrolled or not.
        .overlayPreferenceValue(RailAnchors.self, alignment: .topLeading) { anchors in
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if let t = railTip.tip, s.railMenu == nil, let a = anchors[t.id] {
                        let r = g[a]
                        RailTipView(tip: t)
                            .alignmentGuide(.leading) { _ in -(r.maxX + 10) }
                            .alignmentGuide(.top) { d in -(r.midY - d.height / 2) }
                            .id(t.id)
                            .transition(.asymmetric(insertion: .scale(scale: RailTip.popFrom, anchor: .leading), removal: .identity))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        // Settings opens above your profile, over everything (the sidebar clips its own content).
        .overlay(alignment: .bottomLeading) { if MV.on { MVProfileBar() } }
        .overlay(alignment: .bottomLeading) { if s.settingsOpen { SettingsMenu().offset(x: 8, y: -66) } }
        .overlay { if s.searchOpen { CommandPalette() } }   // ⌘K: commands, agents, chats, files, settings, messages
        .overlay { if s.newAgentOpen { NewAgentForm() } }
        .overlay { if let a = s.agents.first(where: { $0.id == s.editingAgent }) { NewAgentForm(editing: a).id(a.id) } }
        .overlay { if s.createWorkspaceOpen { WorkspaceForm() } }
        .overlay { if let w = s.workspaces.first(where: { $0.id == s.editingWorkspace }) { WorkspaceForm(editing: w).id(w.id) } }
        .overlay { if let r = s.openReport { ReportSheet(report: r) } }
        .overlay(alignment: .bottom) { if let t = s.toast { Toast(text: t) } }
        .confirmationDialog("Remove \(s.workspaces.first { $0.id == s.removingWorkspace }?.name ?? "this workspace")?", isPresented: Binding(get: { s.removingWorkspace != nil }, set: { if !$0 { s.removingWorkspace = nil } })) {
            Button("Remove", role: .destructive) { if let id = s.removingWorkspace { Task { await s.removeWorkspace(id) } } }
        } message: { Text("Its agents move back to Personal. Nothing on disk is deleted.") }
        // Light or dark comes from the theme's appearance (Themes.swift), so switching redraws every colour.
    }
}

// MARK: Top bar (web: renderTop)

struct TopBar: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    var drawLights: Bool
    /// Lights and the back/forward/history buttons end where the sidebar's rows end; with the rail, they need 172.
    static func leftWidth(_ p: Panes) -> CGFloat { max(p.sidebar - 28, 172) }
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if drawLights { Lights() } else { Color.clear.frame(width: 52, height: 12) }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    NavButton(icon: "arrowL", enabled: s.canBack, label: "Back") { s.step(-1) }
                    NavButton(icon: "arrowR", enabled: s.canForward, label: "Forward") { s.step(1) }
                    NavButton(icon: "clock", enabled: true, label: "History", active: s.historyOpen) { s.settingsOpen = false; s.historyOpen.toggle() }
                }
            }
            .frame(width: TopBar.leftWidth(panes))   // 20 → 272 at the standard width: ends where the sidebar rows end
            HStack(spacing: 8) {
                if let w = s.currentWorkspace {
                    WsPic(name: w.name, color: w.color, image: w.image, size: 22, radius: R.xs)
                    Line(w.name, 16, .semibold)
                } else if s.view == .messages, let id = s.openAgent, let a = s.agents.first(where: { $0.id == id }) {
                    Avatar(agent: a, size: 22, status: false)
                    Line(a.name, 16, .semibold)
                } else {
                    Icon(s.view.info.icon, 20).foregroundStyle(C.i10)
                    Line(s.view.info.title, 16, .semibold)
                }
            }
            .padding(.leading, 8)                    // title starts on the panel's edge (280)
            Spacer(minLength: 0)
            ToolsGroup()
        }
        .padding(.leading, 20).padding(.trailing, 13)
        .frame(height: 56)
    }
}

/// The lights where the MAVIS rail draws them (for snapshots; the real ones are moved there by App.place).
struct MavisLights: View {
    var body: some View {
        HStack(spacing: MV.Shell.lightsStep - MV.Shell.light) {
            ForEach([C.lightRed, C.lightYellow, C.lightGreen], id: \.self) { c in
                Circle().fill(c).frame(width: MV.Shell.light, height: MV.Shell.light)
            }
        }
        .padding(.leading, MV.Shell.lightsX).padding(.top, MV.Shell.lightsY)
    }
}

struct Lights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([C.lightRed, C.lightYellow, C.lightGreen], id: \.self) { c in
                Circle().fill(c).overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)).frame(width: 12, height: 12)
            }
        }
    }
}

/// 32×32, 10 corners, #0a0a0a with a 1px #2e2e2e outline; disabled = 40% (web: .top-nav .icon-btn).
struct NavButton: View {
    let icon: String; let enabled: Bool; let label: String; var active = false; let action: () -> Void
    var body: some View {
        Hover { hover in
            Button(action: action) {
                Icon(icon, 18).foregroundStyle(hover || active ? C.i12 : C.i10)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(hover || active ? C.v3 : C.v1))
                    .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(Press())
        }
        .opacity(enabled ? 1 : 0.4).allowsHitTesting(enabled)
        .tip(label).accessibilityLabel(label)
    }
}

/// Pen and search share one outline with a hairline between them (web: .top-tools).
struct ToolsGroup: View {
    @EnvironmentObject var s: Store
    var body: some View {
        HStack(spacing: 0) {
            ToolSegment(icon: "pen", label: "New agent", keys: "⌘N") { s.newAgentOpen = true }
            ToolSegment(icon: "search", label: "Search and commands", keys: "⌘K") { s.closeMenus(); s.searchOpen.toggle() }
                .overlay(alignment: .leading) { Rectangle().fill(C.v5).frame(width: 1) }
        }
        .frame(height: 32)
        .background(C.v1)
        .clipShape(RoundedRectangle(cornerRadius: R.ctl))
        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
    }
}
struct ToolSegment: View {
    let icon: String; let label: String; var keys: String? = nil; let action: () -> Void
    var body: some View {
        Hover { hover in
            Button(action: action) {
                Icon(icon, 18).foregroundStyle(hover ? C.i12 : C.i10).frame(width: 36, height: 32).background(hover ? C.v3 : .clear).contentShape(Rectangle())
            }.buttonStyle(Press())
        }.tip(label, keys).accessibilityLabel(label)
    }
}

// MARK: Sidebar (web: renderSide)

struct Sidebar: View {
    @EnvironmentObject var s: Store
    let nav = Kind.nav
    @State private var menuFor: String? = ProcessInfo.processInfo.environment["AL_TEST_MENU"].flatMap { $0.hasPrefix("ws:") ? String($0.dropFirst(3)) : nil }
    func wsMenu(_ id: String) -> Binding<Bool> { Binding(get: { menuFor == id }, set: { menuFor = $0 ? id : (menuFor == id ? nil : menuFor) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Personal")
            VStack(spacing: 4) { ForEach(nav, id: \.self) { k in NavRow(kind: k) } }
                .padding(.top, 4)
            Rectangle().fill(C.split).frame(height: 1).padding(.horizontal, 12).padding(.top, 12)   // split, centred in the 24 gap
            HStack(spacing: 0) {
                Line("Workspaces", 14, .medium, C.i10)
                Spacer(minLength: 0)
                Hover { h in
                    Button { s.createWorkspaceOpen = true } label: {
                        Icon("plus", 16).foregroundStyle(h ? C.i12 : C.i10).frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: R.xs).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                    }.buttonStyle(Press())
                }.tip("Create a workspace").accessibilityLabel("Create a workspace")
            }
            .padding(.leading, 12).padding(.trailing, 0).frame(height: 24).padding(.top, 11)
            if s.workspaces.isEmpty {
                Para(text: "Create a workspace to give a team of agents its own place.", size: 14, weight: .regular, color: C.i10)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8).padding(.top, 18)
                Spacer(minLength: 0)
            } else {
                ScrollView { VStack(spacing: 4) { ForEach(s.workspaces) { w in WsRow(w: w, menuOpen: wsMenu(w.id)).zIndex(menuFor == w.id ? 1 : 0) } }.padding(.vertical, 8) }
                    .scrollClipDisabled()
                    .scrollIndicators(.never).padding(.top, 4)
            }
            UserPanel()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Line(text, 14, .medium, C.i10).padding(.leading, 12).frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading) }
}

/// 40 tall, 10 corners, icon 20 at 12, label 16/24 medium at 44 (web: .snav).
struct NavRow: View {
    @EnvironmentObject var s: Store
    let kind: Kind
    var body: some View {
        let on = s.view == kind && s.openWorkspace == nil
        Hover { hover in
            Button { s.go(kind) } label: {
                HStack(spacing: 12) {
                    Icon(kind.info.icon, 20)
                    Line(kind.info.title, 16, .medium, on || hover ? C.i12 : C.i10)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(on || hover ? C.i12 : C.i10)
                .padding(.leading, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: R.ctl).fill(on ? C.sel : hover ? C.rowHover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(kind.info.title)
    }
}

/// The profile panel at the bottom: 52 tall, #0a0a0a, 14 corners, 1px #1f1f1f, 4 inside (web: .upanel).
struct UserPanel: View {
    @EnvironmentObject var s: Store
    var body: some View {
        HStack(spacing: 4) {
            Hover { h in
                Button { s.go(.profile) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(C.v4).frame(width: 32, height: 32).overlay(Icon("person", 20).foregroundStyle(C.i10))
                        VStack(alignment: .leading, spacing: 0) {
                            Line(s.handle, 14, .semibold)
                            Line("\(s.agentCount) \(s.agentCount == 1 ? "agent" : "agents")", 12, .medium, C.i10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4).frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Hover { h in
                Button { s.historyOpen = false; s.settingsOpen.toggle() } label: {
                    Icon("gear", 18).foregroundStyle(h || s.settingsOpen ? C.i12 : C.i10).frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                }.buttonStyle(Press(scale: 0.92))
            }.tip("Plugins and settings", edge: .top).accessibilityLabel("Plugins and settings")
        }
        .padding(4)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1))
    }
}

/// The sidebar at a width: the open sidebar and the rail stacked, each faded by the width as drawn (Panes.openOpacity,
/// railOpacity). Animatable, so a settle or a fold runs the fade frame by frame with the width: out to nothing, then in.
struct SidebarStack: View, Animatable {
    var width: CGFloat
    var animatableData: CGFloat { get { width } set { width = newValue } }
    var body: some View {
        let open = Panes.openOpacity(width), rail = Panes.railOpacity(width)
        ZStack(alignment: .topLeading) {
            if open > 0 { Sidebar().frame(minWidth: PaneID.sidebar.min).opacity(open).allowsHitTesting(open > 0.5) }
            if rail > 0 { RailSidebar().frame(width: Panes.rail).opacity(rail).allowsHitTesting(rail > 0.5).zIndex(3) }
        }
        .frame(width: max(width, 0), alignment: .topLeading)
        .clipped()                                   // never spills into the panel, at any width mid-drag
    }
}

// MARK: Rail (the sidebar folded): Discord's server column

/// Icons only, every item a 48 pt tile on the rail's centre line, 8 apart. One highlight for everything: a rounded
/// square behind the tile (a page's icon, a workspace's picture). Add a workspace is a tile of the same size, on top
/// of the workspaces. Your picture alone at the bottom; clicking it opens settings.
struct RailSidebar: View {
    @EnvironmentObject var s: Store
    let nav = Kind.nav
    var body: some View {
        VStack(spacing: 8) {
            ForEach(nav, id: \.self) { k in
                RailTile(selected: s.view == k && s.openWorkspace == nil, label: k.info.title) { s.go(k) } content: { _ in
                    // MAVIS draws the prototype's Hugeicons (home, compass, chat) at 22.
                    Icon(MV.on ? (["agents": "mvHome", "discover": "mvCompass", "messages": "mvChat", "apps": "mvApps"][k.rawValue] ?? k.info.icon) : k.info.icon, MV.Size.iconLarge)
                }
            }
            if MV.on {
                Rectangle().fill(MV.Tone.line).frame(width: MV.Shell.railDivider.width, height: MV.Shell.railDivider.height)
            } else {
                Rectangle().fill(C.divider).frame(width: 32, height: 1).padding(.vertical, 4)
            }
            ScrollView {
                VStack(spacing: 8) {
                    RailTile(selected: false, label: "Create a workspace") { s.createWorkspaceOpen = true } content: { h in
                        if MV.on {
                            RoundedRectangle(cornerRadius: MV.Radius.rail, style: .continuous).fill(MV.Tone.omni)
                                .overlay(Icon("mvPlus", MV.Size.iconLarge).foregroundStyle(h ? MV.Ink.t1 : MV.Ink.t2))
                                .frame(width: MV.Size.railButton, height: MV.Size.railButton)
                        } else {
                            RoundedRectangle(cornerRadius: Rail.inner, style: .continuous).fill(h ? C.v4 : C.v2)
                                .overlay(Icon("plus", 20).foregroundStyle(h ? C.i12 : C.i10))
                                .frame(width: 40, height: 40)
                        }
                    }
                    ForEach(s.workspaces) { w in
                        let waiting = s.approvals.contains { p in (w.members ?? []).contains(p.agentId ?? "") }
                        let pool = s.members(of: w), working = pool.filter { s.state(of: $0) == "working" }.count
                        let detail = pool.isEmpty ? "No agents yet" : "\(pool.count) \(pool.count == 1 ? "agent" : "agents")" + (waiting ? " · waiting for you" : working > 0 ? " · \(working) working" : "")
                        // MAVIS: the picture fills the 48 tile; the selected one gets a 3 pt blue ring right on it.
                        RailTile(selected: !MV.on && s.openWorkspace == w.id, label: w.name, detail: detail, id: "ws:" + w.id) { s.openSpace(w.id) } content: { _ in
                            WsPic(name: w.name, color: w.color, image: w.image, size: MV.on ? MV.Size.railButton : 40, radius: MV.on ? MV.Radius.rail : Rail.inner)
                                .overlay {
                                    if MV.on && s.openWorkspace == w.id {
                                        // A 3 pt ring right outside the tile (prototype: box-shadow 0 0 0 3px).
                                        RoundedRectangle(cornerRadius: MV.Radius.rail + MV.Stroke.dotRing, style: .continuous)
                                            .strokeBorder(MV.Accent.blue, lineWidth: MV.Stroke.dotRing).padding(-MV.Stroke.dotRing)
                                    }
                                }
                                .opacity(w.muted == true ? 0.55 : 1)
                                .overlay(alignment: .topTrailing) {
                                    if !MV.on, waiting && w.muted != true { Circle().fill(WAIT).frame(width: 10, height: 10).overlay(Circle().strokeBorder(C.v0, lineWidth: 2).padding(-2)).offset(x: 2, y: -2) }
                                }
                                // MAVIS: Discord's red count in the corner: what needs you there, and replies since you left.
                                .overlay(alignment: .bottomTrailing) {
                                    if MV.on { let n = s.needsCount(w); if n > 0 { MVCountBadge(count: n, ring: MV.Tone.frame).offset(x: MV.Home.dotOffset, y: MV.Home.dotOffset) } }
                                }
                        }
                        // Unread (classic): Discord's pill at the rail's edge.
                        .overlay(alignment: .leading) { if !MV.on, s.unread(w) { Capsule().fill(C.i12).frame(width: 4, height: 8).offset(x: -10) } }
                        .onRightClick { s.railMenu = w.id }
                        // Its workspace menu (right-click) floats beside the tile, over everything.
                        .floatingMenu(Binding(get: { s.railMenu == w.id }, set: { if !$0, s.railMenu == w.id { s.railMenu = nil } }), placement: .beside(gap: 10)) {
                            WorkspaceActions(w: w, open: Binding(get: { s.railMenu == w.id }, set: { if !$0 { s.railMenu = nil } }))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()                       // a tile's menu opens beside it, past the rail's edge
            Spacer(minLength: 0)
            // Your picture, in a tile like everything else on the rail: lit while settings is open or on your profile.
            // MAVIS: the profile bar (MVProfileBar, over the window's corner) takes its place.
            if !MV.on {
                RailTile(selected: s.settingsOpen || (s.view == .profile && s.openWorkspace == nil), label: s.handle, detail: "Profile and settings") {
                    s.historyOpen = false; s.settingsOpen.toggle()
                } content: { _ in
                    Circle().fill(C.v4).frame(width: 36, height: 36).overlay(Icon("person", 20))
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, MV.on ? MV.Shell.railBottom : 8)   // the first tile's top sits exactly on the panel's top edge
        .frame(maxWidth: .infinity)
    }
}

/// One rail item: 48 × 48, its highlight a 14 pt rounded square (selected: the sidebar's selection fill; hover: its
/// hover fill), content centred.
enum Rail { static let inner: CGFloat = 11 }     // the corner of a 40 pt picture inside a 48 pt tile (14 − 4 + 1)
struct RailTile<Content: View>: View {
    @EnvironmentObject var railTip: RailTip
    let selected: Bool; let label: String; var detail: String? = nil; var id: String? = nil; let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    var key: String { id ?? label }
    var body: some View {
        tile
        // Keyed by the tile's own id (two workspaces can share a name), so each tip sits on its own tile.
        .anchorPreference(key: RailAnchors.self, value: .bounds) { [key: $0] }
        .onHover { on in if on { railTip.enter(.init(id: key, title: label, detail: detail, frame: .zero)) } else { railTip.leave(key) } }
        .onDisappear { railTip.leave(key) }
        .accessibilityLabel(label)
    }
    @ViewBuilder private var tile: some View {
        if MV.on {
            // MAVIS (prototype .sri): selected sits on box2; hover lays 10% white over it, pressing 16%.
            let shape = RoundedRectangle(cornerRadius: MV.Radius.rail, style: .continuous)
            Hover { h in
                Button(action: action) {
                    content(h)
                        .foregroundStyle(selected || h ? MV.Ink.t1 : MV.Ink.t2)
                        .frame(width: MV.Size.railButton, height: MV.Size.railButton)
                        .background(shape.fill(selected ? MV.Tone.box2 : .clear))
                        .contentShape(shape)
                }.buttonStyle(MVStates(shape: shape))
            }
        } else {
            Hover { h in
                Button(action: action) {
                    content(h)
                        .foregroundStyle(selected || h ? C.i12 : C.i10)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? C.sel : h ? C.rowHover : .clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: Main panel (web: .main)

struct MainPanel: View {
    @EnvironmentObject var s: Store
    var body: some View {
        if MV.on {
            // MAVIS: no panel of its own. Each page lays out its own floating surfaces (spec 4): Messages and a
            // workspace keep their list on the frame beside a chat surface; Home has Home and Today; the rest one.
            ZStack(alignment: .top) {
                if let w = s.currentWorkspace { WorkspacePage(w: w) } else { Page() }
            }
        } else {
            let shape = UnevenRoundedRectangle(topLeadingRadius: R.card)
            ZStack(alignment: .top) {
                shape.fill(C.v1)
                if let w = s.currentWorkspace { WorkspacePage(w: w) } else { Page() }
            }
            .clipShape(shape)
            .overlay(PanelEdge(radius: R.card).allowsHitTesting(false))   // drawn on top, like the web's ::after
        }
    }
}

extension View {
    /// A MAVIS surface (spec 4): page fill, radius 14, clipped, 0.5 pt hairline on top.
    func mvSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.surface, style: .continuous)
        return background(shape.fill(MV.Tone.page))
            .clipShape(shape)
            .overlay(shape.strokeBorder(MV.Tone.hairline, lineWidth: MV.Stroke.surface).allowsHitTesting(false))
    }
}

extension View {
    /// MAVIS list column (prototype .list.lpanel): no fill, a 1 pt outline at 3% white with 12 pt top corners, running
    /// off the window's bottom edge (its bottom line is never seen).
    func mvListPanel() -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: MV.Radius.list, topTrailingRadius: MV.Radius.list, style: .continuous)
        return background(alignment: .top) {
            shape.strokeBorder(MV.Tone.listEdge, lineWidth: MV.Stroke.list)
                .padding(.bottom, -(MV.Space.gutter + MV.Stroke.list))
                .allowsHitTesting(false)
        }
    }
}

/// CSS `box-shadow: inset 1px 1px 0 #1f1f1f`: a 1px line along the top and left that follows the corner.
struct PanelEdge: View {
    let radius: CGFloat
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            let outer = UnevenRoundedRectangle(topLeadingRadius: radius).path(in: r)
            let inner = UnevenRoundedRectangle(topLeadingRadius: radius).path(in: r).offsetBy(dx: 1, dy: 1)
            Path { p in p.addPath(outer); p.addPath(inner) }.fill(C.v4, style: FillStyle(eoFill: true))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius))
        }
    }
}

/// One message at a time, bottom centre; goes away by itself (web: toast).
struct Toast: View {
    @EnvironmentObject var s: Store
    let text: String
    var body: some View {
        Text(text).font(F.font(14, .medium)).foregroundStyle(C.i12).lineLimit(2).multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v2))
            .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
            .shadow(color: .black.opacity(MV.on ? 0 : 0.5), radius: 8, y: 4)
            .frame(maxWidth: 480).padding(.bottom, 24)
            .task(id: text) { try? await Task.sleep(for: .seconds(4)); if s.toast == text { s.toast = nil } }
            .onTapGesture { s.toast = nil }
    }
}

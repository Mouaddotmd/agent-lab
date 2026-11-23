// Home, the same page with or without agents (web: homeView). Phase 1 has no agents, so every
// section shows its empty state, like Discord's empty Friends page.
import SwiftUI
import AppKit

struct HomePage: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    @State private var ask = ""
    @State private var filter = "all"
    @State private var ideasHidden = false
    @State private var ideaAt = 0
    @State private var pickId: String?
    @State private var pickOpen = SnapshotMode.on && ProcessInfo.processInfo.environment["SNAP_PICK"] == "1"
    /// Getting started: hidden for now (flip to bring it back).
    static let showsGettingStarted = false
    /// web: scope, sorted by state then most recent
    var scope: [Agent] { s.agents.enumerated().sorted { lastAt($0.element) != lastAt($1.element) ? lastAt($0.element) > lastAt($1.element) : $0.offset < $1.offset }.map(\.element) }
    /// web: homePick
    var pick: Agent? { scope.first { $0.id == pickId } ?? scope.first }
    var greeting: String { let h = Calendar.current.component(.hour, from: Date()); return h < 5 ? "Good evening" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening" }
    let quick: [(String, String, String)] = [("branch", "Fix a bug", "Fix this bug: "), ("check", "Review changes", "Review my uncommitted changes and point out bugs, risky changes and missing tests."), ("search", "Research", "Research "), ("pen", "Write tests", "Write tests for "), ("book", "Plan", "Plan how to ")]

    var body: some View {
        HStack(spacing: 0) {
            let column = VStack(alignment: .leading, spacing: 0) {
                // Greeting (6px optical nudge so its capitals line up with "Right now")
                VStack(alignment: .leading, spacing: 8) {
                    Line(greeting, 28, .semibold, C.i12, tracking: -0.56)
                    Line("All quiet. Your agents are ready when you are.", 14, .regular, C.i10)
                }
                .padding(.top, 6)
                askBox.padding(.top, 20)
                // Agents
                VStack(alignment: .leading, spacing: 8) {
                    agentsBar
                    let list = filter == "all" ? scope : []                // nothing works or waits until runs are wired
                    if list.isEmpty {
                        Para(text: filter == "working" ? "Nobody is working right now." : filter == "needs" ? "Nobody is waiting for you." : "No agents yet. Make one, or add a ready-made one from Discover.", size: 14, weight: .regular, color: C.i10)
                            .opacity(s.loaded ? 1 : 0)                 // same card, blank until your agents have loaded
                            .padding(.horizontal, 17).padding(.vertical, 21).frame(maxWidth: .infinity, alignment: .leading).card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                                if i > 0 { Rectangle().fill(C.divider).frame(height: 1) }
                                AgentRow(agent: a, home: s.home).onTapGesture { s.openChat(a.id) }
                            }
                        }
                        .padding(1).clipShape(RoundedRectangle(cornerRadius: R.card)).card()
                    }
                }
                .split()
                if Self.showsGettingStarted && !ideasHidden { ideas.split() }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32).padding(.top, 16).padding(.bottom, 48)
            Group {
                if SnapshotMode.on { GeometryReader { _ in column.fixedSize(horizontal: false, vertical: true) }.clipped() }
                else { ScrollView { column }.scrollIndicators(.never) }
            }
            .frame(maxWidth: .infinity)
            if panes.showsNow {
                RightNow().frame(width: panes.width(PaneID.now))
                    .overlay(alignment: .leading) { SplitHandle(pane: PaneID.now).offset(x: -4.5) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, gutter)
    }

    // The ask box: a #111 field in a #0a0a0a well; starters under it (web: .sx).
    var askBox: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if ask.isEmpty { Line("Ask \(pick?.name ?? "an agent") to fix, build, review or research something…", 16, .regular, C.i9) }
                    if !SnapshotMode.on {
                        TextField("", text: $ask, axis: .vertical).textFieldStyle(.plain).font(F.font(16, .regular)).foregroundStyle(C.i12).lineLimit(1...6)
                            .onSubmit { submitAsk() }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4).frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                HStack(spacing: 8) {
                    if let pick {
                        // The agent this box talks to; a menu to pick another (web: sx-who + pick-menu)
                        WhoPicker(pick: pick, open: $pickOpen).help("Choose an agent")
                            .anchorPreference(key: PickAnchor.self, value: .bounds) { $0 }
                    } else {
                        Hover { h in
                            Button { s.newAgentOpen = true } label: {
                                HStack(spacing: 8) { Icon("plus", 16).foregroundStyle(h ? C.i12 : C.i10); Line("Make an agent", 14, .medium, h ? C.i12 : C.i10) }
                                    .padding(.leading, 4).padding(.trailing, 8).frame(height: 28)
                                    .background(Capsule().fill(h ? C.v3 : .clear)).contentShape(Capsule())
                            }.buttonStyle(.plain)
                        }.help("Make your first agent")
                    }
                    Spacer(minLength: 0)
                    Hover { h in
                        Button { submitAsk() } label: {
                            Icon("send", 16).foregroundStyle(C.v1).frame(width: 32, height: 32).background(Circle().fill(C.i12).opacity(h ? 0.88 : 1)).contentShape(Circle())
                        }.buttonStyle(.plain)
                    }.tip("Send", "↵", edge: .top)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16).frame(height: 56)
            }
            .background(RoundedRectangle(cornerRadius: R.card).fill(C.v2))
            .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edgeControl, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            // As many starters as fit, in order (never a half-cut button).
            tray.padding(8)
        }
        .card(C.v1)
        // The agent list drops down from the chip, 6 below it, left-aligned with it, drawn over everything on the page
        // (placed here, on the box's outermost layer, so nothing in the box paints over it).
        .overlayPreferenceValue(PickAnchor.self) { anchor in
            GeometryReader { g in
                if pickOpen, let anchor, let pick {
                    let chip = g[anchor]
                    PickMenu(scope: scope, chosen: pick.id, open: $pickOpen) { pickId = $0 }
                        .offset(x: chip.minX, y: chip.maxY + 6)
                }
            }
        }
        .zIndex(1)
    }
    /// As many starters as fit whole, in order, at least two. One measuring pass (FittingRow): ViewThatFits laid out
    /// four versions of this row on every resize frame and every change in the app (17 Nov: most of Home's cost).
    var tray: some View {
            FittingRow(spacing: 4, minimum: 2) {
                ForEach(Array(quick.enumerated()), id: \.offset) { _, q in
                    Hover { h in
                        Button { ask = q.2; s.newAgentOpen = false } label: {
                            HStack(spacing: 8) { Icon(q.0, 15).foregroundStyle(h ? C.i12 : C.i10); Line(q.1, 14, .medium, h ? C.i12 : C.i10) }
                                .padding(.horizontal, 12).frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: R.xs).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// web: homeForm submit — sends to the picked agent and opens its chat; with no agent, the form.
    func submitAsk() {
        let t = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = pick else { s.newAgentOpen = true; return }
        guard !t.isEmpty else { return }
        ask = ""
        s.openChat(p.id)
        s.sendMessage(p.id, t)
    }

    // Agents: icon, title, dot, tabs, New agent (web: .agbar).
    var agentsBar: some View {
        HStack(spacing: 0) {
            Icon("agents", 18).foregroundStyle(C.i10).padding(.trailing, 8)
            Line("Agents", 16, .semibold)
            Circle().fill(C.v6).frame(width: 4, height: 4).padding(.horizontal, 12)
            HStack(spacing: 4) {
                // Full names when they fit, then shorter ones: never a cut-off tab.
                FirstFit {
                    HStack(spacing: 4) { tab("all", "All"); tab("working", "Working"); tab("needs", "Waiting for you") }
                    HStack(spacing: 4) { tab("all", "All"); tab("working", "Working"); tab("needs", "Waiting") }
                    HStack(spacing: 4) { tab("all", "All"); tab("needs", "Waiting") }
                }
            }
            Spacer(minLength: 0)
            SmallSecondaryButton(title: "New agent") { s.newAgentOpen = true }
        }
        .frame(height: 44)
    }
    func tab(_ id: String, _ label: String) -> some View {
        let on = filter == id
        return Hover { h in
            Button { filter = id } label: {
                Line(label, 14, .medium, on || h ? C.i12 : C.i10).padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(on ? C.v4 : h ? C.v3 : .clear)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    // Getting started: title and line, then the four actions as a 2×2 grid (web: .sx-ideas).
    var ideas: some View {
        let rows: [(String, String, () -> Void)] = [
            ("plug", "Connect GitHub", { s.go(.apps) }), ("chat", "Message one of your agents", { s.go(.messages) }),
            ("folder", "Create a workspace for a project", { s.createWorkspaceOpen = true }),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Line("Getting started", 16, .semibold)
                Spacer(minLength: 0)
                navBtn(Icon("chev", 14).rotationEffect(.degrees(90))) { ideaAt += 1 }.tip("Previous ideas")
                navBtn(Icon("chev", 14).rotationEffect(.degrees(-90))) { ideaAt += 1 }.tip("More ideas")
                navBtn(Icon("x", 12)) { ideasHidden = true }.tip("Hide ideas")
            }
            .padding(.horizontal, 4).frame(height: 24)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Line("Your first week in Agent Lab", 16, .semibold)
                    Line("A few things that make your agents more useful. Do them in any order.", 14, .regular, C.i10)
                }
                .padding(.horizontal, 4)
                IdeaGrid(rows: rows)
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }
    func navBtn<L: View>(_ label: L, _ action: @escaping () -> Void) -> some View {
        Hover { h in
            Button(action: action) {
                label.foregroundStyle(h ? C.i12 : C.i10).frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// The 2×2 grid, two equal columns while both fit their full labels; narrower, one column of four rows.
struct IdeaGrid: View {
    let rows: [(String, String, () -> Void)]
    var body: some View {
        let need = { (i: Int) -> CGFloat in 12 + 20 + 12 + textWidth(rows[i].1) + 12 + 16 + 8 }
        let left = max(need(0), need(2)), right = max(need(1), need(3))
        FirstFit {
            // Equal halves when there's room; a column never narrower than its longest label (CSS `1fr 1fr`).
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) { row(0); row(2) }.frame(minWidth: left, maxWidth: .infinity)
                VStack(spacing: 4) { row(1); row(3) }.frame(minWidth: right, maxWidth: .infinity)
            }
            VStack(spacing: 4) { ForEach(0..<rows.count, id: \.self) { row($0) } }
        }
    }
    func row(_ i: Int) -> some View { IdeaRow(icon: rows[i].0, title: rows[i].1, action: rows[i].2) }
    func textWidth(_ s: String) -> CGFloat {
        guard let f = NSFont(name: "AnthropicSansText-Medium", size: 14) else { return 0 }
        return (s as NSString).size(withAttributes: [.font: f]).width
    }
}
struct IdeaRow: View {
    let icon: String; let title: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 12) {
                    Icon(icon, 20).foregroundStyle(C.i10)
                    Line(title, 14, .medium).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
                    Icon("chev", 16).rotationEffect(.degrees(-90)).foregroundStyle(C.i10).opacity(h ? 1 : 0.6).offset(x: h ? 2 : 0)
                        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: h)
                }
                .padding(.leading, 12).padding(.trailing, 8).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// Right now: 360 wide, a line on its left; nothing running yet (web: .now-col).
/// What your agents are doing this minute: who needs your OK first, then who's working, each opening its chat.
/// Nothing going on: one quiet line.
struct RightNow: View {
    @EnvironmentObject var s: Store
    var body: some View {
        let busy = s.agents.filter { ["needs", "working"].contains(s.state(of: $0)) }
            .sorted { (s.state(of: $0) == "needs" ? 0 : 1) < (s.state(of: $1) == "needs" ? 0 : 1) }
        VStack(alignment: .leading, spacing: 16) {
            Line("Right now", 16, .semibold, C.i12, tracking: -0.16)
            if busy.isEmpty {
                Line("Nothing is running.", 14, .regular, C.i10)
            } else {
                VStack(spacing: 2) {
                    ForEach(busy) { a in
                        let needs = s.state(of: a) == "needs"
                        let run = s.runs["agent:\(a.id)"]
                        let place = run?.by != nil ? s.workspaces.first { w in w.channels.contains { w.conv($0.id) == run?.conv } }.map { "in \($0.name)" } : nil
                        Hover { h in
                            Button { s.openChat(a.id) } label: {
                                HStack(spacing: 12) {
                                    Avatar(agent: a, size: 32, status: false)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Line(a.name, 14, .medium, C.i12)
                                        Text(needs ? "Waiting for your OK" : [run?.activity ?? "Working", place].compactMap { $0 }.joined(separator: " · "))
                                            .font(F.font(12, .regular)).foregroundStyle(needs ? WAIT_TEXT : C.i10).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Circle().fill(needs ? WAIT : Color(0xe0a100)).frame(width: 8, height: 8)
                                }
                                .padding(.horizontal, 8).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, -8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.leading, 17).padding(.trailing, 11).padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// The Home split: 40 above, a 1px line at 60%, 40 below (web: .ag-sec / .sx-ideas border-top).
    func split() -> some View {
        VStack(spacing: 0) { Rectangle().fill(C.split).frame(height: 1); self.padding(.top, 40) }.padding(.top, 40)
    }
}

/// web: lastAt — newest message, last run, or when it was made (ms).
func lastAt(_ a: Agent) -> Double { a.last?.at ?? a.createdAt ?? 0 }
let OPS = ["claude-code": "Claude Code", "codex": "Codex", "mavis": "Mavis"]

/// An operator's own logo (transparent PNGs in native/Assets/operators, from @lobehub/icons: Claude Code's pixel crab,
/// the Codex cloud). Its name shows on hover and to VoiceOver. One with no logo (Mavis) falls back to its name.
struct OpLogo: View {
    let op: String?; var size: CGFloat = 16
    var body: some View {
        let name = OPS[op ?? ""] ?? op ?? ""
        Group {
            if let img = OpLogo.image(op) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: size, height: size)
            }
            else { Line(name, 12, .medium, C.i10) }
        }
        .tip(name).accessibilityElement().accessibilityLabel(name)
    }
    nonisolated(unsafe) static var cache: [String: NSImage] = [:]
    static func image(_ op: String?) -> NSImage? {
        guard let op, ["claude-code", "codex"].contains(op) else { return nil }
        if let hit = cache[op] { return hit }
        // In the app: its Resources. Tools run from native/: Assets/operators.
        let urls = [Bundle.main.url(forResource: op, withExtension: "png"),
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/operators/\(op).png"),
                    URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("../Assets/operators/\(op).png")]
        guard let img = urls.compactMap({ $0 }).lazy.compactMap({ NSImage(contentsOf: $0) }).first else { return nil }
        cache[op] = img
        return img
    }
}

/// A face with its status dot (web: avatar). The idle dot is a small crescent, like Discord's.
/// An agent's picture: its tool's logo on a dark rounded square. Circles are for people (you); a square says "agent"
/// at a glance, as Discord and Slack do for bots. A tool with no logo shows the agent's initial.
struct Avatar: View {
    let agent: Agent; var size: CGFloat = 40; var ring: Color = C.v2; var status = true
    static func radius(_ size: CGFloat) -> CGFloat { (size * 0.28).rounded() }
    var body: some View {
        RoundedRectangle(cornerRadius: Avatar.radius(size), style: .continuous).fill(C.v3)
            .frame(width: size, height: size)
            .overlay {
                if OpLogo.image(agent.operator) != nil { OpLogo(op: agent.operator, size: (size * 0.6).rounded()) }
                else { Text(agent.name.prefix(1).uppercased()).font(F.font((size * 0.42).rounded(), .medium)).foregroundStyle(C.i10) }
            }
            .accessibilityElement().accessibilityLabel(agent.name)
            .overlay(alignment: .bottomTrailing) {
                if status {
                    let d = max(10, size * 0.3)
                    Canvas { ctx, sz in
                        let c = CGRect(origin: .zero, size: sz)
                        ctx.fill(Path(ellipseIn: c), with: .color(ring))
                        // inset 3px -2px shadow, turned −30° (web: .st.idle i)
                        ctx.translateBy(x: sz.width / 2, y: sz.height / 2); ctx.rotate(by: .degrees(-30)); ctx.translateBy(x: -sz.width / 2, y: -sz.height / 2)
                        let moon = Path(ellipseIn: c).subtracting(Path(ellipseIn: c.offsetBy(dx: 3, dy: -2)))
                        ctx.fill(moon, with: .color(C.i9))
                    }
                    .frame(width: d, height: d)
                    .background(Circle().fill(ring).padding(-2))
                    .offset(x: 2, y: 2)
                }
            }
    }
}

/// One agent on Home: face, name with its tool and folder, what it did last; Ready, or Chat and More on hover (web: .hx-row.dr).
struct AgentRow: View {
    @EnvironmentObject var s: Store
    let agent: Agent; let home: String
    var outcome: String { let t = lastAt(agent); return t > 0 ? "Idle · last worked \(ago(Date(timeIntervalSince1970: t / 1000)))" : "Ready for its first task" }
    var folder: String { ((agent.cwd ?? home) as NSString).lastPathComponent }
    var body: some View {
        Hover { h in
            HStack(spacing: 12) {
                Avatar(agent: agent, size: 36, ring: h ? C.v3 : C.v2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Line(agent.name, 16, .semibold)
                        Line(folder, 14, .regular, C.i9).padding(.leading, 16)
                    }
                    Line(outcome, 14, .regular, C.i10)
                }
                Spacer(minLength: 0)
                if h && !SnapshotMode.on {
                    HStack(spacing: 4) {
                        RowAction(icon: "chat", label: "Open chat") { s.openChat(agent.id) }
                        AgentMenu(agent: agent).background(Circle().fill(C.v3))
                    }
                } else {
                    Line("Ready", 12, .medium, C.i10).padding(.horizontal, 8).frame(height: 24).background(Capsule().fill(C.v4))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).frame(height: 72)
            .background(h ? Color.white(0.05) : .clear).contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine).accessibilityLabel("Open \(agent.name)")
    }
}
struct RowAction: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Icon(icon, 18).foregroundStyle(h ? C.i12 : C.i10).frame(width: 32, height: 32)
                    .background(Circle().fill(h ? C.v4 : C.v3)).contentShape(Circle())
            }.buttonStyle(.plain).tip(label).accessibilityLabel(label)
        }
    }
}

/// The agent the ask box talks to, with a menu to pick another (web: .sx-who + .pick-menu).
struct WhoPicker: View {
    let pick: Agent; @Binding var open: Bool
    @State private var h = false
    var body: some View {
        Button { if Date().timeIntervalSince(PickMenu.closedAt) > 0.3 { open.toggle() } } label: {
            HStack(spacing: 8) {
                Avatar(agent: pick, size: 22, ring: C.v2, status: false)
                Line(pick.name, 14, .medium, h || open ? C.i12 : C.i10)
                Icon("chev", 12).foregroundStyle(h || open ? C.i12 : C.i10).rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.leading, 4).padding(.trailing, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: R.card).fill(h || open ? C.v3 : .clear)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).fixedSize()
        .onHover { h = $0 }
        .accessibilityLabel("Choose an agent, \(pick.name)")
    }
}

/// The agents you can ask (web: .pick-menu): face, name, its operator. Closes on a choice, Esc or a click outside.
struct PickMenu: View {
    let scope: [Agent]; let chosen: String; @Binding var open: Bool
    /// One more row at the end, after a line (icon, title, action): "New agent" in the invite list.
    var extra: (icon: String, title: String, action: () -> Void)? = nil
    let choose: (String) -> Void
    @State private var inside = false
    @State private var monitor: Any?
    /// Its height, so it can be placed exactly (rows 40, 2 apart, 4 inside; the extra row adds a line and a row).
    static func height(rows: Int, extra: Bool = false) -> CGFloat {
        let n = rows + (extra ? 1 : 0)
        return 8 + CGFloat(n) * 40 + CGFloat(max(0, n - 1)) * 2 + (extra && rows > 0 ? 5 : 0)
    }
    @MainActor static var closedAt = Date.distantPast      // a click on the picker that just closed it doesn't reopen it
    var body: some View {
        VStack(spacing: 2) {
            ForEach(scope) { a in
                Hover { h in
                    Button { choose(a.id); open = false } label: {
                        HStack(spacing: 12) {
                            Avatar(agent: a, size: 24, ring: C.v1, status: false)
                            Line(a.name, 14, .medium, C.i12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(a.id == chosen ? C.v4 : h ? C.v3 : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if let extra {
                if !scope.isEmpty { Rectangle().fill(C.divider).frame(height: 1).padding(.vertical, 2) }
                Hover { h in
                    Button { open = false; extra.action() } label: {
                        HStack(spacing: 12) {
                            Icon(extra.icon, 16).foregroundStyle(C.i10).frame(width: 24, height: 24)
                            Line(extra.title, 14, .medium, C.i12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(4).frame(minWidth: 240).fixedSize()
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edgeControl, lineWidth: 1))
        .floatShadow()
        .onHover { inside = $0 }
        .onExitCommand { open = false }
        .onAppear {
            // A click anywhere else closes it (the picker button's own click toggles it, so leave that one alone).
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { e in
                if e.type == .keyDown { if e.keyCode == 53 { DispatchQueue.main.async { open = false }; return nil }; return e }
                if !inside { PickMenu.closedAt = Date(); DispatchQueue.main.async { if open { open = false } } }
                return e
            }
        }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
    }
}

/// Children in a row, left to right, as many as fit whole (never a half-cut one), at least `minimum`. Each child is
/// measured once per layout; the ones that don't fit are placed out of sight.
struct FittingRow: Layout {
    var spacing: CGFloat = 4
    var minimum = 1
    func makeCache(subviews: Subviews) -> [CGSize] { subviews.map { $0.sizeThatFits(.unspecified) } }
    func updateCache(_ cache: inout [CGSize], subviews: Subviews) { cache = makeCache(subviews: subviews) }
    private func count(_ sizes: [CGSize], width: CGFloat) -> Int {
        var x: CGFloat = 0, n = 0
        for s in sizes { let next = x + (n > 0 ? spacing : 0) + s.width; if next > width + 0.5 { break }; x = next; n += 1 }
        return max(n, min(minimum, sizes.count))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        let h = cache.map(\.height).max() ?? 0
        guard let w = proposal.width, w.isFinite else { return CGSize(width: cache.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, cache.count - 1)), height: h) }
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        let n = count(cache, width: bounds.width)
        var x = bounds.minX
        for (i, v) in subviews.enumerated() {
            if i < n { v.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(cache[i])); x += cache[i].width + spacing }
            else { v.place(at: CGPoint(x: -100_000, y: bounds.midY), anchor: .leading, proposal: .zero) }
        }
    }
}

/// ViewThatFits(in: .horizontal) without its cost: the first child whose natural width fits is shown, the rest are
/// placed out of sight at zero size. Natural widths are measured when the children change, not on every layout, so a
/// window resize is one pass over the shown child (ViewThatFits measured every candidate on every frame).
struct FirstFit: Layout {
    func makeCache(subviews: Subviews) -> [CGSize] { subviews.map { $0.sizeThatFits(.unspecified) } }
    func updateCache(_ cache: inout [CGSize], subviews: Subviews) { cache = makeCache(subviews: subviews) }
    private func pick(_ cache: [CGSize], _ width: CGFloat?) -> Int {
        guard let width, width.isFinite else { return 0 }
        return cache.firstIndex { $0.width <= width + 0.5 } ?? max(0, cache.count - 1)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let i = pick(cache, proposal.width)
        return subviews[i].sizeThatFits(ProposedViewSize(width: proposal.width.map { $0.isFinite ? $0 : cache[i].width }, height: proposal.height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        let i = pick(cache, bounds.width)
        for (k, v) in subviews.enumerated() {
            if k == i { v.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
            else { v.place(at: CGPoint(x: -100_000, y: bounds.minY), proposal: .zero) }
        }
    }
}

/// Where the agent chip is, so its list can open right under it from outside the box.
struct PickAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

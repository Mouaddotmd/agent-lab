import SwiftUI
import AppKit

// Layer 1: the ground and the 72px rail. Layer 2: the sheet (sidebar 256 · work · Right now 320).

struct RootView: View {
    @Environment(Lab.self) private var lab

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 1180
            ZStack {
                T.ground.ignoresSafeArea()
                if !lab.loaded {
                    VStack(spacing: 12) {
                        if let err = lab.startupError { Text("Agent Lab couldn’t start").type(T.t3); Text(err).type(T.t2, T.i11).multilineTextAlignment(.center).frame(maxWidth: 480) }
                        else { Loading(text: "Starting Agent Lab") }
                    }
                } else {
                    HStack(spacing: 0) {
                        Rail().frame(width: 72)
                        sheet(wide: wide)
                            .padding(.top, 8).padding(.trailing, 8).padding(.bottom, 8)
                    }
                }
                if let s = lab.sheet { LayerView(sheet: s).transition(.opacity) }
            }
            .overlay(alignment: .bottom) { if let t = lab.toast { Toast(text: t, error: lab.toastIsError) } }
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2), value: lab.toast)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: lab.sheet?.id)
            .environment(\.wide, wide)
        }
        .ignoresSafeArea()
        .background(WindowSetup())
        .task {
            lab.start()
            if TestDriver.enabled { await TestDriver.run(lab) }
        }
    }

    func sheet(wide: Bool) -> some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: 256).background(T.side)
            Hair(vertical: true)
            VStack(spacing: 0) {
                Strip()
                Work().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            .background(T.work)
            if wide && lab.showRightNow {
                Hair(vertical: true)
                RightNow().frame(width: 320).background(T.side)
            }
        }
        .overlay {
            if !wide && lab.nowOpen {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.6).onTapGesture { lab.nowOpen = false }
                    RightNow().frame(width: 320).background(T.side).shadow(color: .black.opacity(0.5), radius: 12, x: -12)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.i5, lineWidth: 0.5))
        .lift()
    }
}

private struct WideKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues { var wide: Bool { get { self[WideKey.self] } set { self[WideKey.self] = newValue } } }

/// A borderless-looking window you can drag by its rail, with the traffic lights over the rail.
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(T.ground)
            w.appearance = NSAppearance(named: .darkAqua)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Rail

struct Rail: View {
    @Environment(Lab.self) private var lab

    var body: some View {
        VStack(spacing: 8) {
            RailBtn(on: lab.scope == nil, help: "Home", dot: lab.scope != nil ? lab.approvals.count : 0) { lab.scope = nil; lab.tab = .all; lab.opq = ""; goHomeView() } label: { Icon(name: .home, size: 20) }
            RailBtn(plain: true, help: "Search everything  ⌘K") { lab.sheet = .search } label: { Icon(name: .search, size: 20) }
            Rectangle().fill(T.i5).frame(width: 32, height: 0.5)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(lab.workspaces) { w in
                        let n = lab.approvals.filter { p in lab.agent(p.agentId ?? "").flatMap { lab.workspace(of: $0)?.id } == w.id }.count
                        RailBtn(on: lab.scope == w.id, help: w.name, hue: Color(hex: w.color), dot: lab.scope == w.id ? 0 : n) {
                            lab.scope = w.id; lab.tab = .all; lab.opq = ""; goHomeView()
                        } label: { Text(initials(w.name)).type(T.t2, lab.scope == w.id ? T.i12 : T.i11) }
                    }
                    RailBtn(plain: true, help: "Add a workspace folder") { if let p = lab.chooseFolder("Add a workspace folder") { Task { await lab.addWorkspace(p) } } } label: { Icon(name: .plus, size: 20) }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
            RailBtn(plain: true, help: "Connections") { lab.nav = .connections } label: { Icon(name: .plug, size: 20) }
        }
        .padding(.top, 52).padding(.bottom, 12)
    }

    func goHomeView() { if case .chats(let op) = lab.nav { lab.nav = .chats(op) } else { lab.nav = .agents } }
    func initials(_ name: String) -> String {
        let s = String(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(2).map(Character.init))
        return s.isEmpty ? "··" : s.prefix(1).uppercased() + s.dropFirst()
    }
}

struct RailBtn<L: View>: View {
    var on = false
    var plain = false
    var help: String
    var hue: Color? = nil
    var dot = 0
    var action: () -> Void
    @ViewBuilder var label: () -> L
    @State private var over = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(on || over ? T.i12 : T.i10)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ring, lineWidth: 0.5))
                .shadow(color: .black.opacity(on ? 0.5 : 0), radius: 1, y: 1)
                .overlay(alignment: .bottomTrailing) {
                    if dot > 0 {
                        Text("\(dot)").type(T.t1, Color(hex: "#1a0f0a")).padding(.horizontal, 4).frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(T.wait)).padding(4).background(Capsule().fill(T.ground)).offset(x: 8, y: 8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { h in withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)) { over = h } }
        .help(help)
    }

    var fill: Color {
        if let hue { return on ? hue.mix(T.i2, 0.34) : hue.mix(T.i1, over ? 0.24 : 0.16) }
        if plain { return over ? T.i2 : .clear }
        return on || over ? T.i3 : T.i2
    }
    var ring: Color {
        if let hue { return on ? hue.mix(.black, 0.55) : hue.mix(T.i3, 0.30) }
        return on ? T.i6 : .clear
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(Lab.self) private var lab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(lab.currentWorkspace?.name ?? "Agent Lab").type(T.t3).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Button { lab.sheet = .search } label: { Icon(name: .search) }.buttonStyle(IconBtn()).help("Search everything  ⌘K")
                Button { lab.sheet = .newAgent(nil) } label: { Icon(name: .pen) }.buttonStyle(IconBtn()).help("New agent  ⌘N")
            }
            .padding(.leading, 16).padding(.trailing, 8).frame(height: 48).hairBottom()

            ScrollView {
                VStack(spacing: 0) {
                    let waiting = lab.waitingCount
                    NavRow(icon: .agents, title: "Agents", on: lab.nav == .agents) { lab.nav = .agents } trailing: { if waiting > 0 { Count(n: waiting).help("\(waiting) waiting for you") } }
                    NavRow(icon: .memory, title: "Memory", on: lab.nav == .memory) { lab.nav = .memory } trailing: { EmptyView() }
                    NavRow(icon: .plug, title: "Connections", on: lab.nav == .connections) { lab.nav = .connections } trailing: { EmptyView() }

                    let team = lab.team
                    let shown = Array(team.prefix(6))
                    SideLabel(title: "Team", key: "team") { lab.sheet = .newAgent(nil) }
                    if !lab.fold.contains("team") {
                        if shown.isEmpty { Meta("No agents yet").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8) }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in TeamRow(agent: a, index: i) }
                        if team.count > 6 {
                            NavRow(icon: .more, title: "\(team.count - 6) more", on: false, dim: true) { lab.tab = .all; lab.nav = .agents } trailing: { EmptyView() }
                        }
                    }

                    SideLabel(title: "Operators", key: "ops") { lab.nav = .connections }
                    if !lab.fold.contains("ops") {
                        ForEach(lab.sidebarOperators, id: \.self) { op in OperatorRow(op: op) }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
        }
    }
}

struct NavRow<Trail: View>: View {
    var icon: Ic
    var title: String
    var on: Bool
    var dim = false
    var action: () -> Void
    @ViewBuilder var trailing: () -> Trail
    @State private var over = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(name: icon).foregroundStyle(on ? T.i12 : T.i10).padding(.horizontal, 8)
                Text(title).type(T.t2, dim ? T.i10 : on || over ? T.i12 : T.i11).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            .padding(.horizontal, 4).frame(height: 32)
        }
        .buttonStyle(RowBtn(on: on))
        .onHover { over = $0 }
    }
}

struct SideLabel: View {
    @Environment(Lab.self) private var lab
    var title: String
    var key: String
    var add: () -> Void
    @State private var over = false
    var body: some View {
        let folded = lab.fold.contains(key)
        HStack {
            Button { if folded { lab.fold.remove(key) } else { lab.fold.insert(key) } } label: {
                HStack(spacing: 4) {
                    Icon(name: .chev, size: 12, weight: 2).rotationEffect(.degrees(folded ? -90 : 0))
                    Text(title)
                }
                .type(T.t1, over ? T.i12 : T.i10).frame(height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).onHover { over = $0 }
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: folded)
            Spacer()
            Button(action: add) { Icon(name: .plus, size: 14) }.buttonStyle(IconBtn(size: 24, radius: 4, hover: T.i2)).help(key == "team" ? "New agent" : "Connections")
        }
        .padding(.leading, 8).padding(.trailing, 4).frame(height: 32).padding(.top, 16)
    }
}

struct TeamRow: View {
    @Environment(Lab.self) private var lab
    var agent: Agent
    var index: Int
    @State private var over = false
    var body: some View {
        let on = lab.nav == .agent(agent.id)
        let st = lab.state(of: agent)
        Button { lab.open(agent) } label: {
            HStack(spacing: 8) {
                Avatar(agent, size: 32, state: st, ground: on ? T.i3 : over ? T.i2 : T.side)
                VStack(alignment: .leading, spacing: 0) {
                    Text(agent.name).type(T.t2, on || over ? T.i12 : T.i11).lineLimit(1)
                    Text(lab.status(of: agent)).type(T.t1, st == .waiting ? T.waitText : st == .failed ? T.failText : T.i10).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if over && index < 9 {
                    Text("⌘\(index + 1)").type(T.t1, T.i10).padding(.horizontal, 4).background(RoundedRectangle(cornerRadius: 4).fill(T.i3)).padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 4).frame(height: 44)
        }
        .buttonStyle(RowBtn(on: on))
        .onHover { over = $0 }
        .contextMenu {
            Button("Open") { lab.open(agent) }
            Button("Edit…") { lab.sheet = .editAgent(agent.id) }
            if agent.worktree != nil { Button("Review Changes") { lab.nav = .review(agent.id) } }
        }
    }
}

struct OperatorRow: View {
    @Environment(Lab.self) private var lab
    var op: String
    @State private var over = false
    var body: some View {
        let on = lab.nav == .chats(op)
        let live = lab.team.filter { $0.operator == op && lab.state(of: $0) == .working }.count
        let n = lab.chats[op] == nil ? nil : lab.visibleChats(op).count
        let sub = n.map { "\($0) \($0 == 1 ? "chat" : "chats")" } ?? "Chats on this Mac"
        Button { lab.opq = ""; lab.nav = .chats(op) } label: {
            HStack(spacing: 8) {
                OpTile(op: op, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Operators.name(op)).type(T.t2, on || over ? T.i12 : T.i11).lineLimit(1)
                    Text(sub + (live > 0 ? " · \(live) working" : "")).type(T.t1, T.i10).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4).frame(height: 44)
        }
        .buttonStyle(RowBtn(on: on))
        .onHover { over = $0 }
    }
}

// MARK: - Top bar

struct Strip: View {
    @Environment(Lab.self) private var lab
    @Environment(\.wide) private var wide

    var body: some View {
        HStack(spacing: 8) {
            title.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                let showing = wide ? lab.showRightNow : lab.nowOpen
                Button { withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)) { if wide { lab.showRightNow.toggle() } else { lab.nowOpen.toggle() } } } label: { Icon(name: .panel) }
                    .buttonStyle(IconBtn(on: showing)).help(showing ? "Hide Right now  ⌥⌘0" : "Show Right now  ⌥⌘0")
                extra
            }
        }
        .padding(.horizontal, 16).frame(height: 48).hairBottom()
    }

    @ViewBuilder var title: some View {
        switch lab.nav ?? .agents {
        case .agents:
            HStack(spacing: 0) {
                HStack(spacing: 8) { Icon(name: .agents); Text("Agents") }.type(T.t2)
                Circle().fill(T.i6).frame(width: 4, height: 4).padding(.horizontal, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { ForEach(AgentsTab.allCases) { t in TabBtn(tab: t) } }
                }
            }
        case .agent(let id):
            if let a = lab.agent(id) {
                HStack(spacing: 8) {
                    Avatar(a, size: 24, state: lab.state(of: a), ground: T.work)
                    Text(a.name).type(T.t2).lineLimit(1)
                    Text(lab.state(of: a).label).type(T.t2, T.i10).lineLimit(1)
                }
            }
        case .chats(let op):
            HStack(spacing: 8) {
                OpTile(op: op, size: 24)
                Text(Operators.name(op)).type(T.t2).fixedSize()
                if let c = lab.chat(op, lab.selectedChat[op]) { Text(c.title).type(T.t2, T.i10).lineLimit(1) }
            }
        case .review(let id):
            HStack(spacing: 8) {
                if let a = lab.agent(id) { Avatar(a, size: 24, state: lab.state(of: a), ground: T.work) }
                Text("Review changes").type(T.t2).fixedSize()
                Text(lab.agent(id)?.branch ?? "").type(T.t2, T.i10).lineLimit(1)
            }
        case .memory: Text("Memory").type(T.t2)
        case .connections: Text("Connections").type(T.t2)
        }
    }

    @ViewBuilder var extra: some View {
        switch lab.nav ?? .agents {
        case .agents:
            let n = lab.waitingCount
            Button { lab.sheet = .newAgent(nil) } label: { Icon(name: .plus, size: 14, weight: 2); Text("New agent") }
                .buttonStyle(Btn(kind: lab.tab == .waiting && n > 0 ? .second : .primary))
        case .agent(let id):
            Button { lab.sheet = .editAgent(id) } label: { Icon(name: .more) }.buttonStyle(IconBtn()).help("Edit")
        case .chats(let op):
            if let c = lab.chat(op, lab.selectedChat[op]) {
                Button("Hand off") { lab.sheet = .handoff(c) }.buttonStyle(Btn(kind: .second))
                Button("Make this an agent") { lab.sheet = .promote(c) }.buttonStyle(Btn(kind: .primary))
            }
        case .review(let id):
            if let a = lab.agent(id) {
                Button("Discard") { lab.discard(a) }.buttonStyle(Btn(kind: .danger))
                Button("Ask for changes") { lab.inputs["agent:\(a.id)"] = "About your changes: "; lab.open(a) }.buttonStyle(Btn(kind: .second))
                Button("Merge into \(a.baseBranch ?? "main")") { Task { await lab.merge(a) } }.buttonStyle(Btn(kind: .primary)).disabled(lab.merging)
            }
        default: EmptyView()
        }
    }
}

struct TabBtn: View {
    @Environment(Lab.self) private var lab
    var tab: AgentsTab
    @State private var over = false
    var body: some View {
        let on = lab.tab == tab
        Button { lab.tab = tab; lab.nav = .agents } label: {
            HStack(spacing: 8) {
                Text(tab.label).type(T.t2, on || over ? T.i12 : T.i11)
                if tab == .waiting, lab.waitingCount > 0 { Count(n: lab.waitingCount) }
            }
            .padding(.horizontal, 12).frame(height: 32).fixedSize()
        }
        .buttonStyle(RowBtn(on: on, hover: T.i2, onFill: T.i3))
        .onHover { over = $0 }
    }
}

// MARK: - Right now

struct RightNow: View {
    @Environment(Lab.self) private var lab
    @Environment(\.wide) private var wide

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Right now").type(T.t2)
                Spacer()
                if !wide { Button { lab.nowOpen = false } label: { Icon(name: .x) }.buttonStyle(IconBtn()) }
            }
            .padding(.horizontal, 16).frame(height: 48).hairBottom()
            ScrollView {
                VStack(spacing: 12) {
                    let runs = lab.runs.values.filter { r in r.agentId.map { id in lab.agent(id).map(lab.inScope) ?? false } ?? true }.sorted { $0.startedAt < $1.startedAt }
                    ForEach(runs, id: \.key) { r in LiveCard(run: r) }
                    if runs.isEmpty { Empty(title: "Nothing is running", sub: "Agents show up here while they work") }
                }
                .padding(12)
            }
            .scrollIndicators(.never)
        }
    }
}

struct LiveCard: View {
    @Environment(Lab.self) private var lab
    var run: Run
    var body: some View {
        let a = run.agentId.flatMap { lab.agent($0) }
        let chat = run.chat.flatMap { lab.chat($0.operator, $0.id) }
        Button { open(a) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if let a { Avatar(a, size: 40, state: lab.state(of: a), ground: T.i2) } else { OpTile(op: run.operator ?? "claude-code", size: 40) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a?.name ?? chat.map { clip($0.title, 40) } ?? Operators.name(run.operator ?? "")).type(T.t2).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("\(run.activity ?? "Working") · \(since(run.startedAt))").type(T.t1, T.i10).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    OpTile(op: run.operator ?? "claude-code", size: 24)
                }
                .padding(12)
                if let p = run.preview, !p.isEmpty {
                    Text(p).type(T.t1, T.i11).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
                        .padding(4)
                        .background(Color.black.opacity(0.14))
                        .hairTop()
                }
            }
            .surface(T.i2, ring: T.i6, radius: 12)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .lift()
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }

    func open(_ a: Agent?) {
        lab.nowOpen = false
        if let a { lab.open(a) } else if let c = run.chat { lab.selectedChat[c.operator] = c.id; lab.nav = .chats(c.operator) }
    }
}

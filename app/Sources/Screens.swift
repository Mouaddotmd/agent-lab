import SwiftUI

struct Work: View {
    @Environment(Lab.self) private var lab
    var body: some View {
        switch lab.nav ?? .agents {
        case .agents: AgentsView()
        case .memory: MemoryView()
        case .connections: ConnectionsView()
        case .agent(let id): AgentView(id: id).id(id)
        case .chats(let op): OperatorView(op: op).id(op)
        case .review(let id): ReviewView(id: id).id("\(id)-\(lab.reviewTick)")
        }
    }
}

/// The 800px reading column with the 32px gutter.
struct Col<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 48)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0, x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, w), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + z.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .init(z)); x += z.width + spacing; row = max(row, z.height)
        }
    }
}

// MARK: - Agents

struct AgentsView: View {
    @Environment(Lab.self) private var lab

    var body: some View {
        let scope = lab.scopedAgents
        if lab.agents.isEmpty { EmptyHero() }
        else if lab.tab == .waiting { waiting }
        else {
            Col {
                let list = scope.filter(filter).sorted { (lab.state(of: $0).rawValue, -($0.createdAt ?? 0)) < (lab.state(of: $1).rawValue, -($1.createdAt ?? 0)) }
                if lab.tab == .all { hello(scope) }
                if lab.tab == .all && scope.isEmpty {
                    Empty(title: "No agents in this workspace yet", sub: "New agents made here work in this folder")
                } else if list.isEmpty {
                    lab.tab == .working ? Empty(title: "Nobody is working right now", sub: "Message an agent, or hand off work with ⌘K") : Empty(title: "Nothing here yet", sub: "Agents show up here when they finish")
                } else {
                    ForEach(AgentState.allCases, id: \.self) { s in
                        let group = list.filter { lab.state(of: $0) == s }
                        if !group.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                GroupHead(title: s.label, n: group.count)
                                ForEach(Array(group.enumerated()), id: \.element.id) { i, a in AgentRow(agent: a, last: i == group.count - 1) }
                            }
                            .padding(.top, 32)
                        }
                    }
                }
            }
        }
    }

    func filter(_ a: Agent) -> Bool {
        switch lab.tab {
        case .all: true
        case .working: lab.state(of: a) == .working
        case .waiting: lab.state(of: a) == .waiting
        case .done: [.done, .failed, .ready].contains(lab.state(of: a))
        }
    }

    @ViewBuilder func hello(_ scope: [Agent]) -> some View {
        let w = lab.waitingCount, k = scope.filter { lab.state(of: $0) == .working }.count
        let hr = Calendar.current.component(.hour, from: Date())
        Text(lab.scope == nil ? (hr < 12 ? "Morning." : hr < 18 ? "Afternoon." : "Evening.") : lab.currentWorkspace?.name ?? "").type(T.t5)
        HStack(spacing: 0) {
            if w > 0 {
                LinkText(text: "\(w) \(w == 1 ? "thing is" : "things are") waiting for you. ") { lab.tab = .waiting }
            } else { Text("Nothing is waiting for you. ") }
            Text(k > 0 ? "\(k) \(k == 1 ? "agent is" : "agents are") working." : "Nobody is working right now.")
        }
        .type(T.t3, T.i11).padding(.top, 4)
        if !scope.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(scope.sorted { lab.state(of: $0).rawValue < lab.state(of: $1).rawValue }) { a in Mate(agent: a) }
                }
                .padding(4)
            }
            .padding(.horizontal, -4).padding(.top, 24)
        }
    }

    var waiting: some View {
        Col {
            let aps = lab.approvals.filter { p in lab.agent(p.agentId ?? "").map(lab.inScope) ?? false }
            let ovs = lab.overlaps.filter { $0.agents.contains { lab.agent($0).map(lab.inScope) ?? false } }
            GroupHead(title: "Waiting for you", n: aps.count + ovs.count)
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(aps.enumerated()), id: \.element.id) { i, p in ApprovalCard(approval: p, primary: i == 0, withWho: true).padding(.leading, 44) }
                ForEach(ovs) { o in OverlapNotice(overlap: o) }
            }
            .padding(.top, 32)
            if aps.isEmpty && ovs.isEmpty { Empty(title: "Nothing is waiting for you", sub: "When an agent wants to change something, it asks here first") }
        }
    }
}

struct LinkText: View {
    var text: String
    var action: () -> Void
    @State private var over = false
    var body: some View {
        Button(action: action) { Text(text).foregroundStyle(T.waitText).underline(over, color: T.waitText) }
            .buttonStyle(.plain).onHover { over = $0 }
    }
}

struct Mate: View {
    @Environment(Lab.self) private var lab
    var agent: Agent
    var body: some View {
        let st = lab.state(of: agent)
        Button { lab.open(agent) } label: {
            VStack(spacing: 8) {
                ZStack { Halo(state: st); Avatar(agent, size: 64) }
                VStack(spacing: 0) {
                    Text(agent.name).type(T.t2).lineLimit(1)
                    Text(st.label).type(T.t1, T.i10).lineLimit(1)
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(PressStyle())
        .help("\(agent.name), \(st.label)")
    }
}

struct EmptyHero: View {
    @Environment(Lab.self) private var lab
    var body: some View {
        Col {
            VStack(spacing: 12) {
                Text("No agents yet").type(T.t4)
                Text("An agent is Claude Code or Codex with a name, a folder and a job of your choosing. It answers exactly as that tool does, and asks you before it changes anything.")
                    .type(T.t2, T.i11).multilineTextAlignment(.center).frame(maxWidth: 440)
                HStack(spacing: 8) {
                    Button("New agent") { lab.sheet = .newAgent(nil) }.buttonStyle(Btn(kind: .primary))
                    Button("Make one from a chat") { lab.nav = .chats("claude-code") }.buttonStyle(Btn())
                    Button("Bring in from Mavis") { lab.nav = .connections; Task { await lab.scanMavis() } }.buttonStyle(Btn())
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 48).padding(.horizontal, 16)
        }
    }
}

struct AgentRow: View {
    @Environment(Lab.self) private var lab
    var agent: Agent
    var last: Bool
    @State private var over = false
    var body: some View {
        let st = lab.state(of: agent)
        let where_ = lab.workspace(of: agent)?.name ?? (agent.cwd != nil && agent.cwd != lab.home ? agent.cwd!.lastPathComponent : "")
        HStack(spacing: 16) {
            Avatar(agent, size: 48, state: st, ground: over ? T.i2 : T.work)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) { Text(agent.name).type(T.t3).lineLimit(1); Tag(text: Operators.name(agent.operator)) }
                (Text(lab.status(of: agent)).foregroundStyle(st == .waiting ? T.waitText : st == .failed ? T.failText : T.i11)
                 + Text(lab.scope == nil && !where_.isEmpty ? " · \(where_)" : "").foregroundStyle(T.i10))
                    .font(T.font(T.t2)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if st == .waiting { Button("Review") { lab.open(agent) }.buttonStyle(Btn()) }
            else { Button { lab.open(agent) } label: { Icon(name: .pen).offset(y: 1) }.buttonStyle(RoundBtn()).help("Message \(agent.name)") }
        }
        .padding(.horizontal, 8).frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(over ? T.i2 : .clear))
        .overlay(alignment: .bottom) { if !last && !over { Rectangle().fill(T.i5).frame(height: 0.5).padding(.horizontal, 8) } }
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onTapGesture { lab.open(agent) }
        .onHover { h in withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)) { over = h } }
        .contextMenu {
            Button("Edit…") { lab.sheet = .editAgent(agent.id) }
            if agent.worktree != nil { Button("Review Changes") { lab.nav = .review(agent.id) } }
            Button("Remove…", role: .destructive) { lab.confirmRemove(agent) }
        }
    }
}

struct ApprovalCard: View {
    @Environment(Lab.self) private var lab
    var approval: Approval
    var primary: Bool
    var withWho: Bool
    var body: some View {
        let p = approval
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Badge(text: "Waiting for you").padding(.bottom, 4)
                if withWho, let a = lab.agent(p.agentId ?? "") {
                    Button { lab.open(a) } label: {
                        HStack(spacing: 8) { Avatar(a, size: 24); Text("\(a.name) wants to").type(T.t1, T.i10) }
                    }.buttonStyle(.plain)
                }
                Text("\(p.verb) \(p.line)").type(T.t3).fixedSize(horizontal: false, vertical: true)
                if let d = p.detail, d != p.line {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(clip(d, 400)).type(T.t1, T.waitText, mono: true).lineLimit(1).textSelection(.enabled)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.i3))
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            HStack(spacing: 8) {
                Button("Allow") { lab.answer(p, "allow") }.buttonStyle(Btn(kind: primary ? .primary : .second, raised: true))
                if p.canAlways == true { Button("Always allow") { lab.answer(p, "always") }.buttonStyle(Btn(raised: true)) }
                Button("Don’t allow") { lab.answer(p, "deny") }.buttonStyle(Btn(kind: .danger, raised: true))
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .surface(T.i2, ring: T.i6, radius: 16)
        .lift()
    }
}

struct OverlapNotice: View {
    @Environment(Lab.self) private var lab
    var overlap: Overlap
    var body: some View {
        let names = overlap.agents.compactMap { lab.agent($0) }
        if names.count >= 2 {
            let a = names[0], b = names[1]
            let files = overlap.files.prefix(3).map(\.lastPathComponent).joined(separator: ", ") + (overlap.files.count > 3 ? " and \(overlap.files.count - 3) more" : "")
            VStack(alignment: .leading, spacing: 8) {
                Notice(icon: .branch, bold: "\(a.name) and \(b.name) both changed \(files).", rest: " Merge one first; the other then updates from it instead of conflicting.")
                HStack(spacing: 8) {
                    Button("Review \(a.name)") { lab.nav = .review(a.id) }.buttonStyle(Btn())
                    Button("Review \(b.name)") { lab.nav = .review(b.id) }.buttonStyle(Btn())
                }
            }
        }
    }
}

struct Notice: View {
    var icon: Ic? = nil
    var bold: String
    var rest: String = ""
    var info = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon { Icon(name: icon).padding(.top, 2) }
            (Text(bold).foregroundStyle(info ? T.i11 : T.waitText) + Text(rest)).type(T.t2, info ? T.i11 : T.waitText).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(info ? T.i11 : T.waitText)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .surface(info ? T.i2 : T.waitTint, ring: info ? T.i5 : T.waitEdge, radius: 12)
    }
}

// MARK: - Conversation pieces

/// Light formatting for replies: paragraphs, lists, code blocks, inline code and bold.
struct Rich: View {
    var text: String
    struct Block: Identifiable { let id: Int; let code: Bool; let text: String }
    var blocks: [Block] {
        var out: [Block] = []
        for (i, part) in text.components(separatedBy: "```").enumerated() {
            if i % 2 == 1 {
                var body = part
                if let nl = body.firstIndex(of: "\n"), body[..<nl].allSatisfy({ $0.isLetter || $0.isNumber || "+-_".contains($0) }) { body = String(body[body.index(after: nl)...]) }
                out.append(Block(id: out.count, code: true, text: body.trimmingCharacters(in: .newlines)))
            } else {
                for para in part.components(separatedBy: "\n\n") where !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(Block(id: out.count, code: false, text: para.trimmingCharacters(in: .newlines)))
                }
            }
        }
        return out
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { b in
                if b.code {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(b.text).type(T.t1, T.i12, mono: true).lineSpacing(6).padding(.horizontal, 12).padding(.vertical, 8).textSelection(.enabled)
                    }
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.ground))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(T.i5, lineWidth: 0.5))
                } else { paragraph(b.text) }
            }
        }
    }

    @ViewBuilder func paragraph(_ p: String) -> some View {
        let lines = p.components(separatedBy: "\n")
        let bullet = lines.allSatisfy { $0.range(of: #"^\s*[-*•]\s+"#, options: .regularExpression) != nil }
        let numbered = lines.allSatisfy { $0.range(of: #"^\s*\d+[.)]\s+"#, options: .regularExpression) != nil }
        if bullet || numbered {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(bullet ? "•" : "\(i + 1).").foregroundStyle(T.i11).frame(width: 16, alignment: .trailing)
                        Text(inline(l.replacingOccurrences(of: bullet ? #"^\s*[-*•]\s+"# : #"^\s*\d+[.)]\s+"#, with: "", options: .regularExpression)))
                    }
                }
            }
            .type(T.t2).textSelection(.enabled)
        } else {
            Text(inline(p)).type(T.t2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    func inline(_ s: String) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        for run in a.runs {
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { a[run.range].font = T.mono(T.t2 * 0.9); a[run.range].backgroundColor = T.i3 }
                if intent.contains(.stronglyEmphasized) { a[run.range].foregroundColor = T.i12 }
            }
        }
        return a
    }
}

enum Who { case me, them }

/// A message bubble: 16 radius with the 4px corner pointing at whoever said it.
struct Bubble: View {
    var who: Who
    var text: String
    var draft = false
    var body: some View {
        let mine = who == .me
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Rich(text: text)
            if draft { Cursor() }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous).fill(mine ? T.i4 : T.i2))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous).strokeBorder(mine ? T.i6 : T.i5, lineWidth: 0.5))
    }
}

struct Cursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            Rectangle().fill(T.i11).frame(width: 6, height: 14).padding(.leading, 2)
                .opacity(Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
    }
}

struct MessageRow<A: View>: View {
    var who: Who
    var text: String
    var meta: String?
    var cont: Bool
    var draft = false
    @ViewBuilder var avatar: () -> A
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if who == .them { avatar().opacity(cont ? 0 : 1) }
            VStack(alignment: who == .me ? .trailing : .leading, spacing: 4) {
                if let meta, !cont { Meta(meta).padding(.horizontal, 4) }
                Bubble(who: who, text: text, draft: draft)
            }
        }
        .modifier(CapWidth(fraction: 0.88, trailing: who == .me))
        .padding(.top, cont ? 4 : 16)
    }
}

/// Messages take at most 88% of the column and hug their text below that.
struct CapWidth: ViewModifier {
    var fraction: CGFloat
    var trailing: Bool
    func body(content: Content) -> some View { Capped(fraction: fraction, trailing: trailing) { content } }
}
struct Capped: Layout {
    var fraction: CGFloat
    var trailing: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        let w = proposal.width ?? 600
        let z = s.sizeThatFits(.init(width: w * fraction, height: nil))
        return CGSize(width: w, height: z.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let s = subviews.first else { return }
        let z = s.sizeThatFits(.init(width: bounds.width * fraction, height: nil))
        s.place(at: CGPoint(x: trailing ? bounds.maxX - z.width : bounds.minX, y: bounds.minY), proposal: .init(width: z.width, height: z.height))
    }
}

struct Step: View {
    var verb: String
    var text: String
    var error = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verb).type(T.t1, error ? T.failText : T.i11).fixedSize()
            Text(text).type(T.t1, error ? T.failText : T.i10, mono: true).lineLimit(1).truncationMode(.tail)
        }
        .padding(.leading, 52).padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The composer: 16 radius, send button inset 8. Return sends, Shift-Return adds a line.
struct Composer: View {
    @Environment(Lab.self) private var lab
    var key: String
    var placeholder: String
    var running: Bool
    var onSend: (String) -> Void
    @FocusState private var focused: Bool
    var body: some View {
        @Bindable var lab = lab
        let text = Binding(get: { lab.inputs[key] ?? "" }, set: { lab.inputs[key] = $0 })
        HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(T.i10), axis: .vertical)
                .textFieldStyle(.plain).type(T.t2).lineLimit(1...9)
                .focused($focused)
                .padding(.vertical, 6)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
                    submit(); return .handled
                }
            if running {
                Button { lab.stop(key) } label: { Icon(name: .stop, weight: 2) }.buttonStyle(SendStyle(stop: true)).help("Stop")
            } else {
                Button(action: submit) { Icon(name: .send, weight: 2).offset(y: -1) }.buttonStyle(SendStyle()).help("Send  ↵")
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .frame(minHeight: 48)
        .surface(T.i2, ring: focused ? T.i7 : T.i5, radius: 16)
        .lift()
        .frame(maxWidth: 736)
        .padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(T.work)
        .onAppear { if lab.inputs[key]?.isEmpty == false { focused = true } }
    }
    func submit() {
        let t = (lab.inputs[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !running else { return }
        lab.inputs[key] = ""
        onSend(t)
    }
}

struct SendStyle: ButtonStyle {
    var stop = false
    func makeBody(configuration: Configuration) -> some View { Inner(stop: stop, configuration: configuration) }
    struct Inner: View {
        var stop: Bool
        let configuration: Configuration
        @State private var over = false
        var body: some View {
            configuration.label.foregroundStyle(stop ? T.failText : T.i12)
                .frame(width: 32, height: 32)
                .surface(stop ? T.i3 : over ? T.i5 : T.i4, ring: T.i7, radius: 8).drop()
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .contentShape(Rectangle()).onHover { over = $0 }
        }
    }
}

// MARK: - An agent's conversation

struct AgentView: View {
    @Environment(Lab.self) private var lab
    var id: String

    var body: some View {
        if let a = lab.agent(id) {
            let key = "agent:\(a.id)"
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        thread(a, key).frame(maxWidth: 800).padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 16).frame(maxWidth: .infinity)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .onChange(of: (lab.messages[a.id]?.count ?? 0) + (lab.drafts[key]?.count ?? 0) + lab.approvals(for: a.id).count) { proxy.scrollTo("end", anchor: .bottom) }
                }
                Composer(key: key, placeholder: "Message \(a.name)", running: lab.runs[key] != nil) { t in Task { await lab.send(to: a.id, t) } }
            }
        } else {
            Col { Empty(title: "This agent was removed") }
        }
    }

    @ViewBuilder func thread(_ a: Agent, _ key: String) -> some View {
        let msgs = lab.messages[a.id] ?? []
        let draft = lab.drafts[key]
        let aps = lab.approvals(for: a.id)
        let run = lab.runs[key]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Avatar(a, size: 80, state: lab.state(of: a))
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.name).type(T.t4)
                    Text(a.job?.isEmpty == false ? a.job! : "Behaves exactly like \(Operators.name(a.operator)) normally does.").type(T.t2, T.i11).textSelection(.enabled)
                    FlowLayout { chips(a) }.padding(.top, 8)
                }
            }
            .padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading).hairBottom().padding(.bottom, 8)

            if msgs.isEmpty {
                Meta(a.sessionId != nil ? "This agent continues an existing \(Operators.name(a.operator)) session, so it already knows that conversation." : "Say what you need. \(a.name) works in \(a.cwd ?? lab.home).").padding(.top, 24)
            }
            let rows = MessageList.rows(msgs.map { ($0.role, $0.text, $0.verb, $0.at) })
            ForEach(rows) { r in
                switch r.role {
                case "user":
                    MessageRow(who: .me, text: r.text.count > 1500 ? String(r.text.prefix(1200)) + "\n\n…\(r.text.count - 1200) more characters of context" : r.text, meta: ago(r.at), cont: r.cont) { EmptyView() }
                case "assistant":
                    MessageRow(who: .them, text: r.text, meta: "\(a.name) · \(ago(r.at))", cont: r.cont) { Avatar(a, size: 40) }
                case "tool": Step(verb: r.verb ?? "", text: r.text)
                default: Step(verb: r.text == "Stopped." ? "Stopped" : "Error", text: r.text == "Stopped." ? "You stopped this run." : r.text, error: true)
                }
            }
            if let draft { MessageRow(who: .them, text: draft, meta: a.name, cont: false, draft: true) { Avatar(a, size: 40) } }
            ForEach(Array(aps.enumerated()), id: \.element.id) { i, p in ApprovalCard(approval: p, primary: i == 0, withWho: false).padding(.leading, 52).padding(.top, 12) }
            if let run, draft == nil, aps.isEmpty { Typing(text: "\(a.name) · \(run.activity ?? "Working")") }
        }
    }

    @ViewBuilder func chips(_ a: Agent) -> some View {
        Chip(text: "Runs on \(Operators.name(a.operator))") { lab.nav = .chats(a.operator) }
        Chip(text: lab.workspace(of: a)?.name ?? (a.cwd ?? "").lastPathComponent, icon: .folder) { lab.reveal(a.cwd) }
        if a.worktree != nil { Chip(text: "\(a.branch ?? "") · Review changes", icon: .branch) { lab.nav = .review(a.id) } }
        if let m = a.model, !m.isEmpty { Chip(text: Operators.claudeModels.first { $0.0 == m }?.1 ?? m) }
        Chip(text: Permission(rawValue: a.permission ?? "ask")?.label ?? Permission.ask.label)
        if let o = a.origin {
            if o.type == "chat", let op = o.operator, let ref = o.ref { Chip(text: "From: \(clip(o.title, 40))") { lab.selectedChat[op] = ref; lab.nav = .chats(op) } }
            else if let t = o.title { Chip(text: t) }
        }
    }
}

/// Consecutive messages from the same side join up: 4 apart, no repeated face or name.
enum MessageList {
    struct Row: Identifiable { let id: Int; let role: String; let text: String; let verb: String?; let at: Double?; let cont: Bool }
    static func rows(_ items: [(String, String, String?, Double?)]) -> [Row] {
        var prev: String? = nil
        return items.enumerated().map { i, m in
            let r = Row(id: i, role: m.0, text: m.1, verb: m.2, at: m.3, cont: (m.0 == "user" || m.0 == "assistant") && prev == m.0)
            if m.0 == "user" || m.0 == "assistant" { prev = m.0 }
            return r
        }
    }
}

// MARK: - An operator: its chats beside the open one

struct OperatorView: View {
    @Environment(Lab.self) private var lab
    @Environment(\.wide) private var wide
    var op: String
    @FocusState private var listFocused: Bool

    var body: some View {
        if lab.chats[op] == nil {
            Col { Loading(text: "Reading your \(Operators.name(op)) chats") }.task { await lab.loadChats(op) }
        } else {
            HStack(spacing: 0) {
                list.frame(width: wide ? 320 : 272).background(T.side)
                Hair(vertical: true)
                ChatDetail(chat: lab.chat(op, lab.selectedChat[op])).frame(maxWidth: .infinity)
            }
        }
    }

    var list: some View {
        @Bindable var lab = lab
        let scoped = lab.visibleChats(op)
        let q = lab.opq.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = scoped.filter { q.isEmpty || "\($0.title) \($0.cwd ?? "")".lowercased().contains(q) }
        var order: [String] = []
        var groups: [String: [Chat]] = [:]
        for c in shown { let k = c.cwd ?? ""; if groups[k] == nil { order.append(k) }; groups[k, default: []].append(c) }
        let users = lab.team.filter { $0.operator == op }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        OpTile(op: op)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Operators.name(op)).type(T.t2)
                            Meta("\(scoped.count) \(scoped.count == 1 ? "chat" : "chats")\(lab.scope == nil ? " on this Mac" : " in \(lab.currentWorkspace?.name ?? "")")")
                        }
                    }
                    .padding(.horizontal, 4)
                    if !users.isEmpty {
                        FlowLayout {
                            ForEach(users) { a in
                                Button { lab.open(a) } label: {
                                    HStack(spacing: 8) { Avatar(a, size: 32, state: lab.state(of: a), ground: T.i2); Text(a.name).type(T.t2) }
                                        .padding(.leading, 4).padding(.trailing, 12).frame(height: 40)
                                        .background(Capsule().fill(T.i2)).overlay(Capsule().strokeBorder(T.i5, lineWidth: 0.5))
                                }.buttonStyle(PressStyle())
                            }
                        }
                        .padding(.top, 12)
                    }
                    if !scoped.isEmpty {
                        HStack(spacing: 8) {
                            Icon(name: .search).foregroundStyle(T.i10)
                            TextField("", text: $lab.opq, prompt: Text("Find in \(Operators.name(op)) chats").foregroundStyle(T.i10)).textFieldStyle(.plain).type(T.t2)
                        }
                        .padding(.horizontal, 12).frame(height: 32)
                        .surface(T.i2, ring: T.i5, radius: 8)
                        .padding(.top, 16)
                    }
                    ForEach(order, id: \.self) { dir in
                        let cs = groups[dir] ?? []
                        VStack(alignment: .leading, spacing: 0) {
                            GroupHead(title: dir.isEmpty ? "No folder" : dir.lastPathComponent, n: cs.count, hair: false).padding(.horizontal, 4).padding(.bottom, 4).help(dir)
                            ForEach(cs.prefix(40)) { c in ChatRow(chat: c).id(c.id) }
                            if cs.count > 40 { Meta("\(cs.count - 40) older chats in this folder. Search finds them.").padding(.horizontal, 4).padding(.top, 16) }
                        }
                        .padding(.top, 24)
                    }
                    if scoped.isEmpty {
                        Empty(title: "No \(Operators.name(op)) chats\(lab.scope == nil ? "" : " in this workspace")", sub: op == "mavis" ? "Bring them in from Connections" : "They show up here as you use it")
                    } else if shown.isEmpty { Empty(title: "No chat matches “\(lab.opq)”") }
                }
                .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 24)
            }
            .scrollIndicators(.never)
            .focusable().focused($listFocused).focusEffectDisabled()
            .onKeyPress(.downArrow) { move(shown, 1, proxy) }
            .onKeyPress(.upArrow) { move(shown, -1, proxy) }
            .onAppear { if lab.selectedChat[op] == nil || !scoped.contains(where: { $0.id == lab.selectedChat[op] }) { lab.selectedChat[op] = scoped.first?.id } }
        }
    }

    func move(_ shown: [Chat], _ d: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = shown.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let i = ids.firstIndex(of: lab.selectedChat[op] ?? "") ?? 0
        let next = ids[max(0, min(ids.count - 1, i + d))]
        lab.selectedChat[op] = next
        proxy.scrollTo(next)
        return .handled
    }
}

struct ChatRow: View {
    @Environment(Lab.self) private var lab
    var chat: Chat
    var body: some View {
        let on = lab.selectedChat[chat.operator] == chat.id
        Button { lab.selectedChat[chat.operator] = chat.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.title).type(T.t2).lineLimit(1)
                Meta(ago(chat.updated) + (chat.bot.map { " · \($0)" } ?? "")).lineLimit(1)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(RowBtn(on: on))
    }
}

struct ChatDetail: View {
    @Environment(Lab.self) private var lab
    var chat: Chat?

    var body: some View {
        if let c = chat {
            let tkey = "\(c.operator):\(c.id)", rkey = "chat:\(c.operator):\(c.id)"
            let canContinue = c.operator != "mavis" && lab.operators[c.operator]?.path != nil
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        thread(c, tkey, rkey).frame(maxWidth: 800).padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 16).frame(maxWidth: .infinity)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .onChange(of: (lab.transcripts[tkey]?.count ?? -1) + (lab.live[rkey]?.count ?? 0) + (lab.drafts[rkey]?.count ?? 0)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                if canContinue {
                    Composer(key: rkey, placeholder: "Continue in \(Operators.name(c.operator))", running: lab.runs[rkey] != nil) { t in Task { await lab.send(toChat: c, t) } }
                } else {
                    Notice(bold: c.operator == "mavis" ? "Mavis chats can be read here. Hand it off or make it an agent to keep going." : "\(Operators.name(c.operator)) isn’t installed, so this chat can only be read.", info: true)
                        .frame(maxWidth: 736).padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 16).frame(maxWidth: .infinity).background(T.work)
                }
            }
            .task(id: c.id) { await lab.transcript(c) }
            .id(c.id)
        } else {
            Empty(title: "Pick a chat", sub: "↑ ↓ move through the list").frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder func thread(_ c: Chat, _ tkey: String, _ rkey: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                OpTile(op: c.operator, size: 48)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.title).type(T.t4).lineLimit(2)
                    FlowLayout {
                        Chip(text: c.cwd?.lastPathComponent ?? "No folder", icon: .folder) { lab.reveal(c.cwd) }
                        Chip(text: ago(c.updated))
                        if let b = c.bot { Chip(text: b) }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading).hairBottom().padding(.bottom, 8)
            if let items = lab.transcripts[tkey] {
                let all = Array(items.suffix(400)) + (lab.live[rkey] ?? [])
                if items.count > 400 { Meta("Showing the latest 400 of \(items.count) messages.").padding(.top, 8) }
                if all.isEmpty { Meta("This chat has no messages to show.").padding(.top, 24) }
                ForEach(MessageList.rows(all.map { ($0.role, $0.text, $0.verb, nil) })) { r in
                    switch r.role {
                    case "user": MessageRow(who: .me, text: clip4000(r.text), meta: nil, cont: r.cont) { EmptyView() }
                    case "assistant": MessageRow(who: .them, text: r.text, meta: c.bot ?? Operators.name(c.operator), cont: r.cont) { OpTile(op: c.operator, size: 40) }
                    default: Step(verb: r.verb ?? "", text: r.text)
                    }
                }
                if let d = lab.drafts[rkey] { MessageRow(who: .them, text: d, meta: nil, cont: false, draft: true) { OpTile(op: c.operator, size: 40) } }
                let aps = lab.approvals.filter { $0.key == rkey }
                ForEach(aps) { p in ApprovalCard(approval: p, primary: false, withWho: false).padding(.leading, 52).padding(.top, 12) }
                if let r = lab.runs[rkey], lab.drafts[rkey] == nil, aps.isEmpty { Typing(text: r.activity ?? "Working") }
            } else {
                Loading(text: "Opening this chat").padding(.top, 24)
            }
        }
    }
    func clip4000(_ s: String) -> String { s.count > 4000 ? String(s.prefix(3999)) + "…" : s }
}

// MARK: - Review an agent's branch

struct ReviewView: View {
    @Environment(Lab.self) private var lab
    var id: String
    @State private var files: [FileChange]?
    @State private var error: String?
    @State private var open: String?
    @State private var diffs: [String: [String]] = [:]

    var body: some View {
        if let a = lab.agent(id), a.worktree != nil {
            Col {
                HStack(spacing: 16) {
                    Avatar(a, size: 48, state: lab.state(of: a))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(a.name)’s changes").type(T.t4)
                        FlowLayout {
                            Chip(text: "\(a.branch ?? "") → \(a.baseBranch ?? "main")")
                            Chip(text: "Its folder", icon: .folder) { lab.reveal(a.worktree) }
                        }.padding(.top, 8)
                    }
                }
                .padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading).hairBottom().padding(.bottom, 8)
                if let error { Notice(bold: error).padding(.top, 16) }
                else if let files { body(a, files) }
                else { Loading(text: "Reading the changes").padding(.top, 8) }
            }
            .task {
                do { let c: Changes = try await lab.engine.call("git:changes", a.id); files = c.files; open = c.files.first?.path; if let o = open { await load(o) } }
                catch { self.error = error.localizedDescription }
            }
        } else {
            Col { Empty(title: "This agent doesn’t work on its own branch") }
        }
    }

    @ViewBuilder func body(_ a: Agent, _ files: [FileChange]) -> some View {
        let add = files.reduce(0) { $0 + $1.add }, del = files.reduce(0) { $0 + $1.del }
        let ov = lab.overlaps.first { $0.agents.contains(a.id) }
        HStack(spacing: 4) {
            Text("\(files.count) \(files.count == 1 ? "file" : "files") ·").foregroundStyle(T.i11)
            Text("+\(add)").foregroundStyle(T.codeAdd)
            Text("−\(del)").foregroundStyle(T.codeDel)
        }
        .type(T.t1, T.i11, mono: true).padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(T.i3)).overlay(Capsule().strokeBorder(T.i6, lineWidth: 0.5))
        .padding(.top, 12)
        if let ov {
            let other = lab.agent(ov.agents.first { $0 != a.id } ?? "")?.name ?? "Another agent"
            Notice(icon: .agents, bold: "\(other) also changed \(ov.files.prefix(3).map(\.lastPathComponent).joined(separator: ", ")).", rest: " Merge one first; the other updates from it instead of conflicting.").padding(.top, 16)
        }
        if files.isEmpty { Empty(title: "No changes yet", sub: "When this agent edits files, they show up here") }
        VStack(spacing: 8) {
            ForEach(files) { f in fileCard(f, both: ov?.files.contains(f.path) == true) }
        }
        .padding(.top, 24)
    }

    func fileCard(_ f: FileChange, both: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                open = open == f.path ? nil : f.path
                if let o = open, diffs[o] == nil { Task { await load(o) } }
            } label: {
                HStack(spacing: 12) {
                    Text(f.path).type(T.t2, T.i12, mono: true).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    if both { Badge(text: "Both changed") }
                    if f.binary == true { Text("binary").type(T.t1, T.i10, mono: true) }
                    else { HStack(spacing: 4) { Text("+\(f.add)").foregroundStyle(T.codeAdd); Text("−\(f.del)").foregroundStyle(T.codeDel) }.type(T.t1, T.i10, mono: true) }
                    let t = max(1, f.add + f.del), g = Int((Double(f.add) / Double(t) * 5).rounded())
                    HStack(spacing: 2) { ForEach(0..<5) { i in RoundedRectangle(cornerRadius: 2).fill(i < g ? T.codeAdd : T.codeDel).frame(width: 8, height: 8) } }
                }
                .padding(.horizontal, 16).frame(height: 48)
            }
            .buttonStyle(RowBtn(radius: 0, hover: T.i3))
            if open == f.path {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let lines = diffs[f.path] {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                                let add = l.hasPrefix("+"), del = l.hasPrefix("-"), hunk = l.hasPrefix("@@")
                                Text(l.isEmpty ? " " : l).type(T.t1, add ? T.codeAdd : del ? T.codeDel : T.i10, mono: true).lineLimit(1).fixedSize()
                                    .frame(height: 20).padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(add ? T.codeAdd.opacity(0.08) : del ? T.codeDel.opacity(0.08) : hunk ? T.i1 : .clear)
                            }
                        } else { Loading(text: "Reading").padding(.horizontal, 16) }
                    }
                    .padding(.vertical, 8).textSelection(.enabled)
                }
                .background(T.ground).hairTop()
            }
        }
        .surface(T.i2, ring: T.i6, radius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .lift()
    }

    func load(_ path: String) async {
        do { diffs[path] = try await lab.engine.call("git:diff", id, path) as [String] }
        catch { diffs[path] = ["Could not read this file: \(error.localizedDescription)"] }
    }
}

// MARK: - Memory

struct Page<C: View>: View {
    var title: String
    var lede: String
    @ViewBuilder var content: () -> C
    var body: some View {
        Col {
            Text(title).type(T.t4)
            Text(lede).type(T.t2, T.i11).frame(maxWidth: 520, alignment: .leading).padding(.top, 4).padding(.bottom, 24).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }
}

struct TileRow<C: View>: View {
    var top = false
    @ViewBuilder var content: () -> C
    var body: some View {
        HStack(alignment: top ? .top : .center, spacing: 16) { content() }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(T.i2, ring: T.i6, radius: 12).lift()
    }
}

struct Field40: ViewModifier {
    var fill: Color = T.i3
    var ring: Color? = nil
    @FocusState.Binding var focused: Bool
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).type(T.t2)
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(focused && ring == nil ? T.i4 : fill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ring.map { focused ? T.i7 : $0 } ?? (focused ? T.i10 : .clear), lineWidth: ring == nil ? 2 : 0.5))
    }
}

/// A select drawn as a field, opening the system menu.
struct Select: View {
    var options: [(String, String)]
    @Binding var value: String
    var fill: Color = T.i3
    var ring: Color? = nil
    var body: some View {
        Menu {
            ForEach(options, id: \.0) { o in Button(o.1) { value = o.0 } }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == value }?.1 ?? value).type(T.t2).lineLimit(1)
                Spacer(minLength: 0)
                Icon(name: .chev, size: 12, weight: 2).foregroundStyle(T.i10)
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ring ?? .clear, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

struct MemoryView: View {
    @Environment(Lab.self) private var lab
    @State private var text = ""
    @State private var scope = ""
    @FocusState private var focused: Bool

    var body: some View {
        let list = lab.memory.filter { lab.scope == nil || $0.workspace == nil || $0.workspace == lab.scope }.sorted { $0.n > $1.n }
        Page(title: "Memory", lede: "Decisions you’ve made, once. Every Claude Code agent is told them before it starts, alongside Claude Code’s own instructions. Nothing else is added.") {
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text("A decision, like “Never merge to main without tests passing”").foregroundStyle(T.i10))
                    .focused($focused).modifier(Field40(fill: T.i2, ring: T.i5, focused: $focused)).onSubmit(add)
                Select(options: [("", "Everywhere")] + lab.workspaces.map { ($0.id, $0.name) }, value: $scope, fill: T.i2, ring: T.i5).fixedSize()
                Button("Add", action: add).buttonStyle(Btn(kind: .primary))
            }
            .padding(.bottom, 16)
            VStack(spacing: 8) {
                ForEach(list) { d in
                    TileRow(top: true) {
                        Text("#\(d.n)").type(T.t1, T.i10, mono: true).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.text).type(T.t2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Meta([d.workspace.map { id in lab.workspaces.first { $0.id == id }?.name ?? "A removed workspace" } ?? "Everywhere", d.by, d.source.map { "from \($0)" }, ago(d.at)].compactMap { $0 }.joined(separator: " · "))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button { Task { await lab.removeDecision(d) } } label: { Icon(name: .trash) }.buttonStyle(IconBtn()).help("Remove").padding(.top, -6)
                    }
                }
            }
            if list.isEmpty { Empty(title: "No decisions yet", sub: "Add one above, or save them from a chat when you make it an agent") }
        }
        .onAppear { scope = lab.scope ?? "" }
    }

    func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        Task { if await lab.addDecision(t, workspace: scope.isEmpty ? nil : scope) != nil { text = "" } }
    }
}

// MARK: - Connections

struct ConnectionsView: View {
    @Environment(Lab.self) private var lab
    @State private var busy = false

    var body: some View {
        Page(title: "Connections", lede: "Agents run through the tools already on this Mac, with your own logins and settings. Agent Lab never sees your passwords.") {
            VStack(spacing: 8) {
                ForEach(Operators.all, id: \.self) { id in
                    let o = lab.operators[id]
                    TileRow {
                        OpTile(op: id, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Operators.name(id)).type(T.t2)
                            Meta(o?.path.map { "\(o?.version ?? "Installed") · \($0)" } ?? "Not found on this Mac").lineLimit(1).truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) { Circle().fill(o?.path != nil ? T.codeAdd : T.i6).frame(width: 8, height: 8); Text(o?.path != nil ? "Connected" : "Not installed") }.type(T.t1, T.i10).fixedSize()
                    }
                }
            }
            section("Mavis", "Brings Mavis’s agents and conversations in by name. Mavis’s own prompts and rules stay behind: agents here answer the way Claude Code does.") {
                TileRow {
                    OpTile(op: "mavis", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mavis on this Mac").type(T.t2)
                        Meta(lab.mavis.map { $0.found ? "\($0.bots) \($0.bots == 1 ? "agent" : "agents") · \($0.chats) conversations" : "No Mavis data found" } ?? "Not checked yet")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let m = lab.mavis {
                        if m.found && (m.newChats > 0 || m.newAgents > 0) {
                            Button(busy ? "Bringing in…" : "Bring them in") { busy = true; Task { await lab.importMavis(); busy = false } }.buttonStyle(Btn(kind: .primary)).disabled(busy)
                        } else if m.found { Meta("Everything is here") }
                    } else {
                        Button(busy ? "Checking…" : "Check") { busy = true; Task { await lab.scanMavis(); busy = false } }.buttonStyle(Btn()).disabled(busy)
                    }
                }
            }
            section("Workspaces", "A workspace is a folder. Agents made in it work there, and its chats and agents get their own space on the left.") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lab.workspaces) { w in
                        TileRow {
                            Circle().fill(Color(hex: w.color)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 4) { Text(w.name).type(T.t2); Meta(w.path).lineLimit(1).truncationMode(.middle) }.frame(maxWidth: .infinity, alignment: .leading)
                            Button { Task { await lab.removeWorkspace(w) } } label: { Icon(name: .x) }.buttonStyle(IconBtn()).help("Remove from the sidebar")
                        }
                    }
                    Button { if let p = lab.chooseFolder("Add a workspace folder") { Task { await lab.addWorkspace(p) } } } label: { Icon(name: .folder, size: 14); Text("Add a folder") }.buttonStyle(Btn())
                }
                let s = suggested
                if !s.isEmpty {
                    Meta("Folders you work in most, from your chats").padding(.top, 16)
                    VStack(spacing: 8) {
                        ForEach(s, id: \.0) { p, n in
                            TileRow {
                                Circle().fill(T.i6).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 4) { Text(p.lastPathComponent).type(T.t2); Meta("\(p) · \(n) chats").lineLimit(1).truncationMode(.middle) }.frame(maxWidth: .infinity, alignment: .leading)
                                Button("Add") { Task { await lab.addWorkspace(p) } }.buttonStyle(Btn())
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task { await lab.loadChats("claude-code") }
    }

    @ViewBuilder func section<C: View>(_ title: String, _ lede: String, @ViewBuilder _ content: () -> C) -> some View {
        Text(title).type(T.t3).padding(.top, 32).padding(.bottom, 12)
        Text(lede).type(T.t2, T.i11).frame(maxWidth: 520, alignment: .leading).padding(.bottom, 24).fixedSize(horizontal: false, vertical: true)
        content()
    }

    var suggested: [(String, Int)] {
        var counts: [String: Int] = [:]
        for c in (lab.chats["claude-code"] ?? []) + (lab.chats["codex"] ?? []) { if let d = c.cwd, d != lab.home { counts[d, default: 0] += 1 } }
        return counts.filter { k, _ in !lab.workspaces.contains { $0.path == k } }.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }
}

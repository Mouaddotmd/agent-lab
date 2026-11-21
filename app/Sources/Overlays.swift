import SwiftUI

// Overlays: a dim backdrop, 16-radius panels, rows inset 8.

struct LayerView: View {
    @Environment(Lab.self) private var lab
    var sheet: Sheet

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: isSearch ? .top : .center) {
                Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { lab.sheet = nil }
                Group {
                    switch sheet {
                    case .newAgent(let op): AgentForm(editing: nil, preset: op)
                    case .editAgent(let id): AgentForm(editing: lab.agent(id), preset: nil)
                    case .promote(let c): PromoteForm(chat: c)
                    case .handoff(let c): HandoffPanel(chat: c)
                    case .confirm(let c): ConfirmPanel(confirm: c)
                    case .search: SearchPanel()
                    }
                }
                .frame(maxHeight: geo.size.height - 32)
                .padding(.top, isSearch ? geo.size.height * 0.12 : 0)
                .padding(16)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .onExitCommand { lab.sheet = nil }
    }
    var isSearch: Bool { if case .search = sheet { return true }; return false }
}

/// The modal: 464 wide, head centred, body, then a footer under a hairline.
struct Modal<Head: View, Content: View, Foot: View>: View {
    @ViewBuilder var head: () -> Head
    @ViewBuilder var content: () -> Content
    @ViewBuilder var foot: () -> Foot
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) { head() }.multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
                    VStack(alignment: .leading, spacing: 12) { content() }
                        .padding(.horizontal, 24).padding(.bottom, 16)
                }
            }
            .scrollIndicators(.never)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { foot() }.padding(8).hairTop()
        }
        .frame(width: 464)
        .surface(T.i2, ring: T.i6, radius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .float()
    }
}

struct FieldBlock<C: View>: View {
    var label: String
    var optional = false
    var hint: String? = nil
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) { Text(label).type(T.t2, T.i11); if optional { Meta("optional") } }
            content()
            if let hint { Meta(hint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct Check: View {
    @Binding var on: Bool
    var title: String
    var meta: String
    var disabled = false
    var body: some View {
        Button { if !disabled { on.toggle() } } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(on ? T.i12 : T.i3)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(on ? T.i12 : T.i7, lineWidth: 0.5))
                    .overlay { if on { Icon(name: .check, size: 12, weight: 2.4).foregroundStyle(T.i1) } }
                    .frame(width: 16, height: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 0) { Text(title).type(T.t2); Meta(meta).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(disabled ? 0.6 : 1)
    }
}

// MARK: - New agent / edit

struct AgentForm: View {
    @Environment(Lab.self) private var lab
    var editing: Agent?
    var preset: String?
    @State private var name = ""
    @State private var job = ""
    @State private var look = Faces.random()
    @State private var op = "claude-code"
    @State private var model = ""
    @State private var permission = "ask"
    @State private var cwd = ""
    @State private var ownBranch = false
    @State private var repo: RepoInfo?
    @State private var saving = false
    @State private var ready = false
    @FocusState private var nameFocus: Bool
    @FocusState private var jobFocus: Bool

    var body: some View {
        let isEdit = editing != nil
        Modal {
            Avatar(look: look, size: 80)
            Button("New face") { look = Faces.random() }.buttonStyle(Btn(pill: true))
            Text(isEdit ? "Edit \(editing!.name)" : "New agent").type(T.t3)
        } content: {
            FieldBlock(label: "Name") {
                TextField("", text: $name, prompt: Text("Juno").foregroundStyle(T.i10)).focused($nameFocus).modifier(Field40(focused: $nameFocus)).onSubmit(save)
            }
            FieldBlock(label: "Its job", optional: true, hint: "Left empty, it behaves exactly like \(Operators.name(op)) normally does.") {
                TextField("", text: $job, prompt: Text("Reviews every pull request in this repo before I do").foregroundStyle(T.i10), axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.plain).type(T.t2).focused($jobFocus)
                    .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 72, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(jobFocus ? T.i4 : T.i3))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(jobFocus ? T.i10 : .clear, lineWidth: 2))
            }
            if !isEdit {
                FieldBlock(label: "Runs on") {
                    HStack(spacing: 8) {
                        ForEach(Operators.all, id: \.self) { k in
                            let on = op == k, ok = lab.operators[k]?.path != nil
                            Button { op = k; model = "" } label: {
                                Text(Operators.name(k)).type(T.t2, on ? T.i12 : T.i11).padding(.horizontal, 12).frame(height: 32)
                                    .background(Capsule().fill(on ? T.i4 : T.i3)).overlay(Capsule().strokeBorder(on ? T.i9 : T.i6, lineWidth: 0.5))
                                    .shadow(color: .black.opacity(on ? 0.5 : 0), radius: 1, y: 1)
                            }
                            .buttonStyle(PressStyle()).disabled(!ok).opacity(ok ? 1 : 0.6).help(ok ? "" : "Not installed")
                        }
                    }
                }
            }
            let models = op == "codex" ? [("", "Codex default")] + lab.codexModels.map { ($0, $0) } : op == "claude-code" ? Operators.claudeModels : []
            if models.count > 1 { FieldBlock(label: "Model") { Select(options: models, value: $model) } }
            if !isEdit {
                FieldBlock(label: "Works in") {
                    Button { pickFolder() } label: {
                        HStack(spacing: 8) { Icon(name: .folder); Text(cwd).type(T.t1, T.i12, mono: true).lineLimit(1).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading) }
                            .padding(.horizontal, 12).frame(height: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(RowBtn(normal: T.i3, hover: T.i4))
                }
                let ok = repo?.hasCommits == true && repo?.branch != nil && repo?.branch != "HEAD"
                Check(on: $ownBranch, title: "Its own branch and folder", meta: ok ? "Branches from \(repo?.branch ?? ""). You review and merge its changes." : "Needs a git repository with at least one commit.", disabled: !ok)
            }
            FieldBlock(label: "What it may do", hint: op != "claude-code" ? "\(Operators.name(op)) can’t pause to ask, so “Asks before changes” lets it edit inside its own sandbox." : nil) {
                Select(options: Permission.allCases.map { ($0.rawValue, $0.label) }, value: $permission)
            }
        } foot: {
            if let e = editing { Button("Remove agent") { lab.confirmRemove(e) }.buttonStyle(Btn(kind: .danger)) }
            else { Button("Cancel") { lab.sheet = nil }.buttonStyle(Btn()) }
            Spacer()
            Button(saving ? (ownBranch ? "Making its branch…" : "Saving…") : isEdit ? "Save" : "Add agent", action: save).buttonStyle(Btn(kind: .primary)).disabled(saving)
        }
        .onAppear(perform: setup)
    }

    func setup() {
        guard !ready else { return }
        ready = true
        if let a = editing {
            name = a.name; job = a.job ?? ""; look = Faces.of(a); op = a.operator; model = a.model ?? ""; permission = a.permission ?? "ask"; cwd = a.cwd ?? lab.home
        } else {
            op = preset ?? lab.availableOperators.first ?? "claude-code"
            cwd = lab.currentWorkspace?.path ?? lab.home
            Task { await readRepo() }
        }
        DispatchQueue.main.async { nameFocus = true }
    }

    func readRepo() async {
        let info: FolderInfo? = try? await lab.engine.call("folder:info", cwd)
        repo = info?.repo
    }

    func pickFolder() {
        if let p = lab.chooseFolder("Where should this agent work?") { cwd = p; ownBranch = false; Task { await readRepo() } }
    }

    func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { lab.show("Give it a name first.", error: true); nameFocus = true; return }
        saving = true
        Task {
            if let a = editing {
                await lab.updateAgent(a.id, ["name": n, "job": job, "look": look.dict, "model": model.isEmpty ? NSNull() : model, "permission": permission])
                lab.sheet = nil; lab.show("Saved")
            } else if let a = await lab.createAgent(["name": n, "job": job, "look": look.dict, "operator": op, "model": model.isEmpty ? NSNull() : model, "permission": permission, "cwd": cwd, "ownBranch": ownBranch]) {
                lab.sheet = nil; lab.show("\(a.name) joined"); lab.open(a)
            }
            saving = false
        }
    }
}

extension Look {
    var dict: [String: Any] { ["bg": bg, "skin": skin, "hair": hair, "style": style, "shirt": shirt, "glasses": glasses] }
}

// MARK: - Make a chat an agent

struct PromoteForm: View {
    @Environment(Lab.self) private var lab
    var chat: Chat
    @State private var name = ""
    @State private var job = ""
    @State private var look = Faces.random()
    @State private var permission = "ask"
    @State private var decisions: [String]?
    @State private var finding = false
    @State private var keep: [Bool] = []
    @State private var repo: RepoInfo?
    @State private var saving = false

    var body: some View {
        let same = chat.operator != "mavis"
        Modal {
            Avatar(look: look, size: 80)
            Button("New face") { look = Faces.random() }.buttonStyle(Btn(pill: true))
            Text("Make this chat an agent").type(T.t3)
            Text(clip(chat.title, 70)).type(T.t2, T.i11)
        } content: {
            FieldBlock(label: "Name") {
                TextField("", text: $name, prompt: Text("Juno").foregroundStyle(T.i10)).focused($nameFocus).modifier(Field40(focused: $nameFocus))
            }
            FieldBlock(label: "Its job", optional: true) {
                TextField("", text: $job, prompt: Text("Owns checkout reliability").foregroundStyle(T.i10)).focused($jobFocus).modifier(Field40(focused: $jobFocus))
            }
            FieldBlock(label: "Brings along") {
                VStack(alignment: .leading, spacing: 0) {
                    packRow(first: true) {
                        Icon(name: .check, weight: 2).foregroundStyle(T.i11).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(same ? "This exact \(Operators.name(chat.operator)) session" : "This conversation, handed over as context").type(T.t2)
                            Meta(same ? "It continues the same conversation, so it remembers everything in it" : "Sent as its first message")
                        }
                    }
                    packRow {
                        Icon(name: .check, weight: 2).foregroundStyle(T.i11).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Works in \(chat.cwd?.lastPathComponent ?? "your home folder")").type(T.t2)
                            Meta(chat.cwd ?? lab.home)
                        }
                    }
                    if finding { packRow { Loading(text: "Reading the chat for decisions") } }
                    else if let d = decisions {
                        if d.isEmpty { packRow { Meta("No decisions found in this chat") } }
                        ForEach(Array(d.enumerated()), id: \.offset) { i, t in
                            packRow { Check(on: Binding(get: { keep.indices.contains(i) && keep[i] }, set: { if keep.indices.contains(i) { keep[i] = $0 } }), title: t, meta: "Saved to Memory") }
                        }
                    } else {
                        packRow {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Decisions from this chat").type(T.t2)
                                Meta("Claude reads the chat and lists them. You choose which to keep.")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Find them", action: find).buttonStyle(Btn(raised: true))
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .surface(T.i3, ring: T.i6, radius: 12)
            }
            if same && repo?.hasCommits == true { Meta("It continues in the chat’s own folder. To give it a separate branch, make a new agent instead.").fixedSize(horizontal: false, vertical: true) }
            FieldBlock(label: "What it may do") { Select(options: Permission.allCases.map { ($0.rawValue, $0.label) }, value: $permission) }
        } foot: {
            Button("Cancel") { lab.sheet = nil }.buttonStyle(Btn())
            Spacer()
            Button(saving ? "Making…" : "Make agent", action: save).buttonStyle(Btn(kind: .primary)).disabled(saving)
        }
        .task {
            let info: FolderInfo? = try? await lab.engine.call("folder:info", chat.cwd ?? lab.home)
            repo = info?.repo
            nameFocus = true
        }
    }

    @FocusState private var nameFocus: Bool
    @FocusState private var jobFocus: Bool

    func packRow<C: View>(first: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) { c() }
            .padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .overlay(alignment: .top) { if !first { Rectangle().fill(T.i6).frame(height: 0.5) } }
    }

    func find() {
        finding = true
        Task {
            let list: [String] = await lab.attempt { try await lab.engine.call("chat:decisions", chat.operator, chat.id) } ?? []
            decisions = list; keep = list.map { _ in true }; finding = false
        }
    }

    func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { lab.show("Give it a name first.", error: true); return }
        saving = true
        Task {
            var spec: [String: Any] = ["name": n, "job": job, "look": look.dict, "permission": permission, "cwd": chat.cwd ?? lab.home,
                                       "origin": ["type": "chat", "operator": chat.operator, "ref": chat.id, "title": chat.title]]
            if chat.operator == "mavis" { spec["operator"] = "claude-code" } else { spec["operator"] = chat.operator; spec["sessionId"] = chat.id }
            guard let a = await lab.createAgent(spec) else { saving = false; return }
            let kept = (decisions ?? []).enumerated().filter { keep.indices.contains($0.offset) && keep[$0.offset] }.map(\.element)
            let ws = lab.workspaces.first { lab.inside(a.cwd, $0.path) }
            for t in kept { _ = await lab.addDecision(t, workspace: ws?.id, source: "“\(clip(chat.title, 40))”") }
            lab.sheet = nil
            lab.show("\(a.name) joined\(kept.isEmpty ? "" : " with \(kept.count) \(kept.count == 1 ? "decision" : "decisions") in Memory")")
            lab.open(a)
            if chat.operator == "mavis" {
                let items: [Line] = (try? await lab.engine.call("chat:transcript", chat.operator, chat.id)) ?? []
                let text = items.filter { $0.role != "tool" }.map { "\($0.role == "user" ? "Me" : "Mavis"): \($0.text)" }.joined(separator: "\n\n")
                await lab.send(to: a.id, "Here is an earlier conversation I had, titled “\(chat.title)”. Read it so you know where things stand, then tell me in a sentence or two what you understood.\n\n\(text)")
            }
        }
    }
}

// MARK: - Hand off a chat

struct HandoffPanel: View {
    @Environment(Lab.self) private var lab
    var chat: Chat
    @State private var writing = false

    var body: some View {
        let list = lab.agents.sorted { rel($0) > rel($1) }
        Modal {
            Text("Hand off this chat").type(T.t3)
            Text("Claude writes a short note of where things stand, and the agent you pick starts from it.").type(T.t2, T.i11)
        } content: {
            if writing { Loading(text: "Writing the hand-off note") }
            else if list.isEmpty { Meta("You have no agents yet. Make this chat an agent instead.") }
            else {
                ForEach(list) { a in
                    Button { go(a) } label: {
                        HStack(spacing: 12) {
                            Avatar(a, size: 40, state: lab.state(of: a), ground: T.i3)
                            VStack(alignment: .leading, spacing: 0) { Text(a.name).type(T.t2); Meta(lab.status(of: a)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                            Meta(lab.state(of: a).label)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ChoiceStyle())
                }
            }
        } foot: {
            Meta("The chat stays as it is").padding(.leading, 8)
            Spacer()
            Button("Cancel") { lab.sheet = nil }.buttonStyle(Btn())
        }
    }

    func rel(_ a: Agent) -> Int { lab.inside(a.cwd, chat.cwd) || lab.inside(chat.cwd, a.cwd) ? 1 : 0 }

    func go(_ a: Agent) {
        if lab.runs["agent:\(a.id)"] != nil { lab.show("\(a.name) is still working. Try again when it’s done.", error: true); return }
        writing = true
        Task {
            let note: String? = await lab.attempt { try await lab.engine.call("chat:summary", chat.operator, chat.id) }
            lab.sheet = nil
            guard let note else { return }
            lab.open(a)
            await lab.send(to: a.id, "I’m handing you a \(Operators.name(chat.operator)) chat called “\(chat.title)” (folder: \(chat.cwd ?? "none")). Here is where it stands:\n\n\(note)\n\nPick it up from here.")
        }
    }
}

struct ChoiceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var over = false
        var body: some View {
            configuration.label
                .surface(over ? T.i4 : T.i3, ring: T.i6, radius: 12).drop()
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .onHover { over = $0 }
        }
    }
}

// MARK: - Confirm

struct ConfirmPanel: View {
    @Environment(Lab.self) private var lab
    var confirm: Confirm
    var body: some View {
        Modal {
            Text(confirm.title).type(T.t3)
            Text(confirm.body).type(T.t2, T.i11).fixedSize(horizontal: false, vertical: true)
        } content: {
            EmptyView()
        } foot: {
            Spacer()
            Button("Cancel") { lab.sheet = nil }.buttonStyle(Btn())
            Button(confirm.ok) { lab.sheet = nil; confirm.action() }.buttonStyle(Btn(kind: confirm.danger ? .danger : .primary)).keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - ⌘K: find an agent or a chat, or hand text straight to an agent

struct SearchPanel: View {
    @Environment(Lab.self) private var lab
    @State private var q = ""
    @State private var sel = 0
    @FocusState private var focused: Bool

    enum Row: Identifiable {
        case agent(Agent), chat(Chat)
        var id: String { switch self { case .agent(let a): "a\(a.id)"; case .chat(let c): "c\(c.operator)\(c.id)" } }
    }

    var body: some View {
        let t = q.trimmingCharacters(in: .whitespaces), lower = t.lowercased(), long = t.count > 12
        let agents = lab.agents.filter { lower.isEmpty || long || "\($0.name) \($0.job ?? "")".lowercased().contains(lower) }.prefix(6)
        let chats = lower.isEmpty ? [] : ["claude-code", "codex", "mavis"].flatMap { op in (lab.chats[op] ?? []).filter { !Set(lab.agents.compactMap(\.sessionId)).contains($0.id) && "\($0.title) \($0.cwd ?? "")".lowercased().contains(lower) }.prefix(4) }
        let rows: [Row] = agents.map { .agent($0) } + chats.map { .chat($0) }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Icon(name: .search, size: 18).foregroundStyle(T.i10)
                TextField("", text: $q, prompt: Text("Find an agent or a chat, or type what you need").foregroundStyle(T.i10))
                    .textFieldStyle(.plain).type(T.t3).focused($focused)
                    .onKeyPress(.downArrow) { if !rows.isEmpty { sel = (sel + 1) % rows.count }; return .handled }
                    .onKeyPress(.upArrow) { if !rows.isEmpty { sel = (sel - 1 + rows.count) % rows.count }; return .handled }
                    .onSubmit { if rows.indices.contains(sel) { go(rows[sel], t) } }
                    .onChange(of: q) { sel = 0 }
            }
            .padding(.horizontal, 16).frame(height: 56).hairBottom()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !agents.isEmpty { Meta(long ? "Hand it to" : "Agents").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4) }
                    ForEach(Array(agents.enumerated()), id: \.element.id) { i, a in
                        row(i == sel, { Avatar(a, size: 32, state: lab.state(of: a), ground: i == sel ? T.i4 : T.i2) },
                            long ? "Hand to \(a.name)" : a.name, long ? clip(t, 80) : lab.status(of: a), lab.state(of: a).label) { go(.agent(a), t) }
                    }
                    if !chats.isEmpty { Meta("Chats").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4) }
                    ForEach(Array(chats.enumerated()), id: \.element.id) { j, c in
                        let i = agents.count + j
                        row(i == sel, { OpTile(op: c.operator) }, c.title, "\(Operators.name(c.operator)) · \(c.cwd?.lastPathComponent ?? "No folder") · \(ago(c.updated))", "Open") { go(.chat(c), t) }
                    }
                    if rows.isEmpty { Empty(title: lab.agents.isEmpty ? "No agents yet" : "Nothing matches", sub: lab.agents.isEmpty ? "Press ⌘N to make one" : "Try other words") }
                }
                .padding(8)
            }
            .frame(maxHeight: 360).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                hint(["↵"], "open or hand off"); hint(["↑", "↓"], "choose"); hint(["esc"], "close")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8).hairTop()
        }
        .frame(width: 560)
        .surface(T.i2, ring: T.i6, radius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .float()
        .onAppear { focused = true }
        .task { for op in ["claude-code", "codex"] where lab.operators[op]?.path != nil { await lab.loadChats(op) }; if lab.importedCount > 0 { await lab.loadChats("mavis") } }
    }

    func row<A: View>(_ on: Bool, @ViewBuilder _ lead: () -> A, _ title: String, _ sub: String, _ go: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                lead()
                VStack(alignment: .leading, spacing: 0) { Text(title).type(T.t2).lineLimit(1); Meta(sub).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                Meta(go).fixedSize()
            }
            .padding(8).frame(minHeight: 48)
        }
        .buttonStyle(RowBtn(on: on, hover: T.i3, onFill: T.i4))
    }

    func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { k in Text(k).padding(.horizontal, 4).background(RoundedRectangle(cornerRadius: 4).fill(T.i3)) }
            Text(label)
        }
        .type(T.t1, T.i10)
    }

    func go(_ r: Row, _ text: String) {
        lab.sheet = nil
        switch r {
        case .chat(let c):
            if lab.scope != nil, !lab.inScope(c) { lab.scope = nil }
            lab.selectedChat[c.operator] = c.id; lab.nav = .chats(c.operator)
        case .agent(let a):
            lab.open(a)
            if text.count > 12 { Task { await lab.send(to: a.id, text) } }
        }
    }
}

// The command palette's contents (⌘K): every command, agent, chat, file of the agent in front and setting, found by
// letters in order ("nwag" finds New agent), plus words across all your messages (engine: palette:messages). Built
// once each time it opens; the matching runs off the main thread.
import SwiftUI
import AppKit

/// One thing the palette can do.
struct PaletteItem: Identifiable {
    enum Group: Int, CaseIterable {
        case recent, commands, agents, chats, files, settings, messages
        var title: String {
            switch self {
            case .recent: "Recent"; case .commands: "Commands"; case .agents: "Agents"; case .chats: "Chats"
            case .files: "Files"; case .settings: "Settings"; case .messages: "Messages"
            }
        }
        /// How many show for a search (all of them while nothing is typed, files aside).
        var limit: Int {
            switch self {
            case .recent: 6; case .commands: 8; case .agents: 6; case .chats: 6; case .files: 10; case .settings: 5; case .messages: 12
            }
        }
    }
    enum Look { case icon(String), symbol(String), agent(Agent), workspace(Workspace) }
    let id: String
    var group: Group
    var title: String
    var detail: String? = nil
    var look: Look
    var shortcut: String? = nil
    /// Other words it answers to (not highlighted).
    var also: String = ""
    /// A message found: the piece of its line shown, and where the words matched in it (UTF-16).
    var snippet: (text: String, start: Int, length: Int)? = nil
    let run: @MainActor () -> Void
}

/// A message the engine found (engine/palette.js).
struct PaletteHit: Decodable {
    let conv: String; let agentId: String?; let workspaceId: String?; let channelId: String?
    let title: String; let place: String?; let id: String; let role: String; let by: String; let at: Double
    let snippet: Snip
    struct Snip: Decodable { let text: String; let start: Int; let length: Int }
}

/// A row as shown: the item and, for a search, which letters of its title matched.
struct PaletteRow: Identifiable {
    let item: PaletteItem; var marks: [Int] = []
    var id: String { item.id }
}

@MainActor final class PaletteModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { search() } } }
    /// The groups as shown, in order, and every row in one list for the keys.
    @Published private(set) var groups: [(group: PaletteItem.Group, rows: [PaletteRow])] = []
    @Published private(set) var flat: [PaletteRow] = []
    @Published var selected = 0
    @Published private(set) var filesLoading = false
    @Published private(set) var messagesLoading = false
    @Published private(set) var messageProblem: String?

    private weak var s: Store?
    private var items: [PaletteItem] = []
    private var keys: [Key] = []
    private var hits: [PaletteItem] = []
    private var matching: Task<Void, Never>?
    private var messageSearch: Task<Void, Never>?

    // MARK: Index (once per open)

    func build(_ s: Store) {
        self.s = s
        items = Palette.commands(s) + Palette.agents(s) + Palette.chats(s) + Palette.settings(s)
        keys = items.map(Key.init)
        show(reset: true)
        if let a = Palette.front(s) { loadFiles(a, s) }
    }
    private func loadFiles(_ a: Agent, _ s: Store) {
        let folder = a.cwd ?? s.home
        filesLoading = true
        Task {
            struct Files: Decodable { let files: [String]; let more: Bool }
            let got = try? await s.engine.call("palette:files", [folder], as: Files.self)
            filesLoading = false
            guard let got else { return }
            let files = got.files.map { rel in Palette.file(rel, of: a, s) }
            items += files
            keys += files.map(Key.init)
            if !query.isEmpty { search() }
        }
    }

    // MARK: Search

    private func search() {
        matching?.cancel(); messageSearch?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { hits = []; messagesLoading = false; messageProblem = nil; show(reset: true); return }
        let keys = self.keys
        let needle = Array(q.lowercased().utf16)
        matching = Task {
            let found = await Task.detached(priority: .userInitiated) { Palette.match(needle, keys) }.value
            guard !Task.isCancelled else { return }
            show(found, reset: true)
        }
        // Words in messages: after a short pause in typing, two letters or more.
        guard q.count >= 2, let s else { hits = []; messagesLoading = false; return }
        messagesLoading = true; messageProblem = nil
        messageSearch = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            do {
                let found = try await s.engine.call("palette:messages", [q, 40], as: [PaletteHit].self)
                guard !Task.isCancelled else { return }
                hits = found.map { Palette.message($0, s) }
                messagesLoading = false
                showMessages()
            } catch {
                guard !Task.isCancelled else { return }
                hits = []; messagesLoading = false; messageProblem = error.localizedDescription
                showMessages()
            }
        }
    }

    /// The last matches for the letters (index, score, marks), kept so the messages can arrive without matching again.
    private var lastFound: [(Int, Double, [Int])] = []
    private func show(_ found: [(Int, Double, [Int])]? = nil, reset: Bool = false) {
        var out: [(PaletteItem.Group, [PaletteRow])] = []
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            // Nothing typed: what you picked lately, then everything but files, in its own order.
            let recent = Palette.recent.compactMap { id in items.first { $0.id == id } }
            let seen = Set(recent.map(\.id))
            if !recent.isEmpty { out.append((.recent, recent.prefix(PaletteItem.Group.recent.limit).map { var i = $0; i.group = .recent; return PaletteRow(item: i) })) }
            for g in [PaletteItem.Group.commands, .agents, .chats, .settings] {
                let rows = items.filter { $0.group == g && !seen.contains($0.id) }.map { PaletteRow(item: $0) }
                if !rows.isEmpty { out.append((g, rows)) }
            }
        } else {
            if let found { lastFound = found }
            var by: [PaletteItem.Group: [(Double, PaletteRow)]] = [:]
            for (i, score, marks) in lastFound where items.indices.contains(i) {
                by[items[i].group, default: []].append((score, PaletteRow(item: items[i], marks: marks)))
            }
            for g in PaletteItem.Group.allCases where g != .messages && g != .recent {
                guard let list = by[g] else { continue }
                out.append((g, list.sorted { $0.0 > $1.0 }.prefix(g.limit).map(\.1)))
            }
            if !hits.isEmpty { out.append((.messages, hits.prefix(PaletteItem.Group.messages.limit).map { PaletteRow(item: $0) })) }
        }
        let keep = flat.indices.contains(selected) ? flat[selected].id : nil
        groups = out.map { (group: $0.0, rows: $0.1) }
        flat = out.flatMap(\.1)
        // A new search starts at the top; messages arriving later never move what you've chosen.
        if reset || keep == nil { selected = 0 }
        else { selected = flat.firstIndex { $0.id == keep } ?? 0 }
    }
    private func showMessages() { show(nil, reset: false) }

    // MARK: Keys

    func move(_ d: Int) {
        guard !flat.isEmpty else { return }
        selected = (selected + d + flat.count) % flat.count
    }
    func pick(_ i: Int? = nil) -> PaletteItem? {
        let i = i ?? selected
        guard flat.indices.contains(i) else { return nil }
        let item = flat[i].item
        if item.group != .messages { Palette.remember(item.id) }
        return item
    }

    // MARK: Matching (off the main thread)

    /// What's matched for one item: its title, and the other words it answers to, lowercased as UTF-16.
    struct Key: Sendable {
        let title: [UInt16]; let also: [UInt16]; let sameLength: Bool
        init(_ i: PaletteItem) {
            let low = i.title.lowercased()
            title = Array(low.utf16); sameLength = low.utf16.count == i.title.utf16.count
            also = Array(([i.detail ?? "", i.also].joined(separator: " ")).lowercased().utf16)
        }
    }
}

// MARK: The contents

@MainActor enum Palette {
    /// The agent whose chat is in front (in Messages, or a member's DM in a workspace).
    static func front(_ s: Store) -> Agent? {
        guard s.openWorkspace != nil || s.view == .messages, let id = s.openAgent else { return nil }
        return s.agents.first { $0.id == id }
    }
    /// The channel in front, when a workspace shows one.
    static func frontChannel(_ s: Store) -> (Workspace, Workspace.Channel)? {
        guard let w = s.currentWorkspace, s.openAgent == nil, let ch = w.channels.first(where: { $0.id == s.openChannel }) ?? w.channels.first else { return nil }
        return (w, ch)
    }

    static func commands(_ s: Store) -> [PaletteItem] {
        var out: [PaletteItem] = [
            .init(id: "cmd:newAgent", group: .commands, title: "New agent", look: .icon("pen"), shortcut: "⌘N", also: "create make") { s.newAgentOpen = true },
            .init(id: "cmd:newWorkspace", group: .commands, title: "New workspace", look: .icon("plus"), also: "create server team") { s.createWorkspaceOpen = true },
        ]
        for k in Kind.nav {
            out.append(.init(id: "cmd:go.\(k.rawValue)", group: .commands, title: "Open \(k.info.title)", look: .icon(k.info.icon), also: "go page") { s.go(k) })
        }
        if s.canBack { out.append(.init(id: "cmd:back", group: .commands, title: "Go back", look: .icon("arrowL"), shortcut: "⌘[") { s.step(-1) }) }
        if s.canForward { out.append(.init(id: "cmd:forward", group: .commands, title: "Go forward", look: .icon("arrowR"), shortcut: "⌘]") { s.step(1) }) }
        out.append(.init(id: "cmd:history", group: .commands, title: "Show history", detail: "Recently viewed", look: .icon("clock")) { s.settingsOpen = false; s.historyOpen = true })

        if let a = front(s) {
            let panel = SidePanel.of(a, home: s.home)
            out.append(.init(id: "cmd:findChat", group: .commands, title: "Find in chat", look: .icon("search"), shortcut: "⌘F", also: "search") { FindKeys.openActive() })
            out.append(.init(id: "cmd:panel", group: .commands, title: panel.open ? "Hide side panel" : "Show side panel", look: .icon("panel"), shortcut: "⌘\\", also: "toggle") { panel.toggle() })
            let tabs: [(PanelTab.Kind, String)] = [(.files, "Show files"), (.changes, "Show changes"), (.terminal("main"), "Show terminal")]
            for (kind, title) in tabs {
                let tab = PanelTab(kind: kind)
                out.append(.init(id: "cmd:tab.\(tab.id)", group: .commands, title: title, detail: a.name, look: IconData.all[tab.icon] != nil ? .icon(tab.icon) : .symbol(tab.icon), also: "side panel tab") { panel.show(tab) })
            }
            out.append(.init(id: "cmd:newTab", group: .commands, title: "New tab", detail: "Open a page, search, or ask \(a.name)", look: .symbol("globe"), shortcut: "⌘T", also: "browser web search side chat") { panel.newTab() })
            out.append(.init(id: "cmd:compact", group: .commands, title: "Compact \(a.name)'s chat", detail: "Summarise it to free up room", look: .symbol("arrow.down.right.and.arrow.up.left"), also: "context tokens") {
                ConvoHub.shared.context(a.id).compact()
            })
            if s.runs["agent:\(a.id)"] != nil {
                out.append(.init(id: "cmd:stop", group: .commands, title: "Stop \(a.name)", look: .icon("stop"), shortcut: "⌘.", also: "cancel halt") { s.stop("agent:\(a.id)") })
            }
            let current = Mode.of(a.permission)
            for m in Mode.allCases where m != current {
                out.append(.init(id: "cmd:mode.\(m.rawValue)", group: .commands, title: "Mode: \(m.title)", detail: m.detail, look: .symbol(m.symbol), also: "permission change mode") {
                    Task { do { try await s.updateAgent(a.id, ["permission": m.rawValue]) } catch { s.toast = error.localizedDescription } }
                })
            }
            out.append(.init(id: "cmd:pin", group: .commands, title: a.pinned == true ? "Unpin \(a.name)" : "Pin \(a.name)", look: .symbol(a.pinned == true ? "pin.slash" : "pin")) {
                Task { do { try await s.updateAgent(a.id, ["pinned": a.pinned != true]) } catch { s.toast = error.localizedDescription } }
            })
            out.append(.init(id: "cmd:duplicate", group: .commands, title: "Duplicate \(a.name)", look: .symbol("plus.square.on.square"), also: "copy") { Task { await s.duplicateAgent(a.id) } })
        }
        if let (w, ch) = frontChannel(s) {
            let conv = w.conv(ch.id)
            out.append(.init(id: "cmd:findChat", group: .commands, title: "Find in #\(ch.name)", look: .icon("search"), shortcut: "⌘F", also: "search chat") { FindKeys.openActive() })
            let working = s.runs.values.filter { $0.conversation == conv }
            if !working.isEmpty {
                out.append(.init(id: "cmd:stopChannel", group: .commands, title: "Stop agents in #\(ch.name)", look: .icon("stop"), also: "cancel halt") { for r in working { s.stop(r.key) } })
            }
        }
        if let w = s.currentWorkspace {
            out.append(.init(id: "cmd:invite", group: .commands, title: "Invite agents to \(w.name)", look: .icon("personAdd"), also: "add member") { s.invitingWorkspace = w.id })
        }
        return out
    }

    static func agents(_ s: Store) -> [PaletteItem] {
        func lastAt(_ a: Agent) -> Double { s.messages[a.id]?.last?.at ?? a.last?.at ?? a.createdAt ?? 0 }
        return s.agents.sorted { ($0.pinned == true) != ($1.pinned == true) ? $0.pinned == true : lastAt($0) > lastAt($1) }.map { a in
            let state = s.state(of: a)
            let detail = state == "idle" ? (a.job?.isEmpty == false ? a.job : nil) : STATE_LABEL[state]
            return PaletteItem(id: "agent:\(a.id)", group: .agents, title: a.name, detail: detail, look: .agent(a), also: a.job ?? "") { openAgent(a.id, s) }
        }
    }
    /// An agent's DM: inside the workspace in front when it's a member there, else in Messages.
    static func openAgent(_ id: String, _ s: Store) {
        if let w = s.currentWorkspace, (w.members ?? []).contains(id) {
            s.openAgent = id; Task { await s.loadMessages(id) }
        } else { s.openChat(id) }
    }

    static func chats(_ s: Store) -> [PaletteItem] {
        var out: [PaletteItem] = []
        for w in s.workspaces {
            out.append(.init(id: "ws:\(w.id)", group: .chats, title: w.name, detail: "Workspace", look: .workspace(w), also: "workspace server") { s.openSpace(w.id) })
            for ch in w.channels {
                out.append(.init(id: "ch:\(w.conv(ch.id))", group: .chats, title: "#\(ch.name)", detail: w.name, look: .icon("hash"), also: "channel") { openChannel(w.id, ch.id, s) })
            }
        }
        return out
    }
    static func openChannel(_ wsId: String, _ channel: String, _ s: Store) {
        guard let w = s.workspaces.first(where: { $0.id == wsId }) else { return }
        s.openSpace(w.id); s.openChannel = channel
        Task { await s.loadMessages(w.conv(channel)) }
    }

    static func settings(_ s: Store) -> [PaletteItem] {
        var out: [PaletteItem] = [
            .init(id: "set:plugins", group: .settings, title: "Plugins", look: .icon("plug"), also: "connections settings") { s.go(.connections) },
            .init(id: "set:profile", group: .settings, title: "Profile", look: .icon("person"), also: "settings account") { s.go(.profile) },
            .init(id: "set:usage", group: .settings, title: "Usage", look: .icon("chart"), also: "settings runs") { s.go(.usage) },
            .init(id: "set:menu", group: .settings, title: "Plugins and settings", detail: "Menu", look: .icon("gear"), also: "preferences") { s.historyOpen = false; s.settingsOpen = true },
        ]
        if let a = front(s) {
            out.append(.init(id: "set:agent", group: .settings, title: "Edit \(a.name)", detail: "Name, job, look, model", look: .agent(a), also: "agent settings") { s.editingAgent = a.id })
        }
        if let w = s.currentWorkspace {
            out.append(.init(id: "set:workspace", group: .settings, title: "Edit \(w.name)", detail: "Workspace settings", look: .workspace(w), also: "workspace settings") { s.editingWorkspace = w.id })
        }
        return out
    }

    /// A file of the agent in front, opened in a tab of its side panel.
    static func file(_ rel: String, of a: Agent, _ s: Store) -> PaletteItem {
        let name = (rel as NSString).lastPathComponent, dir = (rel as NSString).deletingLastPathComponent
        return PaletteItem(id: "file:\(a.id):\(rel)", group: .files, title: name, detail: dir.isEmpty ? nil : dir, look: .icon("file"), also: rel) {
            SidePanel.of(a, home: s.home).openFile(rel)
        }
    }

    /// A message found: opens its chat (a DM or a channel), then asks the chat to show it.
    static func message(_ h: PaletteHit, _ s: Store) -> PaletteItem {
        let agent = h.agentId.flatMap { id in s.agents.first { $0.id == id } }
        let look: PaletteItem.Look = agent.map { .agent($0) } ?? .icon("hash")
        let title = h.place.map { "\(h.title) · \($0)" } ?? h.title
        return PaletteItem(id: "msg:\(h.conv):\(h.id)", group: .messages, title: title, detail: "\(h.by) · \(shortWhen(h.at))", look: look,
                           snippet: (h.snippet.text, h.snippet.start, h.snippet.length)) {
            if let ws = h.workspaceId, let ch = h.channelId { openChannel(ws, ch, s) }
            else if let id = h.agentId { openAgent(id, s) }
            Task {
                await s.loadMessages(h.conv)
                // The chat's view is made (or brought back) on the next pass; then it can scroll.
                try? await Task.sleep(for: .milliseconds(120))
                NotificationCenter.default.post(name: ChatFindNote.jump, object: nil, userInfo: ["agentId": h.conv, "messageId": h.id])
            }
        }
    }
    static func shortWhen(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        if Calendar.current.isDateInToday(d) { return clock(ms) }
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return f.string(from: d)
    }

    // MARK: Recent picks

    static var recent: [String] { UserDefaults.standard.stringArray(forKey: "palette.recent") ?? [] }
    static func remember(_ id: String) {
        var r = recent.filter { $0 != id }; r.insert(id, at: 0)
        UserDefaults.standard.set(Array(r.prefix(12)), forKey: "palette.recent")
    }

    // MARK: Letters in order

    /// Every item whose title (or other words) has the typed letters in order, with a score and the title's matched
    /// letters (UTF-16 offsets). Whole words found together score highest, then the start of the title, then the
    /// start of a word, then letters close together.
    nonisolated static func match(_ q: [UInt16], _ keys: [PaletteModel.Key]) -> [(Int, Double, [Int])] {
        var out: [(Int, Double, [Int])] = []
        for (i, k) in keys.enumerated() {
            if Task.isCancelled { return [] }
            if let (sc, marks) = score(q, k.title) { out.append((i, sc, k.sameLength ? marks : [])) }
            else if let (sc, _) = score(q, k.also) { out.append((i, sc - 600, [])) }
        }
        return out
    }
    nonisolated static func score(_ q: [UInt16], _ h: [UInt16]) -> (Double, [Int])? {
        guard !q.isEmpty, q.count <= h.count else { return nil }
        // Together: the typed text appears as it is.
        if let at = find(q, h) {
            var sc = 1000 - Double(at) * 2 - Double(h.count - q.count) * 0.5
            if at == 0 { sc += 300 } else if boundary(h, at) { sc += 150 }
            return (sc, Array(at..<(at + q.count)))
        }
        // Apart: the letters in order (spaces typed are skipped), preferring the start of words.
        let letters = q.filter { $0 != 32 }
        guard !letters.isEmpty else { return nil }
        var marks: [Int] = [], j = 0, prev = -1, sc = 500.0
        var i = 0
        while i < h.count && j < letters.count {
            if h[i] == letters[j] {
                // A later start of a word with the same letter, before the next letter is needed, reads better.
                var at = i
                if !boundary(h, i), prev != i - 1 {
                    var k = i + 1
                    while k < h.count, j + 1 >= letters.count || h[k] != letters[j + 1] {
                        if h[k] == letters[j] && boundary(h, k) { at = k; break }
                        k += 1
                    }
                }
                if at == prev + 1 { sc += 15 } else if prev >= 0 { sc -= Double(at - prev - 1).squareRoot() * 6 }
                if boundary(h, at) { sc += 25 }
                marks.append(at); prev = at; j += 1; i = at + 1
            } else { i += 1 }
        }
        guard j == letters.count else { return nil }
        return (sc - Double(h.count) * 0.5, marks)
    }
    nonisolated private static func find(_ q: [UInt16], _ h: [UInt16]) -> Int? {
        guard q.count <= h.count else { return nil }
        outer: for i in 0...(h.count - q.count) {
            for j in 0..<q.count where h[i + j] != q[j] { continue outer }
            return i
        }
        return nil
    }
    /// The start of a word: the first letter, or one after a space, -, _, /, . or #.
    nonisolated private static func boundary(_ h: [UInt16], _ i: Int) -> Bool {
        i == 0 || [32, 45, 95, 47, 46, 35, 40, 58].contains(h[i - 1])
    }
}

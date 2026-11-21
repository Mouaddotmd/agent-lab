// App state and behaviour, mirroring src/renderer/app.js: views, back/forward, History, menus.
// Data comes from the engine (Engine.swift); snapshots for the pixel diff run without it.
import SwiftUI
import AppKit

enum Kind: String, CaseIterable {
    case agents, discover, reviews, messages, team, memory, usage, connections, profile
    /// The pages the sidebar, the rail and the Go menu offer. Review, Team and Playbook are parked until they're ready
    /// for the launch: their pages stay in the code, nothing leads to them.
    /// The rail's pages. Discover is hidden for now (its page stays in the code, reachable from nowhere).
    static let nav: [Kind] = [.agents, .messages]
    /// Title-bar icon and name (web: viewInfo / pageHead).
    var info: (icon: String, title: String) {
        switch self {
        case .agents: return ("home", "Home")
        case .discover: return ("compass", "Discover")
        case .reviews: return ("inbox", "Review")
        case .messages: return ("chat", "Messages")
        // Your agents as a team: a map of who's doing what, where each one works and what it's connected to (to come).
        case .team: return ("agents", "Team")
        case .memory: return ("book", "Playbook")
        case .usage: return ("chart", "Usage")
        case .connections: return ("plug", "Plugins")
        case .profile: return ("person", "Profile")
        }
    }
}

/// Where you are: the page, and inside it the workspace, channel or chat that's open. Back and forward (the arrows,
/// ⌘[ ⌘], mouse buttons 4 and 5) walk these, so every place you opened is one step, never skipped.
struct Place: Equatable { var kind: Kind; var workspace: String?; var channel: String; var agent: String? }
struct HistoryEntry: Identifiable { let id = UUID(); var place: Place; var at: Date; var kind: Kind { place.kind } }

@MainActor
final class Store: ObservableObject {
    @Published var view: Kind = .agents { didSet { placeChanged() } }
    @Published var stack: [HistoryEntry] = [.init(place: Place(kind: .agents, workspace: nil, channel: "general", agent: nil), at: Date())]
    @Published var index = 0
    @Published var settingsOpen = false
    @Published var historyOpen = false
    @Published var searchOpen = false
    @Published var newAgentOpen = false
    /// The agent whose Edit form is open (its ⋯ menu: Edit agent).
    @Published var editingAgent: String?
    @Published var createWorkspaceOpen = false

    // Data from the engine.
    @Published var agents: [Agent] = []
    @Published var workspaces: [Workspace] = []
    @Published var home = NSHomeDirectory()
    @Published var engineProblem: String?
    @Published var messages: [String: [Message]] = [:]        // conversation id (an agent's id for a DM, a channel's conv) → its lines
    @Published var runs: [String: Run] = [:]
    /// The channels' own assistant (never listed with your agents): its mode shows in a channel with no agents.
    @Published var assistants: [Agent] = []                  // run key → run
    /// The engine has answered once. Until then nothing says "No agents yet": your agents just haven't arrived.
    @Published var loaded = false
    @Published var drafts: [String: String] = [:]             // run key → reply so far
    @Published var approvals: [Approval] = []
    @Published var openAgent: String? { didSet { placeChanged() } }            // the chat open (in Messages, or a member's DM in a workspace)
    @Published var openWorkspace: String? { didSet { placeChanged() } }        // the workspace open in the sidebar (web: S.space)
    @Published var openChannel = "general" { didSet { placeChanged() } }       // the channel open in that workspace
    @Published var toast: String?
    /// What each agent's box offers (engine: agent:catalog), and its tool's plugins (engine: agent:plugins).
    @Published var catalogs: [String: Catalog] = [:] {
        // Commands and skills any agent offers: they're highlighted wherever they're written (CommandTokens).
        didSet { CommandTokens.learn(Set(catalogs.values.flatMap { $0.commands.map { $0.name.lowercased() } })) }
    }
    @Published var plugins: [String: [PluginItem]] = [:]
    /// Words that go back in an agent's box (after going back to one of your messages).
    @Published var restore: [String: DraftStore.Draft] = [:]
    private var loadingCatalog: Set<String> = []
    @Published var removingWorkspace: String?
    @Published var pending: [PendingSend] = []                // sends not confirmed yet, and queued ones
    @Published var openReport: ReportTag.Report?
    /// Engine message id → the id its row was first shown under, so a confirmed send never remounts.
    private var aliases: [String: String] = [:]
    @Published var editingWorkspace: String?
    /// Something covers the whole window: kept chats take no clicks while it shows (ChatHost).
    var coversChats: Bool { searchOpen || newAgentOpen || editingAgent != nil || createWorkspaceOpen || editingWorkspace != nil || openReport != nil }
    var currentWorkspace: Workspace? { workspaces.first { $0.id == openWorkspace } }
    /// web: data-act="space" — open a workspace; its #general shows first.
    func openSpace(_ id: String) {
        if openWorkspace == nil, view == .messages, let a = openAgent { messagesAgent = a }   // kept for coming back
        openWorkspace = id; openAgent = nil; openChannel = "general"; historyOpen = false; settingsOpen = false
        if let w = workspaces.first(where: { $0.id == id }) { markRead(w) }
    }
    var handle: String { (home as NSString).lastPathComponent }
    var agentCount: Int { agents.count }
    let engine = Engine()
    /// Pane widths and the sidebar's rail (Panes.swift).
    let panes = Panes()
    /// The folded sidebar's floating labels (Panes.swift).
    let railTip = RailTip()

    /// Starts the engine and loads everything (web: loadState). Events reload what changed.
    private var connected = false
    func connect() {
        if connected { return }; connected = true
        listenForMouseButtons()
        // Helpers, running commands, side chats, context, find and jump (ConvoModel.swift) hear the engine from here on.
        ConvoHub.shared.attach(self)
        // The agents' hands on their side panes (browser, terminal, files) answer the engine from here on.
        AgentHands.start(self)
        // A mouse wheel glides as on mouad.work, everywhere that scrolls up and down (SmoothScroll.swift).
        SmoothScroll.shared.start()
        ClickAway.install()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [engine] _ in
            MainActor.assumeIsolated { engine.stop() }
        }
        engine.onEvent = { [weak self] ev in
            guard let self else { return }
            switch ev["type"] as? String {
            case "state": Task { await self.load() }
            case "run":
                if let r = ev["run"], let run = try? Store.decode(r, Run.self) { self.runs[run.key] = run }
            case "run-end":
                // The finished turn swaps in in one update: the run and its words stay until its saved messages are
                // here, so nothing vanishes for a moment and types back in.
                let key = ev["key"] as? String ?? ""
                self.endedAt[key] = Date()
                if let id = (ev["conv"] as? String) ?? (ev["agentId"] as? String) {
                    self.settle(key)
                    Task { await self.loadMessages(id) { self.runs[key] = nil; self.drafts[key] = nil }; self.sendQueued(id); self.openFinishedReports(id) }
                } else { self.runs[key] = nil; self.drafts[key] = nil }
                if let e = ev["error"] as? String, e != "Stopped.", let id = ev["agentId"] as? String, self.openAgent != id {
                    self.toast = "\(self.agents.first { $0.id == id }?.name ?? "An agent") stopped: \(e)"
                }
                Task { await self.load() }
            case "delta":
                if let key = ev["key"] as? String { self.drafts[key] = ev["text"] as? String }
            case "messages":
                // A block of words was saved: its draft holds its place until the saved copy is loaded (17 Nov).
                // `agentId` is the conversation; `key` the run that wrote it (a DM's run key is "agent:" + its id).
                if let id = ev["agentId"] as? String { self.settle((ev["key"] as? String) ?? "agent:\(id)"); Task { await self.loadMessages(id) } }
            case "approvals": Task { self.approvals = (try? await self.engine.call("approvals", as: [Approval].self)) ?? self.approvals }
            default: break
            }
            // Every event also goes out to whoever listens (the side panel's tabs: helpers, terminal, changes…).
            NotificationCenter.default.post(name: .engineEvent, object: nil, userInfo: ev)
        }
        engine.onExit = { [weak self] why in self?.engineProblem = why }
        do { try engine.start(); engineProblem = nil } catch { engineProblem = error.localizedDescription; return }
        Task { await load() }
    }
    func load() async {
        let asked = Date()
        do {
            let st = try await engine.call("state", as: EngineState.self)
            agents = st.agents.filter { $0.hidden != true }; assistants = st.agents.filter { $0.hidden == true }; workspaces = st.workspaces; home = st.home; approvals = st.approvals; loaded = true
            // Names in the agents' words that are real files link to them (RichText.fileLink).
            RichText.roots = Array(Set(st.agents.compactMap(\.cwd))).sorted() + [st.home, (st.home as NSString).appendingPathComponent("Desktop")]
            FileNames.shared.refresh(roots: RichText.roots)
            CommandTokens.rootsChanged(RichText.roots)
            // Every conversation is fetched once in the background, so opening or switching chats never waits on it.
            for a in agents where messages[a.id] == nil { Task { await loadMessages(a.id) } }
            // Runs change in the same update as the open chat's messages: a run that just ended never leaves its turn
            // without its words for a frame.
            // A run that ended while this was on its way stays ended (a late reply never brings back a finished run).
            let apply = { self.runs = Dictionary(st.runs.filter { (self.endedAt[$0.key] ?? .distantPast) < asked }.map { ($0.key, $0) }, uniquingKeysWith: { $1 }) }
            if let id = openAgent ?? currentWorkspace?.conv(openChannel) { await loadMessages(id, then: apply) } else { apply() }
        } catch { engineProblem = error.localizedDescription }
    }

    static func decode<T: Decodable>(_ v: Any, _ t: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]))
    }
    /// Words already streamed whose saved copy is on its way: (number, text) per run key, shown before the live draft.
    private var settling: [String: [(n: Int, text: String)]] = [:]
    private var settled = 0
    private var endedAt: [String: Date] = [:]
    private func settle(_ key: String) {
        guard let d = drafts[key], !d.isEmpty else { return }
        settled += 1
        settling[key, default: []].append((settled, d))
        drafts[key] = nil
    }
    /// The words streaming now: anything still settling, then the live draft.
    func draft(_ key: String) -> String? {
        let parts = (settling[key] ?? []).map(\.text) + [drafts[key]].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
    /// Loads one conversation. `then` runs in the same update as the new messages (never a frame apart).
    func loadMessages(_ id: String, then: (() -> Void)? = nil) async {
        let upTo = settled
        // The runs writing into this conversation: their settled words are in the saved copy now.
        let keys = Set(runs.values.filter { $0.conversation == id }.map(\.key) + ["agent:\(id)"])
        func clear() { for k in keys { settling[k]?.removeAll { $0.n <= upTo } } }
        guard let m = try? await engine.call("agent:messages", [id], as: [Message].self) else {
            then?(); clear()
            if messages[id] == nil { messages[id] = [] }      // a failed load still opens the chat (never blank for good)
            return
        }
        clear()
        then?()
        // Sends the engine now has take over their rows (same id), and leave the pending list.
        let mine = pending.filter { $0.agentId == id }
        let (_, claimed) = Transcript.build(m, run: nil, draft: nil, pending: mine, aliases: aliases)
        for (msg, temp) in claimed { aliases[msg] = temp }
        if !claimed.isEmpty { pending.removeAll { p in claimed.values.contains(p.id) } }
        // Unchanged (opening a chat reloads it): leave it, so nothing that shows it is redrawn for no reason.
        // The files its steps touched name the files its words mention (before the rows are drawn: same look every time).
        if messages[id] != m { FileNames.shared.touched(m); messages[id] = m; if id.hasPrefix("c_") { noteActivity(id) } }
        // First time this chat is seen: what's there now counts as read (only newer replies are counted).
        if !id.hasPrefix("c_"), readAt[id] == nil, let last = m.last?.at { readAt[id] = last; UserDefaults.standard.set(readAt, forKey: "chat.readAt") }
    }
    /// One conversation as rows (ChatTurns.swift): a DM (the agent's id) or a channel (its conv id). Pure: drawing
    /// never changes anything.
    func rows(for id: String) -> [ChatRow] {
        let live = runs.values.filter { $0.conversation == id }.sorted { $0.key < $1.key }.map { (run: $0, draft: draft($0.key)) }
        let input = RowsInput(messages: messages[id] ?? [], runs: live.map(\.run), drafts: live.map(\.draft), pending: pending.filter { $0.agentId == id }, aliases: aliases)
        // Built once per change to this conversation, not once per redraw: any change anywhere in the app redraws the
        // open chat, and rebuilding every row each time grew with the chat's length. Comparing is cheap: an unchanged
        // messages array is the same storage, which == checks first.
        if let hit = rowsCache[id], hit.input == input { return hit.rows }
        let rows = Transcript.build(input.messages, live: live, pending: input.pending, aliases: aliases).rows
        rowsCache[id] = (input, rows)
        return rows
    }
    struct RowsInput: Equatable { var messages: [Message]; var runs: [Run]; var drafts: [String?]; var pending: [PendingSend]; var aliases: [String: String] }
    private var rowsCache: [String: (input: RowsInput, rows: [ChatRow])] = [:]
    /// Post in a channel: shows at once, never waits (each tagged agent answers when it can; a busy one says so).
    func sendToChannel(_ w: Workspace, _ channel: String, _ text: String, images: [String] = [], files: [String] = []) {
        let t = Attachments.prompt(text.trimmingCharacters(in: .whitespacesAndNewlines), files: files)
        guard !t.isEmpty || !images.isEmpty else { return }
        let conv = w.conv(channel)
        let p = PendingSend(id: "p\(UUID().uuidString.prefix(8))", agentId: conv, text: t, at: Date().timeIntervalSince1970 * 1000, queued: false, channel: channel)
        pending.append(p)
        Task {
            do { _ = try await engine.call("channel:send", [w.id, channel, t, images]); await loadMessages(conv) }
            catch { pending.removeAll { $0.id == p.id }; toast = error.localizedDescription }
        }
    }
    /// Invite an agent to a workspace, or take it out. It's the same agent either way: same DM, same memory.
    func setMember(_ agentId: String, _ wsId: String, _ on: Bool) async {
        do {
            let w = try await engine.call("workspace:member", [wsId, agentId, on], as: Workspace.self)
            if let i = workspaces.firstIndex(where: { $0.id == wsId }) { workspaces[i] = w }
        } catch { toast = error.localizedDescription }
    }
    func members(of w: Workspace) -> [Agent] { (w.members ?? []).compactMap { id in agents.first { $0.id == id } } }
    /// Channels are saved as the workspace's categories (engine: workspace:update).
    func saveChannels(_ w: Workspace, _ categories: [Workspace.Category]) async {
        let plain: [[String: Any]] = categories.map { c in
            var d: [String: Any] = ["id": c.id, "name": c.name, "open": c.open ?? true, "channels": c.channels.map { ch -> [String: Any] in
                var x: [String: Any] = ["id": ch.id, "name": ch.name]
                if let a = ch.agents { x["agents"] = a }
                return x
            }]
            if let color = c.color { d["color"] = color }
            return d
        }
        do { try await updateWorkspace(w.id, ["categories": plain]) } catch { toast = error.localizedDescription }
    }
    /// Send from the chat box (chat-rules §6): your message shows at once; while the agent works it waits its turn.
    func sendMessage(_ id: String, _ text: String, images: [String] = [], files: [String] = []) {
        let t = Attachments.prompt(text.trimmingCharacters(in: .whitespacesAndNewlines), files: files)
        guard !t.isEmpty || !images.isEmpty else { return }
        // While it works, a message goes into what it's doing; if it just finished, it waits its turn like before.
        if runs["agent:\(id)"] != nil {
            Task {
                let took = (try? await engine.call("agent:steer", [id, t, images])) as? Bool ?? false
                if took { await loadMessages(id) } else { queue(id, t, images) }
            }
            return
        }
        queue(id, t, images)
    }
    private func queue(_ id: String, _ t: String, _ images: [String]) {
        let busy = runs["agent:\(id)"] != nil || pending.contains { $0.agentId == id && !$0.queued }
        let p = PendingSend(id: "p\(UUID().uuidString.prefix(8))", agentId: id, text: t, at: Date().timeIntervalSince1970 * 1000, queued: busy, channel: nil, images: images)
        pending.append(p)
        if !busy { deliver(p) }
    }
    private func deliver(_ p: PendingSend) {
        Task {
            do { _ = try await engine.call("agent:send", [p.agentId, p.text, p.images]); await loadMessages(p.agentId) }
            catch {
                pending.removeAll { $0.id == p.id }
                toast = error.localizedDescription
            }
        }
    }
    /// The run ended: the next queued message goes in.
    private func sendQueued(_ id: String) {
        guard runs["agent:\(id)"] == nil, !pending.contains(where: { $0.agentId == id && !$0.queued }),
              let i = pending.firstIndex(where: { $0.agentId == id && $0.queued }) else { return }
        pending[i].queued = false
        pending[i] = PendingSend(id: pending[i].id, agentId: id, text: pending[i].text, at: Date().timeIntervalSince1970 * 1000, queued: false, channel: nil, images: pending[i].images)
        deliver(pending[i])
    }
    /// web: go({ kind: 'dm', id })
    func openChat(_ id: String) {
        openAgent = id; go(.messages)
        Task { await loadMessages(id) }
    }
    /// An agent's asks in its own chat (a channel's asks stay in the channel).
    func approvalsFor(_ id: String) -> [Approval] { approvals.filter { $0.agentId == id && ($0.conv == nil || $0.conv == id) } }
    /// web: stateOf
    func state(of a: Agent) -> String {
        if !approvalsFor(a.id).isEmpty { return "needs" }
        if runs["agent:\(a.id)"] != nil { return "working" }
        if a.last?.state == "failed" { return "failed" }
        if a.last?.state == "done" && a.last?.seen != true { return "done" }
        return "idle"
    }
    /// Sends a message; the reply streams in through events.
    func send(_ id: String, _ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        do { _ = try await engine.call("agent:send", [id, t]) } catch { toast = error.localizedDescription }
    }
    func stop(_ key: String) { Task { _ = try? await engine.call("run:stop", [key]) } }

    /// Back to just before one of your messages: the chat loses it and what followed, the box gets it back.
    func rewind(_ agentId: String, _ messageId: String) {
        let real = aliases.first(where: { $0.value == messageId })?.key ?? messageId
        Task {
            do {
                struct Back: Decodable { let text: String; let images: [String]; let note: String? }
                let back = try await engine.call("agent:rewind", [agentId, real], as: Back.self)
                await loadMessages(agentId)
                restore[agentId] = DraftStore.Draft(text: back.text, images: back.images, files: [])
                toast = "Went back." + (back.note.map { " " + $0 } ?? "")
            } catch { toast = error.localizedDescription }
        }
    }

    /// The row a message of a conversation shows in (yours, the turn it belongs to, or a note), for jumping to it.
    func rowId(forMessage id: String, in conv: String) -> String? {
        let list = messages[conv] ?? []
        guard let i = list.firstIndex(where: { $0.id == id }) else { return nil }
        let m = list[i]
        func name(_ x: String) -> String { aliases[x] ?? x }
        switch m.role {
        case "user": return "you-" + name(m.id)
        case "note": return "note-" + m.id
        default:
            guard let parent = m.turn.map(name) ?? list[..<i].last(where: { $0.role == "user" }).map({ name($0.id) }) else { return nil }
            let turn = "turn-" + (m.by.map { "\(parent)·\($0)" } ?? parent)
            return rows(for: conv).contains { $0.id == turn } ? turn : "you-" + parent
        }
    }

    // MARK: Fork, hand off, side chats (engine/convo.js)

    /// The agent whose hand-off picker is open (its ⋯ menu, or /handoff in its box).
    @Published var handingOff: String?

    /// A new agent like this one, its chat everything before one of your messages; that message goes in its box.
    func fork(_ agentId: String, _ messageId: String) {
        let real = aliases.first(where: { $0.value == messageId })?.key ?? messageId
        Task {
            struct Forked: Decodable { let agent: Agent; let text: String; let images: [String] }
            do {
                let f = try await engine.call("convo:fork", [agentId, real], as: Forked.self)
                if !agents.contains(where: { $0.id == f.agent.id }) { agents.append(f.agent) }
                if let st = try? await engine.call("state", as: EngineState.self) { workspaces = st.workspaces }
                restore[f.agent.id] = DraftStore.Draft(text: f.text, images: f.images, files: [])
                openChat(f.agent.id)
                toast = "Forked into \(f.agent.name). Change the message and send it."
            } catch { toast = error.localizedDescription }
        }
    }

    /// Passes a DM to another agent: it gets a note on where things stand as your first message, its chat opens and
    /// it starts on it. The note takes a few seconds to write.
    func handOff(_ from: String, to: String) {
        guard let target = agents.first(where: { $0.id == to }) else { return }
        toast = "Writing a hand-over note for \(target.name)…"
        Task {
            do {
                _ = try await engine.call("convo:handoff", [from, to])
                await loadMessages(from)
                openChat(to)
                toast = "Handed to \(target.name)."
            } catch { toast = error.localizedDescription }
        }
    }

    /// A side chat with an agent in its panel: asked at once when there's a question (/btw), else empty to ask in.
    /// `replacing`: a new tab that becomes this chat (it stays there, in place, as the chat starts).
    func openSideChat(_ agent: Agent, question: String? = nil, replacing: String? = nil) {
        let panel = SidePanel.of(agent, home: home)
        let q = (question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                struct Made: Decodable { let id: String; let title: String }
                let made = q.isEmpty ? try await engine.call("convo:sideNew", [agent.id], as: Made.self)
                                     : try await engine.call("convo:sideAsk", [agent.id, NSNull(), q], as: Made.self)
                _ = ConvoHub.shared.side(agent.id, made.id)
                let tab = PanelTab(kind: .side(id: made.id, title: made.title))
                if let replacing { panel.replace(replacing, with: tab) } else { panel.show(tab) }
            } catch { toast = error.localizedDescription }
        }
    }

    // MARK: What the box offers

    /// A turn just finished with a long report: it opens beside the chat by itself, once (Reports.opened), as a thread
    /// you can close. Only in an agent's own chat, which has the side panel.
    func openFinishedReports(_ id: String) {
        guard let agent = agents.first(where: { $0.id == id }), let ms = messages[id] else { return }
        let rows = Transcript.build(ms, run: nil, draft: nil, pending: []).rows
        guard let turn = rows.reversed().compactMap({ r -> Turn? in if case .agent(let t) = r { t } else { nil } }).first else { return }
        for (i, r) in ReportTag.reports(turn.raw).enumerated() {
            let report = ReportTag.Report(title: r.title, body: r.body, finished: true)
            let rid = Reports.id(turn.id, i)
            guard report.long, !Reports.shared.opened.contains(rid) else { continue }
            Reports.shared.opened.insert(rid)
            SidePanel.of(agent, home: home).showReport(id: rid, report)
        }
    }

    func loadCatalog(_ id: String, fresh: Bool = false) {
        guard fresh || catalogs[id] == nil, !loadingCatalog.contains(id) else { return }
        loadingCatalog.insert(id)
        Task {
            defer { loadingCatalog.remove(id) }
            if let c = try? await engine.call("agent:catalog", [id, fresh], as: Catalog.self) { catalogs[id] = c }
        }
    }

    func loadPlugins(_ id: String) {
        Task {
            do { plugins[id] = try await engine.call("agent:plugins", [id], as: [PluginItem].self) }
            catch { plugins[id] = []; toast = error.localizedDescription }
        }
    }

    func setPlugin(_ id: String, _ plugin: PluginItem, on: Bool) {
        if let i = plugins[id]?.firstIndex(where: { $0.id == plugin.id }) { plugins[id]?[i].enabled = on }
        Task {
            do {
                _ = try await engine.call("agent:plugin", [id, plugin.id, on])
                toast = "\(plugin.name) is \(on ? "on" : "off")."
                loadCatalog(id, fresh: true)
            } catch {
                if let i = plugins[id]?.firstIndex(where: { $0.id == plugin.id }) { plugins[id]?[i].enabled = !on }
                toast = error.localizedDescription
            }
        }
    }

    /// "Use my Claude Code setup" for one agent: its next runs start with your skills, plugins and CLAUDE.md.
    func setClaudeSetup(_ agent: Agent, on: Bool) {
        Task {
            do {
                try await updateAgent(agent.id, ["claudeSetup": on])
                toast = on ? "\(agent.name) now uses your Claude Code setup." : "\(agent.name) runs on Agent Lab's rules only."
                loadCatalog(agent.id, fresh: true)
            } catch { toast = error.localizedDescription }
        }
    }
    func answer(_ id: String, _ decision: String, _ extra: Any? = nil) {
        Task { do { _ = try await engine.call("approval:answer", [id, decision, extra ?? NSNull()]) } catch { toast = error.localizedDescription } }
    }
    func updateAgent(_ id: String, _ patch: [String: Any]) async throws {
        let a = try await engine.call("agent:update", [id, patch], as: Agent.self)
        if let i = agents.firstIndex(where: { $0.id == id }) { agents[i] = a }
    }
    /// A copy of an agent (engine: agent:duplicate), opened.
    func duplicateAgent(_ id: String) async {
        do {
            let copy = try await engine.call("agent:duplicate", [id], as: Agent.self)
            agents.append(copy)
            if let st = try? await engine.call("state", as: EngineState.self) { workspaces = st.workspaces }
            toast = "Made \(copy.name)."
            openChat(copy.id)
        } catch { toast = error.localizedDescription }
    }

    func deleteAgent(_ id: String) async {
        do { _ = try await engine.call("agent:delete", [id]); agents.removeAll { $0.id == id }; messages[id] = nil; if openAgent == id { openAgent = nil } }
        catch { toast = error.localizedDescription }
    }
    /// web: saveProject (new). A workspace is a name and a colour; a folder is optional.
    func createWorkspace(name: String, about: String, color: String, path: String?, image: String? = nil) async throws -> Workspace {
        let w = try await engine.call("workspace:create", [["name": name, "about": about, "color": color, "path": (path as Any?) ?? NSNull(), "image": (image as Any?) ?? NSNull()] as [String: Any]], as: Workspace.self)
        if !workspaces.contains(where: { $0.id == w.id }) { workspaces.append(w) }
        return w
    }
    /// web: saveProject (edit). image: a data URL to set, NSNull to remove.
    func updateWorkspace(_ id: String, _ patch: [String: Any]) async throws {
        var w = try await engine.call("workspace:update", [id, patch], as: Workspace.self)
        if let i = workspaces.firstIndex(where: { $0.id == id }) { w.activityAt = workspaces[i].activityAt; workspaces[i] = w }
    }

    // MARK: Workspaces: read, muted, invite

    /// When an agent last spoke in each workspace, as messages arrive (on top of what the engine said at load).
    @Published var wsActivity: [String: Double] = [:]
    /// A workspace whose invite list should open (from its menu).
    @Published var invitingWorkspace: String?
    /// The rail tile whose workspace menu is open (right-click).
    @Published var railMenu: String?
    /// Something new in it since you last caught up, and it isn't muted.
    func unread(_ w: Workspace) -> Bool {
        guard w.muted != true, openWorkspace != w.id else { return false }
        return max(w.activityAt ?? 0, wsActivity[w.id] ?? 0) > (w.readAt ?? 0)
    }
    func markRead(_ w: Workspace) {
        let now = Date().timeIntervalSince1970 * 1000
        guard (w.readAt ?? 0) < max(w.activityAt ?? 0, wsActivity[w.id] ?? 0, 1) else { return }
        if let i = workspaces.firstIndex(where: { $0.id == w.id }) { workspaces[i].readAt = now }
        Task { try? await updateWorkspace(w.id, ["readAt": now]) }
    }
    func setMuted(_ w: Workspace, _ on: Bool) {
        if let i = workspaces.firstIndex(where: { $0.id == w.id }) { workspaces[i].muted = on }
        Task {
            do { try await updateWorkspace(w.id, ["muted": on]); toast = on ? "\(w.name) is muted." : "\(w.name) is unmuted." }
            catch { toast = error.localizedDescription }
        }
    }
    /// A channel conversation's workspace, from its id (c_<workspace>_<channel>).
    func workspaceOf(conv: String) -> Workspace? {
        guard conv.hasPrefix("c_") else { return nil }
        return workspaces.filter { conv.hasPrefix("c_\($0.id)_") }.max { $0.id.count < $1.id.count }
    }
    /// Notes when an agent spoke in a channel: unread elsewhere, read at once in the one you're in.
    func noteActivity(_ conv: String) {
        guard let w = workspaceOf(conv: conv), let last = messages[conv]?.last(where: { $0.role != "user" })?.at else { return }
        if last > (wsActivity[w.id] ?? 0) { wsActivity[w.id] = last }
        if openWorkspace == w.id { markRead(w) }
    }
    func removeWorkspace(_ id: String) async {
        do { _ = try await engine.call("workspace:remove", [id]); workspaces.removeAll { $0.id == id }; if openWorkspace == id { openWorkspace = nil } }
        catch { toast = error.localizedDescription }
    }

    /// web: saveAgentForm (new agent). Returns the agent, or throws with a message to show.
    func createAgent(name: String, job: String, look: Look, operator op: String, model: String?, permission: String, cwd: String, workspace: String? = nil) async throws -> Agent {
        var spec: [String: Any] = ["name": name, "job": job, "look": ["bg": look.spec.bg, "skin": look.spec.skin, "hair": look.spec.hair, "shirt": look.spec.shirt, "style": look.style, "glasses": look.glasses],
                                   "operator": op, "permission": permission, "cwd": cwd, "ownBranch": false]
        spec["model"] = model ?? NSNull()
        spec["workspace"] = workspace ?? NSNull()
        let a = try await engine.call("agent:create", [spec], as: Agent.self)
        if !agents.contains(where: { $0.id == a.id }) { agents.append(a) }
        if workspace != nil { await load() }                 // it was invited there: pick up the new member list
        return a
    }

    var canBack: Bool { index > 0 }
    var canForward: Bool { index < stack.count - 1 }

    /// Opens a Personal page (it leaves the workspace; web: S.space = 'home').
    func go(_ kind: Kind, nav: Bool = false) {
        historyOpen = false; settingsOpen = false
        let fromWorkspace = openWorkspace != nil
        openWorkspace = nil
        // Back to Messages from a workspace: the chat you had open there, not none.
        if kind == .messages, fromWorkspace || openAgent == nil, let a = messagesAgent, agents.contains(where: { $0.id == a }) { openAgent = a }
        view = kind
    }
    /// The chat open in Messages, kept while you visit a workspace.
    var messagesAgent: String?

    // MARK: Unread (the red counts): replies since you last had a chat or a workspace open

    /// When you last saw each agent's chat (ms), kept across launches.
    @Published var readAt: [String: Double] = (UserDefaults.standard.dictionary(forKey: "chat.readAt") as? [String: Double]) ?? [:]
    func markAgentRead(_ id: String) {
        let last = messages[id]?.last?.at ?? Date().timeIntervalSince1970 * 1000
        guard (readAt[id] ?? 0) < last else { return }
        readAt[id] = last
        UserDefaults.standard.set(readAt, forKey: "chat.readAt")
    }
    /// Replies (turns) in an agent's chat since you last saw it; none while it's the one open.
    func unreadReplies(_ id: String) -> Int {
        if view == .messages, openWorkspace == nil, openAgent == id { return 0 }
        guard let r = readAt[id] else { return 0 }
        return Set((messages[id] ?? []).filter { $0.role == "assistant" && ($0.at ?? 0) > r }.map { $0.turn ?? $0.id }).count
    }
    /// What a workspace's tile counts: approvals its agents are waiting on, plus replies in its channels since you were
    /// last there (at least one when something's new).
    func needsCount(_ w: Workspace) -> Int {
        guard w.muted != true else { return 0 }
        let members = Set(w.members ?? [])
        let asks = approvals.filter { members.contains($0.agentId ?? "") }.count
        var replies = 0
        if unread(w) {
            for ch in w.channels {
                replies += Set((messages[w.conv(ch.id)] ?? []).filter { $0.role == "assistant" && ($0.at ?? 0) > (w.readAt ?? 0) }.map { $0.turn ?? $0.id }).count
            }
            replies = max(replies, 1)
        }
        return asks + replies
    }

    // History. Whatever changes the place (a page, a workspace, a channel, a chat; any number of fields at once) is
    // recorded once, after the change settles, as one step. Going back or forward puts the place back exactly, which
    // matches the entry, so it records nothing new.
    var place: Place { Place(kind: view, workspace: openWorkspace, channel: openChannel, agent: openAgent) }
    private var recordPending = false
    private func placeChanged() {
        guard !recordPending else { return }
        recordPending = true
        DispatchQueue.main.async { [weak self] in self?.recordPending = false; self?.record() }
    }
    private func record() {
        let p = place
        if stack.indices.contains(index), stack[index].place == p { return }
        stack = Array(stack.prefix(index + 1)); stack.append(.init(place: p, at: Date()))
        if stack.count > 100 { stack.removeFirst() }
        index = stack.count - 1
    }
    func step(_ d: Int) { jump(index + d) }
    func jump(_ j: Int) {
        guard stack.indices.contains(j) else { return }
        index = j; stack[j].at = Date()
        var p = stack[j].place
        // A chat or workspace removed since is skipped over: its page opens without it.
        if let a = p.agent, !agents.contains(where: { $0.id == a }) { p.agent = nil }
        if let w = p.workspace, !workspaces.contains(where: { $0.id == w }) { p.workspace = nil; p.agent = nil }
        historyOpen = false; settingsOpen = false
        view = p.kind; openWorkspace = p.workspace; openChannel = p.channel; openAgent = p.agent
        stack[j].place = p
        if let a = p.agent { Task { await loadMessages(a) } }
        else if let w = currentWorkspace { Task { await loadMessages(w.conv(p.channel)) } }
    }

    /// Mouse buttons 4 and 5 go back and forward, like a browser (on release, as browsers do).
    private var mouseButtons: Any?
    func listenForMouseButtons() {
        guard mouseButtons == nil else { return }
        mouseButtons = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self] e in
            guard e.buttonNumber == 3 || e.buttonNumber == 4 else { return e }
            if e.type == .otherMouseUp { self?.step(e.buttonNumber == 3 ? -1 : 1) }
            return nil
        }
    }

    /// Recently viewed: newest first, each screen once, at most 8 (web: histMenu).
    var recent: [(Int, HistoryEntry)] {
        var seen = Set<Kind>(), rows: [(Int, HistoryEntry)] = []
        for j in stack.indices.reversed() where rows.count < 8 { let e = stack[j]; if seen.insert(e.kind).inserted { rows.append((j, e)) } }
        return rows
    }
    func closeMenus() { settingsOpen = false; historyOpen = false }
}

/// "just now", "4 min ago", … (web: ago)
func ago(_ d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    if s < 45 { return "just now" }
    if s < 3600 { return "\(max(1, s / 60)) min ago" }
    if s < 86400 { return "\(s / 3600) h ago" }
    return "\(s / 86400) d ago"
}

import SwiftUI
import AppKit

enum Nav: Hashable {
    case agents, memory, connections
    case agent(String)
    case chats(String)
    case review(String)
}

enum AgentsTab: String, CaseIterable, Identifiable {
    case working, waiting, done, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .done: "Done"
        case .all: "All"
        }
    }
}

enum Sheet: Identifiable {
    case newAgent(String?)
    case editAgent(String)
    case promote(Chat)
    case handoff(Chat)
    case search
    case confirm(Confirm)
    var id: String {
        switch self {
        case .newAgent(let op): "new-\(op ?? "")"
        case .editAgent(let id): "edit-\(id)"
        case .promote(let c): "promote-\(c.id)"
        case .handoff(let c): "handoff-\(c.id)"
        case .search: "search"
        case .confirm(let c): "confirm-\(c.title)"
        }
    }
}

struct Confirm {
    var title: String
    var body: String
    var ok: String
    var danger: Bool
    var action: () -> Void
}

/// Everything on screen, kept in step with the engine.
@MainActor @Observable
final class Lab {
    let engine = EngineClient()

    // From the engine
    var agents: [Agent] = []
    var workspaces: [Workspace] = []
    var memory: [Decision] = []
    var runs: [String: Run] = [:]
    var approvals: [Approval] = []
    var operators: [String: OperatorInfo] = [:]
    var codexModels: [String] = []
    var importedCount = 0
    var home = NSHomeDirectory()
    var messages: [String: [Message]] = [:]
    var drafts: [String: String] = [:]
    var chats: [String: [Chat]] = [:]
    var transcripts: [String: [Line]] = [:]
    var live: [String: [Line]] = [:]
    var overlaps: [Overlap] = []
    var mavis: MavisScan?

    // Where you are
    var nav: Nav? = .agents
    var tab: AgentsTab = .all
    var scope: String?               // a workspace id, or nil for everything
    var selectedChat: [String: String] = [:]
    var sheet: Sheet?
    var showRightNow = true
    var nowOpen = false              // the Right now drawer, when the window is narrow
    var fold: Set<String> = []
    var opq = ""
    var inputs: [String: String] = [:]   // unsent text, per conversation
    var merging = false
    var reviewTick = 0
    var toast: String?
    var toastIsError = false
    var startupError: String?
    var loaded = false

    // MARK: start

    func start() {
        engine.onEvent = { [weak self] ev in self?.handle(ev) }
        engine.onExit = { [weak self] tail in
            Task { @MainActor in self?.startupError = tail.isEmpty ? "The engine stopped." : "The engine stopped: \(tail.suffix(400))" }
        }
        do { try engine.start() } catch { startupError = error.localizedDescription }
    }

    func reload() async {
        do {
            let s: LabState = try await engine.call("state")
            agents = s.agents; workspaces = s.workspaces; memory = s.memory
            runs = Dictionary(uniqueKeysWithValues: s.runs.map { ($0.key, $0) })
            approvals = s.approvals; operators = s.operators; codexModels = s.codexModels ?? []
            importedCount = s.imported; home = s.home
            if let scope, !workspaces.contains(where: { $0.id == scope }) { self.scope = nil }
            for a in agents where messages[a.id] == nil { messages[a.id] = (try? await engine.call("agent:messages", a.id)) ?? [] }
            loaded = true
            await refreshOverlaps()
            for op in ["claude-code", "codex"] where operators[op]?.path != nil { Task { await loadChats(op) } }
            if importedCount > 0 { Task { await loadChats("mavis") } }
        } catch {
            startupError = error.localizedDescription
        }
    }

    // MARK: events

    func handle(_ ev: EngineEvent) {
        switch ev.type {
        case "ready": Task { await reload() }
        case "run":
            if let r = ev.run { runs[r.key] = r }
        case "run-end":
            guard let key = ev.key else { return }
            runs[key] = nil; drafts[key] = nil
            if let id = ev.agentId {
                Task {
                    if let list: [Agent] = try? await engine.call("agents") { agents = list }
                    await refreshOverlaps()
                    if let err = ev.error, err != "Stopped.", nav != .agent(id) { show("\(agent(id)?.name ?? "An agent") stopped: \(err)", error: true) }
                }
            }
        case "delta":
            if let key = ev.key { drafts[key] = ev.text }
        case "messages":
            guard let id = ev.agentId else { return }
            Task {
                if let list: [Message] = try? await engine.call("agent:messages", id) { messages[id] = list }
                drafts["agent:\(id)"] = nil
            }
        case "approvals":
            Task { if let list: [Approval] = try? await engine.call("approvals") { approvals = list } }
        case "chat-line":
            if let key = ev.key, let line = ev.line { live[key, default: []].append(line); drafts[key] = nil }
        case "chat-end":
            guard let key = ev.key else { return }
            let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return }
            Task {
                if let t: [Line] = try? await engine.call("chat:transcript", parts[1], parts[2]) { transcripts["\(parts[1]):\(parts[2])"] = t; live[key] = nil }
                if let err = ev.error, err != "Stopped." { show(err, error: true) }
                await loadChats(parts[1], force: true)
            }
        case "git": Task { await refreshOverlaps() }
        default: break
        }
    }

    // MARK: derived

    func agent(_ id: String) -> Agent? { agents.first { $0.id == id } }
    func workspace(of a: Agent) -> Workspace? {
        workspaces.first { w in inside(a.cwd, w.path) || a.baseRepo == w.path || inside(a.baseRepo, w.path) }
    }
    func inside(_ dir: String?, _ root: String?) -> Bool {
        guard let dir, let root else { return false }
        return dir == root || dir.hasPrefix(root + "/")
    }
    var currentWorkspace: Workspace? { workspaces.first { $0.id == scope } }
    func inScope(_ a: Agent) -> Bool { scope == nil || workspace(of: a)?.id == scope }
    func inScope(_ c: Chat) -> Bool { scope == nil || inside(c.cwd, currentWorkspace?.path) }
    var scopedAgents: [Agent] { agents.filter(inScope) }

    func approvals(for id: String) -> [Approval] { approvals.filter { $0.agentId == id } }
    func state(of a: Agent) -> AgentState {
        if !approvals(for: a.id).isEmpty { return .waiting }
        if runs["agent:\(a.id)"] != nil { return .working }
        if a.last?.state == "failed" { return .failed }
        if a.last?.state == "done", a.last?.seen != true { return .done }
        return .ready
    }
    func status(of a: Agent) -> String {
        switch state(of: a) {
        case .waiting: if let p = approvals(for: a.id).first { return "Wants to \(p.verb.lowercased()) \(p.line)" }
        case .working: return runs["agent:\(a.id)"]?.activity ?? "Working"
        case .failed: return "Stopped with an error"
        default: break
        }
        if let last = messages[a.id]?.last(where: { $0.role == "assistant" }) { return last.text.replacingOccurrences(of: "\n", with: " ") }
        if let job = a.job, !job.isEmpty { return job }
        return a.origin?.title ?? "Ready when you are"
    }
    var waitingCount: Int {
        approvals.filter { p in agent(p.agentId ?? "").map(inScope) ?? false }.count
        + overlaps.filter { $0.agents.contains { agent($0).map(inScope) ?? false } }.count
    }
    /// A chat that is an agent's own session belongs to that agent.
    func visibleChats(_ op: String) -> [Chat] {
        let own = Set(agents.compactMap(\.sessionId))
        return (chats[op] ?? []).filter { !own.contains($0.id) && inScope($0) }
    }
    func chat(_ op: String, _ id: String?) -> Chat? { (chats[op] ?? []).first { $0.id == id } }
    /// The team in the order it matters: waiting, working, failed, done, ready; pinned first; newest first.
    var team: [Agent] {
        scopedAgents.sorted { a, b in
            (state(of: a).rawValue, a.pinned == true ? 0 : 1, -(a.createdAt ?? 0)) < (state(of: b).rawValue, b.pinned == true ? 0 : 1, -(b.createdAt ?? 0))
        }
    }
    var sidebarOperators: [String] { ["claude-code", "codex", "mavis"].filter { $0 == "mavis" ? importedCount > 0 : operators[$0]?.path != nil } }
    var availableOperators: [String] { Operators.all.filter { operators[$0]?.path != nil } }

    // MARK: actions

    func show(_ text: String, error: Bool = false) {
        toast = text; toastIsError = error
        let current = text
        Task { try? await Task.sleep(for: .seconds(error ? 5 : 2.5)); if toast == current { toast = nil } }
    }

    func attempt<T>(_ work: () async throws -> T) async -> T? {
        do { return try await work() } catch { show(error.localizedDescription, error: true); return nil }
    }

    func open(_ a: Agent) {
        if scope != nil, !inScope(a) { scope = nil }
        nav = .agent(a.id)
        if let last = a.last, last.seen != true, let i = agents.firstIndex(where: { $0.id == a.id }) {
            var l = last; l.seen = true
            agents[i].last = l
            Task { _ = try? await engine.call("agent:update", a.id, ["last": ["state": l.state, "at": l.at ?? 0, "seen": true]], as: Ignored.self) }
        }
    }

    func send(to agentId: String, _ text: String) async {
        let key = "agent:\(agentId)"
        guard runs[key] == nil else { show("\(agent(agentId)?.name ?? "This agent") is still working. Stop it first, or wait.", error: true); return }
        if (await attempt { try await engine.send("agent:send", agentId, text) }) != nil, runs[key] == nil {
            runs[key] = Run(key: key, agentId: agentId, operator: agent(agentId)?.operator, startedAt: Date().timeIntervalSince1970 * 1000, activity: "Starting")
        }
    }

    func send(toChat c: Chat, _ text: String) async {
        let key = "chat:\(c.operator):\(c.id)"
        live[key, default: []].append(Line(role: "user", text: text))
        if (await attempt { try await engine.send("chat:send", c.operator, c.id, text) }) == nil { live[key]?.removeLast() }
        else if runs[key] == nil { runs[key] = Run(key: key, chat: ChatRef(operator: c.operator, id: c.id), operator: c.operator, startedAt: Date().timeIntervalSince1970 * 1000, activity: "Starting") }
    }

    func stop(_ key: String) { Task { _ = await attempt { try await engine.send("run:stop", key) } } }

    func answer(_ p: Approval, _ decision: String) {
        approvals.removeAll { $0.id == p.id }
        Task { _ = await attempt { try await engine.send("approval:answer", p.id, decision) } }
    }

    func loadChats(_ op: String, force: Bool = false) async {
        guard chats[op] == nil || force else { return }
        if let list: [Chat] = try? await engine.call("chats:list", op) { chats[op] = list }
        if selectedChat[op] == nil { selectedChat[op] = visibleChats(op).first?.id }
    }

    func transcript(_ c: Chat) async {
        let k = "\(c.operator):\(c.id)"
        guard transcripts[k] == nil else { return }
        transcripts[k] = (try? await engine.call("chat:transcript", c.operator, c.id)) ?? []
    }

    func refreshOverlaps() async {
        guard agents.contains(where: { $0.worktree != nil }) else { overlaps = []; return }
        overlaps = (try? await engine.call("git:overlaps")) ?? []
    }

    func createAgent(_ spec: [String: Any]) async -> Agent? {
        guard let a: Agent = await attempt({ try await engine.call("agent:create", spec) }) else { return nil }
        agents.append(a); messages[a.id] = []
        return a
    }

    func updateAgent(_ id: String, _ patch: [String: Any]) async {
        guard let a: Agent = await attempt({ try await engine.call("agent:update", id, patch) }) else { return }
        if let i = agents.firstIndex(where: { $0.id == id }) { agents[i] = a }
    }

    func removeAgent(_ id: String) async {
        let name = agent(id)?.name ?? "Agent"
        guard (await attempt { try await engine.send("agent:delete", id) }) != nil else { return }
        agents.removeAll { $0.id == id }; messages[id] = nil
        nav = .agents
        show("\(name) removed")
    }

    func addDecision(_ text: String, workspace: String?, source: String? = nil) async -> Decision? {
        guard let d: Decision = await attempt({ try await engine.call("memory:add", text, workspace, source) }) else { return nil }
        memory.append(d)
        return d
    }

    func removeDecision(_ d: Decision) async {
        if (await attempt { try await engine.send("memory:remove", d.id) }) != nil { memory.removeAll { $0.id == d.id } }
    }

    func chooseFolder(_ title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    func addWorkspace(_ path: String) async {
        guard let w: Workspace = await attempt({ try await engine.call("workspace:add", path) }) else { return }
        if !workspaces.contains(where: { $0.id == w.id }) { workspaces.append(w) }
        scope = w.id; nav = .agents
        show("\(w.name) added")
    }

    func removeWorkspace(_ w: Workspace) async {
        if (await attempt { try await engine.send("workspace:remove", w.id) }) != nil {
            workspaces.removeAll { $0.id == w.id }
            if scope == w.id { scope = nil }
        }
    }

    func confirmRemove(_ a: Agent) {
        sheet = .confirm(Confirm(title: "Remove \(a.name)?", body: a.worktree != nil ? "Its conversation here is deleted. Its branch \(a.branch ?? "") stays in the repository; its folder is removed." : "Its conversation here is deleted. Nothing in its folder changes.", ok: "Remove", danger: true) { [weak self] in
            Task { await self?.removeAgent(a.id) }
        })
    }

    func discard(_ a: Agent) {
        sheet = .confirm(Confirm(title: "Discard \(a.name)’s changes?", body: "Every change on \(a.branch ?? "its branch") since it started is deleted. This can’t be undone. \(a.baseBranch ?? "main") is untouched.", ok: "Discard changes", danger: true) { [weak self] in
            guard let self else { return }
            Task {
                if (await self.attempt { try await self.engine.send("git:discard", a.id) }) != nil { self.reviewTick += 1; await self.refreshOverlaps(); self.show("Discarded") }
            }
        })
    }

    func merge(_ a: Agent) async {
        merging = true
        defer { merging = false }
        guard let r: MergeResult = await attempt({ try await engine.call("git:merge", a.id) }) else { return }
        show("Merged \(r.merged) \(r.merged == 1 ? "file" : "files") into \(a.baseBranch ?? "main")")
        reviewTick += 1
        await refreshOverlaps()
    }

    func reveal(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func scanMavis() async { mavis = await attempt { try await engine.call("mavis:scan") } }

    func importMavis() async {
        guard let r: ImportResult = await attempt({ try await engine.call("mavis:import") }) else { return }
        await reload()
        chats["mavis"] = nil
        await loadChats("mavis")
        await scanMavis()
        show("Brought in \(r.chats) conversations\(r.agents > 0 ? " and \(r.agents) agent\(r.agents == 1 ? "" : "s")" : "")")
    }
}

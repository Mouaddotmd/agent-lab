// What goes on around a DM, kept live from the engine's events (engine/convo.js, engine.js): the helpers Claude starts
// (sub-agents, each with its own transcript), the commands running long enough to show above the box, side chats,
// the chat's context (tokens, cost, how full it is), and find / jump in the transcript.
//
// Each piece is its own small model, so only the view showing it redraws when it changes: the transcript never
// watches any of this (finished turns observe nothing; ChatView.swift).
import SwiftUI
import AppKit

// MARK: What the engine sends

/// A helper (a Task / Agent call): what it was asked, how it's doing, and (in full) its own words and steps.
struct HelperDoc: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var prompt: String?
    var kind: String?
    var parent: String?
    var status: String              // running, done, failed, stopped
    var startedAt: Double?
    var endedAt: Double?
    var activity: String?
    var error: String?
    var taskId: String?
    var steps: Int?                 // in the short form (no messages)
    var messages: [Message]?
    var running: Bool { status == "running" }
    /// Its words and steps as one turn, the way the chat builds one (ChatTurns.swift).
    var turn: Turn {
        var t = Turn(id: id)
        for m in messages ?? [] {
            switch m.role {
            case "assistant":
                if !t.raw.isEmpty { t.raw += "\n\n" }
                t.raw += m.text
            case "tool":
                let n = t.steps.count
                t.steps.append(Step(id: m.toolId ?? m.id, verb: m.verb ?? "", line: m.text, round: m.round ?? (n + 1), done: m.done ?? true, failed: m.failed ?? false,
                                    offset: t.raw.isEmpty ? 0 : t.raw.count + 2, detail: m.detail, output: m.output, diff: m.diff))
            default: break
            }
        }
        t.running = running
        t.startedAt = startedAt
        return t
    }
}

/// A command running long enough (about 3 s) to show above the box, with Stop.
struct RunningCommand: Codable, Equatable, Identifiable {
    let id: String; var toolId: String?; var line: String; var about: String?; var helper: String?; var background: Bool?; var startedAt: Double?
}

/// A side chat: questions about a chat that don't go into it.
struct SideDoc: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var at: Double?
    var sessionId: String?
    var running: Bool?
    var count: Int?
    var messages: [Msg]?
    struct Msg: Codable, Equatable, Identifiable { let id: String; var role: String; var text: String; var at: Double?; var steps: [SideStep]? }
    struct SideStep: Codable, Equatable, Identifiable {
        let id: String; var verb: String; var line: String; var detail: String?; var output: String?; var done: Bool?; var failed: Bool?
        var step: Step { Step(id: id, verb: verb, line: line, round: 1, done: done ?? true, failed: failed ?? false, offset: 0, detail: detail, output: output) }
    }
}

/// What a DM has used (engine: agent.usage, convo:context).
struct ContextInfo: Codable, Equatable {
    var `operator`: String?
    var model: String?
    var usage: Usage?
    var session: Bool?
    var running: Bool?
    var compacting: Bool?
    struct Usage: Codable, Equatable {
        var input: Double?; var output: Double?; var cacheRead: Double?; var cacheWrite: Double?
        var cost: Double?; var runs: Int?; var model: String?; var context: Window?; var since: Double?
    }
    struct Window: Codable, Equatable { var used: Double?; var window: Double?; var model: String?; var at: Double? }
}

/// Claude Code's own count of the context now, by part (convo:contextLive).
struct LiveContext: Codable, Equatable {
    var used: Double; var window: Double?; var percent: Double?; var model: String?; var parts: [Part]; var free: Double?
    struct Part: Codable, Equatable { var name: String; var tokens: Double }
}

// MARK: The hub: engine events to the models

@MainActor final class ConvoHub {
    static let shared = ConvoHub()
    private(set) weak var store: Store?
    private var listening: NSObjectProtocol?
    private var works: [String: AgentWork] = [:]
    private var helpers: [String: HelperModel] = [:]
    private var sides: [String: SideChatModel] = [:]
    private var contexts: [String: ContextModel] = [:]

    func attach(_ store: Store) {
        self.store = store
        guard listening == nil else { return }
        listening = NotificationCenter.default.addObserver(forName: .engineEvent, object: nil, queue: .main) { n in
            let ev = n.userInfo as? [String: Any] ?? [:]
            MainActor.assumeIsolated { ConvoHub.shared.handle(ev) }
        }
        ChatFinder.shared.listen()
    }

    /// One agent's helpers at work and commands running (made on first use, with what's going now).
    func work(_ agentId: String) -> AgentWork {
        if let w = works[agentId] { return w }
        let w = AgentWork(agentId: agentId); works[agentId] = w; w.refresh(); return w
    }
    func helper(_ agentId: String, _ id: String) -> HelperModel {
        let key = agentId + "|" + id
        if let h = helpers[key] { return h }
        let h = HelperModel(agentId: agentId, id: id); helpers[key] = h; h.load(); return h
    }
    func side(_ agentId: String, _ id: String) -> SideChatModel {
        if let m = sides[id] { return m }
        let m = SideChatModel(agentId: agentId, id: id); sides[id] = m; m.load(); return m
    }
    func context(_ agentId: String) -> ContextModel {
        if let c = contexts[agentId] { return c }
        let c = ContextModel(agentId: agentId); contexts[agentId] = c; return c
    }

    private func handle(_ ev: [String: Any]) {
        let agentId = ev["agentId"] as? String ?? ""
        switch ev["type"] as? String {
        case "helper":
            guard let raw = ev["helper"], let h = try? Store.decode(raw, HelperDoc.self) else { return }
            works[agentId]?.apply(h)
            helpers[agentId + "|" + h.id]?.apply(h)
        case "commands":
            guard let raw = ev["commands"], let list = try? Store.decode(raw, [RunningCommand].self) else { return }
            works[agentId]?.commands = list
        case "run-end":
            works[agentId]?.ended()
            contexts[agentId]?.refresh()
        case "side":
            guard let id = ev["sideId"] as? String, let m = sides[id], let raw = ev["side"] as? [String: Any] else { return }
            m.apply(raw)
        case "side-delta":
            guard let id = ev["sideId"] as? String else { return }
            sides[id]?.draft = ev["text"] as? String
        case "compact":
            contexts[agentId]?.refresh()
        default: break
        }
    }
}

/// The capsule above the box: helpers at work and commands running in one agent's DM.
@MainActor final class AgentWork: ObservableObject {
    let agentId: String
    @Published private(set) var helpers: [HelperDoc] = []
    @Published var commands: [RunningCommand] = []
    init(agentId: String) { self.agentId = agentId }
    var isEmpty: Bool { helpers.isEmpty && commands.isEmpty }
    /// "2 helpers working · 1 command running"
    var label: String {
        var parts: [String] = []
        if !helpers.isEmpty { parts.append(helpers.count == 1 ? "1 helper working" : "\(helpers.count) helpers working") }
        if !commands.isEmpty { parts.append(commands.count == 1 ? "1 command running" : "\(commands.count) commands running") }
        return parts.joined(separator: " · ")
    }
    func apply(_ h: HelperDoc) {
        var brief = h; brief.messages = nil
        if let i = helpers.firstIndex(where: { $0.id == h.id }) {
            if h.running { if helpers[i] != brief { helpers[i] = brief } } else { helpers.remove(at: i) }
        } else if h.running { helpers.append(brief) }
    }
    func ended() { if !helpers.isEmpty { helpers = [] }; if !commands.isEmpty { commands = [] } }
    /// What's going now (opening a chat while it works).
    func refresh() {
        Task {
            struct Work: Decodable { let helpers: [HelperDoc]; let commands: [RunningCommand] }
            guard let w = try? await ConvoHub.shared.store?.engine.call("convo:work", [agentId], as: Work.self) else { return }
            helpers = w.helpers; commands = w.commands
        }
    }
}

/// One helper's transcript, live while it works.
@MainActor final class HelperModel: ObservableObject {
    let agentId: String; let id: String
    @Published private(set) var doc: HelperDoc?
    @Published private(set) var missing = false
    init(agentId: String, id: String) { self.agentId = agentId; self.id = id }
    func load() {
        Task {
            do {
                let v = try await ConvoHub.shared.store?.engine.call("convo:helper", [agentId, id])
                if v is NSNull || v == nil { if doc == nil { missing = true }; return }
                let d = try Store.decode(v!, HelperDoc.self)
                if doc == nil || d.messages?.count ?? 0 >= doc?.messages?.count ?? 0 { doc = d }
                missing = false
            } catch { if doc == nil { missing = true } }
        }
    }
    func apply(_ h: HelperDoc) { if doc != h { doc = h }; missing = false }
    func stop() {
        Task {
            do {
                let r = try await ConvoHub.shared.store?.engine.call("convo:stopHelper", [agentId, id]) as? String
                if r == "run" { ConvoHub.shared.store?.toast = "Stopped the run (this helper can't be stopped on its own)." }
            } catch { ConvoHub.shared.store?.toast = error.localizedDescription }
        }
    }
}

/// One side chat, live while it answers.
@MainActor final class SideChatModel: ObservableObject {
    let agentId: String; let id: String
    @Published private(set) var doc: SideDoc?
    /// The answer being written: its words so far, and its steps.
    @Published var draft: String?
    @Published private(set) var reply: SideDoc.Msg?
    @Published private(set) var missing = false
    @Published var problem: String?
    init(agentId: String, id: String) { self.agentId = agentId; self.id = id }
    var running: Bool { doc?.running == true }
    func load() {
        Task {
            let v = try? await ConvoHub.shared.store?.engine.call("convo:side", [agentId, id])
            guard let v, !(v is NSNull), let d = try? Store.decode(v, SideDoc.self) else { if doc == nil { missing = true }; return }
            if doc == nil { doc = d }
        }
    }
    func apply(_ raw: [String: Any]) {
        guard let d = try? Store.decode(raw, SideDoc.self) else { return }
        reply = (raw["reply"]).flatMap { try? Store.decode($0, SideDoc.Msg.self) }
        if d.running != true { draft = nil; reply = nil }
        doc = d; missing = false
        retitle(d.title)
    }
    func ask(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !running else { return }
        problem = nil
        // Shows at once; the engine's copy replaces it.
        if var d = doc { d.messages = (d.messages ?? []) + [SideDoc.Msg(id: "p" + UUID().uuidString.prefix(6), role: "user", text: t, at: Date().timeIntervalSince1970 * 1000)]; d.running = true; doc = d }
        Task {
            do { _ = try await ConvoHub.shared.store?.engine.call("convo:sideAsk", [agentId, id, t]) }
            catch { problem = error.localizedDescription; if var d = doc { d.running = false; d.messages?.removeLast(); doc = d } }
        }
    }
    func stop() { Task { _ = try? await ConvoHub.shared.store?.engine.call("convo:sideStop", [id]) } }
    /// The tab's title follows the side chat's (its first question).
    private func retitle(_ title: String) {
        guard let panel = SidePanel.existing(agentId), let i = panel.tabs.firstIndex(where: { $0.id == "side:" + id }) else { return }
        if case .side(_, let t) = panel.tabs[i].kind, t != title { panel.tabs[i].kind = .side(id: id, title: title) }
    }
}

/// The open chat's context: tokens, cost, how full, and compacting.
@MainActor final class ContextModel: ObservableObject {
    let agentId: String
    @Published private(set) var info: ContextInfo?
    @Published private(set) var live: LiveContext?
    @Published private(set) var loading = false
    @Published private(set) var counting = false
    @Published private(set) var compacting = false
    @Published private(set) var result: String?
    @Published private(set) var problem: String?
    init(agentId: String) { self.agentId = agentId }
    func refresh() {
        guard let engine = ConvoHub.shared.store?.engine else { return }
        loading = info == nil
        Task {
            defer { loading = false }
            do { info = try await engine.call("convo:context", [agentId], as: ContextInfo.self); problem = nil }
            catch { problem = error.localizedDescription; return }
            // Claude Code's own count, by part: only when nothing is working in the chat.
            guard info?.running != true, info?.compacting != true, info?.session == true, info?.operator != "codex" else { return }
            counting = true
            defer { counting = false }
            if let v = try? await engine.call("convo:contextLive", [agentId]), !(v is NSNull), let l = try? Store.decode(v, LiveContext.self) { live = l }
        }
    }
    func compact() {
        guard !compacting, let engine = ConvoHub.shared.store?.engine else { return }
        compacting = true; result = nil; problem = nil
        Task {
            defer { compacting = false; refresh() }
            struct Done: Decodable { let before: Double?; let after: Double? }
            do {
                let d = try await engine.call("convo:compact", [agentId], as: Done.self)
                result = d.before.flatMap { b in d.after.map { "Compacted: \(Tokens.short(b)) → \(Tokens.short($0)) tokens." } } ?? "Compacted."
            } catch { problem = error.localizedDescription }
        }
    }
}

enum Tokens {
    /// 950, 12K, 1.2M
    static func short(_ n: Double) -> String {
        if n >= 1_000_000 { let m = n / 1_000_000; return m >= 10 || m == m.rounded() ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m) }
        if n >= 1000 { return "\(Int((n / 1000).rounded()))K" }
        return "\(Int(n))"
    }
    /// 1,234,567
    static func full(_ n: Double) -> String { let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: Int(n))) ?? "\(Int(n))" }
    static func cost(_ c: Double) -> String { c < 0.01 && c > 0 ? "<$0.01" : String(format: "$%.2f", c) }
}

// MARK: Find in the chat, and jumping to a message (the palette asks; ChatView scrolls)

extension Notification.Name {
    /// userInfo: "agentId", "messageId". Opens that chat, scrolls to the message and lights it for a moment.
    static let jumpToMessage = Notification.Name("agentlab.jumpToMessage")
    /// userInfo: "agentId", "query", "index". Lights every match, scrolls to match `index`; answers with findInChatResult.
    static let findInChat = Notification.Name("agentlab.findInChat")
    /// userInfo: "agentId", "count".
    static let findInChatResult = Notification.Name("agentlab.findInChatResult")
}

@MainActor final class ChatFinder: ObservableObject {
    static let shared = ChatFinder()
    /// What's being found in each chat (agent id → words), and the row of the match in view.
    @Published private(set) var query: [String: String] = [:]
    @Published private(set) var current: [String: Target] = [:]
    /// A row to bring into view and light for a moment (a jump).
    @Published private(set) var jump: [String: Target] = [:]
    /// Rows with a match in each chat (matches light only there: the rest of the chat never redraws).
    private(set) var hits: [String: Set<String>] = [:]
    struct Target: Equatable { let row: String; let token = UUID() }
    private var observers: [NSObjectProtocol] = []

    func listen() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .findInChat, object: nil, queue: .main) { n in
            let u = n.userInfo ?? [:]
            let id = u["agentId"] as? String ?? "", q = u["query"] as? String ?? "", i = u["index"] as? Int ?? 0
            MainActor.assumeIsolated { ChatFinder.shared.find(id, q, index: i) }
        })
        observers.append(nc.addObserver(forName: .jumpToMessage, object: nil, queue: .main) { n in
            let u = n.userInfo ?? [:]
            let id = u["agentId"] as? String ?? "", m = u["messageId"] as? String ?? ""
            MainActor.assumeIsolated { ChatFinder.shared.jumpTo(id, message: m) }
        })
    }

    func query(_ agentId: String) -> String { query[agentId] ?? "" }
    func lit(_ agentId: String, _ rowId: String) -> String { hits[agentId]?.contains(rowId) == true ? query(agentId) : "" }

    /// Finds `q` in the chat's words as shown (the model, not the views: fast however long the chat is), lights every
    /// match, brings match `index` into view and says how many there are.
    func find(_ agentId: String, _ q: String, index: Int) {
        let words = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store = ConvoHub.shared.store, !words.isEmpty else {
            if query[agentId] != nil { query[agentId] = nil; current[agentId] = nil; hits[agentId] = nil }
            post(agentId, 0); return
        }
        let rows = store.rows(for: agentId)
        // Off the main thread for a long chat: counting is plain string work on values.
        let texts = rows.map { ($0.id, ChatSearch.visibleText($0)) }
        Task.detached(priority: .userInitiated) {
            var order: [String] = []
            for (id, text) in texts { let n = ChatSearch.count(words, in: text); if n > 0 { order += Array(repeating: id, count: n) } }
            let found = order
            await MainActor.run {
                let order = found
                let ch = ChatFinder.shared
                ch.hits[agentId] = Set(order)
                ch.query[agentId] = words
                if order.isEmpty { ch.current[agentId] = nil } else {
                    let i = ((index % order.count) + order.count) % order.count
                    ch.current[agentId] = Target(row: order[i])
                }
                ch.post(agentId, order.count)
            }
        }
    }
    private func post(_ agentId: String, _ count: Int) {
        NotificationCenter.default.post(name: .findInChatResult, object: nil, userInfo: ["agentId": agentId, "count": count])
    }

    /// Opens the chat if it isn't, then brings the message into view and lights it for a moment.
    func jumpTo(_ agentId: String, message: String) {
        guard let store = ConvoHub.shared.store, store.agents.contains(where: { $0.id == agentId }) else { return }
        if store.openAgent != agentId || store.view != .messages { store.openChat(agentId) }
        func go() -> Bool {
            guard let row = store.rowId(forMessage: message, in: agentId) else { return false }
            jump[agentId] = Target(row: row); return true
        }
        if go() { return }
        // Its messages may still be on their way.
        Task { await store.loadMessages(agentId); if !go() { store.toast = "That message is no longer in this chat." } }
    }
    func jumped(_ agentId: String) { jump[agentId] = nil }
}

/// Finding words in a chat's rows: the text each row shows, and how often the words appear in it.
enum ChatSearch {
    /// What a row shows as words: yours whole (as shown, cut past 1,500), a turn's answer (and, while it's open, its
    /// opening and the words between steps), a note.
    nonisolated static func visibleText(_ row: ChatRow) -> String {
        switch row {
        case .you(_, let text, _, _, _, _, _): return plain(text.count > 1500 ? String(text.prefix(1200)) : text)
        case .note(_, let text, _): return text
        case .agent(let t):
            let all = TurnFlow.pieces(steps: t.steps, raw: t.raw, shown: Int.max)
            let (opening, work, tail) = TurnFlow.split(all)
            let shown = !t.running && !work.isEmpty ? tail : t.running ? opening : all
            return plain(shown.compactMap { p -> String? in if case .words(_, let w) = p { w } else { nil } }.joined(separator: "\n"))
        }
    }
    /// Markdown's marks out, the way the words are drawn.
    nonisolated static func plain(_ s: String) -> String {
        guard s.contains("*") || s.contains("`") || s.contains("[") || s.contains("#") else { return s }
        var t = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
        return t
    }
    nonisolated static func count(_ q: String, in text: String) -> Int {
        guard !q.isEmpty, !text.isEmpty else { return 0 }
        var n = 0, from = text.startIndex
        while let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) { n += 1; from = r.upperBound }
        return n
    }
    /// Where the words appear in `text` (for lighting them).
    nonisolated static func ranges(_ q: String, in text: NSString) -> [NSRange] {
        guard q.count > 0 else { return [] }
        var out: [NSRange] = [], at = 0
        while at < text.length {
            let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: at, length: text.length - at))
            if r.location == NSNotFound { break }
            out.append(r); at = r.location + max(1, r.length)
        }
        return out
    }
}

extension EnvironmentValues {
    /// The DM a view is in (steps that open a helper use it).
    @Entry var chatAgentId: String? = nil
    /// The conversation a view belongs to (an agent's id, or a channel's conv): asks, runs and work are matched to it.
    @Entry var chatConv: String? = nil
    /// A pane's tab is the one in front (behind, its AppKit views are hidden: no cursor zones over the front tab).
    @Entry var paneTabOn = true
    /// Set by ChatHost: whether this kept chat is the one on screen (a chat you've left keeps drawing, but goes inert).
    @Entry var chatActivity: ChatActivity? = nil
    /// Words to light in the text under here (find in chat).
    @Entry var findQuery: String = ""
}


/// Whether a kept chat is on screen. ChatHost sets it; what animates or listens checks it.
@MainActor final class ChatActivity: ObservableObject {
    @Published var on = true
}

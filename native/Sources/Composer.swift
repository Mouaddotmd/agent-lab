// The message box's brain and its pieces, shared by DMs and channels: a real Mac text view (IME, undo, every editing
// key), `/` for the agent's commands (its tool's own; with "Use my Claude Code setup" on, your skills' and plugins' too),
// `@` for members, helpers, folders and files, the + menu (files or photos, a folder, the commands, plugins), pictures
// and files attached by paste, drop or ⌘U, ↑ for what you sent before, and a draft kept per conversation.
// Keys: ↵ sends (or picks), ⇧↵ / ⌥↵ a new line, ↑↓ or ⌃P ⌃N move, Page ↑↓ jump, Tab completes, → opens Plugins,
// ← and Esc go back.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: What the engine says an agent offers (engine: agent:catalog)

struct Catalog: Codable, Equatable {
    struct Command: Codable, Equatable, Hashable { var name: String; var about: String; var hint: String; var kind: String }
    struct Helper: Codable, Equatable, Hashable { var name: String; var about: String }
    struct Model: Codable, Equatable, Hashable { var id: String; var name: String; var about: String }
    var commands: [Command]
    var agents: [Helper]
    var models: [Model]
}

struct PluginItem: Codable, Equatable, Identifiable, Hashable {
    let id: String; var name: String; var about: String; var enabled: Bool
}

// MARK: Suggestions

struct Suggestion: Identifiable, Equatable {
    enum Kind { case command, skill, plugin, model, member, helper, folder, file }
    var kind: Kind
    var label: String
    var detail: String
    /// What replaces the `/word` or `@word` being typed.
    var insert: String
    /// What a command takes after its name; none means ↵ sends it at once.
    var hint = ""
    var id: String { "\(kind)/" + insert }
    var section: String {
        switch kind {
        case .command: "Commands"
        case .skill: "Skills"
        case .plugin: "Plugins"
        case .model: "Models"
        case .member: "Members"
        case .helper: "Helpers"
        case .folder: "Folders"
        case .file: "Files"
        }
    }
    var symbol: String {
        switch kind {
        case .command: "chevron.left.forwardslash.chevron.right"
        case .skill: "sparkles"
        case .plugin: "powerplug"
        case .model: "cpu"
        case .member: "person"
        case .helper: "person.2"
        case .folder: "folder"
        case .file: "doc"
        }
    }
}

/// The + menu's rows.
enum PlusItem: Int, CaseIterable {
    case files, folder, commands, side, plugins
    var title: String {
        switch self {
        case .files: "Add files or photos"
        case .folder: "Add folder"
        case .commands: "Slash commands"
        case .side: "Side chat"
        case .plugins: "Plugins"
        }
    }
    var symbol: String {
        switch self {
        case .files: "paperclip"
        case .folder: "folder"
        case .commands: "chevron.left.forwardslash.chevron.right"
        case .side: "bubble.left.and.bubble.right"
        case .plugins: "powerplug"
        }
    }
    var keys: String? { self == .files ? "⌘U" : nil }
}

// MARK: The model

@MainActor final class ComposerModel: ObservableObject {
    /// Who the box talks to: one agent (a DM), or a channel's members.
    enum Target: Equatable {
        case agent(String)
        case channel(conv: String, members: [String], folder: String?)
        var key: String { switch self { case .agent(let id): "dm:" + id; case .channel(let conv, _, _): "ch:" + conv } }
    }

    @Published var text = ""
    @Published var images: [String] = []
    @Published var files: [String] = []
    @Published var suggestions: [Suggestion] = []
    @Published var highlighted = 0
    @Published var height: CGFloat = 24
    @Published var menu: Int?
    /// Plugins open inside the menu: which row is lit (-1 is the setup switch).
    @Published var submenu: Int?
    /// What the command just picked takes, until you've typed it.
    @Published var hint: String?
    /// Bumped when the words change from here (history, a pick, a restore), so the text view takes them.
    @Published private(set) var revision = 0
    /// Bumped to put the keyboard in the box.
    @Published private(set) var focus = 0

    weak var store: Store?
    var target: Target = .agent("")
    var caret = 0
    /// Sends: the words, pictures and files. Set by the box that owns this model.
    var send: ((String, [String], [String]) -> Void)?
    /// Esc with nothing of the box's own to close (the box then stops the agent, or stops listening).
    var escape: (() -> Void)?
    private var browsing: Int?
    private var stash = ""
    private var tokenRange: NSRange?

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty && files.isEmpty }
    var agentID: String? { if case .agent(let id) = target { id } else { nil } }
    /// In a channel: the agent whose commands and skills "/" offers (the one that answers there, or the assistant).
    var commandsFor: String?
    var agent: Agent? { agentID.flatMap { id in store?.agents.first { $0.id == id } } }

    func attach(_ target: Target, store: Store) {
        self.store = store
        listenForAdds()
        guard target != self.target else { return }
        save()
        self.target = target
        let draft = DraftStore.shared.draft(target.key)
        set(draft.text, caretAtEnd: true)
        images = draft.images.filter { FileManager.default.fileExists(atPath: $0) }
        files = draft.files
        if let id = agentID { store.loadCatalog(id) }
        // The snapshot tool's way in (tools/snapshot.swift): SNAP_COMPOSER=menu|plugins|slash|mention.
        if SnapshotMode.on, let state = ProcessInfo.processInfo.environment["SNAP_COMPOSER"] {
            switch state {
            case "menu": menu = 0
            case "plugins": openPlugins()
            case "slash": set("/", caretAtEnd: true)
            case "mention": set("look at @", caretAtEnd: true)
            default: break
            }
        }
    }

    /// Text from elsewhere (selected lines in a file, a diff line, a web page) put into this agent's box: after what's
    /// there, on its own line, with the keyboard in the box. See `AddToMessage`.
    func add(_ context: String) {
        let joined = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? context : text + (text.hasSuffix("\n") ? "" : "\n") + context
        set(joined + "\n", caretAtEnd: true)
        save()
        takeFocus()
    }
    private var addObserver: NSObjectProtocol?
    func listenForAdds() {
        guard addObserver == nil else { return }
        addObserver = NotificationCenter.default.addObserver(forName: .addToMessage, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, let id = n.userInfo?["agentId"] as? String, id == self.agentID, let t = n.userInfo?["text"] as? String else { return }
                self.add(t)
            }
        }
    }

    func save() {
        guard target.key != "dm:" else { return }
        DraftStore.shared.set(target.key, DraftStore.Draft(text: text, images: images, files: files))
    }

    func set(_ new: String, caretAtEnd: Bool) {
        text = new
        caret = caretAtEnd ? (new as NSString).length : 0
        revision += 1
        refresh()
    }

    func typed(_ new: String, caret: Int) {
        if menu != nil { closeMenu() }
        if hint != nil, !(new.hasPrefix("/") && new.hasSuffix(" ") && new.filter({ $0 == " " }).count == 1) { hint = nil }
        text = new
        self.caret = caret
        if let at = browsing, new != DraftStore.shared.history[safe: at] { browsing = nil }
        refresh()
        save()
    }

    func takeFocus() { focus += 1 }

    // MARK: Sending

    func submit() {
        if menu != nil { activateMenu(); return }
        // ↵ (or a click) on a suggestion writes it into the box, as if you'd typed it all; it never sends (Mavis final
        // launch). The next ↵ sends.
        if !suggestions.isEmpty { accept(); return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isEmpty else { return }
        if words.hasPrefix("/model "), let agent {
            // The agent's model is its own setting: it changes for good, here and in its settings.
            let name = String(words.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            let value: Any = name.isEmpty || name == "default" ? NSNull() : name
            Task { try? await store?.updateAgent(agent.id, ["model": value]) }
            store?.toast = "\(agent.name) now uses \(name.isEmpty ? "its default model" : name)."
            clear()
            return
        }
        // `/btw question`: asked in a side chat, not in this one. `/handoff`: pass this chat to another agent.
        if let agent, words == "/btw" || words.hasPrefix("/btw ") {
            DraftStore.shared.remember(words)
            store?.openSideChat(agent, question: String(words.dropFirst(4)))
            clear()
            return
        }
        if let agent, words == "/handoff" {
            store?.handingOff = agent.id
            clear()
            return
        }
        DraftStore.shared.remember(words)
        send?(words, images, files)
        clear()
    }

    private func clear() {
        images = []
        files = []
        browsing = nil
        hint = nil
        set("", caretAtEnd: true)
        save()
    }

    func add(_ paths: [String]) {
        for path in paths {
            if Attachments.isImage(path) { if !images.contains(path) { images.append(path) } }
            else if !files.contains(path) { files.append(path) }
        }
        save()
        takeFocus()
    }
    func remove(_ path: String) { images.removeAll { $0 == path }; files.removeAll { $0 == path }; save() }

    // MARK: Keys

    func up() -> Bool {
        if menu != nil { moveMenu(-1); return true }
        if !suggestions.isEmpty { highlighted = (highlighted - 1 + suggestions.count) % suggestions.count; return true }
        let history = DraftStore.shared.history
        guard !history.isEmpty, browsing != nil || (text.isEmpty && caret == 0) else { return false }
        if browsing == nil { stash = text; browsing = history.count }
        guard let at = browsing, at > 0 else { return true }
        browsing = at - 1
        set(history[at - 1], caretAtEnd: false)
        return true
    }

    func down() -> Bool {
        if menu != nil { moveMenu(1); return true }
        if !suggestions.isEmpty { highlighted = (highlighted + 1) % suggestions.count; return true }
        guard let at = browsing else { return false }
        let history = DraftStore.shared.history
        if at + 1 < history.count { browsing = at + 1; set(history[at + 1], caretAtEnd: true) }
        else { browsing = nil; set(stash, caretAtEnd: true) }
        return true
    }

    func page(_ delta: Int) -> Bool {
        guard !suggestions.isEmpty else { return false }
        highlighted = min(max(0, highlighted + delta * 6), suggestions.count - 1)
        return true
    }

    /// Tab, or ↵ on a suggestion: it replaces what you were typing.
    @discardableResult func accept() -> Bool {
        guard suggestions.indices.contains(highlighted), let range = tokenRange else { return false }
        let pick = suggestions[highlighted]
        hint = pick.hint.isEmpty ? nil : pick.hint
        let replaced = (text as NSString).replacingCharacters(in: range, with: pick.insert)
        text = replaced
        caret = range.location + (pick.insert as NSString).length
        revision += 1
        suggestions = []
        tokenRange = nil
        // `/model ` opens the models next.
        if pick.insert == "/model " { refresh() }
        save()
        return true
    }

    /// Esc: the menu, then the suggestions, then history, then whatever the box does with Esc.
    func cancel() {
        if menu != nil { _ = menuLeft(); return }
        if !suggestions.isEmpty { suggestions = []; tokenRange = nil; return }
        if browsing != nil { browsing = nil; set(stash, caretAtEnd: true); return }
        escape?()
    }

    // MARK: The + menu

    func toggleMenu() {
        if menu != nil { closeMenu() } else { suggestions = []; tokenRange = nil; menu = 0; submenu = nil }
        takeFocus()
    }
    func closeMenu() { menu = nil; submenu = nil }

    /// The rows the menu has here: a channel has no one agent's commands or plugins.
    var menuItems: [PlusItem] { agentID == nil ? [.files, .folder] : PlusItem.allCases }

    private func moveMenu(_ delta: Int) {
        if let sub = submenu {
            let count = store?.plugins[agentID ?? ""]?.count ?? 0
            let first = showsSetup ? -1 : 0
            var next = sub + delta
            if next < first { next = max(first, count - 1) } else if next >= count { next = first }
            submenu = next
        } else if let at = menu, let i = menuItems.firstIndex(where: { $0.rawValue == at }) {
            menu = menuItems[(i + delta + menuItems.count) % menuItems.count].rawValue
        }
    }

    func menuRight() -> Bool {
        guard let at = menu else { return false }
        if PlusItem(rawValue: at) == .plugins, submenu == nil { openPlugins() }
        return true
    }

    func menuLeft() -> Bool {
        guard menu != nil else { return false }
        if submenu != nil { submenu = nil } else { closeMenu() }
        return true
    }

    /// Claude Code agents have the setup switch; Codex always runs with its own setup.
    var showsSetup: Bool { agent?.operator != "codex" }

    func openPlugins() {
        menu = PlusItem.plugins.rawValue
        submenu = showsSetup ? -1 : 0
        if let id = agentID { store?.loadPlugins(id) }
    }

    func activateMenu() {
        if let sub = submenu {
            guard let agent else { return }
            if sub == -1 { store?.setClaudeSetup(agent, on: agent.claudeSetup != true); return }
            guard let plugin = store?.plugins[agent.id]?[safe: sub] else { return }
            store?.setPlugin(agent.id, plugin, on: !plugin.enabled)
            return
        }
        guard let at = menu, let item = PlusItem(rawValue: at) else { return }
        choose(item)
    }

    func choose(_ item: PlusItem) {
        switch item {
        case .files: closeMenu(); pick(folders: false)
        case .folder: closeMenu(); pick(folders: true)
        case .commands:
            closeMenu()
            if !text.hasPrefix("/") { set("/" + (text.isEmpty ? "" : " " + text), caretAtEnd: false); caret = 1; revision += 1 }
            refresh()
            takeFocus()
        case .side:
            closeMenu()
            if let agent { store?.openSideChat(agent) }
        case .plugins: openPlugins()
        }
    }

    /// The Mac's own picker, starting in the folder the agent works in.
    func pick(folders: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = folders
        panel.canChooseFiles = !folders
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK { add(panel.urls.map(\.path)) }
        takeFocus()
    }

    /// The folder this box's agent works in.
    var folder: String {
        switch target {
        case .agent: agent?.cwd ?? store?.home ?? NSHomeDirectory()
        case .channel(_, _, let folder): folder ?? store?.home ?? NSHomeDirectory()
        }
    }

    // MARK: Building the suggestions

    func refresh() {
        guard let store else { suggestions = []; return }
        let agentID = self.agentID ?? commandsFor
        let ns = text as NSString
        let upto = ns.substring(to: min(caret, ns.length))
        // `/model name`: the agent's models.
        if let agentID, upto.hasPrefix("/model "), !upto.dropFirst(7).contains(" "), let catalog = store.catalogs[agentID] {
            let q = String(upto.dropFirst(7))
            var found: [Suggestion] = []
            for m in catalog.models where Rank.score(q, name: m.name + " " + m.id, about: "") != nil {
                let id = m.id.isEmpty ? "default" : m.id
                found.append(Suggestion(kind: .model, label: m.name, detail: m.about, insert: "/model " + id))
            }
            show(found, range: NSRange(location: 0, length: (upto as NSString).length))
            return
        }
        // `/command`: the first word only.
        if let agentID, upto.hasPrefix("/"), !upto.contains(" "), !upto.contains("\n") {
            let q = String(upto.dropFirst())
            let catalog = store.catalogs[agentID]
            var all = catalog?.commands ?? []
            if !all.contains(where: { $0.name == "model" }) { all.append(.init(name: "model", about: "Switch this agent's model", hint: "[model]", kind: "command")) }
            // Agent Lab's own: a side question that stays out of the chat, and passing the chat to another agent.
            all.removeAll { $0.name == "btw" || $0.name == "handoff" }
            all.append(.init(name: "btw", about: "Ask about this chat without adding to it", hint: "<question>", kind: "command"))
            all.append(.init(name: "handoff", about: "Pass this chat to another agent", hint: "", kind: "command"))
            let order = ["command": 0, "skill": 1, "plugin": 2]
            let ranked = all.compactMap { c -> (Int, Catalog.Command)? in Rank.score(q, name: c.name, about: c.about).map { ($0, c) } }
                .sorted { a, b in
                    let ga = q.isEmpty ? order[a.1.kind] ?? 0 : 0, gb = q.isEmpty ? order[b.1.kind] ?? 0 : 0
                    if ga != gb { return ga < gb }
                    if a.0 != b.0 { return a.0 < b.0 }
                    return a.1.name.localizedCaseInsensitiveCompare(b.1.name) == .orderedAscending
                }
            let codex = agent?.operator == "codex"
            let found = ranked.prefix(200).map { _, c in
                Suggestion(kind: c.kind == "skill" ? .skill : c.kind == "plugin" ? .plugin : .command, label: "/" + c.name, detail: c.about,
                           insert: (codex && c.kind == "skill" ? "$" : "/") + c.name + " ", hint: c.hint)
            }
            show(Array(found), range: NSRange(location: 0, length: (upto as NSString).length))
            if catalog == nil { store.loadCatalog(agentID) }
            return
        }
        // `@`: members (in a channel), helpers, folders, files.
        if let at = upto.range(of: #"(^|\s)@[^\s@]*$"#, options: .regularExpression) {
            let token = upto[at].trimmingCharacters(in: .whitespacesAndNewlines)
            let q = String(token.dropFirst())
            let start = (upto as NSString).length - (token as NSString).length
            var found: [Suggestion] = []
            if case .channel(_, let members, _) = target {
                if Rank.score(q, name: "everyone", about: "") != nil {
                    found.append(Suggestion(kind: .member, label: "everyone", detail: "Every member answers", insert: "@everyone "))
                }
                for id in members {
                    guard let a = store.agents.first(where: { $0.id == id }), Rank.score(q, name: a.name, about: "") != nil else { continue }
                    found.append(Suggestion(kind: .member, label: a.name, detail: a.job.map { Words.line($0, 60) } ?? "", insert: "@\(a.name) "))
                }
            }
            if let agentID, let helpers = store.catalogs[agentID]?.agents {
                for h in helpers where Rank.score(q.replacingOccurrences(of: "agent-", with: ""), name: h.name, about: "") != nil {
                    found.append(Suggestion(kind: .helper, label: h.name, detail: Words.line(h.about, 80), insert: "@agent-\(h.name) "))
                }
            }
            let paths = FileIndex.shared.search(q, in: folder)
            let folders = paths.filter { $0.hasSuffix("/") }.prefix(5)
            for path in folders + paths.filter({ !$0.hasSuffix("/") }) {
                let isFolder = path.hasSuffix("/")
                let trimmed = isFolder ? String(path.dropLast()) : path
                found.append(Suggestion(kind: isFolder ? .folder : .file, label: (trimmed as NSString).lastPathComponent,
                                        detail: (trimmed as NSString).deletingLastPathComponent, insert: "@\(path) "))
            }
            show(found, range: NSRange(location: start, length: (token as NSString).length))
            return
        }
        suggestions = []
        tokenRange = nil
    }

    private func show(_ found: [Suggestion], range: NSRange) {
        if found.map(\.id) != suggestions.map(\.id) { highlighted = 0 }
        suggestions = found
        tokenRange = found.isEmpty ? nil : range
    }
}

/// How well what you typed matches a name: lower is better, nil is no match. Its start, then a word's start, then
/// anywhere, then its letters in order; its description last.
enum Rank {
    static func score(_ query: String, name: String, about: String) -> Int? {
        let q = query.lowercased(), n = name.lowercased()
        guard !q.isEmpty else { return 0 }
        if n == q { return 0 }
        if n.hasPrefix(q) { return 1 }
        if n.split(whereSeparator: { "-_:. ".contains($0) }).contains(where: { $0.hasPrefix(q) }) { return 2 }
        if n.contains(q) { return 3 }
        var i = n.startIndex
        var inOrder = true
        for c in q {
            guard let found = n[i...].firstIndex(of: c) else { inOrder = false; break }
            i = n.index(after: found)
        }
        if inOrder { return 4 }
        if about.lowercased().contains(q) { return 5 }
        return nil
    }
}

enum Words {
    static func line(_ text: String, _ limit: Int) -> String {
        let one = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let t = one.trimmingCharacters(in: .whitespaces)
        return t.count > limit ? String(t.prefix(limit - 1)) + "…" : t
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: Drafts and history

/// What you were writing in each conversation, kept until sent (and across restarts), and what you've sent, for ↑.
@MainActor final class DraftStore {
    static let shared = DraftStore()
    struct Draft: Codable, Equatable { var text = ""; var images: [String] = []; var files: [String] = []
        var isEmpty: Bool { text.isEmpty && images.isEmpty && files.isEmpty } }
    private var drafts: [String: Draft] = [:]
    private(set) var history: [String] = []
    private var timer: Timer?
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Agent Lab", isDirectory: true).appendingPathComponent("composer.json")
    private struct Saved: Codable { var drafts: [String: Draft]; var history: [String] }

    private init() {
        if let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)) { drafts = saved.drafts; history = saved.history }
    }
    func draft(_ key: String) -> Draft { drafts[key] ?? Draft() }
    func set(_ key: String, _ draft: Draft) {
        guard drafts[key] ?? Draft() != draft else { return }
        drafts[key] = draft.isEmpty ? nil : draft
        later()
    }
    func remember(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, history.last != t else { return }
        history.append(t)
        if history.count > 200 { history.removeFirst(history.count - 200) }
        later()
    }
    private func later() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { DraftStore.shared.write() } }
    }
    func write() {
        // The box test types into a real chat: it never writes your drafts or history.
        if ProcessInfo.processInfo.processName == "boxtest" { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Saved(drafts: drafts, history: history)).write(to: url, options: .atomic)
    }
}

// MARK: Attachments

enum Attachments {
    static func isImage(_ path: String) -> Bool { ["png", "jpg", "jpeg", "gif", "webp"].contains((path as NSString).pathExtension.lowercased()) }

    /// A pasted picture, saved so it can be sent and kept with the draft.
    static func save(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agent Lab/Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Pasted \(UUID().uuidString.prefix(8)).png")
        return (try? png.write(to: url)) != nil ? url.path : nil
    }

    /// The words an agent gets for attached files: each named so it can open it.
    static func prompt(_ text: String, files: [String]) -> String {
        guard !files.isEmpty else { return text }
        let named = files.map { "@\($0)" }.joined(separator: "\n")      // one per line: a path with spaces stays whole
        return text.isEmpty ? named : "\(text)\n\n\(named)"
    }
}

// MARK: Files for @

/// A folder's files and folders, listed once in the background (skipping build output and dependencies), searched by
/// the letters you type, best first.
@MainActor final class FileIndex {
    static let shared = FileIndex()
    private var lists: [String: [String]] = [:]
    private var listing: Set<String> = []
    /// Bumped when a folder finishes listing, so an open `@` list fills in.
    var onListed: (() -> Void)?

    func search(_ query: String, in folder: String) -> [String] {
        guard let files = lists[folder] else { build(folder); return [] }
        let q = query.lowercased()
        guard !q.isEmpty else { return Array(files.prefix(40)) }
        var scored: [(Int, String)] = []
        for path in files {
            let lower = path.lowercased()
            let name = ((lower.hasSuffix("/") ? String(lower.dropLast()) : lower) as NSString).lastPathComponent
            guard let s = Rank.score(q, name: name, about: "") ?? (lower.contains(q) ? 3 : nil) else { continue }
            scored.append((s * 1000 + path.count, path))
            if scored.count > 4000 { break }
        }
        return scored.sorted { $0.0 < $1.0 }.prefix(40).map(\.1)
    }

    private func build(_ folder: String) {
        guard !listing.contains(folder) else { return }
        listing.insert(folder)
        Task.detached(priority: .utility) {
            let skip: Set<String> = [".git", "node_modules", ".build", "build", "DerivedData", "dist", ".next", "Pods", ".venv", "venv",
                                     "__pycache__", "target", ".swiftpm", "Library", "Applications", "Pictures", "Music", "Movies"]
            var found: [String] = []
            let root = URL(fileURLWithPath: folder)
            if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in walker {
                    if skip.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
                    let relative = String(url.path.dropFirst(root.path.count + 1))
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { found.append(relative + "/") } else { found.append(relative) }
                    if found.count >= 20_000 { break }
                }
            }
            let list = found.sorted { $0.count < $1.count }
            await MainActor.run { FileIndex.shared.lists[folder] = list; FileIndex.shared.listing.remove(folder); FileIndex.shared.onListed?() }
        }
    }
}

// MARK: The text view

/// The box's words: a real text view in Agent Lab's type, growing with what you write to eight lines.
struct ComposerField: NSViewRepresentable {
    @ObservedObject var model: ComposerModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        let text = ComposerTextView()
        text.model = model
        text.delegate = context.coordinator
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.drawsBackground = false
        let size: CGFloat = MV.on ? MV.Text.chatInput : 16
        let font = NSFont(name: "AnthropicSansText-Regular", size: size) ?? .systemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = MV.Chat.inputLine
        style.maximumLineHeight = MV.Chat.inputLine
        // AppKit puts a fixed line's extra height above the glyphs; MAVIS lifts them back to the line's centre so typed
        // words sit where the placeholder does.
        let lift = MV.on ? (MV.Chat.inputLine - (font.ascender - font.descender)) / 2 : 0
        text.font = font
        text.textColor = NSColor(C.i12)
        text.insertionPointColor = NSColor(C.i12)
        // Room for a chip's fill as line padding inside the text area (an inset outside it got the fill clipped at a line's
        // start); the field sits Chip.room wider, so the words are where they were.
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = Chip.room
        text.textContainer?.replaceLayoutManager(ChipLayoutManager())
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.typingAttributes = [.font: font, .foregroundColor: NSColor(C.i12), .paragraphStyle: style, .baselineOffset: lift]
        text.defaultParagraphStyle = style
        text.registerForDraggedTypes([.fileURL, .png, .tiff])
        scroll.documentView = text
        context.coordinator.text = text
        text.string = model.text
        DispatchQueue.main.async { context.coordinator.measure(); text.window?.makeFirstResponder(text) }
        FileIndex.shared.onListed = { [weak model] in model?.refresh() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = context.coordinator.text else { return }
        text.model = model
        if context.coordinator.revision != model.revision {
            context.coordinator.revision = model.revision
            let wanted = model.caret
            if text.string != model.text { text.string = model.text }
            let caret = min(wanted, (text.string as NSString).length)
            model.caret = caret
            text.setSelectedRange(NSRange(location: caret, length: 0))
            text.scrollRangeToVisible(NSRange(location: caret, length: 0))
            CommandTokens.paint(text)
            context.coordinator.measure()
        }
        if context.coordinator.focus != model.focus {
            context.coordinator.focus = model.focus
            DispatchQueue.main.async { text.window?.makeFirstResponder(text) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let model: ComposerModel
        weak var text: ComposerTextView?
        var revision = -1
        var focus = -1
        init(model: ComposerModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let text else { return }
            model.typed(text.string, caret: text.selectedRange().location)
            CommandTokens.paint(text)
            measure()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let text, model.caret != text.selectedRange().location else { return }
            model.caret = text.selectedRange().location
        }
        func measure() {
            guard let text, let manager = text.layoutManager, let container = text.textContainer else { return }
            manager.ensureLayout(for: container)
            let used = ceil(manager.usedRect(for: container).height)
            let height = min(max(24, used), 24 * 8)
            if abs(model.height - height) > 0.5 { model.height = height }
        }
    }
}

/// The text view's keys, and pasted or dropped pictures and files as attachments.
final class ComposerTextView: NSTextView {
    weak var model: ComposerModel?

    override func keyDown(with event: NSEvent) {
        guard let model, !hasMarkedText() else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        let handled: Bool = MainActor.assumeIsolated {
            switch event.keyCode {
            case 36, 76:                                                    // ↵
                if flags.contains(.shift) || flags.contains(.option) { return false }
                if !event.isARepeat { model.submit() }
                return true
            case 53: model.cancel(); return true                           // Esc
            case 48 where flags.isEmpty: return model.accept()             // Tab
            case 126 where flags.isEmpty: return model.up()                // ↑
            case 125 where flags.isEmpty: return model.down()              // ↓
            case 35 where flags == .control: return model.menu != nil || !model.suggestions.isEmpty ? model.up() : false     // ⌃P
            case 45 where flags == .control: return model.menu != nil || !model.suggestions.isEmpty ? model.down() : false   // ⌃N
            case 116: return model.page(-1)                                 // Page ↑
            case 121: return model.page(1)                                  // Page ↓
            case 124 where flags.isEmpty: return model.menuRight()         // →
            case 123 where flags.isEmpty: return model.menuLeft()          // ←
            case 32 where flags == .command: model.pick(folders: false); return true      // ⌘U
            default: return false
            }
        }
        if handled { return }
        if event.keyCode == 36 || event.keyCode == 76 { insertNewlineIgnoringFieldEditor(nil); return }
        super.keyDown(with: event)
    }

    /// Backspace just after a command or skill takes it away whole, in one undo step (Mavis: SkillTokens).
    override func deleteBackward(_ sender: Any?) {
        let caret = selectedRange()
        if caret.length == 0, caret.location > 0,
           let token = CommandTokens.ranges(in: string).first(where: { NSMaxRange($0) == caret.location }),
           shouldChangeText(in: token, replacementString: "") {
            replaceCharacters(in: token, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: token.location, length: 0))
            return
        }
        super.deleteBackward(sender)
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { if model?.menu != nil { model?.closeMenu() } }
        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            MainActor.assumeIsolated { model?.add(urls.map(\.path)) }
            return
        }
        if board.string(forType: .string) == nil, let image = NSImage(pasteboard: board), let path = Attachments.save(image) {
            MainActor.assumeIsolated { model?.add([path]) }
            return
        }
        pasteAsPlainText(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            MainActor.assumeIsolated { model?.add(urls.map(\.path)) }
            return true
        }
        return super.performDragOperation(sender)
    }
}

// MARK: The pieces around the words

/// A menu's surface, as the Mode card's: the panel grey, its outline, a deep soft shadow.
extension View {
    func menuCard() -> some View {
        background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
            .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edgeControl, lineWidth: 1))
            .floatShadow()
    }
}

/// `/` commands or `@` mentions above the box, in sections. The pointer lights and picks too.
struct SuggestionList: View {
    @ObservedObject var model: ComposerModel
    static func height(_ items: [Suggestion]) -> CGFloat {
        let headers = CGFloat(Set(items.map(\.section)).count) * 28
        return min(CGFloat(items.count) * 42 + headers, 6.5 * 42 + 28) + 8
    }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { i, s in
                        if i == 0 || model.suggestions[i - 1].section != s.section {
                            Text(s.section).font(F.font(12, .medium)).foregroundStyle(C.i10).padding(.horizontal, 10).frame(height: 26, alignment: .bottom)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: s.symbol).font(.system(size: 14)).foregroundStyle(i == model.highlighted ? C.i12 : C.i10).frame(width: 20)
                            Text(s.label).font(F.font(14, .medium)).foregroundStyle(C.i12).lineLimit(1).layoutPriority(2)
                            if !s.hint.isEmpty { Text(Words.line(s.hint, 24)).font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).layoutPriority(1) }
                            Text(s.detail).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1)
                                .truncationMode([.file, .folder].contains(s.kind) ? .head : .tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == model.highlighted ? C.v4 : .clear))
                        .contentShape(Rectangle())
                        .clipped()
                        .onTapGesture { model.highlighted = i; model.submit() }
                        .onContinuousHover { if case .active = $0 { model.highlighted = i } }
                        .id(s.id)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height(model.suggestions))
            .onChange(of: model.highlighted) { _, i in if model.suggestions.indices.contains(i) { reader.scrollTo(model.suggestions[i].id) } }
        }
        .menuCard()
    }
}

/// The + menu: files or photos, a folder, the commands, plugins (opening in place, with the setup switch first).
struct PlusMenu: View {
    @EnvironmentObject var s: Store
    @ObservedObject var model: ComposerModel
    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.submenu == nil {
                ForEach(model.menuItems, id: \.rawValue) { item in
                    row(symbol: item.symbol, title: item.title, keys: item.keys, lit: model.menu == item.rawValue, more: item == .plugins) { model.choose(item) }
                        .onContinuousHover { if case .active = $0 { model.menu = item.rawValue } }
                }
            } else {
                Button { model.submenu = nil } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(C.i10)
                        Text("Plugins").font(F.font(12, .medium)).foregroundStyle(C.i10)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).tip("Back", "←", edge: .leading)
                plugins
            }
        }
        .padding(4).frame(width: Self.width)
        .menuCard()
    }

    @ViewBuilder private var plugins: some View {
        if let agent = model.agent {
            if model.showsSetup {
                let on = agent.claudeSetup == true
                toggleRow(title: "Use my Claude Code setup", detail: on ? "Your skills, plugins and CLAUDE.md · slower to start" : "Off: Agent Lab's rules only · fastest",
                          on: on, lit: model.submenu == -1) { s.setClaudeSetup(agent, on: !on) }
                    .onContinuousHover { if case .active = $0 { model.submenu = -1 } }
                Rectangle().fill(C.divider).frame(height: 1).padding(.vertical, 4)
            }
            if let list = s.plugins[agent.id] {
                if list.isEmpty {
                    Text("No plugins installed").font(F.font(14, .regular)).foregroundStyle(C.i10).padding(.horizontal, 10).frame(height: 40)
                } else {
                    let usable = !model.showsSetup || agent.claudeSetup == true
                    ScrollViewReader { reader in
                        ScrollView(.vertical) {
                            VStack(spacing: 2) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                                    toggleRow(title: p.name, detail: p.about, on: p.enabled, lit: model.submenu == i) { s.setPlugin(agent.id, p, on: !p.enabled) }
                                        .opacity(usable ? 1 : 0.55)
                                        .onContinuousHover { if case .active = $0 { model.submenu = i } }
                                        .id(p.id)
                                }
                            }
                        }
                        .scrollIndicators(.never)
                        .frame(maxHeight: 6.5 * 52).fixedSize(horizontal: false, vertical: true)
                        .onChange(of: model.submenu) { _, i in if let i, list.indices.contains(i) { reader.scrollTo(list[i].id) } }
                    }
                    if !usable {
                        Text("Plugins load when the setup is on.").font(F.font(12, .regular)).foregroundStyle(C.i9).padding(.horizontal, 10).frame(height: 28)
                    }
                }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading plugins…").font(F.font(14, .regular)).foregroundStyle(C.i10) }
                    .padding(.horizontal, 10).frame(height: 40)
            }
        }
    }

    private func row(symbol: String, title: String, keys: String?, lit: Bool, more: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(C.i12).frame(width: 20)
                Text(title).font(F.font(14, .medium)).foregroundStyle(C.i12)
                Spacer(minLength: 8)
                if let keys { Text(keys).font(F.font(12, .medium)).foregroundStyle(C.i9) }
                if more { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(C.i10) }
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? C.v4 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(title: String, detail: String, on: Bool, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(F.font(14, .medium)).foregroundStyle(C.i12).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Switch(on: on)
            }
            .padding(.horizontal, 10).frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? C.v4 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A small on/off switch in the app's greys.
struct Switch: View {
    let on: Bool
    var body: some View {
        Capsule().fill(on ? C.i12 : C.v5).frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(on ? C.v1 : C.i10).frame(width: 14, height: 14).padding(2) }
            .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// What's attached, above the words: a thumbnail per picture, a chip per file, each with ×.
struct AttachmentStrip: View {
    @ObservedObject var model: ComposerModel
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.images, id: \.self) { path in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = NSImage(contentsOfFile: path) { Image(nsImage: image).resizable().scaledToFill() }
                            else { Image(systemName: "photo").foregroundStyle(C.i10) }
                        }
                        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: Box.inner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
                        remove(path).offset(x: 6, y: -6)
                    }
                    .padding(.top, 6).padding(.trailing, 6)
                }
                ForEach(model.files, id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: path.hasSuffix("/") || FileManager.default.isDirectory(path) ? "folder" : "doc").font(.system(size: 12)).foregroundStyle(C.i10)
                        Text((path as NSString).lastPathComponent).font(F.font(13, .medium)).foregroundStyle(C.i12).lineLimit(1)
                        remove(path)
                    }
                    .padding(.leading, 10).padding(.trailing, 4).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(C.v3))
                    .help(path)
                }
            }
        }
        .scrollIndicators(.never)
    }
    private func remove(_ path: String) -> some View {
        Hover { h in
            Button { model.remove(path) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(h ? C.i12 : C.i10)
                    .frame(width: 20, height: 20).background(Circle().fill(C.v4)).overlay(Circle().strokeBorder(C.edgeControl, lineWidth: 1))
            }.buttonStyle(.plain).tip("Remove", edge: .top)
        }
    }
}

extension FileManager {
    func isDirectory(_ path: String) -> Bool { var d: ObjCBool = false; return fileExists(atPath: path, isDirectory: &d) && d.boolValue }
}

/// The + button, the suggestions and the menu around a box: put this on the box.
struct ComposerOverlays: ViewModifier {
    @ObservedObject var model: ComposerModel
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if !model.suggestions.isEmpty {
                    SuggestionList(model: model).offset(y: -(SuggestionList.height(model.suggestions) + 8))
                }
            }
            // A click anywhere else closes the menu.
            .overlay {
                if model.menu != nil {
                    Color.black.opacity(0.001).frame(width: 4000, height: 4000).onTapGesture { model.closeMenu() }
                }
            }
            // The menu sits on the box's top edge, 8 above it, from the + button's side.
            .overlay(alignment: .topLeading) {
                if model.menu != nil {
                    // A zero-height frame on the box's top edge, the menu hanging up from it.
                    PlusMenu(model: model).fixedSize(horizontal: false, vertical: true)
                        .frame(width: PlusMenu.width, height: 0, alignment: .bottom).offset(y: -8)
                }
            }
    }
}


/// A click anywhere but the text box you're typing in lets go of it, as every Mac text box does: any editable box (a
/// chat's, Home's, a field's). Only after the click is handled, so a button still gets it, and only if nothing else
/// took the keyboard meanwhile.
@MainActor enum ClickAway {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { e in
            MainActor.assumeIsolated {
                guard let w = e.window, let tv = w.firstResponder as? NSTextView, tv.isEditable, let content = w.contentView else { return }
                // A one-line field types through the window's shared editor: the field itself is what you clicked into.
                let owner: NSView = tv.isFieldEditor ? ((tv.delegate as? NSView) ?? tv) : (tv.enclosingScrollView ?? tv)
                let hit = content.hitTest(content.superview?.convert(e.locationInWindow, from: nil) ?? e.locationInWindow)
                if let hit, hit === owner || hit === tv || hit.isDescendant(of: owner) { return }
                DispatchQueue.main.async { if w.firstResponder === tv { w.makeFirstResponder(nil) } }
            }
            return e
        }
    }
}


/// Your message's attached files, out of its words: the trailing "@/path" lines (also older "@/a @/b" on one line),
/// each an existing file. The bubble shows the words; the files show as tiles above it.
enum SentFiles {
    static func split(_ text: String) -> (words: String, files: [String]) {
        var lines = text.components(separatedBy: "\n")
        var files: [String] = []
        while let last = lines.last {
            let t = last.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { lines.removeLast(); continue }
            guard t.hasPrefix("@/") else { break }
            let whole = String(t.dropFirst())
            if FileManager.default.fileExists(atPath: whole) { files.insert(whole, at: 0); lines.removeLast(); continue }
            let parts = t.components(separatedBy: " @/").enumerated().map { $0.offset == 0 ? String($0.element.dropFirst()) : "/" + $0.element }
            guard parts.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { break }
            files.insert(contentsOf: parts, at: 0); lines.removeLast()
        }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), files)
    }
}

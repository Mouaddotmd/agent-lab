// The native app's link to Agent Lab's engine (engine/server.js), the same engine the web app uses.
// It runs as a child process and speaks one JSON object per line:
//   in:  { "id": 1, "method": "agent:create", "params": [...] }
//   out: { "id": 1, "ok": true, "value": ... }  or  { "id": 1, "ok": false, "error": "…" }
//   out: { "event": { "type": "run", ... } }
import Foundation

struct EngineError: LocalizedError { let message: String; var errorDescription: String? { message } }

@MainActor
final class Engine {
    private var proc: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextId = 1
    private var waiting: [Int: CheckedContinuation<Any, Error>] = [:]
    var onEvent: (([String: Any]) -> Void)?
    var onExit: ((String) -> Void)?

    /// Starts the engine. Throws with a plain reason if Node or the engine can't be found.
    func start() throws {
        guard let node = Engine.findNode() else { throw EngineError(message: "Agent Lab needs Node.js to run agents. Install it from nodejs.org, then reopen Agent Lab.") }
        guard let server = Engine.findServer() else { throw EngineError(message: "Agent Lab's engine is missing. Reinstall Agent Lab.") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [server.path]
        p.currentDirectoryURL = server.deletingLastPathComponent().deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        // Apps opened from the Dock get a bare PATH; the engine needs to find claude, codex, git.
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "\(NSHomeDirectory())/.npm-global/bin", (node as NSString).deletingLastPathComponent]
        env["PATH"] = (extra + [(env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")]).joined(separator: ":")
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe
        p.standardError = FileHandle.standardError
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            Task { @MainActor in self?.receive(d) }
        }
        p.terminationHandler = { [weak self] pr in
            Task { @MainActor in self?.stopped("The engine stopped (\(pr.terminationStatus)).") }
        }
        try p.run()
        proc = p; input = inPipe.fileHandleForWriting
    }

    func stop() { try? input?.close(); proc?.terminate() }

    /// Calls an engine method. `params` are passed as the method's arguments, in order.
    func call(_ method: String, _ params: [Any] = []) async throws -> Any {
        guard let input, proc?.isRunning == true else { throw EngineError(message: "The engine isn't running.") }
        let id = nextId; nextId += 1
        let line = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]) + Data([10])
        return try await withCheckedThrowingContinuation { c in
            waiting[id] = c
            do { try input.write(contentsOf: line) } catch { waiting[id] = nil; c.resume(throwing: error) }
        }
    }
    /// Calls a method and decodes its value.
    func call<T: Decodable>(_ method: String, _ params: [Any] = [], as: T.Type) async throws -> T {
        let v = try await call(method, params)
        let data = try JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func receive(_ d: Data) {
        if d.isEmpty { return }
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 10) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty, let m = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let ev = m["event"] as? [String: Any] { onEvent?(ev); continue }
            guard let id = m["id"] as? Int, let c = waiting.removeValue(forKey: id) else { continue }
            if m["ok"] as? Bool == true { c.resume(returning: m["value"] ?? NSNull()) }
            else { c.resume(throwing: EngineError(message: m["error"] as? String ?? "Something went wrong.")) }
        }
    }

    private func stopped(_ why: String) {
        for (_, c) in waiting { c.resume(throwing: EngineError(message: why)) }
        waiting.removeAll(); proc = nil; input = nil
        onExit?(why)
    }

    // MARK: Finding Node and the engine

    static func findNode() -> String? {
        let fm = FileManager.default
        var tries = [ProcessInfo.processInfo.environment["AGENT_LAB_NODE"], Bundle.main.resourceURL?.appendingPathComponent("node/bin/node").path,
                     "/opt/homebrew/bin/node", "/usr/local/bin/node"].compactMap { $0 }
        // nvm installs: newest first
        let nvm = "\(NSHomeDirectory())/.nvm/versions/node"
        if let v = try? fm.contentsOfDirectory(atPath: nvm) { tries += v.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(nvm)/\($0)/bin/node" } }
        return tries.first { fm.isExecutableFile(atPath: $0) }
    }

    /// engine/server.js: next to the app in the project (development), or inside the app (shipped).
    static func findServer() -> URL? {
        let fm = FileManager.default
        var tries: [URL] = []
        if let e = ProcessInfo.processInfo.environment["AGENT_LAB_ENGINE"] { tries.append(URL(fileURLWithPath: e)) }
        if let r = Bundle.main.resourceURL { tries.append(r.appendingPathComponent("engine/server.js")) }
        // native/build/Agent Lab Native.app → the project folder
        tries.append(Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("engine/server.js"))
        // native/build/<tool> → the project folder
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        tries.append(exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("engine/server.js"))
        return tries.first { fm.fileExists(atPath: $0.path) }?.standardizedFileURL
    }
}

// MARK: What the engine sends back

/// An agent as the engine stores it (engine/store.js addAgent).
struct Agent: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var job: String?
    var look: LookSpec?
    var `operator`: String?
    var model: String?
    var permission: String?
    /// The channels' own assistant (engine): never listed as one of your agents.
    var hidden: Bool? = nil
    var alwaysEdits: Bool?      // "Always allow file changes", whatever the mode (engine: answer "always")
    var apps: Bool?             // may use your connected apps (nil and true: yes)
    var claudeSetup: Bool?      // "Use my Claude Code setup": your skills, plugins and CLAUDE.md (engine: settingSources)
    var cwd: String?
    var workspace: String?
    var pinned: Bool?
    var createdAt: Double?
    var worktree: String?
    var branch: String?
    var last: Last?
    var origin: Origin?
    var memory: [Note]?         // what it noted to remember, from every chat (engine: store.remember)
    struct Note: Codable, Equatable, Identifiable { let id: String; var text: String; var at: Double? }
    struct Last: Codable, Equatable { var state: String?; var at: Double?; var seen: Bool? }
    struct Origin: Codable, Equatable { var type: String?; var title: String? }
}
/// A face as hex colours (web: randLook).
struct LookSpec: Codable, Equatable { var bg: String; var skin: String; var hair: String; var shirt: String; var style: Int; var glasses: Bool }

struct Workspace: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var path: String?
    var color: String?
    var about: String?
    var image: String?          // data:image/…;base64, under 400 KB (engine checks)
    var members: [String]?      // agent ids invited here (the same agents, with their own memory, as in your DMs)
    var categories: [Category]? // text channels in groups, like a Discord server; always at least #general
    var muted: Bool?            // no badge, no unread dot
    var readAt: Double?         // when you last caught up (ms)
    var activityAt: Double?     // when an agent last said something in it (ms; engine: state)
    struct Category: Codable, Equatable, Identifiable { var id: String; var name: String; var open: Bool?; var channels: [Channel]; var color: String? = nil }
    /// `agent`: the one agent that answers this channel without being tagged (nil: the workspace's first agent).
    /// `agents`: the agents given this channel (a session of its own): they answer here, the first unless you tag one.
    /// None: the channel's own assistant answers.
    struct Channel: Codable, Equatable, Identifiable { var id: String; var name: String; var agents: [String]? = nil }
    /// Who answers `channel` when you don't tag anyone.
    func answerer(_ channel: Channel, among all: [Agent]) -> Agent? { granted(channel, among: all).first }
    /// The agents given `channel`, in the order you gave them.
    func granted(_ channel: Channel, among all: [Agent]) -> [Agent] {
        (channel.agents ?? []).compactMap { id in all.first { $0.id == id } }
    }
    var channels: [Channel] { (categories ?? []).flatMap(\.channels) }
    /// The conversation id of one of its channels (engine: channelConv).
    func conv(_ channel: String) -> String { "c_\(id)_\(channel)" }
}

struct EngineState: Decodable {
    var agents: [Agent]
    var workspaces: [Workspace]
    var home: String
    var runs: [Run]
    var approvals: [Approval]
}

/// One line of an agent's conversation (engine/store.js addMessage).
struct Message: Codable, Identifiable, Equatable {
    let id: String; var role: String; var text: String; var verb: String?; var at: Double?
    var turn: String?; var ch: String?; var by: String?     // by: the agent that wrote it, in a channel
    var toolId: String?; var round: Int?; var done: Bool?; var failed: Bool?
    var images: [String]?       // pictures sent with it
    var detail: String?         // a step's whole command or path
    var output: String?         // what came back from a step
    var diff: [FileChange]?     // what a step changed
    var seconds: Int?           // a thought: how long
    var steered: Bool?          // sent while the agent worked: it went into what it was doing
}

/// One file's change: lines in (+), out (-), around ( ), and gaps (~).
struct FileChange: Codable, Equatable, Hashable {
    var path: String; var change: String; var lines: [DiffLine]
    struct DiffLine: Codable, Equatable, Hashable { var k: String; var t: String }
    var added: Int { lines.filter { $0.k == "+" }.count }
    var removed: Int { lines.filter { $0.k == "-" }.count }
    var name: String { (path as NSString).lastPathComponent }
}
/// A run in progress (engine.js snapshot).
/// `conv` is the conversation it writes into (the agent's id for a DM, a channel's conv id); `by` is set in a channel.
struct Run: Codable, Equatable { var key: String; var agentId: String?; var startedAt: Double?; var activity: String?; var turn: String?; var conv: String? = nil; var by: String? = nil
    /// What it's on right now, under the status line: the thought, or the file being written and how far.
    var detail: String? = nil
    var conversation: String? { conv ?? agentId }
}
/// Something an agent wants to do that needs your yes (engine.js pending).
struct Approval: Codable, Identifiable, Equatable { let id: String; var agentId: String?; var verb: String?; var line: String?; var detail: String?; var canAlways: Bool?; var tool: String? = nil; var risk: String? = nil; var command: String? = nil; var conv: String? = nil
    /// What the step is for, in the agent's words ("Check mouad.work's DNS records"): the card's title.
    var about: String? = nil
    /// Its questions (AskUserQuestion), and the change it would make (an edit).
    var questions: [Question]? = nil; var diff: [FileChange]? = nil
    struct Question: Codable, Equatable, Hashable { var question: String; var header: String; var multiple: Bool; var options: [Option] }
    struct Option: Codable, Equatable, Hashable { var label: String; var about: String }
}

/// For code inside enums that have a nested type called Workspace (MV.Workspace).
typealias WorkspaceCategory = Workspace.Category

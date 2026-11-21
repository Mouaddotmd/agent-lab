import Foundation

// Everything the engine sends, as plain value types. Optional fields stay optional: the engine omits what it doesn't know.

struct Origin: Codable, Hashable {
    var type: String
    var `operator`: String?
    var ref: String?
    var title: String?
}

struct LastRun: Codable, Hashable {
    var state: String
    var at: Double?
    var cost: Double?
    var seen: Bool?
}

struct Look: Codable, Hashable {
    var bg: String
    var skin: String
    var hair: String
    var style: Int
    var shirt: String
    var glasses: Bool
}

struct Agent: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var job: String?
    var color: Int?
    var look: Look?
    var `operator`: String
    var model: String?
    var permission: String?
    var cwd: String?
    var sessionId: String?
    var worktree: String?
    var branch: String?
    var baseRepo: String?
    var baseBranch: String?
    var origin: Origin?
    var last: LastRun?
    var createdAt: Double?
    var pinned: Bool?
}

struct Message: Codable, Identifiable, Hashable {
    var id: String
    var role: String
    var text: String
    var verb: String?
    var at: Double?
}

struct ChatRef: Codable, Hashable {
    var `operator`: String
    var id: String
}

struct Run: Codable, Hashable {
    var key: String
    var agentId: String?
    var chat: ChatRef?
    var `operator`: String?
    var startedAt: Double
    var activity: String?
    var preview: String?
}

struct Approval: Codable, Identifiable, Hashable {
    var id: String
    var key: String
    var agentId: String?
    var chat: ChatRef?
    var tool: String?
    var verb: String
    var line: String
    var detail: String?
    var canAlways: Bool?
    var at: Double?
}

struct Chat: Codable, Identifiable, Hashable {
    var `operator`: String
    var id: String
    var cwd: String?
    var title: String
    var updated: Double
    var bot: String?
    var model: String?
}

struct Line: Codable, Hashable {
    var role: String
    var text: String
    var verb: String?
}

struct Workspace: Codable, Identifiable, Hashable {
    var id: String
    var path: String
    var name: String
    var color: String
}

struct Decision: Codable, Identifiable, Hashable {
    var id: String
    var n: Int
    var text: String
    var workspace: String?
    var by: String?
    var source: String?
    var at: Double?
}

struct OperatorInfo: Codable, Hashable {
    var id: String
    var name: String
    var path: String?
    var version: String?
}

struct LabState: Codable {
    var agents: [Agent]
    var workspaces: [Workspace]
    var memory: [Decision]
    var runs: [Run]
    var approvals: [Approval]
    var operators: [String: OperatorInfo]
    var codexModels: [String]?
    var imported: Int
    var home: String
}

struct FileChange: Codable, Hashable, Identifiable {
    var path: String
    var add: Int
    var del: Int
    var binary: Bool?
    var id: String { path }
}

struct Changes: Codable { var files: [FileChange] }

struct Overlap: Codable, Hashable, Identifiable {
    var id: String
    var agents: [String]
    var files: [String]
}

struct RepoInfo: Codable, Hashable {
    var root: String
    var branch: String?
    var hasCommits: Bool
}

struct FolderInfo: Codable { var exists: Bool; var repo: RepoInfo? }

struct MavisScan: Codable, Hashable {
    var found: Bool
    var bots: Int
    var chats: Int
    var newChats: Int
    var newAgents: Int
}

struct ImportResult: Codable { var chats: Int; var agents: Int }
struct MergeResult: Codable { var merged: Int }

struct EngineEvent: Decodable {
    var type: String
    var key: String?
    var agentId: String?
    var error: String?
    var text: String?
    var run: Run?
    var line: Line?
    var command: String?
}

/// Accepts any JSON value; for calls whose answer we don't read.
struct Ignored: Decodable { init(from decoder: Decoder) throws {} }

// What an agent is doing, in the order it matters to you.
enum AgentState: Int, CaseIterable {
    case waiting, working, failed, done, ready
    var label: String {
        switch self {
        case .waiting: "Waiting for you"
        case .working: "Working"
        case .failed: "Failed"
        case .done: "Done"
        case .ready: "Ready"
        }
    }
}

enum Operators {
    static let all = ["claude-code", "codex"]
    static func name(_ id: String) -> String {
        switch id {
        case "claude-code": "Claude Code"
        case "codex": "Codex"
        case "mavis": "Mavis"
        default: id
        }
    }
    static func symbol(_ id: String) -> String {
        switch id {
        case "claude-code": "asterisk"
        case "codex": "chevron.left.forwardslash.chevron.right"
        case "mavis": "sparkles"
        default: "cpu"
        }
    }
    /// Claude models people pick; Codex's come from what it has actually answered on in your chats.
    static let claudeModels: [(String, String)] = [("", "Claude Code default"), ("claude-opus-5-5", "Opus 5.5"), ("claude-sonnet-5-5", "Sonnet 5.5"), ("claude-haiku-5-5", "Haiku 5.5")]
}

enum Permission: String, CaseIterable, Identifiable {
    case ask, edits, plan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: "Asks before changes"
        case .edits: "Edits files freely"
        case .plan: "Plans only"
        }
    }
}

extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}

func relativeTime(_ ms: Double?) -> String {
    guard let ms else { return "" }
    let date = Date(timeIntervalSince1970: ms / 1000)
    if Date().timeIntervalSince(date) < 45 { return "just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

func elapsed(since ms: Double) -> String {
    let s = max(0, Int(Date().timeIntervalSince1970 - ms / 1000))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

// The chat's rules as pure logic: no views, no engine, no clock you can't pass in. Ported from Mavis final launch
// (App/Sources/NextSteps.swift, AgentSteps.swift, ShellChat.swift; rules in App/docs/chat-rules.md), where each piece was
// measured and fixed against real runs. Everything here is checked by `build/chattest` (tools/chattest.swift): change a
// number and the test says what it broke.
import Foundation
import CoreGraphics

// MARK: Hidden lines Claude writes (Mavis: NextSteps.swift)

/// The depth behind an answer: a card the user can open (⟦report: Title⟧ … ⟦/report⟧).
enum ReportTag {
    static let closed = try! NSRegularExpression(pattern: #"\s*⟦\s*report\s*:[^⟧]*⟧[\s\S]*?⟦\s*/\s*report\s*⟧\s*"#, options: [.caseInsensitive])
    static let open = try! NSRegularExpression(pattern: #"\s*⟦\s*report\s*:[^⟧]*⟧[\s\S]*$"#, options: [.caseInsensitive])
    private static let parts = try! NSRegularExpression(pattern: #"⟦\s*report\s*:\s*([^⟧]*)⟧([\s\S]*?)(⟦\s*/\s*report\s*⟧|$(?![\s\S]))"#, options: [.caseInsensitive])

    struct Report: Equatable { let title: String; let body: String; let finished: Bool
        var words: Int { body.split(whereSeparator: \.isWhitespace).count }
        /// Long enough to be read on its own beside the chat (heavy work): about two pages. Shorter is part of the answer.
        var long: Bool { words >= 900 }
    }
    /// The reports in a reply as written so far; the last may still be arriving.
    static func reports(_ raw: String) -> [Report] {
        guard raw.contains("⟦") else { return [] }
        let ns = raw as NSString
        return parts.matches(in: raw, range: NSRange(location: 0, length: ns.length)).map { m in
            Report(title: ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines),
                   body: ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines),
                   finished: m.range(at: 3).length > 0)
        }
    }
}

/// The plan behind a task with several steps, ticked as it's done (⟦plan: a | b | c⟧, then ⟦done: N⟧).
enum PlanTag {
    struct Plan: Equatable { var items: [String]; var done: Set<Int> }
    static let planLine = try! NSRegularExpression(pattern: #"⟦\s*plan\s*:\s*([^⟧]*)⟧"#, options: [.caseInsensitive])
    static let doneLine = try! NSRegularExpression(pattern: #"⟦\s*done\s*:\s*(\d+)\s*⟧"#, options: [.caseInsensitive])
    static let any = try! NSRegularExpression(pattern: #"\s*⟦\s*(?:plan|done)\s*:[^⟧]*⟧"#, options: [.caseInsensitive])

    static func parse(_ raw: String) -> Plan? {
        guard raw.contains("⟦") else { return nil }
        let ns = raw as NSString
        guard let match = planLine.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let items = ns.substring(with: match.range(at: 1)).split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        var done = Set<Int>()
        for m in doneLine.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            if let n = Int(ns.substring(with: m.range(at: 1))), n >= 1, n <= items.count { done.insert(n) }
        }
        return Plan(items: Array(items.prefix(7)), done: done)
    }
    /// Claude's own ticks lead; rounds of finished work fill in when it forgets. Ticks only ever grow.
    static func progress(_ plan: Plan, finishedRounds: Int, answering: Bool) -> Plan {
        let n = plan.items.count
        guard n > 1 else { return plan }
        var done = plan.done
        let ticked = done.max() ?? 0
        let inferred = min(max(ticked, finishedRounds), n - 1)
        if inferred > 0 { done.formUnion(1...inferred) }
        if answering, done.count < n - 1, ticked == 0, finishedRounds == 0 { done.insert(1) }
        return Plan(items: plan.items, done: done)
    }
    /// Rounds of work finished before the first unfinished one. The engine numbers rounds (calls Claude sent together);
    /// progress never skips over work still running.
    static func finishedRounds(_ calls: [(round: Int, finished: Bool)]) -> Int {
        var byRound: [Int: Bool] = [:]
        for c in calls { byRound[c.round] = (byRound[c.round] ?? true) && c.finished }
        return byRound.keys.sorted().prefix { byRound[$0] == true }.count
    }
}

/// A to-do list Claude wrote as text ("To-do list:" then "- [ ] …" lines) is the plan all the same: it becomes the
/// to-do card, never a checklist in the words (17 Nov). Lines ticked "[x]" count as done.
enum Checklist {
    private static let item = try! NSRegularExpression(pattern: #"^[ \t]*[-*][ \t]*\[([ xX])\][ \t]+(.+?)[ \t]*$"#, options: [.anchorsMatchLines])
    private static let header = try! NSRegularExpression(pattern: #"(?im)^[ \t]*(?:\*\*)?(?:to-?do(?: list)?|plan|steps|checklist)(?:\*\*)?[ \t]*:?(?:\*\*)?[ \t]*\n+(?=[ \t]*⟦plan)"#)
    static func asPlan(_ text: String) -> String {
        guard text.contains("[ ]") || text.contains("[x]") || text.contains("[X]") else { return text }
        let ns = text as NSString
        let found = item.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let first = found.first, let last = found.last else { return text }
        // Only one block of consecutive items: the plan.
        var block = [first]
        for m in found.dropFirst() {
            let gap = ns.substring(with: NSRange(location: NSMaxRange(block.last!.range), length: m.range.location - NSMaxRange(block.last!.range)))
            if gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { block.append(m) } else { break }
        }
        _ = last
        let items = block.map { ns.substring(with: $0.range(at: 2)).replacingOccurrences(of: "|", with: "/") }
        let done = block.enumerated().filter { ns.substring(with: $0.element.range(at: 1)) != " " }.map { "⟦done: \($0.offset + 1)⟧" }
        let tag = "⟦plan: " + items.joined(separator: " | ") + "⟧" + done.joined()
        var out = ns.replacingCharacters(in: NSRange(location: first.range.location, length: NSMaxRange(block.last!.range) - first.range.location), with: tag)
        out = header.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        return out
    }
    /// A turn that already has its to-do card never shows a to-do list written as text too: checkbox lines (and a
    /// "To-do list:" heading right above them) are taken out.
    static func withoutChecklist(_ text: String) -> String {
        guard text.contains("[ ]") || text.contains("[x]") || text.contains("[X]") else { return text }
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        for l in lines {
            if l.range(of: #"^[ \t]*(?:[-*•][ \t]*)?\[[ xX]\][ \t]+"#, options: .regularExpression) != nil {
                if let prev = out.last, prev.range(of: #"(?i)^[ \t]*(?:\*\*)?(?:to-?do(?: list)?|plan|steps|checklist)(?:\*\*)?[ \t]*:?(?:\*\*)?[ \t]*$"#, options: .regularExpression) != nil { out.removeLast() }
                continue
            }
            out.append(l)
        }
        return out.joined(separator: "\n")
    }
}

/// A permission request as a person would ask it (Mavis: ApprovalText). "cd ~; ls -A | head" becomes "Run ls and head?"
/// with the exact command kept for the card's quiet code line; a short command is the question itself ("Run “npm
/// test”?"); a file change names its file ("Edit refund.js?"). Links read as their site, never with "https://".
enum ApprovalWords {
    struct Parsed: Equatable { let title: String; let command: String? }
    static let risk = ["write": "Changes files on this Mac.", "delete": "Deletes things on this Mac.", "host": "Runs on this Mac.",
                       "send": "Sends something on your behalf.", "share": "Shares something outside this Mac."]
    static func parse(tool: String?, verb: String?, line: String?, command: String?, about: String? = nil) -> Parsed {
        // The agent said what the command is for: that's the question, and the command shows under it.
        if let command, !command.isEmpty, let about = about?.trimmingCharacters(in: .whitespacesAndNewlines), !about.isEmpty {
            var t = about; if t.hasSuffix(".") { t.removeLast() }
            return Parsed(title: t.prefix(1).uppercased() + t.dropFirst(), command: command)
        }
        if let command, !command.isEmpty { return run(command) }
        let what = tidy(line ?? "")
        // A web address says the site, not the link: "Open YouTube?", never "Open youtube.com/results?search_query=…".
        // Only a real address (a scheme or www., or a step that opens pages): "refund.js" is a file, not a site.
        let raw = (line ?? "").lowercased()
        let webby = raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("www.")
            || (tool ?? "").lowercased().contains("browser") || tool == "WebFetch"
        if webby, let name = site(what) { return Parsed(title: "\(verb ?? "Open") \(name)?", command: nil) }
        switch tool {
        case "Write": return Parsed(title: "Create \(what)?", command: nil)
        case "Edit", "MultiEdit", "NotebookEdit": return Parsed(title: "Edit \(what)?", command: nil)
        default: return Parsed(title: [verb ?? "Use", what].filter { !$0.isEmpty }.joined(separator: " ") + "?", command: nil)
        }
    }
    static func run(_ command: String) -> Parsed {
        let oneLine = !command.contains("\n"), shown = tidy(command)
        // "cd somewhere; …" only says where: the question is about what runs there.
        let body = shown.replacingOccurrences(of: #"^(\s*cd\s+("[^"]*"|'[^']*'|\S+)\s*(;|&&)\s*)+"#, with: "", options: .regularExpression)
        if oneLine, body.count <= 44 { return Parsed(title: "Run \u{201C}\(body)\u{201D}?", command: body == shown ? nil : command) }
        // Each statement's program: its first word after "do", "sudo", "VAR=x" and the like. Statements that only
        // move around, print or loop ("cd", "echo", "for d in …", "done") name nothing.
        let lead: Set<String> = ["do", "then", "else", "sudo", "env", "time", "{", "(", "!", "exec", "command", "nohup"]
        let quiet: Set<String> = ["cd", "echo", "printf", "for", "in", "done", "fi", "if", "while", "until", "true", "false", "}", ")", "esac", "case", "export", "set", "local", "read", "sleep"]
        var programs: [String] = []
        for part in body.components(separatedBy: CharacterSet(charactersIn: ";|&\n")) {
            var program: String?
            for w in part.split(whereSeparator: \.isWhitespace).map(String.init) {
                if lead.contains(w) || w.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil { continue }
                if !quiet.contains(w), !w.hasPrefix("$"), !w.hasPrefix("\""), !w.hasPrefix("'") { program = (w as NSString).lastPathComponent }
                break
            }
            if let p = program, !p.isEmpty, !programs.contains(p) { programs.append(p) }
        }
        let list = listed(Array(programs.prefix(3)))
        return Parsed(title: list.isEmpty ? "Run a command?" : "Run \(list)?", command: command)
    }
    /// The site's own name when `text` is a web address (youtube.com/…, www.github.com): its main label, written the
    /// way the site writes it when known.
    static func site(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let host = String(t.split(separator: "/", maxSplits: 1).first ?? "").lowercased()
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2, labels.last!.count >= 2, labels.last!.allSatisfy(\.isLetter) else { return nil }
        let main = labels[labels.count - 2]
        let known = ["youtube": "YouTube", "github": "GitHub", "linkedin": "LinkedIn", "tiktok": "TikTok", "chatgpt": "ChatGPT",
                     "x": "X", "google": "Google", "reddit": "Reddit", "figma": "Figma", "gmail": "Gmail", "instagram": "Instagram"]
        return known[main] ?? main.prefix(1).uppercased() + main.dropFirst()
    }
    static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
    static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://(www\.)?"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
}

enum Tags {
    private static let partial = try! NSRegularExpression(pattern: #"\s*⟦[^⟧]*$"#)
    private static let next = try! NSRegularExpression(pattern: #"\s*⟦\s*next\s*:\s*([^⟧]*)⟧\s*"#, options: [.caseInsensitive])
    /// The words as shown: no plan, done, report or half-written tag. A closed report leaves a paragraph break, never
    /// two sentences glued together ("build.Shall").
    static func strip(_ text: String) -> String {
        guard text.contains("⟦") else { return text }
        var out = ReportTag.closed.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n")
        for r in [ReportTag.open, PlanTag.any, next, partial] { out = r.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "") }
        return out == text ? text : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Words arriving (Mavis: AgentSteps.swift WordReveal)

/// Words come onto the screen a whole word at a time, 30 times a second, at an even speed that eases toward staying
/// about half a second behind what has arrived: never slower than 120 characters a second, never faster than 1,800
/// (about a line per step), so a reply that lands all at once still flows instead of dropping in as a block
/// (16 Nov: a 2,000-character backlog came out as several lines in one step, then a crawl).
/// A word with no space after it waits while the reply is still arriving, and a list or heading marker always comes
/// with its word.
enum WordReveal {
    static let tick = 1.0 / 30
    static let tickNanos = UInt64(tick * 1_000_000_000)
    static let behind = 0.5, floor = 120.0, ceiling = 1800.0
    /// One word longer than this still shows once this much has been saved up (a long link never waits forever).
    static let longWord = 48.0

    /// The speed for the next step: eases toward the speed that keeps it `behind` seconds behind. Speeds up gently,
    /// slows down faster, so a burst of new text never makes the words lurch.
    static func pace(_ rate: Double, backlog: Int) -> Double {
        let target = min(ceiling, max(floor, Double(backlog) / behind))
        return rate + (target - rate) * (target > rate ? 0.25 : 0.5)
    }
    /// How much a step may save up: a pause never turns into a burst.
    static func cap(_ rate: Double) -> Double { max(rate * tick * 2, longWord) }

    /// Shows as many whole words after `shown` as `budget` characters allow. Returns the new end and what's left.
    static func advance(_ text: String, after shown: Int, budget: Double, streaming: Bool) -> (end: Int, budget: Double) {
        let chars = Array(text)
        let total = chars.count
        guard shown < total else { return (total, budget) }
        var end = shown, i = shown
        while i < total {
            while i < total, chars[i].isWhitespace { i += 1 }        // the space before the next word
            guard i < total else { end = total; break }               // only spaces left: show them
            while i < total, !chars[i].isWhitespace { i += 1 }       // the word
            if i == total, streaming { break }                        // the last word may still be growing
            // A list or heading marker on its own ("- ", "## ", "2. ") never shows without its word.
            let lineStart = (chars[..<i].lastIndex(of: "\n").map { $0 + 1 }) ?? 0
            if String(chars[lineStart..<i]).range(of: #"^\s*(#{1,6}|[-*+•]|\d+[.)]|>)$"#, options: .regularExpression) != nil { continue }
            let cost = Double(i - shown)
            if cost <= budget || (end == shown && budget >= longWord) { end = i } else { break }
        }
        return (end, max(0, budget - Double(end - shown)))
    }
}

/// Inline markdown cut off mid-span shows its marks as plain text, then flips style and re-wraps when the closing
/// mark arrives (`**Notes: Mavis` → bold). Closing every open `code` and **bold** span keeps the style from the first
/// word.
enum InlineMarks {
    static func closed(_ s: String) -> String {
        var code = false, bold = false
        let c = Array(s); var i = 0
        while i < c.count {
            if c[i] == "`" { code.toggle(); i += 1; continue }
            if !code, c[i] == "*", i + 1 < c.count, c[i + 1] == "*" { bold.toggle(); i += 2; continue }
            i += 1
        }
        guard code || bold else { return s }
        var out = s.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        if code { out += "`" }
        if bold { out += "**" }
        return out
    }
}

// MARK: A turn's shape

/// One tool call in a turn.
struct Step: Equatable, Identifiable {
    let id: String; var verb: String; var line: String; var round: Int; var done: Bool; var failed: Bool
    /// How much of the turn's raw text had been written when it started (characters).
    var offset: Int
    /// The whole of it (a full command or path), what came back, and what it changed: shown when you open it.
    var detail: String? = nil
    var output: String? = nil
    var diff: [FileChange]? = nil
    var opens: Bool { !(detail ?? "").isEmpty || !(output ?? "").isEmpty || !(diff ?? []).isEmpty }
}

/// A turn as pieces: words, then work, then words, in the order they happened (Mavis: TurnFlow).
enum Piece: Identifiable, Equatable {
    case steps(id: String, steps: [Step])
    case words(id: String, text: String)
    var id: String { switch self { case .steps(let id, _), .words(let id, _): id } }
    var isSteps: Bool { if case .steps = self { true } else { false } }
}

enum TurnFlow {
    /// The words on screen so far (`shown` characters of the stripped text), cut wherever work happened. Work waits
    /// for the words before it to be written.
    static func pieces(steps: [Step], raw: String, shown: Int) -> [Piece] {
        let text = Tags.strip(raw)
        let chars = Array(text)
        let written = min(shown, chars.count)
        var out: [Piece] = []
        var cursor = 0
        func addWords(upTo end: Int) {
            let e = min(end, written)
            if e > cursor {
                let chunk = String(chars[cursor..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty { out.append(.words(id: "w\(cursor)", text: chunk)) }
            }
            cursor = max(cursor, e)
        }
        for step in steps {
            let place = position(of: step.offset, raw: raw)
            if place > written { break }
            if place > cursor { addWords(upTo: place) }
            if case .steps(let id, let group)? = out.last { out[out.count - 1] = .steps(id: id, steps: group + [step]) }
            else { out.append(.steps(id: step.id, steps: [step])) }
        }
        addWords(upTo: written)
        return out
    }
    /// Where a raw offset falls in the words you see.
    static func position(of offset: Int, raw: String) -> Int {
        guard offset > 0 else { return 0 }
        let chars = Array(raw)
        guard offset <= chars.count else { return Int.max }
        return Tags.strip(String(chars[..<offset])).count
    }
    /// (opening, work, tail): words before the first step, the first step to the last with the words between, the
    /// words after the last step (the final message).
    static func split(_ all: [Piece]) -> (opening: [Piece], work: [Piece], tail: [Piece]) {
        let first = all.firstIndex(where: \.isSteps), last = all.lastIndex(where: \.isSteps)
        let opening = first.map { Array(all[..<$0]) } ?? all
        let work = first.flatMap { f in last.map { Array(all[f...$0]) } } ?? []
        let tail = last.map { Array(all[($0 + 1)...]) } ?? []
        return (opening, work, tail)
    }
}

// MARK: Words for work (Mavis: StepWords, TurnStatus)

enum StepWords {
    /// A run of work in one line, in everyday words. Counts and names are one click away.
    static func summary(_ steps: [Step]) -> String {
        var n: [String: Int] = [:]
        for s in steps { n[kind(s.verb), default: 0] += 1 }
        let changes = (n["edit"] ?? 0), looked = (n["read"] ?? 0) + (n["search"] ?? 0)
        var parts: [String] = []
        if changes > 0 { parts.append(changes == 1 ? "Made a change" : "Made some changes") }
        if looked > 0 { parts.append(looked == 1 && n["read"] == 1 ? "Looked at a file" : "Looked through your files") }
        if (n["web"] ?? 0) > 0 { parts.append("Looked on the web") }
        if let c = n["command"] { parts.append(c == 1 ? "Ran a quick check" : "Ran a few checks") }
        if (n["app"] ?? 0) > 0 { parts.append("Worked in your apps") }
        if (n["helper"] ?? 0) > 0 { parts.append("Asked a helper") }
        if parts.isEmpty { parts.append("Worked on it") }
        return parts.prefix(2).enumerated().map { i, t in i == 0 ? t : t.prefix(1).lowercased() + t.dropFirst() }.joined(separator: " and ")
    }
    static func kind(_ verb: String) -> String {
        switch verb {
        case "Edit", "Write": return "edit"
        case "Read": return "read"
        case "Search": return "search"
        case "Run": return "command"
        case "Open", "Search the web for": return "web"
        case "Start a helper for": return "helper"
        case "Use", "Prepare": return "app"
        default: return "other"
        }
    }
    /// The step under way, as the live line says it ("Running npm test", "Reading app.js").
    static func live(_ s: Step) -> String {
        return "\(ing(s.verb)) \(s.line)"
    }
    /// A step's verb done ("Ran", "Read") and under way ("Running"), as Mavis's step lines say it.
    static func past(_ verb: String) -> String {
        ["Run": "Ran", "Edit": "Edited", "Write": "Created", "Read": "Read", "Search": "Searched for", "Open": "Opened",
         "Search the web for": "Searched the web for", "Start a helper for": "Asked a helper to", "Update": "Updated", "Use": "Used", "Prepare": "Prepared", "Look up": "Looked up",
         "Look at": "Looked at", "Click": "Clicked", "Type": "Typed", "Choose": "Chose", "Press": "Pressed", "Scroll": "Scrolled",
         "Point at": "Pointed at", "Wait for": "Waited for", "Close": "Closed", "Show": "Showed", "Go": "Went", "Reload": "Reloaded",
         "Find": "Found", "Ask you": "Asked you", "Thought": "Thought", "Check": "Checked"][verb] ?? verb
    }
    static func ing(_ verb: String) -> String {
        ["Run": "Running", "Edit": "Editing", "Write": "Writing", "Read": "Reading", "Search": "Searching for", "Open": "Opening",
         "Search the web for": "Searching the web for", "Start a helper for": "Asking a helper to", "Update": "Updating", "Use": "Using", "Prepare": "Preparing", "Look up": "Looking up",
         "Look at": "Looking at", "Click": "Clicking", "Type": "Typing", "Choose": "Choosing", "Press": "Pressing", "Scroll": "Scrolling",
         "Point at": "Pointing at", "Wait for": "Waiting for", "Close": "Closing", "Show": "Showing", "Go": "Going", "Reload": "Reloading",
         "Find": "Finding", "Ask you": "Asking you", "Thought": "Thinking", "Check": "Checking"][verb] ?? verb
    }
    /// What a step acted on, as its line shows it: a page is its site and path (x.com/i/account_analytics), never the
    /// whole address with its scheme and query (as Mavis final launch names pages).
    static func object(_ verb: String, _ line: String) -> String {
        guard ["Open", "Opened"].contains(verb), let u = URL(string: line), let host = u.host(), u.scheme == "http" || u.scheme == "https" else { return line }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = u.path == "/" ? "" : u.path.hasSuffix("/") ? String(u.path.dropLast()) : u.path
        return site + path
    }
    static func clock(_ seconds: TimeInterval) -> String { let s = Int(seconds); return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s" }
}

// MARK: The follower's spring (Mavis: TranscriptMetrics.glide)

enum Glide {
    static let response: CGFloat = 0.3
    /// Your own send: one quick ease-out to the end, fast first and settling, about 0.3 s (OpenBot, 17 Nov). It starts
    /// at the speed that makes the spring a pure ease-out: 75% of the way after 0.1 s, all of it by about 0.3 s.
    static let sendResponse: CGFloat = 0.45
    static func launch(gap: CGFloat, response: CGFloat = sendResponse) -> CGFloat { 2 * .pi / response * gap }
    /// One step of a critically damped spring toward a gap: how far to move now, and the new speed. Never moves up,
    /// never past the gap.
    static func step(gap: CGFloat, velocity: CGFloat, dt: CGFloat, response: CGFloat = response) -> (move: CGFloat, velocity: CGFloat) {
        let w = 2 * .pi / response
        var v = max(0, velocity), moved: CGFloat = 0
        let steps = max(1, Int((dt / (1.0 / 240)).rounded(.up)))
        let h = dt / CGFloat(steps)
        for _ in 0..<steps {
            let left = gap - moved
            v += (w * w * left - 2 * w * v) * h
            v = max(0, v)
            moved += v * h
            if moved >= gap { return (gap, 0) }
        }
        return (moved, v)
    }
}

// MARK: Markdown blocks (what an answer is made of: OpenBot / ChatGPT-style structure)

/// One block of an answer. Inline marks (bold, code, links) stay in the text; the view styles them.
enum MDBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// A list item: its depth (0 = top), its number when the list is numbered.
    case item(depth: Int, number: Int?, text: String)
    case quote(String)
    case rule
    case code(String)
    case table(header: [String], rows: [[String]])
}

enum Markdown {
    /// Splits Markdown into blocks. Tolerates text still being written: an unclosed code fence is code so far, a half
    /// line is just a line.
    static func blocks(_ text: String) -> [MDBlock] {
        var out: [MDBlock] = []
        var para: [String] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        var i = 0
        while i < lines.count {
            let raw = lines[i], line = raw.trimmingCharacters(in: .whitespaces)
            // Code fence: everything up to the closing fence (or the end, while it's still arriving).
            if line.hasPrefix("```") {
                flush()
                var body: [String] = []; i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { body.append(lines[i]); i += 1 }
                out.append(.code(body.joined(separator: "\n"))); i += 1; continue
            }
            if line.isEmpty { flush(); i += 1; continue }
            // Table: a header row, a |---| row, then rows.
            if line.hasPrefix("|"), i + 1 < lines.count, isTableRule(lines[i + 1]) {
                flush()
                let header = cells(line); var rows: [[String]] = []; i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(cells(lines[i])); i += 1 }
                out.append(.table(header: header, rows: rows)); continue
            }
            if let h = heading(line) { flush(); out.append(.heading(level: h.0, text: h.1)); i += 1; continue }
            if line.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { flush(); out.append(.rule); i += 1; continue }
            if line.hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                out.append(.quote(q.joined(separator: "\n"))); continue
            }
            if let it = item(raw) { flush(); out.append(it); i += 1; continue }
            // A line under a list item, indented: it continues that item.
            if case .item(let d, let n, let t)? = out.last, para.isEmpty, raw.hasPrefix("  ") {
                out[out.count - 1] = .item(depth: d, number: n, text: t + "\n" + line); i += 1; continue
            }
            para.append(line); i += 1
        }
        flush()
        return out
    }
    static func heading(_ line: String) -> (Int, String)? {
        guard let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) else { return nil }
        let level = line[m].filter { $0 == "#" }.count
        return (level, String(line[m.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
    }
    static func item(_ raw: String) -> MDBlock? {
        let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let line = raw.trimmingCharacters(in: .whitespaces)
        let depth = min(indent / 2, 3)
        if let m = line.range(of: #"^[-*•+]\s+"#, options: .regularExpression) { return .item(depth: depth, number: nil, text: String(line[m.upperBound...])) }
        if let m = line.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
            let n = Int(line[m].filter(\.isNumber)) ?? 1
            return .item(depth: depth, number: n, text: String(line[m.upperBound...]))
        }
        return nil
    }
    static func isTableRule(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil }
    static func cells(_ s: String) -> [String] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

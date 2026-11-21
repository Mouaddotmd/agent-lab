// Words in the chat that are more than words. A file or folder a message names ("Composer.swift", "App/Sources/",
// "~/Desktop/notes.md") is a link when it's really on this Mac: blue, and it opens in the app (Files, or the Browser for
// a page). A command or skill ("/stageshow") is highlighted in the box as you write it and set as a chip once sent
// (Mavis final launch: SkillTokens, SkillChip).
import AppKit
import SwiftUI

// MARK: Files a message names

/// Every file and folder in your projects by name, so a bare "ShellChat.swift" finds its file. Built in the background
/// from each agent's folder and the project folders on your Desktop; read again every few minutes.
@MainActor final class FileNames: ObservableObject {
    static let shared = FileNames()
    /// Bumped when the index is (re)built: text drawn before it can link what it names now.
    @Published private(set) var version = 0
    /// Lowercased name → full paths (folders end in "/").
    private var byName: [String: [String]] = [:]
    /// Files the agents' own steps read, wrote, ran or opened, by name: what a reply means by "index.html" when it just
    /// worked on one. Checked before the index, as Claude Code links the files it touched.
    private var touchedByName: [String: Set<String>] = [:]
    nonisolated static let pathPattern = try! NSRegularExpression(pattern: #"(?:file://)?(?:~|/Users)/[^\s'"`;|&<>()]+\.[A-Za-z][A-Za-z0-9]{0,7}"#)
    func touched(_ messages: [Message]) {
        loadSaved()
        if note(messages) { RichText.clearCache(); TextEpoch.shared.bump() }
    }
    /// Steps already read for paths (a chat's messages arrive again with every saved block: only new ones are read).
    private var seen = Set<String>()
    @discardableResult private func note(_ messages: [Message]) -> Bool {
        let fm = FileManager.default
        var changed = false
        for m in messages where m.role == "tool" && seen.insert(m.id).inserted {
            let text = [m.detail, m.text].compactMap { $0 }.joined(separator: " ")
            guard text.contains("/") else { continue }
            for r in Self.pathPattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                var p = (text as NSString).substring(with: r.range)
                if p.hasPrefix("file://") { p = URL(string: p)?.path ?? String(p.dropFirst(7)) }
                p = (p as NSString).expandingTildeInPath.removingPercentEncoding ?? p
                var dir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &dir), !dir.boolValue else { continue }
                let name = (p as NSString).lastPathComponent.lowercased()
                if touchedByName[name, default: []].insert(p).inserted { changed = true }
            }
        }
        return changed
    }
    /// The project folders indexed.
    private var projects: [String] = []
    private var builtAt: Date?
    private var building = false

    /// The index as it was last built, kept on disk: a message drawn the moment the app opens links exactly what it
    /// linked before, instead of waiting for a new index (and looking different until then).
    private static let saved: URL = {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab/file-names.json")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        return u
    }()
    private struct Saved: Codable { var byName: [String: [String]]; var projects: [String] }
    private var loaded = false
    /// Read at launch (Store), before anything is drawn: never in the middle of drawing a chat.
    func prepare() { loadSaved() }
    /// Reads the saved index once, before the first word is resolved.
    private func loadSaved() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: Self.saved), let v = try? JSONDecoder().decode(Saved.self, from: d) { byName = v.byName; projects = v.projects }
        // Every chat's steps, read now (not chat by chat as they open), so which file a name means never depends on which
        // chat you opened first.
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Agent Lab/messages")
        for f in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let list = try? JSONDecoder().decode([Message].self, from: d) { note(list) }
        }
    }

    func refresh(roots: [String]) {
        loadSaved()
        guard !building, builtAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true else { return }
        building = true
        Task.detached(priority: .utility) {
            let (index, projects) = Self.build(roots)
            if let d = try? JSONEncoder().encode(Saved(byName: index, projects: projects)) { try? d.write(to: Self.saved, options: .atomic) }
            await MainActor.run {
                let s = FileNames.shared
                s.builtAt = Date(); s.building = false
                guard index != s.byName || projects != s.projects else { return }     // nothing new: nothing redrawn
                s.byName = index; s.projects = projects
                RichText.clearCache(); s.version += 1; TextEpoch.shared.bump()
            }
        }
    }

    /// The project folders worth indexing: each root, and the folders on the Desktop that hold code.
    nonisolated private static func build(_ roots: [String]) -> ([String: [String]], [String]) {
        let fm = FileManager.default
        var folders: [String] = []
        let desktop = NSHomeDirectory() + "/Desktop"
        let marks = [".git", "package.json", "Package.swift", "build.sh", "Cargo.toml", "pyproject.toml", "go.mod", "index.html", "App", "Sources", "src"]
        for name in (try? fm.contentsOfDirectory(atPath: desktop)) ?? [] where !name.hasPrefix(".") {
            let p = desktop + "/" + name
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &dir), dir.boolValue else { continue }
            if marks.contains(where: { fm.fileExists(atPath: p + "/" + $0) }) || (try? fm.contentsOfDirectory(atPath: p))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true { folders.append(p) }
        }
        for r in roots where r != NSHomeDirectory() && r != desktop && !folders.contains(r) { folders.append(r) }
        let skip: Set<String> = [".git", "node_modules", ".build", "build", "DerivedData", "dist", ".next", "Pods", ".venv", "venv", "__pycache__",
                                 "target", ".swiftpm", "Library", "Applications", "Pictures", "Music", "Movies", "worktrees"]
        var out: [String: [String]] = [:]
        for folder in folders {
            let root = URL(fileURLWithPath: folder)
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var n = 0
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if skip.contains(name) { walker.skipDescendants(); continue }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                out[name.lowercased(), default: []].append(url.path + (isDir ? "/" : ""))
                n += 1
                if n >= 25_000 { break }
            }
        }
        for k in out.keys { out[k]?.sort() }
        return (out, folders.sorted())
    }

    /// The file or folder `token` names, if there's exactly one sensible answer: a full path that exists, a path under
    /// one of `roots`, or a name (with the folders before it, if given) found in the index. `context` (the message)
    /// breaks ties: a file under a project the message names wins.
    func resolve(_ token: String, roots: [String], context: String) -> URL? {
        loadSaved()
        var t = token.trimmingCharacters(in: .whitespaces)
        while let last = t.last, ".,:;)".contains(last) { t.removeLast() }
        guard t.count >= 3, t.count <= 300, !t.contains("\n"), !t.contains("://"), !t.hasPrefix("-") else { return nil }
        // Only files: a folder isn't something you open here, so it stays a plain word (as in Claude Code).
        guard !t.hasSuffix("/") else { return nil }
        let fm = FileManager.default
        func file(_ p: String) -> Bool { var dir: ObjCBool = false; return fm.fileExists(atPath: p, isDirectory: &dir) && !dir.boolValue }
        if t.hasPrefix("/") || t.hasPrefix("~") {
            let p = (t as NSString).expandingTildeInPath
            return file(p) ? URL(fileURLWithPath: p) : nil
        }
        for root in roots {
            let p = (root as NSString).appendingPathComponent(t)
            if file(p) { return URL(fileURLWithPath: p) }
        }
        let folder = false
        let name = ((folder ? String(t.dropLast()) : t) as NSString).lastPathComponent.lowercased()
        // A file the agents' own steps touched: that one (if it's the only one by that name and path).
        if let touched = touchedByName[name] {
            let tail = "/" + t.lowercased()
            let fits = touched.filter { !t.contains("/") || $0.lowercased().hasSuffix(tail) }.sorted()
            if fits.count == 1 { return URL(fileURLWithPath: fits[0]) }
        }
        guard var found = byName[name], !found.isEmpty else { return nil }
        // "App/Sources/DockWidget.swift": the folders before the name must match too. A folder is written with its slash.
        if t.contains("/") { let tail = "/" + t.lowercased(); found = found.filter { $0.lowercased().hasSuffix(tail) || $0.lowercased().hasSuffix(tail + "/") } }
        if !folder { found = found.filter { !$0.hasSuffix("/") } }
        // The message is about a project ("Mavis final launch"): only that project's files count. A name it says is gone
        // from there never links to a copy in another project.
        let words = context.lowercased()
        let named = projects.filter { p in
            let n = NSRegularExpression.escapedPattern(for: (p as NSString).lastPathComponent.lowercased())
            return words.range(of: "(^|[^a-z0-9-])" + n + "($|[^a-z0-9-])", options: .regularExpression) != nil
        }
        if !named.isEmpty { found = found.filter { p in named.contains { p.hasPrefix($0 + "/") } } }
        guard !found.isEmpty else { return nil }
        let pick: String
        if found.count == 1 { pick = found[0] }
        else {
            let mentioned = found.filter { path in
                path.split(separator: "/").contains { part in part.count > 3 && words.contains(part.lowercased()) && !part.lowercased().hasPrefix(name) }
            }
            let inRoot = found.filter { p in roots.contains { r in p.hasPrefix(r + "/") } }
            let order: (String, String) -> Bool = { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }     // the same pick every time
            guard let best = (mentioned.isEmpty ? inRoot : mentioned).min(by: order) ?? found.min(by: order) else { return nil }
            pick = best
        }
        let path = pick.hasSuffix("/") ? String(pick.dropLast()) : pick
        return URL(fileURLWithPath: path)
    }

    /// File-like words in plain text: a name with an extension ("Composer.swift") or a path to one ("App/Sources/x.swift",
    /// "~/Desktop/notes.md"). Never a folder.
    nonisolated static let pattern = try! NSRegularExpression(pattern: #"(?<![\w/~.@-])(?:~|\.{1,2})?/?(?:[\w.\-]+/)*[\w\-]+(?:\.[\w\-]+)*\.[A-Za-z][A-Za-z0-9]{0,7}(?![\w/])"#)
}

/// Bumped when anything that decides how words are drawn changes (the commands known, the file index): text drawn
/// before is drawn again, so a message never looks different depending on when it was first shown.
@MainActor final class TextEpoch: ObservableObject {
    static let shared = TextEpoch()
    @Published private(set) var n = 0
    func bump() { n += 1 }
}

// MARK: Commands and skills

@MainActor enum CommandTokens {
    /// Every command and skill the agents offer, lowercased. Known from launch, before any agent has told us its list, so
    /// a sent "/stageshow" looks the same the moment the app opens as it did when you sent it: your installed skills,
    /// read from their folders at once, and every command an agent has listed before (kept on disk). An agent's list,
    /// when it arrives, only adds to it.
    static var names: Set<String> = initial() {
        didSet {
            guard names != oldValue else { return }
            UserDefaults.standard.set(Array(names.subtracting(own)).sorted(), forKey: "knownCommands")
            RichText.clearCache(); TextEpoch.shared.bump()
        }
    }
    /// Adds what an agent lists (never takes away: a name once known stays highlighted in what was sent with it).
    static func learn(_ more: Set<String>) { if !more.isSubset(of: names) { names.formUnion(more) } }
    private static func initial() -> Set<String> {
        var out = own
        out.formUnion(UserDefaults.standard.stringArray(forKey: "knownCommands") ?? [])
        out.formUnion(installedSkills(roots: RichText.roots))
        return out
    }
    /// Skills installed as folders with a SKILL.md, as Claude Code and Codex keep them: yours, and each agent folder's.
    static func installedSkills(roots: [String]) -> Set<String> {
        let home = NSHomeDirectory(), fm = FileManager.default
        var places = [home + "/.claude/skills", home + "/.agents/skills", home + "/.codex/skills"]
        for r in roots where r != home { places += [r + "/.claude/skills", r + "/.agents/skills"] }
        var out = Set<String>()
        for folder in places {
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where !name.hasPrefix(".") {
                if fm.fileExists(atPath: folder + "/" + name + "/SKILL.md") { out.insert(name.lowercased()) }
            }
        }
        return out
    }
    /// The agents' folders are known: their skills count too.
    static func rootsChanged(_ roots: [String]) { learn(installedSkills(roots: roots)) }
    /// Agent Lab's own commands.
    static let own: Set<String> = ["model", "btw", "handoff"]

    /// Where each known command or skill is in the text: "/name" (or Codex's "$name") on its own, at the start or after a space.
    static func ranges(in text: String) -> [NSRange] {
        guard text.contains("/") || text.contains("$") else { return [] }
        let ns = text as NSString
        var out: [NSRange] = []
        var index = 0
        while index < ns.length {
            let c = ns.character(at: index)
            guard c == 0x2F || c == 0x24 else { index += 1; continue }
            let boundary = index == 0 || CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: index - 1)) ?? " ")
            var end = index + 1
            while end < ns.length, let u = UnicodeScalar(ns.character(at: end)), !CharacterSet.whitespacesAndNewlines.contains(u) { end += 1 }
            let name = ns.substring(with: NSRange(location: index + 1, length: end - index - 1)).lowercased()
            if boundary, !name.isEmpty, names.contains(name) { out.append(NSRange(location: index, length: end - index)) }
            index = max(end, index + 1)
        }
        return out
    }

    /// Colours the tokens in the box (layout-only: the words, undo and spelling are untouched).
    /// The box as the sent message will look: a command or skill as its chip, a link blue on its soft underline
    /// (layout-only attributes: the words themselves, undo and spelling are untouched).
    static func paint(_ view: NSTextView) {
        guard let layout = view.layoutManager else { return }
        let text = view.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        for key: NSAttributedString.Key in [.foregroundColor, .backgroundColor, .underlineStyle, .underlineColor, .commandChip] {
            layout.removeTemporaryAttribute(key, forCharacterRange: all)
        }
        guard all.length > 0 else { return }
        for m in RichText.detector?.matches(in: text, range: all) ?? [] {
            guard let url = m.url, url.scheme == "http" || url.scheme == "https" else { continue }
            layout.addTemporaryAttributes([.foregroundColor: NSColor(MARK_BLUE), .underlineStyle: NSUnderlineStyle.thick.rawValue,
                                           .underlineColor: NSColor(MARK_BLUE.opacity(0.3))], forCharacterRange: m.range)
            layout.removeTemporaryAttribute(.spellingState, forCharacterRange: m.range)
        }
        for r in ranges(in: text) {
            layout.addTemporaryAttributes([.foregroundColor: NSColor(Chip.ink), .commandChip: true], forCharacterRange: r)
            layout.addTemporaryAttribute(.foregroundColor, value: NSColor(Chip.ink.opacity(0.6)), forCharacterRange: NSRange(location: r.location, length: 1))
            layout.removeTemporaryAttribute(.spellingState, forCharacterRange: r)
        }
    }
}

extension NSAttributedString.Key {
    /// A command or skill set as a chip in sent words (ChipLayoutManager draws its rounded fill).
    static let commandChip = NSAttributedString.Key("agentlab.commandChip")
}

enum Chip {
    /// The room a chip's fill takes on each side of its words.
    static let room: CGFloat = 5
    /// Between a chip's fill and the words beside it.
    static let gap: CGFloat = 3
    static let radius: CGFloat = 6
    /// Its words (MAVIS: the pale selection blue, which reads on the page and on your blue bubble) and its fill.
    static var ink: Color { MV.on ? MV.Accent.selectedText : MARK_BLUE }
    static var fill: Color { MV.on ? MV.Accent.blue.opacity(0.2) : MARK_BLUE.opacity(0.14) }
}

/// Draws a chip's fill with round corners and a little room around its words, instead of the plain rectangle text
/// backgrounds get.
final class ChipLayoutManager: NSLayoutManager {
    /// One rounded pill per chip (per line it spans), drawn under its words: whatever runs its colours split it into.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let ts = textStorage, let container = textContainers.first, ts.length > 0 else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var chips: [NSRange] = []
        ts.enumerateAttribute(.commandChip, in: chars) { v, r, _ in if v != nil { chips.append(r) } }
        var i = chars.location
        while i < NSMaxRange(chars) {
            var r = NSRange()
            let v = temporaryAttribute(.commandChip, atCharacterIndex: i, longestEffectiveRange: &r, in: chars)
            if v != nil { chips.append(r) }
            i = max(NSMaxRange(r), i + 1)
        }
        guard !chips.isEmpty else { return }
        NSColor(Chip.fill).setFill()
        for c in chips {
            let g = glyphRange(forCharacterRange: c, actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                let font = (ts.attribute(.font, at: c.location, effectiveRange: nil) as? NSFont) ?? RichText.font(RichText.size, .regular)
                let h = min(rect.height, ceil(font.ascender - font.descender) + Chip.gap * 2)
                // Centred on the words, not the line: a fixed line height sets the words low in it.
                let gi = self.glyphIndex(for: NSPoint(x: rect.midX, y: rect.midY), in: container)
                let line = self.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
                let baseline = line.minY + self.location(forGlyphAt: gi).y
                let mid = baseline - (font.ascender + font.descender) / 2
                // The kern after the last letter (sent words) sits inside the line's rect: leave it out of the pill.
                let kern = (ts.attribute(.kern, at: NSMaxRange(c) - 1, effectiveRange: nil) as? CGFloat) ?? 0
                let w = rect.width - kern
                let box = NSRect(x: rect.minX + origin.x - Chip.room, y: mid + origin.y - h / 2, width: w + Chip.room * 2, height: h)
                NSBezierPath(roundedRect: box, xRadius: Chip.radius, yRadius: Chip.radius).fill()
            }
        }
    }
    override func fillBackgroundRectArray(_ rects: UnsafePointer<NSRect>, count: Int, forCharacterRange range: NSRange, color: NSColor) {
        // Chips draw their pill in drawBackground; any other fill (a selection) is drawn as it is.
        if MV.on { super.fillBackgroundRectArray(rects, count: count, forCharacterRange: range, color: color); return }
        guard let ts = textStorage, range.location < ts.length,
              ts.attribute(.commandChip, at: range.location, effectiveRange: nil) != nil
                || temporaryAttribute(.commandChip, atCharacterIndex: range.location, effectiveRange: nil) != nil else {
            super.fillBackgroundRectArray(rects, count: count, forCharacterRange: range, color: color); return
        }
        color.setFill()
        for i in 0..<count {
            // A little room around the words (the text views leave Chip.room at their sides for it).
            let r = rects[i]
            let h = min(r.height, 24)
            let box = NSRect(x: r.minX - Chip.room, y: r.minY + (r.height - h) / 2, width: r.width + Chip.room * 2, height: h)
            NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        }
    }
}

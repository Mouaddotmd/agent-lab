// An open file in the side panel: read and coloured off the main thread, edited in place, saved with ⌘S. The editor is
// a text view with a line-number gutter beside it (the numbers aren't part of the text, so editing and selecting lines
// work as in any editor). Colours stay while you type: the paragraph you change is coloured again at once, the whole
// file a moment after you stop. If the file changes on disk (the agent edited it), a clean tab reloads by itself and
// one with your edits asks: Reload, Keep mine or Overwrite.
import SwiftUI
import AppKit

// MARK: The document

@MainActor final class FileDoc: ObservableObject {
    let path: String
    /// The file as read (or last saved): what the editor starts from. A new value means "show this", so it changes only
    /// on load and reload, never while you type.
    @Published private(set) var styled: NSAttributedString?
    /// The words as last read, saved, or handed to the Markdown preview.
    @Published private(set) var text: String?
    @Published private(set) var problem: String?
    @Published private(set) var image: NSImage?
    /// Shown but not editable (not UTF-8, or too big to edit smoothly).
    @Published private(set) var readOnly: String?
    /// Edited since it was read or saved.
    @Published var dirty = false
    /// The file changed on disk while you have edits.
    @Published var conflict = false
    @Published var notice: String?
    @Published var saveError: String?
    /// The lines you have selected (1-based, first...last), for Add to message.
    @Published var selection: ClosedRange<Int>?
    /// How many times what you're finding appears.
    @Published var matches = 0
    /// The editor showing it, for its current words.
    weak var editor: NSTextView?
    /// When and how big the file was when read or saved, to notice changes made elsewhere.
    private var stamp: Stamp?
    private var noticeTask: Task<Void, Never>?
    struct Stamp: Equatable { let date: Date?; let size: Int }
    /// What a read found, handed to the main thread in one piece.
    private struct Loaded: @unchecked Sendable { let text: String?; let styled: NSAttributedString?; let problem: String?; let readOnly: String? }

    var ext: String { (path as NSString).pathExtension.lowercased() }
    var isImage: Bool { ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff", "bmp", "ico", "icns"].contains(ext) }
    var isMarkdown: Bool { ["md", "markdown", "mdx"].contains(ext) }
    var editable: Bool { styled != nil && problem == nil && image == nil && readOnly == nil }
    /// The words as they are now (with your edits).
    var current: String? { editor?.string ?? text }

    init(path: String) { self.path = path; load() }

    nonisolated static func stampOf(_ path: String) -> Stamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return Stamp(date: a[.modificationDate] as? Date, size: (a[.size] as? NSNumber)?.intValue ?? 0)
    }

    func load() {
        let p = path, ext = ext, image = isImage
        Task.detached(priority: .userInitiated) {
            let stamp = FileDoc.stampOf(p)
            if image {
                let i = NSImage(contentsOfFile: p)
                await MainActor.run { self.stamp = stamp; self.image = i; self.problem = i == nil ? "Couldn't open this picture." : nil }
                return
            }
            let size = stamp?.size ?? 0
            var text: String?, problem: String?, styled: NSAttributedString?, readOnly: String?
            if size > 4_000_000 { problem = "This file is too big to show here (\(size / 1_000_000) MB). Open it in its own app." }
            else if let data = FileManager.default.contents(atPath: p) {
                if data.prefix(8000).contains(0) { problem = "This file isn't text. Open it in its own app." }
                else {
                    if let t = String(data: data, encoding: .utf8) { text = t } else { text = String(decoding: data, as: UTF8.self); readOnly = "Read only: this file isn't UTF-8 text." }
                    styled = Highlight.colour(text!, language: ext)
                }
            } else { problem = FileManager.default.fileExists(atPath: p) ? "Couldn't read this file." : "This file isn't there any more." }
            let done = Loaded(text: text, styled: styled, problem: problem, readOnly: readOnly)
            await MainActor.run {
                self.stamp = stamp; self.text = done.text; self.styled = done.styled; self.problem = done.problem; self.readOnly = done.readOnly
                self.dirty = false; self.conflict = false; self.saveError = nil
            }
        }
    }

    /// Called when the agent may have changed files (a turn ended, git changed) and when the tab comes to the front.
    func checkDisk() {
        let p = path
        Task.detached(priority: .utility) {
            let now = FileDoc.stampOf(p)
            await MainActor.run {
                guard now != self.stamp else { return }
                if self.dirty { self.conflict = true }
                else { self.load(); self.say("Updated: it changed on disk") }
            }
        }
    }

    func say(_ words: String) {
        notice = words
        noticeTask?.cancel()
        noticeTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { notice = nil } }
    }

    /// Writes your words to the file. Unless `force`, first checks it hasn't changed on disk (then asks instead).
    @discardableResult func save(force: Bool = false) -> Bool {
        guard editable, let words = editor?.string else { return false }
        if !force, FileDoc.stampOf(path) != stamp, stamp != nil { conflict = true; return false }
        let url = URL(fileURLWithPath: path)
        let perms = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions]
        do {
            try Data(words.utf8).write(to: url, options: .atomic)
            // An atomic write is a new file: keep the old one's permissions (a script stays runnable).
            if let perms { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path) }
            stamp = FileDoc.stampOf(path); text = words; dirty = false; conflict = false; saveError = nil
            say("Saved")
            return true
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }
    /// Keep mine: stay with your edits; the next save writes them over what's on disk now.
    func keepMine() { stamp = FileDoc.stampOf(path); conflict = false }
    /// For the Markdown preview: what you've written so far.
    func syncText() { if let e = editor { text = e.string } }
}

// MARK: Line starts

/// Where each line starts (UTF-16 offsets), kept up to date edit by edit, so the gutter and "which lines are selected"
/// never scan the whole file.
final class LineIndex {
    private(set) var starts: [Int] = [0]
    var count: Int { starts.count }
    func rebuild(_ s: NSString) {
        var out = [0]
        out.reserveCapacity(s.length / 30 + 1)
        scan(s, NSRange(location: 0, length: s.length)) { out.append($0) }
        starts = out
    }
    /// After the characters in `edited` (new range) replaced `edited.length - delta` old ones.
    func update(_ s: NSString, edited: NSRange, delta: Int) {
        let oldEnd = edited.location + edited.length - delta
        let first = upper(edited.location)                          // starts <= location stay
        var added: [Int] = []
        scan(s, edited) { added.append($0) }
        var last = first
        while last < starts.count, starts[last] <= oldEnd { last += 1 }   // starts made by newlines that were replaced
        var tail = Array(starts[last...])
        for i in tail.indices { tail[i] += delta }
        starts.replaceSubrange(first..., with: added + tail)
    }
    /// The 0-based line holding `offset`.
    func line(at offset: Int) -> Int { max(0, upper(offset) - 1) }
    /// The first index whose start is past `offset`.
    private func upper(_ offset: Int) -> Int {
        var lo = 0, hi = starts.count
        while lo < hi { let mid = (lo + hi) / 2; if starts[mid] <= offset { lo = mid + 1 } else { hi = mid } }
        return lo
    }
    private func scan(_ s: NSString, _ r: NSRange, _ found: (Int) -> Void) {
        guard r.length > 0 else { return }
        let chunk = 8192
        var buf = [unichar](repeating: 0, count: chunk)
        var at = r.location
        let end = r.location + r.length
        while at < end {
            let n = min(chunk, end - at)
            s.getCharacters(&buf, range: NSRange(location: at, length: n))
            for i in 0..<n where buf[i] == 10 { found(at + i + 1) }
            at += n
        }
    }
}

// MARK: The editor

/// The file's words in a text view: editable (unless the file can't be), coloured, with line numbers in a gutter;
/// matches of `find` marked without touching the text.
struct CodeEditor: NSViewRepresentable {
    @ObservedObject var doc: FileDoc
    @Environment(\.paneTabOn) private var tabOn
    var find = ""
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = false
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.font = Highlight.font
        view.textColor = Highlight.ink
        view.insertionPointColor = Highlight.ink
        view.selectedTextAttributes = [.backgroundColor: NSColor(C.sel)]
        view.typingAttributes = Highlight.base
        view.defaultParagraphStyle = Highlight.paragraph
        view.textContainerInset = NSSize(width: 4, height: 10)
        view.isHorizontallyResizable = true
        view.autoresizingMask = [.width, .height]
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.layoutManager?.allowsNonContiguousLayout = true
        let c = context.coordinator
        view.delegate = c
        view.textStorage?.delegate = c
        c.view = view
        let gutter = LineGutter(scrollView: scroll, index: c.lines)
        gutter.clientView = view
        gutter.textView = view
        c.gutter = gutter
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if scroll.isHidden == tabOn { scroll.isHidden = !tabOn }        // behind another tab: no I-beam over it
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        let c = context.coordinator
        c.doc = doc
        doc.editor = view
        view.isEditable = doc.editable
        if let styled = doc.styled, c.styled !== styled {
            // A load or a reload: the file's words replace what's shown (keeping where you were, roughly).
            let keep = view.selectedRange()
            c.styled = styled; c.find = ""
            c.loading = true
            storage.setAttributedString(styled)
            c.loading = false
            c.lines.rebuild(storage.string as NSString)
            c.gutter?.fit()
            view.undoManager?.removeAllActions()
            if NSMaxRange(keep) <= storage.length { view.setSelectedRange(keep) }
            c.language = doc.ext
        }
        if c.find != find { c.find = find; c.paintFind(scrollTo: true) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        weak var view: NSTextView?
        weak var doc: FileDoc?
        weak var gutter: LineGutter?
        var styled: NSAttributedString?
        var find = ""
        var language = ""
        var loading = false
        let lines = LineIndex()
        private var version = 0
        private var recolour: Task<Void, Never>?

        @objc func scrolled() { gutter?.needsDisplay = true }

        nonisolated func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
            guard mask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { edited(storage, range, delta) }
        }
        private func edited(_ storage: NSTextStorage, _ range: NSRange, _ delta: Int) {
            guard !loading else { return }
            let s = storage.string as NSString
            lines.update(s, edited: range, delta: delta)
            // The changed lines get their colours back at once (attributes may change here; characters may not).
            let para = s.paragraphRange(for: range)
            Highlight.paint(storage, para, language: language)
            version += 1
            doc?.dirty = true
            gutter?.fit()
            gutter?.needsDisplay = true
            scheduleRecolour()
        }
        /// A moment after typing stops, the whole file is coloured again (for what spans lines: block comments,
        /// long strings), off the main thread; applied only if nothing was typed meanwhile.
        private func scheduleRecolour() {
            recolour?.cancel()
            guard let storage = view?.textStorage, storage.length <= 400_000 else { return }
            let text = storage.string, lang = language, at = version
            recolour = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                let colours = await Task.detached(priority: .utility) { Highlight.runs(text, language: lang) }.value
                guard let self, !Task.isCancelled, self.version == at, let storage = self.view?.textStorage, storage.length == (text as NSString).length else { return }
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: Highlight.ink, range: NSRange(location: 0, length: storage.length))
                for (r, colour) in colours { storage.addAttribute(.foregroundColor, value: colour, range: r) }
                storage.endEditing()
                if !self.find.isEmpty { self.paintFind(scrollTo: false) }
            }
        }

        func paintFind(scrollTo: Bool) {
            guard let view, let lm = view.layoutManager, let storage = view.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            var first: NSRange?, n = 0
            if !find.isEmpty, let re = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: find), options: .caseInsensitive) {
                for m in re.matches(in: storage.string, range: all) {
                    lm.addTemporaryAttribute(.backgroundColor, value: Highlight.found, forCharacterRange: m.range)
                    if first == nil { first = m.range }
                    n += 1
                }
            }
            if doc?.matches != n { DispatchQueue.main.async { [weak doc] in doc?.matches = n } }
            if scrollTo, let first { view.scrollRangeToVisible(first) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view, let doc else { return }
            let r = view.selectedRange()
            var lines: ClosedRange<Int>?
            if r.length > 0 {
                let a = self.lines.line(at: r.location), b = self.lines.line(at: r.location + r.length - 1)
                lines = (a + 1)...(b + 1)
            }
            if doc.selection != lines { doc.selection = lines }
        }
    }
}

/// Line numbers beside the editor, drawn only for the lines on screen.
final class LineGutter: NSRulerView {
    weak var textView: NSTextView?
    let index: LineIndex
    private var digits = 0
    init(scrollView: NSScrollView, index: LineIndex) {
        self.index = index
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 36
    }
    required init(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    /// As wide as the biggest line number needs.
    func fit() {
        let d = max(2, String(index.count).count)
        guard d != digits else { return }
        digits = d
        ruleThickness = CGFloat(d) * 7.3 + 18
    }
    override func draw(_ dirtyRect: NSRect) { drawHashMarksAndLabels(in: dirtyRect) }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, let storage = tv.textStorage else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: Highlight.font, .foregroundColor: Highlight.quiet]
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let starts = index.starts
        var line = index.line(at: chars.location)
        let end = NSMaxRange(chars)
        let origin = tv.textContainerOrigin
        while line < starts.count, starts[line] <= end {
            let start = starts[line]
            let frag: NSRect
            if start < storage.length {
                frag = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: start), effectiveRange: nil)
            } else {
                frag = lm.extraLineFragmentRect                            // the empty last line after a final newline
                if frag == .zero { break }
            }
            let y = convert(NSPoint(x: 0, y: frag.minY + origin.y), from: tv).y
            let label = String(line + 1) as NSString
            let w = label.size(withAttributes: attrs).width
            label.draw(at: NSPoint(x: ruleThickness - w - 10, y: y), withAttributes: attrs)
            line += 1
        }
    }
}

// MARK: Colours

/// Colours for source, by simple rules every language shares (and per-language keywords). Quiet: the app's greys, with
/// strings and numbers a step warmer, so code reads without a rainbow.
enum Highlight {
    static let keywords: [String: Set<String>] = {
        let c = ["if", "else", "for", "while", "return", "break", "continue", "switch", "case", "default", "do", "try", "catch", "throw", "new", "true", "false", "null", "nil", "in", "of"]
        return [
            "swift": Set(c + ["func", "let", "var", "struct", "class", "enum", "protocol", "extension", "import", "guard", "self", "Self", "static", "private", "public", "internal", "fileprivate", "init", "deinit", "where", "async", "await", "throws", "some", "any", "inout", "defer", "repeat", "final", "override", "mutating", "lazy", "weak", "@MainActor", "typealias", "associatedtype"]),
            "js": Set(c + ["function", "const", "let", "var", "class", "import", "export", "from", "async", "await", "this", "typeof", "instanceof", "undefined", "yield", "extends", "static", "get", "set"]),
            "py": Set(c + ["def", "class", "import", "from", "as", "with", "lambda", "pass", "None", "True", "False", "self", "elif", "except", "finally", "yield", "async", "await", "and", "or", "not", "is", "global"]),
            "go": Set(c + ["func", "package", "import", "type", "struct", "interface", "map", "chan", "go", "defer", "range", "var", "const", "select"]),
            "rs": Set(c + ["fn", "let", "mut", "struct", "enum", "impl", "trait", "use", "mod", "pub", "match", "loop", "self", "Self", "async", "await", "move", "ref", "where", "crate"]),
            "sh": Set(c + ["fi", "then", "elif", "esac", "done", "function", "export", "local", "echo", "set"]),
        ]
    }()
    static func family(_ ext: String) -> String {
        switch ext {
        case "swift": "swift"
        case "js", "mjs", "cjs", "ts", "tsx", "jsx": "js"
        case "py": "py"
        case "go": "go"
        case "rs": "rs"
        case "sh", "zsh", "bash": "sh"
        default: ext
        }
    }
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let ink = NSColor(white: 0.93, alpha: 1)
    static let quiet = NSColor(white: 0.63, alpha: 0.6)
    static let comment = NSColor(white: 0.63, alpha: 1)
    static let keyword = NSColor(srgbRed: 0xc7 / 255.0, green: 0xa6 / 255.0, blue: 1, alpha: 1)
    static let number = NSColor(srgbRed: 0xe0 / 255.0, green: 0xb0 / 255.0, blue: 0x80 / 255.0, alpha: 1)
    static let string = NSColor(srgbRed: 0x9f / 255.0, green: 0xd3 / 255.0, blue: 0xa5 / 255.0, alpha: 1)
    static let found = NSColor(white: 0.93, alpha: 0.25)
    static let paragraph: NSParagraphStyle = { let p = NSMutableParagraphStyle(); p.lineSpacing = 3; return p }()
    static let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]

    /// The rules, compiled once per language: (pattern, colour), later ones winning. Used from any thread.
    private nonisolated(unsafe) static var compiled: [String: [(NSRegularExpression, NSColor)]] = [:]
    private static let lock = NSLock()
    nonisolated private static func rules(_ language: String) -> [(NSRegularExpression, NSColor)] {
        lock.lock(); defer { lock.unlock() }
        if let r = compiled[language] { return r }
        let r = make(language)
        compiled[language] = r
        return r
    }
    nonisolated private static func make(_ language: String) -> [(NSRegularExpression, NSColor)] {
        let keywords = Self.keywords[family(language)] ?? Self.keywords["js"]!
        let hash = ["py", "sh", "rb", "yml", "yaml", "toml", "zsh", "bash"].contains(language)
        let list: [(String, NSColor)] = [
            ("\\b(" + keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b", keyword),
            ("\\b\\d+(\\.\\d+)?\\b", number),
            (#""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`"#, string),
            (hash ? "#[^\\n]*" : "//[^\\n]*|/\\*[\\s\\S]*?\\*/", comment),
        ]
        return list.compactMap { p, c in (try? NSRegularExpression(pattern: p)).map { ($0, c) } }
    }

    /// Where each colour goes in `text`. Safe off the main thread.
    nonisolated static func runs(_ text: String, language: String) -> [(NSRange, NSColor)] {
        guard text.utf16.count <= 400_000 else { return [] }
        let all = NSRange(location: 0, length: (text as NSString).length)
        var out: [(NSRange, NSColor)] = []
        for (re, colour) in rules(language) { for m in re.matches(in: text, range: all) { out.append((m.range, colour)) } }
        return out
    }
    /// The whole file, coloured (FileDoc does this before its tab shows it). Safe off the main thread.
    nonisolated static func colour(_ text: String, language: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: base)
        out.beginEditing()
        for (r, colour) in runs(text, language: language) { out.addAttribute(.foregroundColor, value: colour, range: r) }
        out.endEditing()
        return out
    }
    /// Colours one stretch again (the lines you just changed).
    static func paint(_ storage: NSTextStorage, _ range: NSRange, language: String) {
        guard range.length > 0, range.length <= 200_000 else { return }
        storage.addAttributes(base, range: range)
        let text = storage.string
        for (re, colour) in rules(language) { for m in re.matches(in: text, range: range) { storage.addAttribute(.foregroundColor, value: colour, range: m.range) } }
    }
}

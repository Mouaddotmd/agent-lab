// A message's words, drawn the fast way. Every run of prose (paragraphs, headings, list items) is ONE AppKit text view
// over one attributed string, instead of a SwiftUI view per paragraph, per bullet and per selectable line. The string
// is built once per text and kept (RichText.cache), so opening a chat, switching back to it and resizing the window
// only lay out text; nothing is parsed again.
//
// Measured with tools/chatperf.swift on a real 28-row chat (17 Nov): opening went from ~120 ms to ~20 ms with the lazy
// transcript, and resizing from 15-25 ms a frame to under 10. Debug: `build/chatperf <messages.json> <copies>`.
import SwiftUI
import AppKit

/// What a message is drawn from: prose runs as attributed strings, and the few blocks that need their own view.
enum RichSegment {
    case prose(NSAttributedString)
    case quote(NSAttributedString)
    case rule
    case code(String)
    case table(header: [String], rows: [[String]])
}

enum RichText {
    /// Where a name in the chat's words is looked for: the agents' folders, then home and the Desktop. Set by the Store.
    static var roots: [String] = [] { didSet { if roots != oldValue { cache.removeAllObjects() } } }
    /// A name that's a real file or folder (`index.html`, `Composer.swift`, `~/Desktop/notes.md`): its file link, so
    /// it reads blue and opens in the app. Anything else stays a plain word (FileNames).
    static func fileLink(_ name: String, context: String = "") -> URL? {
        MainActor.assumeIsolated { FileNames.shared.resolve(name, roots: roots, context: context) }
    }
    static func clearCache() { cache.removeAllObjects() }
    /// Built segments by colour and text. Streaming text makes a new entry per update; the cache drops old ones itself.
    private static let cache: NSCache<NSString, Box> = { let c = NSCache<NSString, Box>(); c.countLimit = 600; return c }()
    final class Box { let segments: [RichSegment]; init(_ s: [RichSegment]) { segments = s } }

    static func segments(_ text: String, color: Color, lit: String = "") -> [RichSegment] {
        // Words being found: the same segments with every match lit (cached apart, so the plain ones stay as they are).
        let lit = text.range(of: lit, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? "" : lit
        let key = "\(color.description)\u{1}\(lit)\u{1}\(text)" as NSString
        if let hit = cache.object(forKey: key) { return hit.segments }
        var built = lit.isEmpty ? build(text, color: NSColor(color)) : segments(text, color: color)
        if !lit.isEmpty { built = built.map { light($0, lit) } }
        cache.setObject(Box(built), forKey: key)
        return built
    }
    /// A prose run with every match of `q` on the selection fill, in the strong ink.
    private static func light(_ seg: RichSegment, _ q: String) -> RichSegment {
        func lit(_ a: NSAttributedString) -> NSAttributedString {
            let ranges = ChatSearch.ranges(q, in: a.string as NSString)
            guard !ranges.isEmpty else { return a }
            let m = NSMutableAttributedString(attributedString: a)
            for r in ranges { m.addAttributes([.backgroundColor: NSColor(C.sel), .foregroundColor: NSColor(C.i12)], range: r) }
            return m
        }
        switch seg {
        case .prose(let a): return .prose(lit(a))
        case .quote(let a): return .quote(lit(a))
        default: return seg
        }
    }

    // MARK: Building

    /// Chat words: 16 classic; MAVIS 14.5 on a 23 line (spec 3).
    static var size: CGFloat { MV.on ? MV.Text.message : 16 }
    static func font(_ size: CGFloat, _ w: F.W) -> NSFont {
        let name = switch w { case .regular: "AnthropicSansText-Regular"; case .medium: "AnthropicSansText-Medium"; case .semibold: "AnthropicSansText-Semibold" }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: w == .semibold ? .semibold : w == .medium ? .medium : .regular)
    }
    /// The same look the SwiftUI version had: 16 regular, 5 between lines, 10 between blocks.
    static func style(first: CGFloat = 0, head: CGFloat = 0, before: CGFloat = 0, tabs: [NSTextTab] = []) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        if MV.on {
            p.minimumLineHeight = MV.Text.messageLine; p.maximumLineHeight = MV.Text.messageLine
            p.paragraphSpacing = MV.Space.sm; p.paragraphSpacingBefore = before
        } else {
            p.lineSpacing = 5; p.paragraphSpacing = 10; p.paragraphSpacingBefore = before
        }
        p.firstLineHeadIndent = first; p.headIndent = head; p.tabStops = tabs
        return p
    }

    static func build(_ text: String, color: NSColor) -> [RichSegment] {
        var out: [RichSegment] = []
        var run = NSMutableAttributedString()
        func flush() {
            guard run.length > 0 else { return }
            // The last block's paragraph spacing would add 10 under the message: drop the trailing newline.
            if run.string.hasSuffix("\n") { run.deleteCharacters(in: NSRange(location: run.length - 1, length: 1)) }
            out.append(.prose(run)); run = NSMutableAttributedString()
        }
        for b in Markdown.blocks(text) {
            switch b {
            case .paragraph(let t):
                run.append(inline(t, size: size, base: color, weight: .regular, style: style())); run.append(newline)
            case .heading(let level, let t):
                // A heading at the very top doesn't push down from the name above it.
                let before: CGFloat = run.length == 0 && out.isEmpty ? 0 : (level <= 2 ? 8 : 4)
                run.append(inline(t, size: level <= 2 ? 18 : 16, base: NSColor(C.i12), weight: .semibold, style: style(before: before))); run.append(newline)
            case .item(let depth, let number, let t):
                // Marker right-aligned in a 14 column, the words 8 after it, wrapped lines under the words.
                let lead = CGFloat(depth) * 22 + 2
                let p = style(first: lead, head: lead + 22, tabs: [NSTextTab(textAlignment: .right, location: lead + 14), NSTextTab(textAlignment: .left, location: lead + 22)])
                let marker = number.map { "\($0)." } ?? (depth == 0 ? "•" : "◦")
                run.append(NSAttributedString(string: "\t\(marker)\t", attributes: [.font: font(size, .medium), .foregroundColor: NSColor(number == nil ? C.i9 : C.i10), .paragraphStyle: p]))
                run.append(inline(t, size: size, base: color, weight: .regular, style: p)); run.append(newline)
            case .quote(let t):
                flush(); out.append(.quote(inline(t, size: size, base: NSColor(C.i10), weight: .regular, style: style())))
            case .rule:
                flush(); out.append(.rule)
            case .code(let body):
                flush(); out.append(.code(body))
            case .table(let header, let rows):
                flush(); out.append(.table(header: header, rows: rows))
            }
        }
        flush()
        return out
    }
    private static let newline = NSAttributedString(string: "\n")

    /// Inline marks, as MarkdownText.inline: **bold** semibold and brighter, `code` the text's font a touch heavier and
    /// brighter, links blue on a soft blue underline.
    /// Line breaks inside a block stay in its paragraph (no block spacing between them).
    static func inline(_ s: String, size: CGFloat, base: NSColor, weight: F.W, style: NSParagraphStyle) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: InlineMarks.closed(s), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        let out = NSMutableAttributedString()
        let strong = NSColor(C.i12)
        for r in parsed.runs {
            let piece = String(parsed[r.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
            let intent = r.inlinePresentationIntent ?? []
            var a: [NSAttributedString.Key: Any] = [.font: font(size, weight), .foregroundColor: base, .paragraphStyle: style]
            if intent.contains(.stronglyEmphasized) { a[.font] = font(size, .semibold); a[.foregroundColor] = strong }
            // A name in `code` (a file, a folder, a command) is part of the sentence: the text's own font, a step brighter
            // and a touch heavier, never a box or monospace (no box to break across lines). Only links are blue: mouad.work's
            // blue on a soft underline of it.
            var link = r.link
            if intent.contains(.code) {
                a[.font] = font(size, .medium); a[.foregroundColor] = strong
                // A real file or folder: a link, so it opens (in Files, or Finder for a folder).
                if link == nil, let url = fileLink(piece, context: s) { link = url; a[.font] = font(size, weight) }
            }
            if link != nil {
                a[.foregroundColor] = NSColor(MARK_BLUE)
                a[.underlineStyle] = NSUnderlineStyle.thick.rawValue
                a[.underlineColor] = NSColor(MARK_BLUE.opacity(0.3))
            }
            if let link { a[.link] = link }
            out.append(NSAttributedString(string: piece, attributes: a))
        }
        autolink(out)
        linkFiles(out, context: s)
        chips(out, size: size)
        return out
    }
    private static func linkStyle(_ url: URL) -> [NSAttributedString.Key: Any] {
        [.link: url, .foregroundColor: NSColor(MARK_BLUE), .underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: NSColor(MARK_BLUE.opacity(0.3))]
    }
    /// Files named in plain words ("ShellChat.swift", "App/Sources/", "~/Desktop/x.md") that are really there: links.
    static func linkFiles(_ s: NSMutableAttributedString, context: String) {
        let text = s.string
        guard text.contains(".") || text.contains("/") else { return }
        for m in FileNames.pattern.matches(in: text, range: NSRange(location: 0, length: s.length)).reversed() {
            guard s.attribute(.link, at: m.range.location, effectiveRange: nil) == nil,
                  let url = fileLink((text as NSString).substring(with: m.range), context: context) else { continue }
            var r = m.range
            while r.length > 0, ".,:;)".contains((text as NSString).substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1))) { r.length -= 1 }
            s.addAttributes(linkStyle(url), range: r)
        }
    }
    /// Commands and skills ("/stageshow") set as chips: blue on a soft blue fill, the slash quieter, the name heavier.
    static func chips(_ s: NSMutableAttributedString, size: CGFloat) {
        let ranges = MainActor.assumeIsolated { CommandTokens.ranges(in: s.string) }
        for r in ranges where s.attribute(.link, at: r.location, effectiveRange: nil) == nil {
            // No text background (it drew a square per run): ChipLayoutManager draws one rounded pill per chip.
            s.addAttributes([.commandChip: true, .foregroundColor: NSColor(Chip.ink), .font: font(size, .medium)], range: r)
            s.addAttribute(.foregroundColor, value: NSColor(Chip.ink.opacity(0.6)), range: NSRange(location: r.location, length: 1))
            // Room on both sides, so the words around never touch the pill.
            let ns = s.string as NSString
            if r.location > 0, ns.character(at: r.location - 1) != 10 { s.addAttribute(.kern, value: Chip.room + Chip.gap, range: NSRange(location: r.location - 1, length: 1)) }
            // After it only when words follow (a chip ending its line keeps the bubble even around it).
            if NSMaxRange(r) < ns.length, ns.character(at: NSMaxRange(r)) != 10 { s.addAttribute(.kern, value: Chip.room + Chip.gap, range: NSRange(location: NSMaxRange(r) - 1, length: 1)) }
        }
    }
    /// Bare addresses in the words (https://…, www.…) are links too, so every one is blue and opens in the app.
    static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    static func autolink(_ s: NSMutableAttributedString) {
        guard let detector, s.length > 0 else { return }
        for m in detector.matches(in: s.string, range: NSRange(location: 0, length: s.length)) {
            guard let url = m.url, url.scheme == "http" || url.scheme == "https",
                  s.attribute(.link, at: m.range.location, effectiveRange: nil) == nil else { continue }
            s.addAttributes([.link: url, .foregroundColor: NSColor(MARK_BLUE), .underlineStyle: NSUnderlineStyle.thick.rawValue,
                             .underlineColor: NSColor(MARK_BLUE.opacity(0.3))], range: m.range)
        }
    }
}

/// One run of prose: a read-only, selectable text view that is exactly as tall as its text at the width it's given.
struct ProseView: NSViewRepresentable {
    let text: NSAttributedString

    final class TextView: NSTextView {
        /// The one block of text holding a selection: selecting in another clears it (never two highlights at once).
        @MainActor static weak var selecting: TextView?
        override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            let some = ranges.contains { $0.rangeValue.length > 0 }
            if some, Self.selecting !== self { let old = Self.selecting; Self.selecting = self; old?.clearSelection() }
        }
        /// Clicked elsewhere: the highlight goes (it stayed behind, bright, and read as a glitch).
        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            if ok { clearSelection() }
            return ok
        }
        func clearSelection() {
            guard selectedRange().length > 0 else { return }
            super.setSelectedRanges([NSValue(range: NSRange(location: selectedRange().location, length: 0))], affinity: .downstream, stillSelecting: false)
        }
        // No scrollWheel override: a view that overrides it takes the chat off AppKit's own scrolling thread (responsive
        // scrolling) for every swipe that starts over it, and the wheel already goes to the transcript by itself.
        /// The link under the pointer: its underline turns full blue (as mouad.work's marked words do).
        private var lit: NSRange?
        private var area: NSTrackingArea?
        /// It has links: only then does it watch the pointer (a tracking area on every block of text cost every scroll).
        var links = false { didSet { if links != oldValue { updateTrackingAreas() } } }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area); self.area = nil }
            guard links else { return }
            let a = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(a); area = a
        }
        override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); light(linkRange(at: event)) }
        override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); light(nil) }
        private func linkRange(at event: NSEvent) -> NSRange? {
            guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return nil }
            let p = convert(event.locationInWindow, from: nil)
            var frac: CGFloat = 0
            let i = lm.characterIndex(for: p, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
            guard i < ts.length, lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: i, length: 1), actualCharacterRange: nil), in: tc).insetBy(dx: -2, dy: -2).contains(p) else { return nil }
            var r = NSRange()
            return ts.attribute(.link, at: i, effectiveRange: &r) != nil ? r : nil
        }
        private func light(_ r: NSRange?) {
            guard r != lit, let lm = layoutManager else { return }
            if let old = lit { lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: old) }
            if let r { lm.addTemporaryAttribute(.underlineColor, value: NSColor(MARK_BLUE), forCharacterRange: r) }
            lit = r
        }
    }
    /// Heights already measured for this text, by width. SwiftUI asks several widths per layout pass (ideal, the
    /// column, the row), so one remembered width would be measured again on every pass.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: NSAttributedString?; var heights: [CGFloat: CGFloat] = [:]
        /// A click on a link: a file opens in the chat's Files pane, a folder in Finder, a web page in its Browser pane.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            MainActor.assumeIsolated { ProseView.open(url) }
            return true
        }
    }
    @MainActor static func open(_ url: URL) {
        let s = ConvoHub.shared.store
        let panel = s?.currentPanel
        if url.isFileURL {
            var dir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &dir)
            guard let panel, exists else { NSWorkspace.shared.activateFileViewerSelecting([url]); return }
            // A file opens in Files; a folder of the agent's opens there in the tree; any other folder shows in Finder
            // (Files only holds the agent's own folder).
            if !dir.boolValue { panel.openFile(url.path) }
            else if url.path.hasPrefix((panel.folder.hasSuffix("/") ? panel.folder : panel.folder + "/")) { panel.openPane(.files); panel.files.reveal(url.path) }
            else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } else if let panel { BrowserTab.open(url, in: panel) } else { NSWorkspace.shared.open(url) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    private static let storage = NSTextStorage(), layout = NSLayoutManager(), container = NSTextContainer()
    private static let wired: Void = { container.lineFragmentPadding = 0; layout.addTextContainer(container); storage.addLayoutManager(layout) }()
    static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        _ = wired
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        storage.setAttributedString(text)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

    func makeNSView(context: Context) -> NSTextView {
        let v = TextView(usingTextLayoutManager: false)      // TextKit 1: cheap, exact measuring
        v.textContainer?.replaceLayoutManager(ChipLayoutManager())    // chips' round fills
        v.isEditable = false; v.isSelectable = true; v.drawsBackground = false; v.isRichText = true
        // The chip's room is line padding inside the text area, not an inset outside it: AppKit clips drawing to the
        // text area, which cut a chip at a line's start flat on the left. The words sit exactly where they did.
        v.textContainerInset = .zero; v.textContainer?.lineFragmentPadding = Chip.room
        // The app's selection tone, not the system's bright blue.
        if MV.on { v.selectedTextAttributes = [.backgroundColor: NSColor(MV.Chat.selection)] }
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = false; v.isHorizontallyResizable = false
        v.linkTextAttributes = [.foregroundColor: NSColor(MARK_BLUE), .underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: NSColor(MARK_BLUE.opacity(0.3)), .cursor: NSCursor.pointingHand]
        v.delegate = context.coordinator
        v.textStorage?.setAttributedString(text)
        v.links = Self.hasLinks(text)
        return v
    }
    func updateNSView(_ v: NSTextView, context: Context) {
        if v.textStorage.map({ $0 !== text && !$0.isEqual(to: text) }) ?? true { v.textStorage?.setAttributedString(text); (v as? TextView)?.links = Self.hasLinks(text) }
    }
    static func hasLinks(_ t: NSAttributedString) -> Bool {
        var found = false
        t.enumerateAttribute(.link, in: NSRange(location: 0, length: t.length)) { v, _, stop in if v != nil { found = true; stop.pointee = true } }
        return found
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NSTextView, context: Context) -> CGSize? {
        let w = (proposal.width.map { $0.isFinite ? $0 : 680 } ?? 680).rounded()
        let c = context.coordinator
        if c.text !== text { c.text = text; c.heights.removeAll() }
        if let h = c.heights[w] { return CGSize(width: w, height: h) }
        // Measured with a private layout, so asking a size never re-lays the text view on screen.
        let h = Self.height(text, width: w - Chip.room * 2)     // the words' own width: the view is that plus its sides
        if c.heights.count > 24 { c.heights.removeAll() }
        c.heights[w] = h
        return CGSize(width: w, height: h)
    }
}

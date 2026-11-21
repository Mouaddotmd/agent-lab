// One box for the Browser pane: type anything and it offers, best guess first, to open it (an address), search Google,
// or ask the agent; under those, what Google suggests and pages you've been to. ↑ ↓ choose, Return takes the lit row,
// ⌘Return asks, ⇧Return searches, Esc lets go. A page's address bar becomes this box in place, its rows hanging under it
// (as Chrome's); a new tab is the same box as the app's own ask box (as Home's).
import SwiftUI
import AppKit

/// What the box ends in: a page to open (a search is a page too), or a question for the agent.
enum OmniPick: Equatable { case open(URL), ask(String) }

// MARK: Pages you've been to

/// Pages opened in the panel's tabs, newest first, kept across launches: the box suggests them as you type.
@MainActor final class BrowserHistory {
    static let shared = BrowserHistory()
    struct Visit: Codable, Equatable { var url: String; var title: String; var at: Double }
    private(set) var visits: [Visit]
    private let key = "browser.history"
    private init() {
        visits = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Visit].self, from: $0) } ?? []
    }
    func visit(_ u: URL, title: String) {
        let s = u.absoluteString
        guard !s.isEmpty, !Omni.isSearch(u) else { return }
        let keep = title.isEmpty ? (visits.first { $0.url == s }?.title ?? "") : title
        visits.removeAll { $0.url == s }
        visits.insert(Visit(url: s, title: keep, at: Date().timeIntervalSince1970), at: 0)
        if visits.count > 300 { visits.removeLast(visits.count - 300) }
        if let d = try? JSONEncoder().encode(visits) { UserDefaults.standard.set(d, forKey: key) }
    }
    /// Visits whose title or address has every word of `q`, newest first.
    func matching(_ q: String, limit: Int) -> [Visit] {
        let words = q.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Array(visits.prefix(limit)) }
        return Array(visits.lazy.filter { v in
            let hay = (v.title + " " + v.url).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }.prefix(limit))
    }
}

// MARK: Reading what you typed

enum Omni {
    enum Intent { case open(URL), ask, search }
    static func google(_ q: String) -> URL {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: q)]
        return c.url!
    }
    static func isSearch(_ u: URL) -> Bool { (u.host() ?? "").hasSuffix("google.com") && u.path == "/search" }
    /// Words that start a question or a request to the agent.
    static let asking: Set<String> = ["what", "why", "how", "who", "when", "where", "which", "whats", "what's", "is", "are", "was",
        "were", "can", "could", "should", "would", "will", "do", "does", "did", "explain", "summarize", "summarise", "tell",
        "write", "fix", "help", "make", "create", "add", "change", "review", "describe", "give", "show", "list", "compare",
        "check", "find", "run", "build", "update", "remove", "rename", "refactor", "debug", "test", "plan", "draft", "please",
        "hey", "hi", "hello", "thanks", "ok", "okay", "i", "we", "you", "your", "it", "this", "that", "btw"]
    /// The best guess: an address opens; a question or a request (or a long sentence) asks; anything else searches.
    static func intent(_ typed: String) -> Intent {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://\S+$"#, options: .regularExpression) != nil, let u = URL(string: t) { return .open(u) }
        if let u = BrowserPage.address(t), !isSearch(u) { return .open(u) }
        let words = t.lowercased().split(whereSeparator: { $0 == " " || $0 == "," })
        if t.hasSuffix("?") || words.count >= 6 { return .ask }
        if let first = words.first, asking.contains(String(first).trimmingCharacters(in: .punctuationCharacters)), words.count >= 2 { return .ask }
        return .search
    }
}

// MARK: The model

@MainActor final class OmniModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable { case ask, search, open, suggest, visit }
        let id: Int; let kind: Kind; let text: String; var detail: String? = nil; var url: URL? = nil
        var pick: OmniPick {
            switch kind {
            case .ask: .ask(text)
            case .search, .suggest: .open(Omni.google(text))
            case .open, .visit: .open(url ?? Omni.google(text))
            }
        }
        var symbol: String {
            switch kind {
            case .ask: "bubble.left"
            case .search, .suggest: "magnifyingglass"
            case .open, .visit: "globe"
            }
        }
    }
    @Published private(set) var text = ""
    @Published private(set) var rows: [Row] = []
    @Published var selected = 0
    let agentName: String
    private var suggestions: [String] = []
    private var fetching: Task<Void, Never>?
    /// What the box held when it opened (a page's address): rows wait until you change it.
    private let start: String
    init(agentName: String, start: String) {
        self.agentName = agentName
        self.start = start
        text = start
        rebuild()
    }

    func set(_ t: String) {
        guard t != text else { return }
        text = t
        selected = 0
        // What the web suggested for what you typed before stays (minus what no longer fits) until the new ones come.
        let q = t.trimmingCharacters(in: .whitespaces).lowercased()
        suggestions = suggestions.filter { $0.lowercased().hasPrefix(q) && $0.lowercased() != q }
        rebuild()
        fetch(q)
    }
    func move(_ by: Int) { guard !rows.isEmpty else { return }; selected = (selected + by + rows.count) % rows.count }
    var current: Row? { rows.indices.contains(selected) ? rows[selected] : nil }
    /// The row Return takes with ⌘ (ask) or ⇧ (search).
    func row(_ kind: Row.Kind) -> Row? { rows.first { $0.kind == kind } }

    private func rebuild() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [Row] = []
        if !start.isEmpty && text == start { rows = []; return }
        func add(_ kind: Row.Kind, _ text: String, _ detail: String? = nil, _ url: URL? = nil) {
            out.append(Row(id: out.count, kind: kind, text: text, detail: detail, url: url))
        }
        if t.isEmpty {
            for v in BrowserHistory.shared.matching("", limit: 4) { add(.visit, v.title.isEmpty ? Self.short(v.url) : v.title, Self.short(v.url), URL(string: v.url)) }
            rows = out; return
        }
        switch Omni.intent(t) {
        case .open(let u): add(.open, Self.short(u.absoluteString), "Open", u); add(.search, t, "Google"); add(.ask, t, "Ask \(agentName)")
        case .ask: add(.ask, t, "Ask \(agentName)"); add(.search, t, "Google")
        case .search: add(.search, t, "Google"); add(.ask, t, "Ask \(agentName)")
        }
        for v in BrowserHistory.shared.matching(t, limit: 2) { add(.visit, v.title.isEmpty ? Self.short(v.url) : v.title, Self.short(v.url), URL(string: v.url)) }
        for sug in suggestions.prefix(8 - out.count) where sug.lowercased() != t.lowercased() { add(.suggest, sug) }
        rows = Array(out.prefix(7))
        if selected >= rows.count { selected = 0 }
    }

    private func fetch(_ q: String) {
        fetching?.cancel()
        // Only what reads as a search goes to Google: a question for the agent stays on this Mac.
        guard !q.isEmpty, !q.contains("://"), q.split(separator: " ").count <= 6, !q.hasSuffix("?") else { return }
        fetching = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            var c = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
            c.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: q)]
            guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [Any], arr.count > 1, let list = arr[1] as? [String],
                  let self, self.text.trimmingCharacters(in: .whitespaces).lowercased() == q else { return }
            self.suggestions = list
            self.rebuild()
        }
    }
    /// An address without its scheme and "www.".
    static func short(_ s: String) -> String {
        var t = s
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if t.hasPrefix("www.") { t.removeFirst(4) }
        if t.hasSuffix("/") { t.removeLast() }
        return t
    }
}

// MARK: Rows

/// The rows under the box, compact: an icon, the words, and quietly what picking it does. The lit row follows ↑ ↓.
struct OmniRows: View {
    @ObservedObject var model: OmniModel
    let onPick: (OmniPick) -> Void
    @State private var hover: Int?
    static let rowHeight: CGFloat = 32
    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { r in
                let on = r.id == model.selected
                HStack(spacing: 10) {
                    Image(systemName: r.symbol).font(.system(size: 12)).foregroundStyle(on ? C.i12 : C.i10).frame(width: 16)
                    (Text(r.text).foregroundStyle(C.i12) + Text(r.detail.map { "  ·  \($0)" } ?? "").foregroundStyle(C.i9))
                        .font(F.font(13, .regular)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(height: Self.rowHeight)
                .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(on ? C.v4 : hover == r.id ? C.v3 : .clear))
                .contentShape(Rectangle())
                .onHover { hover = $0 ? r.id : (hover == r.id ? nil : hover) }
                .onTapGesture { onPick(r.pick) }
            }
        }
        .transaction { $0.animation = nil }
    }
    static func height(_ n: Int) -> CGFloat { CGFloat(n) * rowHeight }
}

/// The box's field (AppKit, so ↑ ↓ choose rows and ⌘/⇧ Return reach us instead of moving the caret).
struct OmniField: NSViewRepresentable {
    @ObservedObject var model: OmniModel
    let selectAll: Bool
    let prompt: String
    var size: CGFloat = 16
    let onReturn: (OmniModel.Row.Kind?) -> Void
    let onCancel: () -> Void

    final class Field: NSTextField {
        var focusedOnce = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !focusedOnce else { return }
            focusedOnce = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let w = self.window else { return }
                w.makeFirstResponder(self)
                if let ed = self.currentEditor() { ed.selectedRange = self.selectsAll ? NSRange(location: 0, length: self.stringValue.utf16.count) : NSRange(location: self.stringValue.utf16.count, length: 0) }
            }
        }
        var selectsAll = false
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let f = Field()
        f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none; f.isBezeled = false
        f.font = NSFont(name: "AnthropicSansText-Regular", size: size) ?? .systemFont(ofSize: size)
        f.textColor = NSColor(white: 0.93, alpha: 1)
        f.placeholderAttributedString = NSAttributedString(string: prompt, attributes: [
            .foregroundColor: NSColor(white: 0.53, alpha: 1), .font: f.font!,
        ])
        f.cell?.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.stringValue = model.text
        f.selectsAll = selectAll
        f.delegate = context.coordinator
        return f
    }
    func updateNSView(_ f: Field, context: Context) {
        context.coordinator.parent = self
        if f.currentEditor() == nil, f.stringValue != model.text { f.stringValue = model.text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OmniField
        init(_ p: OmniField) { parent = p }
        @MainActor func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            parent.model.set(f.stringValue)
        }
        @MainActor func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): parent.model.move(-1); return true
            case #selector(NSResponder.moveDown(_:)): parent.model.move(1); return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                let mods = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                parent.onReturn(mods.contains(.command) ? .ask : mods.contains(.shift) ? .search : nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}

// MARK: A new tab

/// A new tab: the app's ask box (as Home's: the field, then a row with what Return will do and the send circle), with
/// its rows opening inside it as you type. What you pick turns this tab into it: a page, or a side chat with the agent.
struct StartTab: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    let tabId: String
    @StateObject private var model: OmniModel
    @State private var starting = false
    @State private var boxHover = false
    init(panel: SidePanel, tabId: String) {
        self.panel = panel; self.tabId = tabId
        let name = ConvoHub.shared.store?.agents.first { $0.id == panel.agentId }?.name ?? "the agent"
        _model = StateObject(wrappedValue: OmniModel(agentName: name, start: ""))
    }
    var body: some View {
        if MV.on {
            GeometryReader { g in
                MVOmniBox(model: model, floating: false, onPick: { pick($0) }, onCancel: {})
                    .frame(maxWidth: MV.Launcher.width)
                    .padding(.horizontal, MV.Space.section)
                    .frame(maxWidth: .infinity)
                    .padding(.top, max(MV.Space.section, g.size.height * MV.Launcher.top))
            }
            .background(MV.Tone.page)
            .opacity(starting ? MV.Browser.disabled : 1).allowsHitTesting(!starting)
        } else {
            classic
        }
    }
    private var classic: some View {
        GeometryReader { g in
            box
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .padding(.top, max(32, g.size.height * 0.28))
        }
        .background(MV.on ? MV.Tone.page : C.v1)
    }

    private var box: some View {
        let rows = model.rows
        let verb: (String, String) = switch model.current?.kind {
        case .ask: ("bubble.left", "Ask \(model.agentName)")
        case .open, .visit: ("globe", "Open the page")
        case .search, .suggest, nil: ("magnifyingglass", "Search Google")
        }
        return VStack(spacing: 0) {
            OmniField(model: model, selectAll: false, prompt: "Ask \(model.agentName), search, or type an address", size: 16,
                      onReturn: { take($0) }, onCancel: {})
                .frame(height: 22)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            if !rows.isEmpty {
                OmniRows(model: model, onPick: { pick($0) }).padding(.horizontal, 6).padding(.bottom, 4)
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: verb.0).font(.system(size: 12)).frame(width: 16)
                    Text(model.text.isEmpty ? "Ask, search or open" : verb.1).font(F.font(13, .medium)).lineLimit(1)
                }
                .foregroundStyle(C.i10).padding(.leading, 4)
                Spacer(minLength: 0)
                Hover { h in
                    if MV.on {
                        Button { take(nil) } label: {
                            Icon("mvSend", MV.Size.icon).foregroundStyle(MV.Ink.onWhite).frame(width: MV.Size.homeSend, height: MV.Size.homeSend)
                                .background(Circle().fill(Color.white)).contentShape(Circle())
                        }.buttonStyle(MVStates(shape: Circle()))
                    } else {
                        Button { take(nil) } label: {
                            Icon("send", 16).foregroundStyle(C.v1).frame(width: 32, height: 32).background(Circle().fill(C.i12).opacity(h ? 0.88 : 1)).contentShape(Circle())
                        }.buttonStyle(.plain)
                    }
                }
                .tip(verb.1, "↵", edge: .top)
                .opacity(model.current == nil ? 0.4 : 1).allowsHitTesting(model.current != nil)
            }
            .padding(.horizontal, 12).padding(.bottom, 12).frame(height: 52, alignment: .bottom)
        }
        // MAVIS: the Home chatbox's shape (radius 24 on box, the 4 / 8% outline, no shadow); classic: the old card.
        .background(RoundedRectangle(cornerRadius: MV.on ? MV.Radius.homeBox : R.card, style: .continuous).fill(MV.on ? MV.Tone.box : C.v2))
        .overlay(RoundedRectangle(cornerRadius: MV.on ? MV.Radius.homeBox : R.card, style: .continuous)
            .strokeBorder(MV.on ? (boxHover ? MV.Stroke.boxHover : MV.Stroke.boxRest) : C.edgeControl, lineWidth: 1))
        .shadow(color: .black.opacity(MV.on ? 0 : 0.2), radius: 1, y: 1)
        .onHover { boxHover = $0 }
        .opacity(starting ? 0.6 : 1).allowsHitTesting(!starting)
        .transaction { $0.animation = nil }
    }

    private func take(_ kind: OmniModel.Row.Kind?) {
        if let r = kind.flatMap({ model.row($0) }) ?? model.current { pick(r.pick) }
    }
    private func pick(_ p: OmniPick) {
        switch p {
        case .open(let u): panel.openWeb(u, replacing: tabId)
        case .ask(let q):
            guard let a = s.agents.first(where: { $0.id == panel.agentId }) else { return }
            starting = true
            s.openSideChat(a, question: q, replacing: tabId)
        }
    }
}


/// MAVIS (Arc's new tab): the box floating over the page in front, the page dimmed under it. Picking opens a new tab
/// (a page) or a side chat (a question); Esc or a click outside puts it away with nothing changed.
struct MVLauncher: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    @StateObject private var model: OmniModel
    init(panel: SidePanel) {
        self.panel = panel
        let name = ConvoHub.shared.store?.agents.first { $0.id == panel.agentId }?.name ?? "the agent"
        _model = StateObject(wrappedValue: OmniModel(agentName: name, start: ""))
    }
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                Color.black.opacity(MV.Launcher.dim).contentShape(Rectangle()).onTapGesture { close() }
                box.frame(maxWidth: MV.Launcher.width).padding(.horizontal, MV.Space.section)
                    .padding(.top, max(MV.Space.section, g.size.height * MV.Launcher.top))
            }
        }
        .transaction { $0.animation = nil }
    }
    private var box: some View {
        MVOmniBox(model: model, floating: true, onPick: { pick($0) }, onCancel: { close() })
            .onTapGesture {}                         // a click on the box doesn't reach the backdrop
    }
    private func close() { panel.launcher = false }
    private func take(_ kind: OmniModel.Row.Kind?) {
        if let r = kind.flatMap({ model.row($0) }) ?? model.current { pick(r.pick) }
    }
    private func pick(_ p: OmniPick) {
        panel.launcher = false
        switch p {
        case .open(let u): panel.openWeb(u)
        case .ask(let q):
            guard let a = s.agents.first(where: { $0.id == panel.agentId }) else { return }
            s.openSideChat(a, question: q)
        }
    }
}


/// MAVIS omnibox (a new tab, and the box floating over a page): one surface on box, radius 24, the 4 / 8% outline.
/// A 52 pt field row (search icon, 15 pt words); under a hairline, the rows: 36 pt, radius 12, an 18 pt icon in t3, the
/// title in t1 and quietly what it opens. The keyboard's row sits on box2, the pointer's takes the 10% wash. Return
/// takes the lit row; Esc closes a floating box. Floating, it carries the menu shadow (level 2).
struct MVOmniBox: View {
    @ObservedObject var model: OmniModel
    let floating: Bool
    let onPick: (OmniPick) -> Void
    let onCancel: () -> Void
    @State private var hover: Int?
    @State private var boxHover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.homeBox, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: MV.Space.inset) {
                Icon("mvSearch", MV.Size.icon).foregroundStyle(MV.Ink.t3)
                OmniField(model: model, selectAll: false, prompt: "Ask \(model.agentName), search, or type an address", size: MV.Text.chatInput,
                          onReturn: { take($0) }, onCancel: onCancel)
                    .frame(height: MV.Chat.inputLine)
            }
            .padding(.horizontal, MV.Launcher.lead)
            .frame(height: MV.Size.chatBox)
            if !model.rows.isEmpty {
                Rectangle().fill(MV.Tone.hairline).frame(height: MV.Stroke.boxRestWidth)
                VStack(spacing: MV.Space.rowGap) {
                    ForEach(model.rows) { r in row(r) }
                }
                .padding(MV.Space.sm)
            }
        }
        .background(shape.fill(MV.Tone.box))
        .overlay(shape.strokeBorder(boxHover ? MV.Stroke.boxHover : MV.Stroke.boxRest, lineWidth: MV.Stroke.boxRestWidth).allowsHitTesting(false))
        .onHover { boxHover = $0 }
        .transaction { $0.animation = nil }
    }
    private func row(_ r: OmniModel.Row) -> some View {
        MVOmniRow(row: r, on: r.id == model.selected, hover: $hover, onPick: onPick)
    }
    static func icon(_ k: OmniModel.Row.Kind) -> String {
        switch k {
        case .ask: "mvChat"
        case .open, .visit: "mvGlobe"
        case .search, .suggest: "mvSearch"
        }
    }
    private func take(_ kind: OmniModel.Row.Kind?) {
        if let r = kind.flatMap({ model.row($0) }) ?? model.current { onPick(r.pick) }
    }
}


/// One omnibox row (the new tab's box, the floating box and the address bar's drop alike): 36 pt, radius 12; the site's
/// own icon (or the search / ask icon) in 18, the title in t1 and quietly what it opens. The lit row (the first, by
/// default) is a pill in the selection tone; the pointer's takes the 10% wash; the lit row shows ↵.
struct MVOmniRow: View {
    let row: OmniModel.Row; let on: Bool
    /// From the row's edge to its icon: chosen so the icon sits under the field's icon and the words under its words.
    var lead: CGFloat = MV.Space.gridGap
    @Binding var hover: Int?
    let onPick: (OmniPick) -> Void
    var body: some View {
        let r = row
        // Chrome: the lit row is a full pill; MAVIS's selection tone (the sidebar's 16% blue), so it reads on any fill.
        let shape = Capsule()
        HStack(spacing: MV.Space.inset) {
            MVOmniIcon(row: r, lit: on).frame(width: MV.Size.icon, height: MV.Size.icon)
            (Text(r.text).foregroundStyle(MV.Ink.t1) + Text(r.detail.map { "  \u{00B7}  \($0)" } ?? "").foregroundStyle(MV.Ink.t3))
                .font(F.font(MV.Text.title, .regular)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if on { Text("\u{21B5}").font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3) }
        }
        .padding(.leading, lead).padding(.trailing, MV.Space.inset).frame(height: MV.Workspace.row)
        .background(shape.fill(on ? MV.Accent.selected : hover == r.id ? MV.Wash.stHover : .clear))
        .contentShape(shape)
        .onHover { hover = $0 ? r.id : (hover == r.id ? nil : hover) }
        .onTapGesture { onPick(r.pick) }
    }
}
/// A row's icon: a site's own (as its tab), else search or ask.
struct MVOmniIcon: View {
    let row: OmniModel.Row; let lit: Bool
    var body: some View {
        if let host = row.url?.host(), row.kind == .open || row.kind == .visit {
            SiteIcon(host: host, size: MV.Size.iconSmall, ink: lit ? MV.Ink.t1 : MV.Ink.t3)
        } else {
            Icon(MVOmniBox.icon(row.kind), MV.Size.icon).foregroundStyle(lit ? MV.Ink.t1 : MV.Ink.t3)
        }
    }
}

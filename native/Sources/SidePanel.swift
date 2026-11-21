// Beside a chat, as Claude Code's: panes stacked one under another (a split), each opened by its icon in the chat's
// header: Terminal, Changes, Browser, Files. Each pane has its header (its tabs or its name, then expand and close).
// Browser holds tabs of its own: + opens a new tab (one box that opens a page, searches or asks the agent, Omnibox.swift),
// and side chats and helpers open there too. Files holds the tree and the files you open. One set per agent, kept while
// the app runs; the column's width is kept for good. ⌘\ shows or hides the column; its edge drags to resize.
import SwiftUI
import Combine
import AppKit

// MARK: Model

/// One tab in the panel.
struct PanelTab: Identifiable, Equatable, Hashable {
    /// Its place in the strip: a new tab that turns into a page or a chat keeps its place (it doesn't close and reopen).
    var slot: String? = nil
    var key: String { slot ?? id }
    /// helper: a Claude helper's tool-use id (its title is what it was asked); side: a side chat's id (its title).
    enum Kind: Equatable, Hashable { case files, file(String), changes, terminal(String), web(String), start(String), helper(id: String, title: String), side(id: String, title: String), report(id: String, title: String) }
    var kind: Kind
    init(kind: Kind, slot: String? = nil) { self.kind = kind; self.slot = slot }
    var id: String {
        switch kind {
        case .files: "files"
        case .file(let path): "file:" + path
        case .changes: "changes"
        case .terminal(let key): key == "main" ? "terminal" : "terminal:" + key
        case .web(let id): "web:" + id
        case .start(let id): "start:" + id
        case .helper(let id, _): "helper:" + id
        case .side(let id, _): "side:" + id
        case .report(let id, _): "report:" + id
        }
    }
    var title: String {
        switch kind {
        case .files: "Files"
        case .file(let path): (path as NSString).lastPathComponent
        case .changes: "Changes"
        case .terminal: "Terminal"
        case .web: "Page"
        case .start: "New tab"
        case .helper(_, let t), .side(_, let t), .report(_, let t): t
        }
    }
    var icon: String {
        switch kind {
        case .files: "folder"
        case .file: "file"
        case .changes: "plus.forwardslash.minus"
        case .terminal: "terminal"
        case .web, .start: "globe"
        case .helper: "agents"
        case .report: "doc.text"
        case .side: "bubble.left.and.bubble.right"
        }
    }
}

extension PanelTab {
    /// The pane a tab lives in.
    var pane: SidePanel.Pane {
        switch kind {
        case .files, .file: .files
        case .changes: .changes
        case .terminal: .terminal
        case .web, .start, .side, .helper, .report: .browser
        }
    }
}

/// An agent's panes: which are open (top to bottom), each one's tabs and the one in front.
@MainActor final class SidePanel: ObservableObject {
    enum Pane: String, CaseIterable { case terminal, changes, browser, files
        var title: String { switch self { case .terminal: "Terminal"; case .changes: "Changes"; case .browser: "Browser"; case .files: "Files" } }
    }
    /// The column shows (⌘\ hides it and keeps what's in it).
    @Published var open = false
    /// The panes open, top to bottom.
    @Published var panes: [Pane] = []
    /// A pane filling the column (expand); the others stay open behind it.
    @Published var maxed: Pane?
    /// Each pane's share of the column's height (the edges between them drag).
    @Published var shares: [Pane: CGFloat] = [:]
    @Published var tabs: [PanelTab] = []
    /// The tab in front in each pane.
    @Published var front: [Pane: String] = [:]
    /// The tab you last brought forward, in any pane.
    @Published private(set) var selected: String?
    /// ⌘P's box is showing.
    @Published var quickOpen = false
    /// MAVIS: the new-tab box floating over the page in front (Arc's), until you pick something or press Esc.
    @Published var launcher = false
    /// A tab with unsaved edits you asked to close: the panel asks first.
    @Published var closing: String?
    /// The agent this panel belongs to.
    let agentId: String
    /// The folder the agent works in: what Files shows.
    let folder: String
    /// Files' state, kept while you look at other tabs: open folders, the filter, what's in each folder, git's marks.
    let files: FilesModel
    /// Open files, read and coloured once (off the main thread) and kept while their tab is open.
    private(set) var docs: [String: FileDoc] = [:]
    /// ⌘P's list and search.
    let quick: QuickOpenModel
    /// The Changes tab's state (which view, what's open, the commit message), kept while you look at other tabs.
    let changes: ChangesModel
    private var listening: NSObjectProtocol?
    private var saving: AnyCancellable?, savingFront: AnyCancellable?
    /// Pages of restored tabs, opened when the tab's page is first made (BrowserPage.of).
    var restored: [String: URL] = [:]
    /// Restored tabs' titles, until their pages say their own.
    var restoredTitles: [String: String] = [:]

    // MARK: The agent's browser, kept

    /// A Browser tab as it's kept on disk.
    private struct SavedTab: Codable { var kind: String; var id: String; var title: String?; var url: String?; var slot: String?; var body: String? = nil }
    private struct SavedBrowser: Codable { var tabs: [SavedTab]; var front: String?; var frontTerminal: String? = nil }
    private var browserKey: String { "browser.tabs." + agentId }
    /// Every Browser tab (pages, new tabs, side chats) with its address and title, and the one in front: written as they
    /// change, so the agent's browser is there as it was after you close the pane or quit (19 Nov).
    func saveBrowser() {
        let list = tabs.compactMap { t -> SavedTab? in
            switch t.kind {
            case .web(let id):
                let url = BrowserPage.existing(id)?.url ?? restored[id]
                return SavedTab(kind: "web", id: id, title: BrowserPage.existing(id)?.title ?? restoredTitles[id], url: url?.absoluteString, slot: t.slot)
            case .start(let id): return SavedTab(kind: "start", id: id, slot: t.slot)
            case .side(let id, let title): return SavedTab(kind: "side", id: id, title: title, slot: t.slot)
            case .report(let id, let title): return SavedTab(kind: "report", id: id, title: title, slot: t.slot, body: Reports.shared.body[id])
            case .terminal(let key): return SavedTab(kind: "terminal", id: key, slot: t.slot)
            default: return nil
            }
        }
        let value = SavedBrowser(tabs: list, front: front[.browser], frontTerminal: front[.terminal])
        if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: browserKey) }
    }
    private func restoreBrowser() {
        guard let d = UserDefaults.standard.data(forKey: browserKey), let v = try? JSONDecoder().decode(SavedBrowser.self, from: d) else { return }
        for t in v.tabs {
            switch t.kind {
            case "web":
                tabs.append(PanelTab(kind: .web(t.id), slot: t.slot))
                if let u = t.url.flatMap(URL.init(string:)) { restored[t.id] = u }
                if let title = t.title, !title.isEmpty { restoredTitles[t.id] = title }
            case "start": tabs.append(PanelTab(kind: .start(t.id), slot: t.slot))
            case "side": tabs.append(PanelTab(kind: .side(id: t.id, title: t.title ?? "Side chat"), slot: t.slot))
            case "terminal": tabs.append(PanelTab(kind: .terminal(t.id), slot: t.slot))
            case "report":
                if let b = t.body { Reports.shared.body[t.id] = b }
                tabs.append(PanelTab(kind: .report(id: t.id, title: t.title ?? "Report"), slot: t.slot))
            default: break
            }
        }
        if let f = v.front, tabs.contains(where: { $0.id == f }) { front[.browser] = f }
        else if let last = tabs.last(where: { $0.pane == .browser }) { front[.browser] = last.id }
        if let f = v.frontTerminal, tabs.contains(where: { $0.id == f }) { front[.terminal] = f }
        else if let last = tabs.last(where: { $0.pane == .terminal }) { front[.terminal] = last.id }
    }

    private static var panels: [String: SidePanel] = [:]
    static func of(_ agent: Agent, home: String) -> SidePanel {
        if let p = panels[agent.id] { return p }
        let p = SidePanel(agentId: agent.id, folder: agent.cwd ?? home)
        panels[agent.id] = p
        return p
    }
    /// A workspace channel's panel: kept under its own key, on the workspace's folder; Changes follows `changesFor`
    /// (the channel's first agent) when there is one.
    static func of(key: String, folder: String, changesFor: String?) -> SidePanel {
        if let p = panels[key] { return p }
        let p = SidePanel(agentId: key, folder: folder, changesFor: changesFor)
        panels[key] = p
        return p
    }
    init(agentId: String, folder: String, changesFor: String? = nil) {
        self.agentId = agentId; self.folder = folder
        files = FilesModel(folder: folder); quick = QuickOpenModel(folder: folder); changes = ChangesModel(agentId: changesFor ?? agentId)
        restoreBrowser()
        saving = $tabs.dropFirst().combineLatest($front.dropFirst()).sink { [weak self] _ in DispatchQueue.main.async { self?.saveBrowser() } }
        savingFront = $front.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.saveBrowser() } }
        // When the agent (or anything) may have changed files: git's marks, the tree, open files and Changes catch up.
        listening = NotificationCenter.default.addObserver(forName: .engineEvent, object: nil, queue: .main) { [weak self] n in
            let type = n.userInfo?["type"] as? String
            guard type == "run-end" || type == "git" else { return }
            MainActor.assumeIsolated { self?.filesChanged() }
        }
    }
    /// Files may have changed: refresh what shows them.
    func filesChanged() {
        files.changed()
        for d in docs.values { d.checkDisk() }
        changes.changed()
    }
    /// The panel of an agent, if one was made (for opening a tab from elsewhere: a helper step, the palette).
    static func existing(_ agentId: String) -> SidePanel? { panels[agentId] }

    /// The panel's width, kept across launches.
    static let standardWidth: CGFloat = 460
    static var width: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "sidePanel.width").nonZero ?? standardWidth) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "sidePanel.width") }
    }
    /// MAVIS: the width you dragged the column to; nil until you do (it then takes half, 50/50 with the chat).
    static var mavisWidth: CGFloat? {
        get { UserDefaults.standard.object(forKey: "sidePanel.mavisWidth") == nil ? nil : CGFloat(UserDefaults.standard.double(forKey: "sidePanel.mavisWidth")) }
        set { if let v = newValue { UserDefaults.standard.set(Double(v), forKey: "sidePanel.mavisWidth") } else { UserDefaults.standard.removeObject(forKey: "sidePanel.mavisWidth") } }
    }

    /// ⌘\: the column shows or hides; shown with nothing in it, Files opens.
    func toggle() {
        if open { open = false; return }
        if panes.isEmpty { openPane(.files) } else { open = true }
    }
    /// A tab is on screen: in front in its pane, its pane open and not hidden behind an expanded one, the column shown.
    func isFront(_ id: String) -> Bool {
        guard open, let t = tabs.first(where: { $0.id == id }), panes.contains(t.pane), maxed == nil || maxed == t.pane else { return false }
        return front[t.pane] == id
    }
    func isShowing(_ p: Pane) -> Bool { open && panes.contains(p) }

    /// The pane's icon: open it (with what it had, or its first tab), or close it if it's showing.
    func togglePane(_ p: Pane) { isShowing(p) ? closePane(p) : openPane(p) }
    func openPane(_ p: Pane) {
        if let id = front[p], tabs.contains(where: { $0.id == id }) { focus(p); return }
        switch p {
        case .files: show(PanelTab(kind: .files))
        case .changes: show(PanelTab(kind: .changes))
        case .terminal: show(PanelTab(kind: .terminal("main")))
        case .browser: newTab()
        }
    }
    /// Shows pane `p` (opening it at the bottom if it wasn't).
    private func focus(_ p: Pane) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            if !panes.contains(p) { panes.append(p) }
            if maxed != nil && maxed != p { maxed = nil }
            open = true
        }
    }
    /// × on a pane: it closes with its tabs (a file with unsaved edits asks first).
    func closePane(_ p: Pane) {
        // The Browser and the Terminal are the agent's own: × hides them, their tabs stay (a window you put away, the
        // shells still running), and their icons bring them back as they were. The last tab closing is what empties one.
        if p == .browser || p == .terminal, tabs.contains(where: { $0.pane == p }) {
            panes.removeAll { $0 == p }
            if maxed == p { maxed = nil }
            if panes.isEmpty { open = false }
            return
        }
        if let dirty = tabs.first(where: { t in t.pane == p && { if case .file(let path) = t.kind { docs[path]?.dirty == true } else { false } }() }) {
            front[p] = dirty.id; closing = dirty.id; return
        }
        for t in tabs where t.pane == p { if case .file(let path) = t.kind { docs.removeValue(forKey: path) } }
        tabs.removeAll { $0.pane == p }
        front[p] = nil
        panes.removeAll { $0 == p }
        if maxed == p { maxed = nil }
        if panes.isEmpty { open = false }
    }
    func toggleMax(_ p: Pane) { maxed = maxed == p ? nil : p }

    /// A new shell in Terminal, in the agent's folder, in front.
    func newTerminal() { show(PanelTab(kind: .terminal(String(UUID().uuidString.prefix(8))))) }
    /// A new tab in Browser: one box that opens a page, searches the web or asks the agent (Omnibox.swift).
    /// MAVIS (as Arc): with a page already open, + (and ⌘T) doesn't make a blank tab. The box floats over the page you're
    /// on (`launcher`); only what you pick opens, in a new tab. An empty browser still gets its one New tab.
    var browserFull: Bool { MV.on && tabs.filter { $0.pane == .browser }.count >= MV.Browser.maxTabs }
    func newTab() {
        // + again while the box floats: it closes (a toggle, as Arc's). Typing in the address bar: + closes that instead.
        if MV.on, launcher { launcher = false; return }
        if MV.on, let id = front[.browser], case .web(let pid)? = tabs.first(where: { $0.id == id })?.kind, BrowserPage.of(self, pid).addressOpen {
            BrowserPage.of(self, pid).dismissAddressBar(); return
        }
        if browserFull { NSSound.beep(); return }
        // The tab in front is already a new tab: just bring it forward (its box is the launcher; never two).
        if MV.on, let id = front[.browser], case .start? = tabs.first(where: { $0.id == id })?.kind {
            focus(.browser); return
        }
        if MV.on, tabs.contains(where: { $0.pane == .browser }) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { focus(.browser); launcher = true }
            return
        }
        show(PanelTab(kind: .start(String(UUID().uuidString.prefix(8)))))
    }
    /// A web page in a tab of its own (in place of `replacing`, a new tab that became this page).
    func openWeb(_ url: URL, replacing: String? = nil) {
        // Full (15 tabs): the page loads in the web tab in front instead of a new one.
        if replacing == nil, browserFull, let id = front[.browser], case .web(let page)? = tabs.first(where: { $0.id == id })?.kind {
            BrowserPage.of(self, page).load(url); focus(.browser); return
        }
        let tab = PanelTab(kind: .web(String(UUID().uuidString.prefix(8))))
        if let replacing { replace(replacing, with: tab) } else { show(tab) }
        if case .web(let id) = tab.kind { BrowserPage.of(self, id).load(url) }
    }
    /// Puts `tab` where the tab `id` is (a new tab turning into the page or chat you picked), in front.
    func replace(_ id: String, with tab: PanelTab) {
        tabs.removeAll { $0.id == tab.id }
        var tab = tab
        if let i = tabs.firstIndex(where: { $0.id == id }) { tab.slot = tabs[i].key; tabs[i] = tab } else { tabs.append(tab) }
        front[tab.pane] = tab.id; selected = tab.id
        focus(tab.pane)
    }

    /// Brings a tab to the front of its pane, opening it (after the pane's others) and the pane if they aren't.
    func show(_ tab: PanelTab) {
        if !tabs.contains(where: { $0.id == tab.id }) { tabs.append(tab) }
        if case .file(let path) = tab.kind { _ = doc(path) }
        front[tab.pane] = tab.id; selected = tab.id
        focus(tab.pane)
    }
    /// A click on a tab.
    func select(_ id: String) {
        guard let t = tabs.first(where: { $0.id == id }) else { return }
        front[t.pane] = id; selected = id
    }

    /// The open file at `path`, read on first use.
    func doc(_ path: String) -> FileDoc {
        if let d = docs[path] { return d }
        let d = FileDoc(path: path)
        docs[path] = d
        return d
    }

    /// Closes a tab; one with unsaved edits asks first (Save, Don't save, Cancel). The pane's last tab closes the pane.
    func close(_ id: String) {
        if let tab = tabs.first(where: { $0.id == id }), case .file(let path) = tab.kind, docs[path]?.dirty == true {
            select(id); closing = id; return
        }
        forceClose(id)
    }
    func forceClose(_ id: String) {
        if closing == id { closing = nil }
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if case .file(let path) = tab.kind { docs.removeValue(forKey: path) }
        let p = tab.pane
        let mine = tabs.filter { $0.pane == p }
        let at = mine.firstIndex { $0.id == id } ?? 0
        tabs.removeAll { $0.id == id }
        let left = tabs.filter { $0.pane == p }
        if left.isEmpty { closePane(p); return }
        if front[p] == id { front[p] = left[min(at, left.count - 1)].id }
    }

    /// Opens a file of the agent's folder (a full path, or one relative to it).
    func openFile(_ path: String) {
        let full = path.hasPrefix("/") ? path : (folder as NSString).appendingPathComponent(path)
        show(PanelTab(kind: .file(full)))
        docs[full]?.checkDisk()
    }
    /// A path as the agent would name it: relative to its folder when it's inside.
    func relative(_ path: String) -> String {
        let base = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : (path as NSString).abbreviatingWithTildeInPath
    }
    /// ⌘P: the panel opens (with Files if it had nothing) and the box shows.
    func openQuick() {
        if quickOpen { quickOpen = false; return }
        if !isShowing(.files) { openPane(.files) }
        quickOpen = true
    }
    /// A report in its own tab beside the chat, in front (from its card, or by itself once a long one is written).
    func showReport(id: String, _ r: ReportTag.Report) {
        Reports.shared.body[id] = r.body
        show(PanelTab(kind: .report(id: id, title: r.title)))
    }
    /// The Changes tab on This chat (from "Changed N files" under a turn).
    func showChatChanges() {
        changes.mode = .chat
        show(PanelTab(kind: .changes))
        changes.refresh()
    }
    /// Opens `agentId`'s panel on its chat's changes (the panel is made if it wasn't yet).
    static func showChatChanges(_ agent: Agent, home: String) { of(agent, home: home).showChatChanges() }
}

private extension Double { var nonZero: Double? { self == 0 ? nil : self } }

// MARK: The panel

/// The chat and its panel side by side, with the edge between them to drag. The panel shows and hides at once, with
/// no animation: the chat takes its new width in one step and the panel is simply there (or gone).
struct ChatWithPanel<Chat: View>: View {
    @ObservedObject var panel: SidePanel
    let chat: Chat
    @State private var width = SidePanel.width
    /// MAVIS: your column width, nil = half. Read by the body so a drag redraws every frame (a static setting the view
    /// didn't watch left the column stuck while dragging); saved when the drag ends.
    @ObservedObject private var width2 = PanelWidth.shared
    @State private var dragFrom: CGFloat?
    /// The panel is in the view (it stays while it slides off).
    @State private var present: Bool
    /// The room the chat leaves for it: its width while open, 0 the moment it starts closing.
    @State private var reserved: Bool
    /// 0 in place, 1 just past the window's edge.
    @State private var slide: CGFloat
    init(panel: SidePanel, chat: Chat) {
        self.panel = panel; self.chat = chat
        _present = State(initialValue: panel.open); _reserved = State(initialValue: panel.open); _slide = State(initialValue: panel.open ? 0 : 1)
    }
    var body: some View {
        Group { if MV.on { mavis } else { classic } }
            .onChange(of: panel.open) { _, open in open ? slideIn() : slideOut() }
            .background(Button("") { panel.toggle() }.keyboardShortcut("\\", modifiers: .command).opacity(0).allowsHitTesting(false))
            // ⌘P: open a file by name. Like ⌘\, it lives in the chat's own view, so it acts only on the chat in front.
            .background(Button("") { panel.openQuick() }.keyboardShortcut("p", modifiers: .command).opacity(0).allowsHitTesting(false))
            .background(Button("") { panel.newTab() }.keyboardShortcut("t", modifiers: .command).opacity(0).allowsHitTesting(false))
    }
    /// MAVIS (spec 8): the chat is one surface; the panel is a 392 column of its own surfaces, 8 to its right. It
    /// shows and hides at once, as before.
    private var mavis: some View {
        GeometryReader { geo in
            let room = max(MV.Resize.sideMin, geo.size.width - MV.Resize.chatMin)
            // Until you drag it, the column takes half (50/50 with the chat); your size is kept after that.
            let half = (geo.size.width - MV.Space.gutter) / 2
            let w = min(max(MV.Resize.sideMin, width2.w ?? half), room)
            HStack(spacing: 0) {
                chat.frame(maxWidth: .infinity, maxHeight: .infinity).mvSurface()
                if present {
                    // The gap is the handle (Chrome's side panel): drag to resize, double-click for the default.
                    MVResizeGap(axis: .horizontal) { dx in
                        if dragFrom == nil { dragFrom = w }
                        width2.w = min(max(MV.Resize.sideMin, (dragFrom ?? w) - dx), room)
                    } end: {
                        dragFrom = nil; SidePanel.mavisWidth = width2.w
                    } reset: {
                        width2.w = nil; SidePanel.mavisWidth = nil
                    }
                    PanelView(panel: panel).frame(width: w).frame(maxHeight: .infinity)
                }
            }
        }
    }
    private var classic: some View {
        GeometryReader { geo in
            let w = min(max(320, width), max(320, geo.size.width - 380))
            ZStack(alignment: .topTrailing) {
                // Clipped to its own column: on the frame the panel appears, nothing of the chat draws under it.
                chat.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .padding(.trailing, reserved ? w + 1 : 0)
                if present {
                    HStack(spacing: 0) {
                        Rectangle().fill(C.divider).frame(width: 1)
                            // The sidebar's handle, the same look and feel: the line lights, the ↔ knob shows,
                            // double-click puts the width back.
                            .overlay {
                                PanelGrip { g in
                                    if dragFrom == nil { dragFrom = w }
                                    width = min(max(320, (dragFrom ?? w) - g), geo.size.width - 380)
                                } end: {
                                    dragFrom = nil; SidePanel.width = width
                                } reset: {
                                    width = SidePanel.standardWidth; SidePanel.width = width
                                }
                            }
                            .zIndex(1)
                        PanelView(panel: panel).frame(width: w)
                    }
                    .frame(width: w + 1)
                    .frame(maxHeight: .infinity)
                    .background(C.v1)
                    .offset(x: slide * (w + 13))
                    .allowsHitTesting(slide < 0.5)
                }
            }
            .background(C.v1)
            .clipped()
        }
    }
    /// Shown at once and gone at once: no slide, no fade (17 Nov: any motion here read as a glitch).
    private func slideIn() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { present = true; reserved = true; slide = 0 }
    }
    private func slideOut() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { reserved = false; slide = 1; present = false }
    }
}

/// The column: the open panes, top to bottom, sharing its height (or the expanded one alone).
struct PanelView: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    @State private var dragFrom: [SidePanel.Pane: CGFloat]?
    static let minPane: CGFloat = 140
    var body: some View {
        GeometryReader { g in
            let shown = panel.maxed.map { [$0] } ?? panel.panes
            // MAVIS: each pane is its own surface, 8 apart (the gap is the drag edge); classic: 1 pt lines.
            let edge = MV.on ? MV.Space.gutter : 1
            let total = max(0, g.size.height - CGFloat(max(0, shown.count - 1)) * edge)
            let sum = shown.reduce(0) { $0 + (panel.shares[$1] ?? 1) }
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element) { i, p in
                    if i > 0 {
                        if MV.on {
                            MVResizeGap(axis: .vertical) { dy in drag(dy, above: shown[i - 1], below: p, total: total, sum: sum) } end: { dragFrom = nil } reset: {
                                panel.shares[shown[i - 1]] = 1; panel.shares[p] = 1
                            }
                        } else {
                            PaneEdge { dy in drag(dy, above: shown[i - 1], below: p, total: total, sum: sum) } end: { dragFrom = nil }
                        }
                    }
                    PaneView(panel: panel, pane: p, first: i == 0)
                        .modifier(MVSurfaceIfOn())
                        .frame(height: total * (panel.shares[p] ?? 1) / max(sum, 0.001))
                }
            }
        }
        .background(MV.on ? Color.clear : C.v1)
        .overlay(alignment: .top) {
            if panel.quickOpen { QuickOpenView(panel: panel, model: panel.quick).padding(.top, MV.on ? MV.Size.header : 56) }
        }
        .overlay {
            if let id = panel.closing, let tab = panel.tabs.first(where: { $0.id == id }), case .file(let path) = tab.kind {
                PanelConfirm(title: "Save changes to \((path as NSString).lastPathComponent)?", detail: "Your edits are lost if you don't save them.",
                             confirm: "Save", danger: false, other: "Don't save",
                             onConfirm: { if panel.doc(path).save() { panel.forceClose(id) } else { panel.closing = nil } },
                             onOther: { panel.forceClose(id) },
                             onCancel: { panel.closing = nil })
            }
        }
    }
    /// The edge between two panes moves: one grows by what the other gives, neither under `minPane`.
    private func drag(_ dy: CGFloat, above a: SidePanel.Pane, below b: SidePanel.Pane, total: CGFloat, sum: CGFloat) {
        if dragFrom == nil { dragFrom = panel.shares }
        let from = dragFrom ?? [:]
        let ha = total * (from[a] ?? 1) / sum, hb = total * (from[b] ?? 1) / sum
        let na = min(max(Self.minPane, ha + dy), ha + hb - Self.minPane)
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            panel.shares[a] = na / total * sum
            panel.shares[b] = (ha + hb - na) / total * sum
        }
    }
}

/// The line between two panes: it lights while you're on it, and drags.
private struct PaneEdge: View {
    /// MAVIS: the 8 pt gap between two pane surfaces, no line; it still drags.
    var gap = false
    let drag: (CGFloat) -> Void
    let end: () -> Void
    @State private var hover = false
    @State private var dragging = false
    var body: some View {
        Rectangle().fill(gap ? Color.clear : dragging ? C.i10 : hover ? C.v6 : C.divider).frame(height: gap ? MV.Space.gutter : 1)
            .overlay { Color.clear.frame(height: 9).contentShape(Rectangle())
                .pointerStyle(.rowResize)
                .onHover { hover = $0 }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in dragging = true; drag(g.translation.height) }
                    .onEnded { _ in dragging = false; end() })
            }
            .zIndex(1)
    }
}

/// One pane: its header (its tabs, or its name; then expand and close), then the tab in front. Every tab stays built:
/// switching only shows one and hides the others, so it's instant and each keeps its place.
private struct PaneView: View {
    @ObservedObject var panel: SidePanel
    let pane: SidePanel.Pane
    /// The top pane's header is as tall as the chat's beside it, so the line under both is one line.
    let first: Bool
    var body: some View {
        let mine = panel.tabs.filter { $0.pane == pane }
        VStack(spacing: 0) {
            header(mine)
            ZStack {
                ForEach(mine) { tab in
                    let on = panel.front[pane] == tab.id
                    Group {
                        switch tab.kind {
                        case .files: FilesTab(panel: panel, model: panel.files)
                        case .file(let path): FileTab(panel: panel, doc: panel.doc(path))
                        case .changes: ChangesTab(panel: panel)
                        case .terminal(let key): TerminalTab(panel: panel, key: key)
                        case .web(let id): BrowserTab(panel: panel, pageId: id)
                        case .start(let id): StartTab(panel: panel, tabId: "start:" + id)
                        case .helper(let id, _): HelperTab(panel: panel, helperId: id)
                        case .side(let id, _): SideChatTab(panel: panel, sideId: id)
                        case .report(let id, _): ReportTab(id: id)
                        }
                    }
                    .opacity(on ? 1 : 0).allowsHitTesting(on).disabled(!on).accessibilityHidden(!on)
                    .environment(\.paneTabOn, on)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay { if MV.on && pane == .browser && panel.launcher { MVLauncher(panel: panel) } }
        }
    }

    /// A web page is in front: its toolbar is what the tab joins (other tabs join the pane itself).
    private var frontIsPage: Bool { panel.tabs.first { $0.id == panel.front[pane] }.map { if case .web = $0.kind { true } else { false } } ?? false }
    @ViewBuilder private func header(_ mine: [PanelTab]) -> some View {
        if MV.on {
            // MAVIS (spec 5, 8): every pane header is 44 on the page tone. Browser and Terminal show pill tabs and +;
            // Files its file tabs; the rest their name. Then expand (when split) and close, 28 round, 8 from the edge.
            HStack(spacing: MV.Space.sm) {
                // The browser always shows its tabs (prototype); other panes show their title until a second tab
                // (another shell, an open file) needs the pills.
                if pane == .browser || mine.count > 1 {
                    MVTabStrip(panel: panel, tabs: mine,
                               new: pane == .terminal ? { panel.newTerminal() } : pane == .browser ? { panel.newTab() } : nil)
                        .frame(maxWidth: .infinity)
                } else {
                    MVPaneTitle(icon: pane == .terminal ? "mvTerm" : pane == .files ? "mvFolder" : pane == .changes ? "mvDiff" : "mvGlobe",
                                title: pane.title,
                                meta: pane == .terminal ? "zsh · " + (panel.folder as NSString).abbreviatingWithTildeInPath
                                    : pane == .files ? (panel.folder as NSString).lastPathComponent : nil)
                }
                Spacer(minLength: 0)
                mvPaneButtons
            }
            .padding(.horizontal, MV.Space.headerEdge)
            .frame(height: MV.Size.header)
            .background(MV.Tone.page)
        } else if pane == .browser || pane == .terminal {
            // As Chrome's: the tabs stand on the frame from the header buttons' top edge (8) down into the surface under
            // them; titles, + and the pane's buttons all centre on the header buttons' line (28 from the top).
            let h = first ? 56 : Bar.height
            HStack(alignment: .top, spacing: Box.pair) {
                BrowserStrip(panel: panel, tabs: mine, new: pane == .terminal ? { panel.newTerminal() } : { panel.newTab() },
                             height: h - Box.pad, surface: frontIsPage ? C.v2 : C.v1)
                    .padding(.top, Box.pad)
                paneButtons.padding(.top, Box.pad + (BrowserStrip.body - Bar.control) / 2)
            }
            .padding(.horizontal, Box.pad)
            .frame(height: h, alignment: .top)
            .background(C.v0)
        } else {
            plainHeader(mine).overlay(alignment: .bottom) { Rectangle().fill(C.divider).frame(height: 1) }
        }
    }
    /// MAVIS: only the browser collapses (sidebar icon); every other pane closes with ✕.
    @ViewBuilder private var mvPaneButtons: some View {
        if panel.panes.count > 1 {
            let big = panel.maxed == pane
            MVIconButton(icon: big ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: big ? "Back to the split" : "Expand") {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { panel.toggleMax(pane) }
            }
        }
        MVIconButton(icon: pane == .browser ? "mvCollapse" : "mvClose", label: pane == .browser ? "Collapse browser" : "Close \(pane.title)") {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { panel.closePane(pane) }
        }
    }
    @ViewBuilder private var paneButtons: some View {
        if panel.panes.count > 1 {
            let big = panel.maxed == pane
            ToolIcon(symbol: big ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: big ? "Back to the split" : "Expand") {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { panel.toggleMax(pane) }
            }
        }
        ToolIcon(symbol: "xmark", label: "Close \(pane.title)") {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { panel.closePane(pane) }
        }
    }
    private func plainHeader(_ mine: [PanelTab]) -> some View {
        HStack(spacing: Box.pair) {
            if pane == .files {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 2) {
                            ForEach(mine) { tab in PaneTab(panel: panel, tab: tab, closable: tab.kind != .files).id(tab.id) }
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: panel.front[pane]) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            } else {
                Text(pane.title).font(F.font(13, .medium)).foregroundStyle(C.i12).padding(.leading, 10)
                Spacer(minLength: 0)
            }
            paneButtons
        }
        .padding(.horizontal, Box.pad)
        .frame(height: first ? 56 : Bar.height)
    }
}

/// Browser's tabs, as Chrome's in the app's colours: they share the strip's width (up to 200 each), a new one grows in
/// from nothing and a closed one shrinks away (0.2 s, Chrome's ease-out) while the others make room; closing with the
/// pointer on the strip holds the others' width until it leaves, so the next × is under the pointer. The tab in front
/// is the page's colour and joins it, its bottom corners curving out; thin lines part the others.
private struct BrowserStrip: View {
    @ObservedObject var panel: SidePanel
    let tabs: [PanelTab]
    /// What + opens: a new tab here (a page, or a shell).
    var new: () -> Void = {}
    /// The tab's height: its body and the neck that joins the surface under it.
    var height: CGFloat = 48
    /// The surface the tab in front shares (the browser's toolbar, the terminal's screen).
    var surface: Color = C.v2
    @State private var frozen: CGFloat?
    @State private var hover: String?
    /// The tab's body (where its title and × sit, centred on the header buttons' line) and the neck below it.
    static let body: CGFloat = 40, neck: CGFloat = 8
    static let maxWidth: CGFloat = 200, minWidth: CGFloat = 40, plus: CGFloat = 40
    static let motion = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)
    var body: some View {
        GeometryReader { g in
            let fit = min(Self.maxWidth, max(Self.minWidth, (g.size.width - Self.plus) / CGFloat(max(tabs.count, 1))))
            let w = min(frozen ?? fit, fit)
            let front = panel.front[.browser]
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.key) { i, tab in
                        let on = tab.id == front
                        let next = i + 1 < tabs.count ? tabs[i + 1] : nil
                        let line = !on && hover != tab.key && next.map { $0.id != front && hover != $0.key } ?? true
                        ChromeTab(panel: panel, tab: tab, on: on, width: w, height: height, surface: surface, line: line, hover: Binding(get: { hover == tab.key }, set: { hover = $0 ? tab.key : (hover == tab.key ? nil : hover) })) {
                            frozen = w
                            panel.close(tab.id)
                        }
                        .modifier(Grow(p: 1, w: w))
                        .transition(.asymmetric(insertion: .modifier(active: Grow(p: 0, w: w), identity: Grow(p: 1, w: w)),
                                                removal: .modifier(active: Grow(p: 0, w: w), identity: Grow(p: 1, w: w))))
                        .zIndex(on ? 1 : 0)
                    }
                    Hover { h in
                        Button { new() } label: {
                            Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(h ? C.i12 : C.i10)
                                .frame(width: Bar.control, height: Bar.control)
                                .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(h ? C.v1 : .clear))
                                .contentShape(Rectangle())
                        }.buttonStyle(Press())
                    }
                    .tip("New tab", "⌘T")
                    .padding(.leading, Box.pair).frame(height: Self.body)
                    Spacer(minLength: 0)
                }
                .frame(height: height, alignment: .top)
                .animation(Self.motion, value: tabs.map(\.key))
                .animation(Self.motion, value: w)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .frame(height: height)
        .onHover { inside in if !inside, frozen != nil { withAnimation(Self.motion) { frozen = nil } } }
    }
}

/// A tab's width while it grows in or shrinks away (p: 0 → 1), its content held at full width and cut off.
private struct Grow: ViewModifier, Animatable {
    var p: CGFloat
    let w: CGFloat
    var animatableData: CGFloat { get { p } set { p = newValue } }
    // Cut to its width, but not its foot: the front tab's curves reach a flare's width past each side.
    func body(content: Content) -> some View { content.frame(width: max(0, w * p), alignment: .leading).mask(Rectangle().padding(.horizontal, -TabShape.flare)) }
}

/// One of Browser's tabs: the site's icon (a turning ring while it loads), the title fading out at its end, ×.
private struct ChromeTab: View {
    @ObservedObject var panel: SidePanel
    let tab: PanelTab
    let on: Bool
    let width: CGFloat
    let height: CGFloat
    let surface: Color
    /// The thin line at its end (not beside the tab in front or the one you're on).
    let line: Bool
    @Binding var hover: Bool
    let close: () -> Void
    var body: some View {
        let showClose = on || width >= 92
        HStack(spacing: 8) {
            TabFace(panel: panel, tab: tab).frame(width: 16, height: 16)
            if width >= 64 || !on {
                // The title from its start, running out under a fade at the tab's end (as Chrome's), never cut at the front.
                Color.clear.frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                    .overlay(alignment: .leading) {
                        TabTitle(panel: panel, tab: tab).font(F.font(12, .medium)).foregroundStyle(on || hover ? C.i12 : C.i10)
                            .lineLimit(1).fixedSize()
                    }
                    .clipped()
                    .mask(HStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18) })
            }
            if showClose {
                Hover { h in
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(h ? C.i12 : C.i10)
                            .frame(width: 20, height: 20).background(Circle().fill(h ? Color.white(0.1) : .clear)).contentShape(Circle())
                    }.buttonStyle(Press())
                }
            }
        }
        // 12 in from its left, 8 from its right (× sits optically square to the corner), all on the body's centre line.
        .padding(.leading, 12).padding(.trailing, Box.pad)
        .frame(width: width, height: BrowserStrip.body)
        .frame(height: height, alignment: .top)
        .background(alignment: .top) {
            if on {
                // The tab and what's under it are one surface: rounded at the top, its foot curving out into it.
                TabShape().fill(surface).padding(.horizontal, -TabShape.flare)
            } else if hover {
                RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(C.v1)
                    .frame(height: Bar.control).padding(.horizontal, 2).padding(.top, (BrowserStrip.body - Bar.control) / 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            Rectangle().fill(C.v4).frame(width: 1, height: 16).padding(.top, (BrowserStrip.body - 16) / 2).opacity(line ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { panel.select(tab.id) }
        .onHover { hover = $0 }
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton).accessibilityLabel(tab.title)
    }
}

/// MAVIS tabs (spec 8): pills 30 tall on the pane header. The tab in front sits on box2; others light on hover. Each
/// shows its icon and title; ✕ in front or on hover. Then + for a new tab.
struct MVTabStrip: View {
    @ObservedObject var panel: SidePanel
    let tabs: [PanelTab]
    /// What + opens; nil: no + (Files opens files from its tree).
    let new: (() -> Void)?
    /// Chrome: after you close a tab with the pointer on the strip, the tabs keep their width until the pointer
    /// leaves, so the next ✕ lands under it and you can close tab after tab without chasing them.
    @State private var frozen: CGFloat?
    /// The tab under the pointer: the separators on both its sides fade out with its hover.
    @State private var hovered: String?
    var body: some View {
        // As Chrome's: tabs share the strip's width (176 at most), narrowing as you add more; + stays right after
        // the last one and never leaves the strip. Thin lines part the tabs that aren't in front.
        GeometryReader { g in
            let plus = new == nil ? 0 : MV.Size.iconButton + MV.Space.sm
            let n = CGFloat(max(tabs.count, 1))
            let gaps = MV.Browser.tabGap * (n - 1)
            let fit = max(MV.Browser.tabMin, min(MV.Size.browserTab.width, floor((g.size.width - plus - gaps) / n)))
            let w = min(frozen ?? fit, fit)
            let front = tabs.first { panel.front[$0.pane] == $0.id }?.id
            // More tabs than fit at their narrowest: they scroll sideways, and + stays at the end, always seen.
            let overflow = n * MV.Browser.tabMin + gaps > g.size.width - plus
            HStack(spacing: MV.Browser.tabGap) {
            ScrollView(.horizontal) {
            HStack(spacing: MV.Browser.tabGap) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                    let next = i + 1 < tabs.count ? tabs[i + 1].id : nil
                    MVTab(panel: panel, tab: tab, width: w, close: {
                        frozen = w
                        panel.close(tab.id)
                    }, hovering: { h in
                        if h { hovered = tab.id } else if hovered == tab.id { hovered = nil }
                    })
                    .overlay(alignment: .trailing) {
                        // Chrome's separator: only between two tabs that aren't in front, and gone beside the one
                        // under the pointer (fading with its hover).
                        if let next {
                            let hide = tab.id == front || next == front || hovered == tab.id || hovered == next
                            Rectangle().fill(MV.Tone.line).frame(width: MV.Stroke.boxRestWidth, height: MV.Browser.separator)
                                .offset(x: (MV.Browser.tabGap + MV.Stroke.boxRestWidth) / 2)   // centred in the gap
                                .opacity(hide ? 0 : 1)
                                .animation(hovered == nil ? MV.Motion.tabHoverOut : MV.Motion.tabHoverIn, value: hovered)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            }
            .scrollDisabled(!overflow).scrollIndicators(.never)
            .frame(maxWidth: overflow ? g.size.width - plus : nil, alignment: .leading)
            .fixedSize(horizontal: !overflow, vertical: false)
                if let new {
                    let full = panel.browserFull && tabs.first?.pane == .browser
                    MVIconButton(icon: "mvPlus", label: full ? "15 tabs is the most" : "New tab") { frozen = nil; new() }
                        .opacity(full ? MV.Browser.disabled : 1).disabled(full)
                }
                Spacer(minLength: 0)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .leading)
            .clipped()
        }
        .frame(height: MV.Size.browserTab.height)
        .contentShape(Rectangle())
        .onHover { if !$0 { frozen = nil } }
        .transaction { $0.animation = nil }
    }
}

/// A pane's title (prototype .sp-h): 16 icon in t2, the name 13 medium, a quiet 12 line after it; 6 in from the
/// header's 8, so it starts 14 from the pane's edge.
struct MVPaneTitle: View {
    let icon: String; let title: String; let meta: String?
    var body: some View {
        HStack(spacing: MV.Space.labelGap) {
            Icon(icon, MV.Size.iconSmall).foregroundStyle(MV.Ink.t2)
            Text(title).font(F.font(MV.Text.footer, .medium)).foregroundStyle(MV.Ink.t1)
            if let meta { Text(meta).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3).lineLimit(1).truncationMode(.middle) }
        }
        .padding(.leading, MV.Space.sm)
    }
}
private struct MVTab: View {
    @ObservedObject var panel: SidePanel
    let tab: PanelTab
    let width: CGFloat
    let close: () -> Void
    var hovering: (Bool) -> Void = { _ in }
    @State private var hover = false
    var body: some View {
        let on = panel.front[tab.pane] == tab.id
        let shape = Capsule()
        // Chrome's steps as the tab narrows: the title goes first (fading at its end, never "…"), then ✕ on the
        // tabs that aren't in front; the narrowest tab in front shows only its ✕. Every part has a set width
        // worked out here, so nothing can spill past the tab's edge.
        let closable = tab.kind != .files
        let showsTitle = width >= MV.Browser.tabTitleMin
        let showsClose = closable && (on ? true : width >= MV.Browser.tabCloseMin && (hover || width >= MV.Browser.tabCloseAlways))
        let closeOnly = !showsTitle && on && closable
        let lead: CGFloat = MV.Space.gridGap, trail: CGFloat = MV.Space.sm
        let slot = MV.Browser.closeSlot
        let titleW = max(0, width - lead - MV.Size.iconSmall - MV.Space.labelGap - (showsClose ? slot + MV.Space.xs : 0) - trail)
        ZStack {
            if closeOnly {
                closeButton(slot)
            } else if !showsTitle {
                TabFace(panel: panel, tab: tab).frame(width: MV.Size.iconSmall, height: MV.Size.iconSmall)
            } else {
                HStack(spacing: 0) {
                    TabFace(panel: panel, tab: tab).frame(width: MV.Size.iconSmall, height: MV.Size.iconSmall)
                    TabTitle(panel: panel, tab: tab).font(F.font(MV.Browser.tabText, .regular)).foregroundStyle(MV.Ink.t1)
                        .lineLimit(1).fixedSize()
                        .frame(width: titleW, alignment: .leading)
                        .clipped()
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: MV.Browser.fadeFrom),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .padding(.leading, MV.Space.labelGap)
                    if showsClose { closeButton(slot).padding(.leading, MV.Space.xs) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, lead).padding(.trailing, trail)
            }
        }
        .frame(width: width, height: MV.Size.browserTab.height)
        .background(shape.fill(on ? MV.Tone.box2 : .clear))
        .overlay(shape.fill(MV.Wash.stHover).opacity(hover && !on ? 1 : 0)
                    .animation(hover ? MV.Motion.tabHoverIn : MV.Motion.tabHoverOut, value: hover).allowsHitTesting(false))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { panel.select(tab.id) }
        .onHover { hover = $0; hovering($0) }
        .help(tab.title)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton).accessibilityLabel(tab.title)
    }
    private func closeButton(_ slot: CGFloat) -> some View {
        Button(action: close) {
            Icon("mvClose", MV.Size.iconSmall - MV.Space.rowGap).foregroundStyle(MV.Ink.t2)
                .frame(width: slot, height: slot).contentShape(Circle())
        }
        .buttonStyle(MVStates(shape: Circle()))
        .accessibilityLabel("Close tab")
    }
}

/// The tab in front: rounded at the top, its bottom corners curving out into the page under it.
struct TabShape: Shape {
    static let flare: CGFloat = 8
    func path(in r: CGRect) -> Path {
        let f = Self.flare, c = R.ctl, w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: f, y: h - f), control: CGPoint(x: f, y: h))
        p.addLine(to: CGPoint(x: f, y: c))
        p.addQuadCurve(to: CGPoint(x: f + c, y: 0), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: w - f - c, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - f, y: c), control: CGPoint(x: w - f, y: 0))
        p.addLine(to: CGPoint(x: w - f, y: h - f))
        p.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w - f, y: h))
        p.closeSubpath()
        return p
    }
}

/// A tab's icon: a page's own (a turning ring while it loads), else the tab's.
private struct TabFace: View {
    @ObservedObject var panel: SidePanel
    let tab: PanelTab
    var body: some View {
        // Only a page that already exists: drawing a tab never builds (and loads) one.
        if case .web(let id) = tab.kind, let page = BrowserPage.existing(id) { WebFace(page: page) }
        else if case .web = tab.kind { Icon("mvGlobe", MV.Size.iconSmall).foregroundStyle(MV.Ink.t3) }
        else { TabIcon(name: tab.icon, size: 14).foregroundStyle(C.i10) }
    }
}
private struct WebFace: View {
    @ObservedObject var page: BrowserPage
    var body: some View {
        if page.loading && page.favicon == nil { StepMark(state: "running") }
        else if let f = page.favicon { Image(nsImage: f).resizable().interpolation(.high).scaledToFit().clipShape(RoundedRectangle(cornerRadius: 3)) }
        else { Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(C.i10) }
    }
}

/// A tab in a pane's header, as a browser's: its icon and title; in front it sits on a fill; × on hover (and in front).
private struct PaneTab: View {
    @ObservedObject var panel: SidePanel
    let tab: PanelTab
    let closable: Bool
    @State private var hover = false
    var body: some View {
        let on = panel.front[tab.pane] == tab.id
        HStack(spacing: 6) {
            TabIcon(name: tab.icon, size: 14).foregroundStyle(on || hover ? C.i12 : C.i10)
            TabTitle(panel: panel, tab: tab).font(F.font(13, .medium)).foregroundStyle(on || hover ? C.i12 : C.i10)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 160, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            if closable {
                ZStack {
                    if case .file(let path) = tab.kind, let doc = panel.docs[path] { DirtyDot(doc: doc, hidden: hover) }
                    Button { panel.close(tab.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(C.i10).frame(width: 18, height: 18)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white(0.06)).opacity(hover ? 1 : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).opacity(hover || on ? 1 : 0).tip("Close tab")
                }
            }
        }
        .padding(.leading, 10).padding(.trailing, closable ? 6 : 10).frame(height: Bar.control)
        .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(on ? C.v3 : hover ? C.v2 : .clear))
        .contentShape(Rectangle())
        .onTapGesture { panel.select(tab.id) }
        .onHover { hover = $0 }
        .accessibilityAddTraits(.isButton).accessibilityLabel(tab.title)
    }
}

/// A file tab's unsaved-edits dot, where its × is (the × shows on hover instead).
private struct DirtyDot: View {
    @ObservedObject var doc: FileDoc
    let hidden: Bool
    var body: some View {
        if doc.dirty && !hidden {
            Circle().fill(C.i12).frame(width: 7, height: 7).frame(width: 18, height: 18)
                .accessibilityLabel("Not saved")
        }
    }
}

/// A question over the panel, for what can't be undone: title, detail, then Cancel and the answer (and a second
/// answer, as Don't save). Esc cancels, Return confirms.
struct PanelConfirm: View {
    let title: String; let detail: String; let confirm: String; var danger = true; var other: String? = nil
    let onConfirm: () -> Void; var onOther: () -> Void = {}; let onCancel: () -> Void
    var body: some View {
        ZStack {
            C.v0.opacity(0.5).contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 8) {
                Line(title, 14, .semibold)
                Text(detail).font(F.font(13, .regular)).foregroundStyle(C.i10).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let other { SecondaryButton(title: other, action: onOther) }
                    Spacer(minLength: 0)
                    SecondaryButton(title: "Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                    if danger { DangerButton(title: confirm, action: onConfirm).keyboardShortcut(.defaultAction) }
                    else { PrimaryButton(title: confirm, action: onConfirm).keyboardShortcut(.defaultAction) }
                }
                .padding(.top, 8)
            }
            .padding(16).frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: R.card, style: .continuous).fill(C.v1))
            .overlay(RoundedRectangle(cornerRadius: R.card, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
            .floatShadow()
            .padding(16)
        }
    }
}

/// The edge between the chat and the panel, as the sidebar's (SplitHandle): a 12 wide grip over the 1 pt line, which
/// lights while you're on it, with the ↔ knob; drag to resize, double-click for the standard width.
private struct PanelGrip: View {
    let drag: (CGFloat) -> Void
    let end: () -> Void
    let reset: () -> Void
    @State private var hover = false
    @State private var dragging = false
    var body: some View {
        let lit = hover || dragging
        ZStack {
            Rectangle().fill(dragging ? C.i10 : lit ? C.v6 : C.v4).frame(width: 1)
            if lit { ResizeKnob(active: dragging) }
        }
        .frame(width: 12)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in dragging = true; drag(g.translation.width) }
                .onEnded { _ in dragging = false; end() }
        )
        .onTapGesture(count: 2) { reset() }
        .tip("Drag to resize", "Double-click to reset", edge: .leading)
        .accessibilityElement()
        .accessibilityLabel("Resize the side panel")
        .accessibilityAction(named: "Reset size") { reset() }
    }
}

// MARK: Files

/// The Files tab's state, owned by the panel so it outlives the tab's view: which folders are open, the filter, each
/// folder's listing (read once, then kept until Refresh), git's marks.
@MainActor final class FilesModel: ObservableObject {
    let folder: String
    @Published var expanded: Set<String> = []
    @Published var filter = ""
    @Published private(set) var marks: [String: String] = [:]
    /// Folders that hold a changed file (for the dot on a folder).
    @Published private(set) var dirty: Set<String> = []
    private var listings: [String: [Item]] = [:]
    private var loadedGit = false
    init(folder: String) { self.folder = folder }

    struct Item: Hashable { let path: String; let name: String; let folder: Bool }
    nonisolated static let skip: Set<String> = [".git", "node_modules", ".build", "DerivedData", ".DS_Store", ".next", "Pods", ".venv", "__pycache__"]

    func children(_ folder: String) -> [Item] {
        if let l = listings[folder] { return l }
        let l = Self.read(folder)
        listings[folder] = l
        return l
    }
    nonisolated static func read(_ folder: String) -> [Item] {
        let url = URL(fileURLWithPath: folder)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])) ?? []
        return urls.compactMap { u -> Item? in
            let name = u.lastPathComponent
            guard !skip.contains(name) else { return nil }
            let v = try? u.resourceValues(forKeys: Set(keys))
            return Item(path: u.path, name: name, folder: v?.isDirectory == true && v?.isPackage != true)
        }
        .sorted { a, b in a.folder != b.folder ? a.folder : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }
    func toggle(_ path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { _ = children(path); expanded.insert(path) }
    }
    /// Opens every folder from the top down to `path` (a folder inside this one), so it shows in the tree.
    func reveal(_ path: String) {
        let base = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        guard path.hasPrefix(base + "/") else { return }
        var at = base
        for part in path.dropFirst(base.count + 1).split(separator: "/") {
            at += "/" + part
            _ = children(at); expanded.insert(at)
        }
    }
    func appeared() { if !loadedGit { loadedGit = true; loadGit() } }
    func refresh() { listings = [:]; objectWillChange.send(); loadGit() }
    /// Something changed files (a turn ended, a commit): re-read the open folders and git's marks, once the tab was seen.
    func changed() {
        guard loadedGit else { return }
        pending?.cancel()
        pending = Task { try? await Task.sleep(for: .milliseconds(250)); if !Task.isCancelled { refresh() } }
    }
    private var pending: Task<Void, Never>?
    private func loadGit() {
        let folder = folder
        Task.detached(priority: .utility) {
            let root = GitMarks.run(["-C", folder, "rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !root.isEmpty else { return }
            let out = GitMarks.run(["-C", folder, "status", "--porcelain=v1", "-z", "--untracked-files=normal"])
            var found: [String: String] = [:], dirs: Set<String> = []
            for entry in out.split(separator: "\0") where entry.count > 3 {
                let code = String(entry.prefix(2)).trimmingCharacters(in: .whitespaces)
                let full = (root as NSString).appendingPathComponent(String(entry.dropFirst(3)))
                found[full] = code == "??" ? "?" : String(code.prefix(1))
                var d = (full as NSString).deletingLastPathComponent
                while d.count > 1, d.hasPrefix(root), dirs.insert(d).inserted { d = (d as NSString).deletingLastPathComponent }
            }
            let marks = found, folders = dirs
            await MainActor.run { self.marks = marks; self.dirty = folders }
        }
    }
}

enum GitMarks {
    nonisolated static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// The agent's folder as a tree: folders open in place; a click on a file opens it in its own tab.
struct FilesTab: View {
    @ObservedObject var panel: SidePanel
    @ObservedObject var model: FilesModel
    @ViewBuilder var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS (prototype .ftree): the tree alone on the pane (⌘P still finds a file by name); rows 32, 2 apart,
    /// padding 4 8 8.
    private var mavis: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: MV.Files.rowGap) {
                ForEach(visible, id: \.0.path) { item, depth in
                    if item.folder { MVFolderRow(model: model, item: item, depth: depth) }
                    else { MVFileRow(panel: panel, path: item.path, depth: depth, mark: model.marks[item.path]) }
                }
            }
            .padding(MV.Files.treePad)
        }
        .scrollIndicators(.never)
        .background(MV.Tone.page)
        .onAppear { model.appeared() }
    }
    private var classic: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon("search", 14).foregroundStyle(C.i10)
                TextField("", text: $model.filter, prompt: Text("Filter files").foregroundStyle(C.i9))
                    .textFieldStyle(.plain).font(F.font(13, .regular)).foregroundStyle(C.i12)
                Hover { h in
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .regular)).foregroundStyle(h ? C.i12 : C.i10)
                    }.buttonStyle(.plain)
                }.tip("Refresh")
            }
            .padding(.horizontal, 10).frame(height: Bar.control)
            .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(C.v2))
            .padding(Box.pad)
            Text((panel.folder as NSString).abbreviatingWithTildeInPath).font(F.font(11, .medium)).foregroundStyle(C.i9)
                .lineLimit(1).truncationMode(.head).padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.filter.isEmpty {
                        ForEach(visible, id: \.0.path) { item, depth in
                            if item.folder { FolderRow(model: model, item: item, depth: depth) }
                            else { FileRow(panel: panel, path: item.path, depth: depth, detail: nil, mark: model.marks[item.path]) }
                        }
                    } else {
                        ForEach(FileIndex.shared.search(model.filter, in: panel.folder).filter { !$0.hasSuffix("/") }, id: \.self) { rel in
                            let full = (panel.folder as NSString).appendingPathComponent(rel)
                            FileRow(panel: panel, path: full, depth: 0, detail: (rel as NSString).deletingLastPathComponent, mark: model.marks[full])
                        }
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
        .onAppear { model.appeared() }
    }
    /// The tree flattened to the rows on show (open folders' children under them), so the list is one lazy run.
    private var visible: [(FilesModel.Item, Int)] {
        var out: [(FilesModel.Item, Int)] = []
        func add(_ folder: String, _ depth: Int) {
            for item in model.children(folder) {
                out.append((item, depth))
                if item.folder, model.expanded.contains(item.path) { add(item.path, depth + 1) }
            }
        }
        add(panel.folder, 0)
        return out
    }
}

/// MAVIS tree rows (prototype .fr): 32 tall, fully round, 8 apart inside, 20 per level; hover white 7%, the open
/// file white 10% with t1 words; the chevron turns over when the folder is shut.
private struct MVFolderRow: View {
    @ObservedObject var model: FilesModel
    let item: FilesModel.Item; let depth: Int
    @State private var hover = false
    var body: some View {
        let open = model.expanded.contains(item.path)
        HStack(spacing: MV.Space.labelGap) {
            Icon("mvChevDown", MV.Files.chevron).foregroundStyle(MV.Ink.t3).rotationEffect(.degrees(open ? 0 : -90))
            Icon("mvFold", MV.Size.icon).foregroundStyle(MV.Ink.t3)
            Text(item.name).font(F.font(MV.Files.text, .regular)).foregroundStyle(MV.Ink.t2).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, MV.Files.lead + CGFloat(depth) * MV.Files.indent).padding(.trailing, MV.Files.trail)
        .frame(height: MV.Files.row)
        .background(Capsule().fill(hover ? MV.Wash.hover : .clear))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { model.toggle(item.path) }
        .accessibilityAddTraits(.isButton).accessibilityLabel(item.name)
    }
}
private struct MVFileRow: View {
    @ObservedObject var panel: SidePanel
    let path: String; let depth: Int; let mark: String?
    @State private var hover = false
    var body: some View {
        let on = panel.isFront("file:" + path)
        HStack(spacing: MV.Space.labelGap) {
            Color.clear.frame(width: MV.Files.chevron, height: MV.Files.chevron)
            Icon("mvFile", MV.Size.icon).foregroundStyle(on ? MV.Ink.t1 : MV.Ink.t3)
            Text((path as NSString).lastPathComponent).font(F.font(MV.Files.text, .regular)).foregroundStyle(on ? MV.Ink.t1 : MV.Ink.t2).lineLimit(1)
            Spacer(minLength: 0)
            if let mark {
                let added = mark == "A" || mark == "?"
                Text(mark == "?" ? "U" : mark).font(F.font(MV.Files.badgeText, .medium)).foregroundStyle(MV.Accent.onTag)
                    .padding(.horizontal, MV.Files.badgePad).frame(minWidth: MV.Size.badge, minHeight: MV.Size.badge)
                    .background(Capsule().fill(added ? MV.Files.badgeAdded : MV.Files.badgeChanged))
                    .help(GitWords.name(mark))
            }
        }
        .padding(.leading, MV.Files.lead + CGFloat(depth) * MV.Files.indent).padding(.trailing, MV.Files.trail)
        .frame(height: MV.Files.row)
        .background(Capsule().fill(on ? MV.Wash.selectedRow : hover ? MV.Wash.hover : .clear))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { panel.openFile(path) }
        .accessibilityAddTraits(.isButton).accessibilityLabel((path as NSString).lastPathComponent)
    }
}

private struct FolderRow: View {
    @ObservedObject var model: FilesModel
    let item: FilesModel.Item; let depth: Int
    @State private var hover = false
    var body: some View {
        let open = model.expanded.contains(item.path)
        HStack(spacing: 6) {
            Icon("chev", 10).foregroundStyle(C.i9).rotationEffect(.degrees(open ? 0 : -90)).frame(width: 12)
            Icon("folder", 14).foregroundStyle(C.i10)
            Text(item.name).font(F.font(13, .regular)).foregroundStyle(C.i12).lineLimit(1)
            if model.dirty.contains(item.path) { Circle().fill(C.i10).frame(width: 5, height: 5) }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8 + CGFloat(depth) * 14).padding(.trailing, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? C.v3 : .clear)).contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.toggle(item.path) }
        .accessibilityAddTraits(.isButton).accessibilityLabel(item.name)
    }
}

/// A file: its name (and folder, when filtered) and its git mark. One click opens it in a tab of its own (or brings
/// its tab to the front); there's no double-click to wait for.
private struct FileRow: View {
    @ObservedObject var panel: SidePanel
    let path: String; let depth: Int; let detail: String?; let mark: String?
    @State private var hover = false
    var body: some View {
        let on = panel.isFront("file:" + path)
        HStack(spacing: 6) {
            Color.clear.frame(width: 12)
            Icon("file", 13).foregroundStyle(C.i9)
            Text((path as NSString).lastPathComponent).font(F.font(13, .regular)).foregroundStyle(C.i12).lineLimit(1)
            if let detail, !detail.isEmpty { Text(detail).font(F.font(11, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.head) }
            Spacer(minLength: 4)
            if let mark { Text(mark == "?" ? "U" : mark).font(F.font(11, .semibold)).foregroundStyle(C.i10).help(GitWords.name(mark)) }
        }
        .padding(.leading, 8 + CGFloat(depth) * 14).padding(.trailing, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? C.v4 : hover ? C.v3 : .clear)).contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { panel.openFile(path) }
        .accessibilityAddTraits(.isButton).accessibilityLabel((path as NSString).lastPathComponent)
    }
}

enum GitWords {
    static func name(_ mark: String) -> String {
        switch mark { case "M": "Changed"; case "A": "Added"; case "D": "Deleted"; case "R": "Renamed"; case "?": "New, not in git yet"; default: "Changed" }
    }
}

// MARK: A file

/// A file in a tab: its path and actions on top, then its words in the editor (line numbers, colours), or a preview
/// for Markdown and pictures. ⌘F finds, ⌘S saves, ⌘L puts the selected lines in the message box.
struct FileTab: View {
    @ObservedObject var panel: SidePanel
    @ObservedObject var doc: FileDoc
    @State private var preview = true
    @State private var finding = false
    @State private var query = ""
    var path: String { doc.path }
    var body: some View {
        let on = panel.isFront("file:" + path)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath + "/")
                    .font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.head)
                Text((path as NSString).lastPathComponent).font(F.font(12, .medium)).foregroundStyle(C.i12).lineLimit(1)
                if let notice = doc.notice { Text(notice).font(F.font(11, .regular)).foregroundStyle(C.i9).lineLimit(1) }
                Spacer(minLength: 8)
                if doc.selection != nil && !(doc.isMarkdown && preview) {
                    small("Add to message") { addSelection() }.tip("Put these lines in the message", "⌘L")
                }
                if doc.isMarkdown {
                    small(preview ? "Edit" : "Preview") {
                        // Into the preview: the keyboard leaves the hidden editor, so typing can't change it unseen.
                        if !preview, let e = doc.editor, e.window?.firstResponder === e { e.window?.makeFirstResponder(nil) }
                        doc.syncText(); preview.toggle()
                    }
                }
                if doc.editable && doc.dirty { small("Save") { doc.save() }.tip("Save", "⌘S") }
                if !doc.isImage { small("Find") { finding.toggle() }.tip("Find in file", "⌘F") }
                small("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                small("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }
            .padding(.leading, 12).padding(.trailing, Box.pad).frame(height: Bar.height)
            if doc.conflict { conflictBar }
            if let e = doc.saveError {
                Text(e).font(F.font(12, .regular)).foregroundStyle(FAIL_TEXT).padding(.horizontal, 12).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let why = doc.readOnly {
                Text(why).font(F.font(11, .regular)).foregroundStyle(C.i9).padding(.horizontal, 12).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if finding {
                HStack(spacing: 8) {
                    Icon("search", 13).foregroundStyle(C.i10)
                    TextField("", text: $query, prompt: Text("Find in file").foregroundStyle(C.i9))
                        .textFieldStyle(.plain).font(F.font(13, .regular)).foregroundStyle(C.i12)
                        .onExitCommand { finding = false; query = "" }
                    if !query.isEmpty {
                        Text(doc.matches == 1 ? "1 match" : "\(doc.matches) matches").font(F.font(11, .regular)).foregroundStyle(C.i9).monospacedDigit()
                    }
                }
                .padding(.horizontal, 10).frame(height: Bar.control)
                .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(C.v2))
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
            Rectangle().fill(C.divider).frame(height: 1)
            Group {
                if let image = doc.image {
                    ScrollView([.vertical, .horizontal]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 900).padding(16) }
                } else if let problem = doc.problem {
                    Line(problem, 13, .regular, C.i10).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if doc.styled != nil {
                    ZStack {
                        // The editor stays built under the preview, so your edits and undo survive switching.
                        CodeEditor(doc: doc, find: query).opacity(doc.isMarkdown && preview ? 0 : 1)
                        if doc.isMarkdown && preview, let text = doc.text {
                            ScrollView { MarkdownText(text: text, color: Color.white(0.82)).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                                .background(C.v1)
                        }
                    }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            // Only the tab in front answers these (the others are disabled).
            Group {
                Button("") { if doc.editable { doc.save() } }.keyboardShortcut("s", modifiers: .command)
                Button("") { addSelection() }.keyboardShortcut("l", modifiers: .command)
                Button("") { if !doc.isImage { finding.toggle() } }.keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false)
        }
        .onChange(of: on) { _, now in if now { doc.checkDisk() } }
    }

    /// The file changed on disk while you have edits.
    private var conflictBar: some View {
        HStack(spacing: 8) {
            Text("It changed on disk since you opened it.").font(F.font(12, .medium)).foregroundStyle(C.i12).lineLimit(2)
            Spacer(minLength: 4)
            small("Reload") { doc.load() }.tip("Take what's on disk; your edits are lost")
            small("Keep mine") { doc.keepMine() }.tip("Keep editing; saving writes over it")
            small("Overwrite") { doc.save(force: true) }.tip("Save your edits over it now")
        }
        .padding(.leading, 12).padding(.trailing, 4).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(C.v3))
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    /// The selected lines into the agent's box: `path:12-18`, then the lines in a fence.
    private func addSelection() {
        guard let r = doc.selection, let text = doc.current, !(doc.isMarkdown && preview) else { return }
        let lines = text.components(separatedBy: "\n")
        guard r.lowerBound >= 1, r.lowerBound <= lines.count else { return }
        let body = lines[(r.lowerBound - 1)..<min(r.upperBound, lines.count)].joined(separator: "\n")
        let rel = panel.relative(path)
        let at = r.lowerBound == r.upperBound ? "\(rel):\(r.lowerBound)" : "\(rel):\(r.lowerBound)-\(r.upperBound)"
        AddToMessage.send(panel.agentId, Fence.wrap(at: at, body: body, language: doc.ext))
    }

    private func small(_ title: String, _ action: @escaping () -> Void) -> some View { ToolText(title: title, action: action) }
}

/// Lines for the message box: where they're from, then the lines fenced (a longer fence if they hold one).
enum Fence {
    static func wrap(at: String, body: String, language: String) -> String {
        var fence = "```"
        while body.contains(fence) { fence += "`" }
        return "`\(at)`\n\(fence)\(language)\n\(body)\n\(fence)"
    }
}

/// The panel's tools, as Claude Code's: one click opens Files, Changes, Terminal or Browser (the one in front is lit),
/// then the panel's own button. They sit at the window's right edge: in the chat's header while the panel is hidden,
/// in the panel's header while it shows (the chat's header leaves them to it), so they're always in the same place.
struct PanelTools: View {
    @ObservedObject var panel: SidePanel
    /// Changes only exist in a workspace (its channels); a chat with an agent has browser, terminal and files.
    var changes = false
    /// From the window's edge, as the top bar's buttons.
    static let trailing: CGFloat = 11
    var body: some View {
        if MV.on {
            // MAVIS: four 28 pt round buttons with 18 pt icons; the open panes are lit.
            HStack(spacing: MV.Space.xs) {
                mvTool(.terminal, "mvTerm")
                if changes { mvTool(.changes, "mvDiff") }
                mvTool(.browser, "mvGlobe"); mvTool(.files, "mvFolder")
            }
        } else {
            HStack(spacing: Box.pair) {
                tool(.terminal, "terminal")
                tool(.changes, "plus.forwardslash.minus")
                tool(.browser, "globe")
                tool(.files, "folder")
            }
        }
    }
    private func mvTool(_ p: SidePanel.Pane, _ icon: String) -> some View {
        MVIconButton(icon: icon, label: p.title, on: panel.isShowing(p)) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { panel.togglePane(p) }
        }
    }
    private func tool(_ p: SidePanel.Pane, _ icon: String) -> some View {
        BarButton(icon: icon, label: p.title, lit: panel.isShowing(p), quiet: true) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { panel.togglePane(p) }
        }
    }
}

/// A tab's title: a page's own title (its address while it has none), else the tab's.
private struct TabTitle: View {
    @ObservedObject var panel: SidePanel
    let tab: PanelTab
    var body: some View {
        if case .web(let id) = tab.kind { WebTabTitle(page: BrowserPage.of(panel, id)) }
        else if case .terminal(let key) = tab.kind { TerminalTitle(session: TerminalSession.of(panel, key: key)) }
        else { Text(tab.title) }
    }
}
private struct TerminalTitle: View {
    @ObservedObject var session: TerminalSession
    var body: some View { Text(session.title) }
}
private struct WebTabTitle: View {
    @ObservedObject var page: BrowserPage
    var body: some View { Text(Self.words(title: page.title, url: page.url)) }
    /// What a tab says, as Chrome's: the page's title; while there's none (loading), or when the "title" is only its
    /// address, the site's name (google.com), never the address itself.
    static func words(title: String, url: URL?) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressy = t.contains("://") || t.hasPrefix("www.") || (url.map { t == $0.absoluteString || t == $0.host() } ?? false)
        if !t.isEmpty, !addressy { return t }
        if let host = url?.host(), !host.isEmpty { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        if url?.isFileURL == true { return url?.lastPathComponent ?? "File" }
        return "New tab"
    }
}

/// A 40 pt control in a header, the chat box's button size, corners and fill: resting on a fill (lit a step brighter),
/// or `quiet` (no fill until you're on it, for a row of tools). Our icons by name; anything else an SF Symbol.
struct BarButton: View {
    let icon: String; let label: String; var keys: String? = nil; var lit = false; var quiet = false
    let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                TabIcon(name: icon, size: 18)
                    .foregroundStyle(h || lit ? C.i12 : C.i10).frame(width: quiet ? 36 : 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(lit ? C.v4 : h ? (quiet ? C.v3 : C.v4) : quiet ? .clear : C.v3))
                    .contentShape(Rectangle())
            }.buttonStyle(Press())
        }
        .tip(label, keys).accessibilityLabel(label)
    }
}

/// One of our drawn icons by name, else an SF Symbol drawn to sit at the same size and weight.
struct TabIcon: View {
    let name: String; let size: CGFloat
    var body: some View {
        if IconData.all[name] != nil || MavisIconData.all[name] != nil { Icon(name, size) }
        else { Image(systemName: name).font(.system(size: size * 0.86, weight: .regular)).frame(width: size, height: size) }
    }
}


/// The side column's width, one for every chat (each kept its own and jumped as you switched).
@MainActor final class PanelWidth: ObservableObject {
    static let shared = PanelWidth()
    @Published var w: CGFloat? = SidePanel.mavisWidth
}

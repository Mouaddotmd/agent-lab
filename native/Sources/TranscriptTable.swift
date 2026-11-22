// The conversation's list, as Messages and Telegram build theirs on the Mac: an AppKit table that keeps only the rows
// near the screen alive, and knows every row's height. Each row is the same SwiftUI view as before (ChatRowView), so
// nothing looks different; only the list under them changed.
//
// Why (22 Nov profile of a 255-message chat, scrolled with a trackpad): in one SwiftUI stack every loaded message is
// a live view, so each scroll frame walked all of them (the window's drag regions, layout, hit tests), and earlier
// messages joined 24 at a time, a 570 ms stall each time. Here a frame costs only the rows on screen, and a row is
// measured once (ahead of you, a few at a time, in the spare part of each frame) and then remembered.
//
// Heights: a row's real height is measured offscreen at the table's width before it comes into view; a row on screen
// reports its own height whenever it changes (words streaming in, a fold opening). Rows not measured yet are guessed
// from their words. When a row above the view changes height, the view moves by the same amount in the same pass
// (Follower.shift), so what you're reading never moves.
import SwiftUI
import AppKit

/// The rows of one conversation, drawn by TranscriptList.
struct TranscriptTable: NSViewRepresentable {
    let agent: Agent?
    let cast: [String: Agent]
    let rows: [ChatRow]
    let intro: AnyView
    let follower: Follower
    /// What find in chat lights: the words, and the row of the match in view; a jump's row lit for a moment.
    let find: (ChatRow) -> String
    let match: String?
    let flash: String?
    @EnvironmentObject var s: Store
    @Environment(\.chatAgentId) private var agentId
    @Environment(\.chatConv) private var conv
    @Environment(\.chatActive) private var active
    @Environment(\.chatActivity) private var activity

    func makeCoordinator() -> TranscriptList { TranscriptList() }
    /// The list fills whatever room it's given. Left to AppKit, SwiftUI's question "how big do you want to be?" was
    /// answered by measuring every row's constraints, on every frame of a scroll (22 Nov profile: the largest cost left).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.make(follower: follower) }
    func updateNSView(_ view: NSScrollView, context: Context) {
        let list = context.coordinator
        let env = EnvKey(agentId: agentId, conv: conv, active: active, activity: activity.map { ObjectIdentifier($0) })
        let store = s, agentId = agentId, conv = conv, active = active, activity = activity
        let agent = agent, cast = cast, rows = rows, intro = intro
        func wrap<V: View>(_ v: V) -> AnyView {
            AnyView(v
                .frame(maxWidth: MV.on ? MV.Chat.column : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MV.on ? MV.Chat.sides : MV.Chat.bubbleX)
                .environmentObject(store)
                .environment(\.chatAgentId, agentId)
                .environment(\.chatConv, conv)
                .environment(\.chatActive, active)
                .environment(\.chatActivity, activity))
        }
        var items: [TranscriptList.Item] = [.init(id: TranscriptList.head, key: .head, words: 0)]
        for (i, row) in rows.enumerated() {
            let prev = i > 0 ? rows[i - 1] : nil
            let speaker = ChatTranscript.speaker(row, agent, cast)
            let lit = find(row)
            let key = RowKey(row: row, prevId: prev?.id, prevAt: prev?.at, agent: speaker, find: lit,
                             flash: flash == row.id, match: match == row.id)
            items.append(.init(id: row.id, key: .row(key), words: Self.words(row)))
        }
        items.append(.init(id: TranscriptList.tail, key: .tail, words: 0))
        list.content = { item in
            switch item.key {
            case .head:
                return wrap(intro.padding(.top, MV.Space.sm))
            case .tail:
                return wrap(Color.clear.frame(height: MV.Chat.tail))
            case .row(let k):
                guard let row = k.row else { return AnyView(EmptyView()) }
                let prev = k.prevId.flatMap { id in rows.first { $0.id == id } }
                return wrap(ChatRowView(agent: k.agent, row: row, prev: prev, find: k.find)
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { if !MV.on { RowLightFill(lit: RowLights.shared.lit(row.id)).padding(.horizontal, -MV.Chat.bubbleX) } }
                    .background {
                        if k.flash || k.match {
                            Rectangle().fill(k.flash ? C.sel : C.rowHover).padding(.horizontal, -MV.Chat.bubbleX)
                        }
                    })
            }
        }
        list.update(items, env: env)
    }

    /// How much there is to read in a row: its guessed height until it's measured.
    static func words(_ row: ChatRow) -> Int {
        switch row {
        case .you(_, let text, _, _, _, _, let images): return text.count + (images.isEmpty ? 0 : 400)
        case .agent(let t): return t.text.count + (t.steps.isEmpty ? 0 : 60)
        case .note(_, let text, _): return text.count
        }
    }
}

/// What a row is drawn from: the same values mean the same picture, so the row is left alone.
struct RowKey: Equatable {
    var row: ChatRow?
    var prevId: String?
    var prevAt: Double?
    var agent: Agent?
    var find: String
    var flash: Bool
    var match: Bool
}

/// The surroundings every row reads (its chat, whether the chat is on screen).
struct EnvKey: Equatable {
    var agentId: String?
    var conv: String?
    var active: Bool
    var activity: ObjectIdentifier?
}

/// A table that never takes the keyboard (the box keeps it) and draws nothing of its own.
final class TranscriptTableView: NSTableView {
    override var acceptsFirstResponder: Bool { false }
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
    override func drawBackground(inClipRect clipRect: NSRect) {}
    /// Rows within a screen or so of the view stay in place; the rest are put aside (kept, not rebuilt). A SwiftUI row
    /// in the window is laid out again on every frame it moves, so keeping all of them there cost every frame; one
    /// taken out and put back is laid out once.
    override func prepareContent(in rect: NSRect) {
        let screen = enclosingScrollView?.contentView.bounds ?? rect
        super.prepareContent(in: screen.insetBy(dx: 0, dy: -screen.height * MV.Chat.keptScreens).intersection(bounds))
    }
}

/// A row's SwiftUI view in the table. Says when its height changes; answers "do you take the keyboard?" from a short
/// memory (asked every frame by AppKit, and SwiftUI walks the whole row to answer: see ChatHostingView).
final class RowHost: NSHostingView<AnyView> {
    var id = ""
    private var accepts = false
    private var askedAt: CFTimeInterval = -1
    override var acceptsFirstResponder: Bool {
        let now = CACurrentMediaTime()
        if now - askedAt > MV.Motion.focusCache { accepts = super.acceptsFirstResponder; askedAt = now }
        return accepts
    }
}

@MainActor final class TranscriptList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let head = "·head", tail = "·tail"
    enum Kind: Equatable { case head, tail, row(RowKey) }
    struct Item { let id: String; let key: Kind; let words: Int }

    let scroll = NSScrollView()
    let table = TranscriptTableView()
    private weak var follower: Follower?
    /// Makes an item's view (set by TranscriptTable on every update).
    var content: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    private(set) var items: [Item] = []
    private var index: [String: Int] = [:]
    private var env: EnvKey?

    /// Every row's height: exact once measured at `width`; otherwise the last measure (at another width) or a guess.
    private struct Height { var h: CGFloat; var w: CGFloat; var exact: Bool }
    private var heights: [String: Height] = [:]
    private var width: CGFloat = 0
    /// Rows alive, newest use last (the table asks for a row's view again as it comes back).
    private var cells: [String: RowHost] = [:]
    private var used: [String] = []
    /// Measures a row offscreen at the table's width.
    private lazy var sizer = NSHostingController(rootView: AnyView(EmptyView()))
    private var opened = false

    func make(follower: Follower) -> NSScrollView {
        self.follower = follower
        follower.list = self
        let column = NSTableColumn(identifier: .init("row"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.usesAutomaticRowHeights = false
        table.rowSizeStyle = .custom
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsColumnReordering = false
        table.allowsTypeSelect = false
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        // The follower's eyes and clock: the same probe the stack used, in the table's (the conversation's) coordinates.
        table.addSubview(ScrollProbe.Probe(follower: follower))
        follower.probeOrigin = .zero
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(liveStart), name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        center.addObserver(self, selector: #selector(liveEnd), name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        center.addObserver(self, selector: #selector(moved), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        table.postsFrameChangedNotifications = true
        center.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification, object: table)
        scroll.contentView.postsFrameChangedNotifications = true
        center.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    // MARK: Where rows are (for the follower)

    func has(_ id: String) -> Bool { index[id].map { items[$0].key != .head && items[$0].key != .tail } ?? false }
    func frame(of id: String) -> CGRect? {
        guard let i = index[id], has(id) else { return nil }
        return table.rect(ofRow: i)
    }
    /// The row at a height in the conversation (none for the space above the first or under the last).
    func row(containing y: CGFloat) -> (key: String, value: CGRect)? {
        let i = table.row(at: NSPoint(x: 1, y: y))
        guard i >= 0, i < items.count, has(items[i].id) else { return nil }
        return (items[i].id, table.rect(ofRow: i))
    }

    // MARK: Changes

    func update(_ new: [Item], env newEnv: EnvKey) {
        let envChanged = env != newEnv
        env = newEnv
        let old = items
        items = new
        index = Dictionary(new.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        // Rows whose picture changed: their live view gets the new one (it reports its own new height).
        var changed = IndexSet()
        let oldKeys = Dictionary(old.map { ($0.id, $0.key) }, uniquingKeysWith: { a, _ in a })
        for (i, item) in new.enumerated() where envChanged || oldKeys[item.id] != item.key {
            if let cell = cells[item.id] { cell.rootView = reporting(item) }
            if oldKeys[item.id] != nil, oldKeys[item.id] != item.key, heights[item.id]?.exact == true { heights[item.id]?.exact = false; changed.insert(i) }
        }
        for gone in Set(cells.keys).subtracting(index.keys) { cells[gone] = nil; used.removeAll { $0 == gone } }
        let oldIds = old.map(\.id), newIds = new.map(\.id)
        if oldIds == newIds {
            if !changed.isEmpty { remeasure(changed) }
        } else if !old.isEmpty, newIds.count > oldIds.count, Array(newIds.prefix(oldIds.count - 1)) == Array(oldIds.dropLast()) {
            // New rows at the end (the tail stays last): only they are added.
            let added = IndexSet(integersIn: (oldIds.count - 1)..<(newIds.count - 1))
            for i in added { measure(i) }
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0
                table.insertRows(at: added, withAnimation: [])
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: newIds.count - 1))
            }
            if !changed.isEmpty { remeasure(changed) }
        } else {
            // Anything else (a chat opened, history arriving above, messages gone after going back): drawn again, the
            // row at the top of the view kept where it was.
            log("reload items=\(new.count) opened=\(opened) clip=\(scroll.contentView.bounds) window=\(scroll.window != nil)")
            if opened {
                let anchor = follower?.atTop
                let wasFollowing = follower?.isFollowing ?? true
                table.reloadData()
                if let anchor, !wasFollowing, let f = frame(of: anchor.id) {
                    let y = f.minY + anchor.share * f.height
                    follower?.shift(y - scroll.contentView.bounds.minY)
                }
            }
        }
        openIfReady()
        if opened { measureLater() }
    }

    /// A chat's first showing, once the view has its real size (measured before that, every row came out at the wrong
    /// width): the newest screens measured, drawn, and the view at the end.
    func openIfReady() {
        guard !opened, !items.isEmpty, scroll.window != nil, scroll.contentView.bounds.height > 1, scroll.contentView.bounds.width > 1 else { return }
        opened = true
        width = currentWidth
        firstScreens()
        table.reloadData()
        table.layoutSubtreeIfNeeded()
        let end = max(0, table.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: end)); scroll.reflectScrolledClipView(scroll.contentView)
        follower?.jumpToLatest()
        log("opened end=\(end) tableH=\(table.frame.height) w=\(width)")
        measureLater()
    }

    /// The row's view with its height report.
    private func reporting(_ item: Item) -> AnyView {
        let id = item.id
        return AnyView(content(item)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] h in self?.reported(id, h) }
            .frame(maxHeight: .infinity, alignment: .top))
    }

    // MARK: Heights

    private var currentWidth: CGFloat { max(1, scroll.contentView.bounds.width) }

    /// A row on screen says how tall it is now.
    private func reported(_ id: String, _ h: CGFloat) {
        guard opened, let i = index[id], h > 0, h.isFinite else { return }
        let w = currentWidth
        let old = height(i)
        log("reported \(i) \(id) w=\(w) h=\(h) old=\(old)")
        heights[id] = Height(h: h, w: w, exact: true)
        if abs(old - h) > 0.5 { pending[i] = old; applySoon() }
    }
    private var pending: [Int: CGFloat] = [:]
    private var applying = false
    private func applySoon() {
        guard !applying else { return }
        applying = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.apply() } }
    }
    /// Tells the table the heights that changed. The row at the top of the view keeps its place on screen (rows above it
    /// growing or shrinking move the view with them), whatever else reacted to the change in between.
    private func apply() {
        applying = false
        guard !pending.isEmpty else { return }
        let top = scroll.contentView.bounds.minY
        let r0 = table.row(at: NSPoint(x: 1, y: top))
        let off = r0 >= 0 ? top - table.rect(ofRow: r0).minY : 0
        let above = r0 >= 0 && pending.keys.contains { $0 < r0 }
        let rows = IndexSet(pending.keys.filter { $0 < items.count })
        pending.removeAll()
        let following = follower?.isFollowing ?? false
        NSAnimationContext.runAnimationGroup { c in c.duration = 0; table.noteHeightOfRows(withIndexesChanged: rows) }
        // At the end, the end is what stays put (a width change rewraps every row; the newest stays on the bottom edge).
        if following, !(follower?.userMoving ?? false) {
            let clip = scroll.contentView
            let end = max(0, table.frame.height - clip.bounds.height)
            if abs(clip.bounds.minY - end) > 0.5 { follower?.shift(end - clip.bounds.minY) }
            return
        }
        log("apply rows=\(Array(rows)) top=\(top) r0=\(r0) above=\(above) tableH=\(table.frame.height) y=\(scroll.contentView.bounds.minY) following=\(follower?.isFollowing ?? false)")
        guard above, r0 < items.count else { return }
        follower?.shift(table.rect(ofRow: r0).minY + off - scroll.contentView.bounds.minY)
    }

    private func height(_ i: Int) -> CGFloat {
        let item = items[i]
        if let h = heights[item.id] { return h.h }
        switch item.key {
        case .tail: return MV.Chat.tail
        case .head: return MV.Space.sm
        case .row:
            let w = max(1, min(currentWidth - 2 * MV.Chat.sides, MV.Chat.readWidth))
            let lines = (CGFloat(item.words) * MV.Chat.guessCharWidth / w).rounded(.up)
            return MV.Chat.guessRoom + max(1, lines) * MV.Chat.guessLine
        }
    }

    /// Measures one row now, offscreen, at the table's width.
    @discardableResult private func measure(_ i: Int) -> CGFloat {
        let item = items[i], w = currentWidth
        if let h = heights[item.id], h.exact, abs(h.w - w) < 0.5 { return h.h }
        sizer.rootView = AnyView(content(item).fixedSize(horizontal: false, vertical: true))
        var h = sizer.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude)).height.rounded(.up)
        if !h.isFinite || h > CGFloat(Int32.max) { h = 0 }
        sizer.rootView = AnyView(EmptyView())
        heights[item.id] = Height(h: max(1, h), w: w, exact: true)
        h = max(1, h)
        log("measure \(i) \(item.id) w=\(w) h=\(h)")
        return h
    }

    private func remeasure(_ rows: IndexSet) {
        for i in rows where cells[items[i].id] == nil {
            let old = height(i)
            heights[items[i].id]?.exact = false
            if abs(measure(i) - old) > 0.5 { pending[i] = old }
        }
        applySoon()
    }

    /// Opening a chat: the newest rows, a couple of screens of them, measured before the first frame (the rest follow in
    /// the spare part of the next frames).
    private func firstScreens() {
        table.layoutSubtreeIfNeeded()
        let screen = max(scroll.contentView.bounds.height, 1)
        var filled: CGFloat = 0
        var i = items.count - 1
        while i >= 0, filled < screen * MV.Chat.firstScreens { filled += measure(i); i -= 1 }
    }

    private var measuring = false
    /// In the spare part of each frame: rows not measured at this width yet, nearest to the view first (above it before
    /// below: that's where you scroll to).
    private func measureLater() {
        guard !measuring else { return }
        measuring = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.measureSome() } }
    }
    private func measureSome() {
        measuring = false
        guard scroll.window != nil, !scroll.isHiddenOrHasHiddenAncestor, !scroll.inLiveResize else {
            if scroll.window != nil { DispatchQueue.main.asyncAfter(deadline: .now() + MV.Motion.hoverAfterScroll) { [weak self] in MainActor.assumeIsolated { self?.measureLater() } } }
            return
        }
        let w = currentWidth
        let visible = table.rows(in: scroll.contentView.bounds)
        let start = CACurrentMediaTime()
        var order: [Int] = []
        let lo = visible.location, hi = visible.location + visible.length
        var up = lo - 1, down = hi
        while up >= 0 || down < items.count {
            if up >= 0 { order.append(up); up -= 1 }
            if down < items.count { order.append(down); down += 1 }
        }
        var left = false
        for i in order {
            let id = items[i].id
            let measured = heights[id].map { $0.exact && abs($0.w - w) < 0.5 } ?? false
            if measured, cells[id] != nil { continue }
            if CACurrentMediaTime() - start > MV.Chat.measureBudget { left = true; break }
            if cells[id] == nil {
                // Built now, in a quiet moment, rather than the moment it scrolls into view (building a row is what a
                // scroll frame couldn't afford: 22 Nov, 25 ms frames while new rows came in, 8 ms over built ones). It
                // reports its own height once laid out.
                _ = table.view(atColumn: 0, row: i, makeIfNecessary: true)
                cells[id]?.layoutSubtreeIfNeeded()
            } else {
                let old = height(i)
                if abs(measure(i) - old) > 0.5 { pending[i] = old }
            }
        }
        if !pending.isEmpty { apply() }
        if left { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120) { [weak self] in MainActor.assumeIsolated { self?.measureLater() } } }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { opened ? items.count : 0 }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { max(1, height(row)) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell: RowHost
        if let c = cells[item.id] { cell = c; used.removeAll { $0 == item.id } }
        else {
            cell = RowHost(rootView: reporting(item))
            cell.id = item.id
            cell.sizingOptions = []
            cells[item.id] = cell
        }
        used.append(item.id)
        evict()
        return cell
    }
    /// Past the keep, the rows used longest ago go (never one on screen).
    private func evict() {
        guard used.count > MV.Chat.keptRows else { return }
        let onScreen = table.rows(in: scroll.contentView.bounds)
        var i = 0
        while used.count > MV.Chat.keptRows, i < used.count {
            let id = used[i]
            if let r = index[id], NSLocationInRange(r, onScreen) { i += 1; continue }
            cells[id] = nil; used.remove(at: i)
        }
    }

    // MARK: Your hand on it

    @objc private func liveStart() { follower?.touching = true }
    @objc private func liveEnd() {
        guard let f = follower else { return }
        f.touching = false
        f.following = f.liveFromEnd <= 8
        measureLater()
    }
    @objc private func moved() {
        guard let f = follower else { return }
        if f.userMoving { f.following = f.liveFromEnd <= 2 }
        f.readEnds()
        if !measuring, heights.count < items.count { measureLater() }
    }
    @objc private func resized() {
        guard opened else { openIfReady(); return }
        let w = currentWidth
        if abs(w - width) > 0.5 { width = w; measureLater() }
    }

    /// Brings a row to the middle of the view (find, a jump).
    func bring(_ id: String) {
        guard let i = index[id] else { return }
        measure(i)
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: i))
        let r = table.rect(ofRow: i), clip = scroll.contentView
        let maxY = max(0, table.frame.height - clip.bounds.height)
        let y = min(max(0, r.midY - clip.bounds.height / 2), maxY)
        clip.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(clip)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // Diagnosis: `defaults write dev.agentlab.native tableLog -bool YES`; ~/Library/Caches/Agent Lab/table-log.txt.
    static let logging = UserDefaults.standard.bool(forKey: "tableLog")
    static let logURL: URL = {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab/table-log.txt")
        if logging { try? Data().write(to: u) }
        return u
    }()
    func log(_ line: @autoclosure () -> String) {
        guard Self.logging else { return }
        let l = String(format: "%.3f ", CACurrentMediaTime()) + line() + "\n"
        if let f = try? FileHandle(forWritingTo: Self.logURL) { f.seekToEndOfFile(); f.write(Data(l.utf8)); try? f.close() }
    }
}

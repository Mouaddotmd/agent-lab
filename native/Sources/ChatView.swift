// A conversation with one agent: Discord-style rows (face, name, time, words; no bubbles) with Mavis's chat behaviour
// (Mavis final launch, App/docs/chat-rules.md): "Thinking" the instant you send, the opening sentence, the to-do card
// and one live line while it works, then one still swap to the summary row, the answer and the report. One scroll
// writer: the follower below; nothing else moves the view.
import SwiftUI
import AppKit
import QuartzCore
import QuickLookThumbnailing

// MARK: The pane

struct ChatPane: View {
    @EnvironmentObject var s: Store
    let agent: Agent
    var key: String { "agent:\(agent.id)" }
    var body: some View {
        let panel = SidePanel.of(agent, home: s.home)
        ChatWithPanel(panel: panel, chat: column)
    }
    var column: some View {
        let rows = s.rows(for: agent.id)
        return VStack(spacing: 0) {
            head
            // The transcript is made once its messages are here, so it opens at its end with everything in it (made
            // empty first, it settled at the top and the rows arrived off screen until you scrolled).
            if s.messages[agent.id] != nil {
                // MAVIS opens straight on the conversation: no intro block (prototype).
                ChatTranscript(agent: agent, cast: [:], rows: rows, intro: MV.on ? AnyView(EmptyView()) : AnyView(ChatIntro(agent: agent)))
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ChatComposer(agent: agent)
                .zIndex(2)
        }
        .background(C.v1)
        .modifier(MVDropZone(key: key))
        .findInChat(agent.id)
        .environment(\.chatAgentId, agent.id)
        .environment(\.chatConv, agent.id)
        .onAppear { LiveWords.shared.update(rows); markRead() }
        .onChange(of: rows) { _, r in LiveWords.shared.update(r); markRead() }
        .onChange(of: s.openAgent) { _, _ in markRead() }
    }
    /// Seen: it's the chat open in Messages (its red count clears).
    func markRead() { if s.view == .messages, s.openWorkspace == nil, s.openAgent == agent.id { s.markAgentRead(agent.id) } }
    var handingOff: Binding<Bool> {
        Binding(get: { s.handingOff == agent.id }, set: { if !$0, s.handingOff == agent.id { s.handingOff = nil } })
    }
    // 56 tall: face, name, state; More at the end (web: .chat-head). MAVIS: 44 tall, name and a state chip, tools.
    @ViewBuilder var head: some View {
        if MV.on { mavisHead } else { classicHead }
    }
    var mavisHead: some View {
        let state = s.state(of: agent)
        return HStack(spacing: MV.Space.gridGap) {
            Text(agent.name).font(F.font(MV.Text.name, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1)
            MVChip(text: MavisToday.stateWord(state), done: state == "done")
            Spacer(minLength: 0)
            HeadTools(panel: SidePanel.of(agent, home: s.home))
                .background(alignment: .trailing) {
                    Color.clear.frame(width: MV.Size.iconButton, height: MV.Size.iconButton).floatingMenu(handingOff, pop: true) { HandOffMenu(agent: agent, open: handingOff) }
                }
        }
        .padding(.leading, MV.Space.headerLead).padding(.trailing, MV.Space.headerEdge).frame(height: MV.Size.header)
    }
    var classicHead: some View {
        HStack(spacing: 8) {
            Avatar(agent: agent, size: 24, ring: C.v1)
            Line(agent.name, 16, .semibold)
            Line(STATE_LABEL[s.state(of: agent)] ?? "Ready", 14, .regular, C.i10)
            Spacer(minLength: 0)
            // The panel's tools, while the panel is hidden (it shows them itself when open).
            HeadTools(panel: SidePanel.of(agent, home: s.home))
                // Hand off (its ⋯ menu, or /handoff): the agents to pass the chat to, from here.
                .background(alignment: .trailing) {
                    Color.clear.frame(width: 40, height: 40).floatingMenu(handingOff, pop: true) { HandOffMenu(agent: agent, open: handingOff) }
                }
        }
        .padding(.leading, 16).padding(.trailing, PanelTools.trailing).frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(C.divider).frame(height: 1) }
    }
}

/// The chat header's end: the panel's tools while the panel is hidden.
private struct HeadTools: View {
    @ObservedObject var panel: SidePanel
    var body: some View { PanelTools(panel: panel) }
}

/// The start of the conversation: big face, name, job, facts (web: .intro)
struct ChatIntro: View {
    @EnvironmentObject var s: Store
    let agent: Agent
    var body: some View {
        let op = OPS[agent.operator ?? ""] ?? agent.operator ?? ""
        let model = agent.model.map { MODEL_NAMES[$0] ?? $0 }
        VStack(alignment: .leading, spacing: 0) {
            Avatar(agent: agent, size: 80, ring: C.v1)
            Line(agent.name, 24, .semibold, C.i12, tracking: -0.36).padding(.top, 12)
            Para(text: (agent.job ?? "").isEmpty ? "This is the start of your conversation with \(agent.name). It answers exactly the way \(op) does, and asks before it changes anything." : agent.job!, size: 16, weight: .regular, color: C.i10)
                .frame(maxWidth: 640, alignment: .leading).padding(.top, 4).textSelection(.enabled)
            HStack(spacing: 8) {
                Line(model ?? op, 14, .regular, C.i10)
                Line("·", 14, .regular, C.v6)
                Hover { h in
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: agent.cwd ?? s.home)) } label: {
                        Text(((agent.cwd ?? s.home) as NSString).lastPathComponent).font(F.font(14, .regular)).foregroundStyle(WAIT_TEXT).underline(h).frame(height: 20)
                    }.buttonStyle(.plain).help(agent.cwd ?? s.home)
                }
                Line("·", 14, .regular, C.v6)
                Line(PERMS[agent.permission ?? "ask"] ?? PERMS["ask"]!, 14, .regular, C.i10)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 8)
    }
}

// MARK: The transcript (chat-rules §5)

struct ChatTranscript: View, Equatable {
    /// A DM's agent; nil in a channel, where each turn names its own agent (`Turn.by`) and `cast` has them.
    let agent: Agent?
    let cast: [String: Agent]
    let rows: [ChatRow]
    let intro: AnyView
    @State private var follower = Follower()
    /// SwiftUI's own record of where the view is. Moves made straight on the scroll view (the follower's) are written
    /// here too: otherwise, on the next change of the content's size, SwiftUI put the view back where it last knew
    /// it to be, and the chat jumped by itself.
    @State private var position = ScrollPosition(edge: .bottom)
    /// How many of the latest rows are drawn (older ones one click away). Real rows only, never estimated: a lazy list
    /// guessed the heights of rows it hadn't built, and opening a long chat at its end showed black until you scrolled.
    @State private var shownCount = ChatTranscript.page
    static let page = 24        // what a chat opens with (more join as you scroll up): opening and resizing cost only this
    /// Scrolled this close to the top: the next earlier page joins.
    static let nearTop: CGFloat = 400
    /// Find in the chat and jumps to a message (ConvoModel.swift). Changes only when you find or jump.
    @ObservedObject private var find = ChatFinder.shared
    /// A row lit for a moment after a jump.
    @State private var flash: String?
    static func == (a: Self, b: Self) -> Bool { a.agent == b.agent && a.cast == b.cast && a.rows == b.rows }
    var body: some View {
        let lastSent = rows.last { if case .you = $0 { true } else { false } }?.id
        let me = agent?.id ?? ""
        let finding = find.query(me), match = find.current[me]?.row
        ScrollViewReader { proxy in
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical) {
                // Not lazy: every shown row (the latest `page`, more on request) is built and measured for real. A
                // lazy list guessed the heights of rows it hadn't built; when the width changed (the window, the side
                // panel) the guess could run thousands of points past the real end and the chat, resting at its end,
                // showed nothing: black, flickering, until you scrolled (17 Nov). Measured on a real chat
                // (tools/chatperf): resizing is faster this way (median 9 ms a frame against 18, worst 23 against 42);
                // a chat's first open costs ~115 ms instead of ~65, once (kept chats aren't rebuilt: ChatHost.swift).
                VStack(alignment: .leading, spacing: 0) {
                    // The latest `page` rows; earlier ones join on their own as you scroll near the top (no button), the
                    // row you're reading kept in place. A long chat costs only what's drawn (resizing, opening).
                    let first = max(0, rows.count - shownCount)
                    if first == 0 { intro }
                    ForEach(Array(rows.enumerated()).dropFirst(first), id: \.element.id) { i, row in
                        ChatRowView(agent: Self.speaker(row, agent, cast), row: row, prev: i > 0 ? rows[i - 1] : nil, find: me.isEmpty ? "" : find.lit(me, row.id))
                            .equatable()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Under the pointer: lit by the chat's one hover tracker (Follower.hover), not by a listener
                            // of its own (one per row made every mouse move hit-test the whole chat: half the main
                            // thread while scrolling, 19 Nov trace).
                            // MAVIS has no row hover in the chat (prototype): only the classic look lights rows.
                            .background { if !MV.on { RowLightFill(lit: RowLights.shared.lit(row.id)).padding(.horizontal, -16) } }
                            // MAVIS: the hovered row above the next, so its tools hang over it.
                            .modifier(LitAbove(lit: RowLights.shared.lit(row.id)))
                            // The match in view while finding, and a jump's row lit for a moment.
                            .background {
                                if flash == row.id || (!finding.isEmpty && match == row.id) {
                                    Rectangle().fill(flash == row.id ? C.sel : C.rowHover).padding(.horizontal, -16)
                                }
                            }
                            
                            .id(row.id)
                            // Where each message sits in the conversation (not on screen: scrolling doesn't change
                            // it), so the one you're reading can be kept in place when the width changes.
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Follower.space)) } action: { f in follower.rowMoved(row.id, f) }
                    }
                    Color.clear.frame(height: 16)            // the space under the last message
                }
                // MAVIS: the conversation keeps a reading column, centred; the scroller stays full width.
                .frame(maxWidth: MV.on ? MV.Chat.column : .infinity)
                .frame(maxWidth: .infinity)
                .background(ScrollProbe(follower: follower))
                // MAVIS: the feed's 8 32 6 (spec 9).
                .padding(.horizontal, MV.on ? MV.Chat.sides : 16).padding(.top, 8)
                .coordinateSpace(name: Follower.space)
            }
            .scrollIndicators(.automatic)
            // Opens at its end; afterwards, when content grows the top stays put and only the follower brings the end
            // into view, by gliding (a view held to the bottom edge was a second scroll writer: Mavis, 15 Nov).
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .sizeChanges)
            .scrollPosition($position)
            .onAppear { follower.tell = { y in var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { position.scrollTo(y: y) } } }

            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y < Self.nearTop } action: { _, near in
                // Only your own scrolling up brings earlier rows: a rewrap (the panel opening) can pass near the top for
                // a frame, and paging then threw the chat 2,384 pt off its end (paneltest).
                guard near, rows.count > shownCount, !follower.following, follower.userMoving, let sv = follower.scrollView else { return }
                // The row at the top now, and where it is on screen: after the earlier rows join above, the view moves by
                // exactly the height they added, so nothing you're reading shifts.
                let keep = rows[max(0, rows.count - shownCount)].id
                let before = follower.frame(of: keep)?.minY, y0 = sv.contentView.bounds.origin.y
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shownCount += Self.page }
                DispatchQueue.main.async {
                    sv.layoutSubtreeIfNeeded()
                    guard let before, let after = follower.frame(of: keep)?.minY else { return }
                    sv.contentView.scroll(to: NSPoint(x: 0, y: y0 + (after - before))); sv.reflectScrolledClipView(sv.contentView)
                }
            }
            .onScrollPhaseChange { _, phase in
                let user = phase == .interacting || phase == .decelerating
                follower.touching = user
                if !user { follower.following = follower.liveFromEnd <= 8 }
            }
            .onScrollGeometryChange(for: CGSize.self) { g in CGSize(width: g.contentOffset.y, height: g.contentSize.height) } action: { _, _ in
                if follower.userMoving { follower.following = follower.liveFromEnd <= 2 }
                follower.restrain()
                follower.readEnds()
                DispatchQueue.main.async { follower.readEnds() }
            }
            .onAppear { follower.opened() }
            .onChange(of: lastSent) { old, new in if new != nil, new != old { follower.sent() } }
            if MV.on {
                // MAVIS: its right edge on the chatbox's right edge (same column, same side inset).
                JumpToLatest(follower: follower)
                    .frame(maxWidth: MV.Chat.column, alignment: .trailing).frame(maxWidth: .infinity)
                    .padding(.horizontal, MV.Space.section - MV.Space.xs).padding(.bottom, MV.Space.inset)
            } else {
                JumpToLatest(follower: follower).padding(.trailing, 16).padding(.bottom, 12)
            }
        }
        .onChange(of: find.current[me]) { _, t in if let t, !me.isEmpty { bring(t.row, proxy, light: false) } }
        .onChange(of: find.jump[me]) { _, t in if let t, !me.isEmpty { bring(t.row, proxy, light: true); find.jumped(me) } }
        .onAppear { if !me.isEmpty, let t = find.jump[me] { DispatchQueue.main.async { bring(t.row, proxy, light: true); find.jumped(me) } } }
        }
    }
    /// Brings a row into view (drawing older rows first if it's among them), and lights it for a moment after a jump.
    private func bring(_ row: String, _ proxy: ScrollViewProxy, light: Bool) {
        guard let i = rows.firstIndex(where: { $0.id == row }) else { return }
        if rows.count - i > shownCount { shownCount = rows.count - i + 4 }
        follower.following = false
        DispatchQueue.main.async {
            proxy.scrollTo(row, anchor: .center)
            guard light else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { flash = row }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.easeOut(duration: 0.45)) { if flash == row { flash = nil } } }
        }
    }
}

extension ChatTranscript {
    /// Who wrote an agent row: the turn's own agent in a channel, else the DM's.
    static func speaker(_ row: ChatRow, _ agent: Agent?, _ cast: [String: Agent]) -> Agent? {
        if case .agent(let t) = row, let by = t.by { return cast[by] }
        return agent
    }
}

/// The one thing that moves the transcript on its own (Mavis: TranscriptMetrics). Plain values, not view state: they
/// change every frame and must never redraw the conversation. Only `away` is published, for the jump button.
final class Follower: ObservableObject {
    weak var scrollView: NSScrollView?
    /// Following the bottom. Only you turn it off, by scrolling up; resting at the very end turns it back on.
    var following = true { didSet { if following != oldValue { heldY = nil; readEnds() } } }
    var touching = false
    /// Your hand on the view (a trackpad, a wheel or a drag). The wheel is heard straight from AppKit too: SwiftUI's
    /// scroll phase arrives a few events late, and in that gap the glide pulled against your first scroll (19 Nov:
    /// "buggy for the first split second" at the bottom of a chat).
    var userMoving: Bool { touching || CACurrentMediaTime() - wheelAt < 0.15 || MainActor.assumeIsolated { SmoothScroll.shared.gliding(scrollView) } }
    private var wheelAt: CFTimeInterval = 0
    /// A click in the transcript: whatever it opens or closes (a step, a card, anything that expands) changes the
    /// content under you. That's you, not the agent, so the view stays where it is instead of following the end.
    private var clickedAt: CFTimeInterval = 0, clickedHeight: CGFloat = -1
    private var events: Any?
    @Published private(set) var away = false
    private var openedAt = Date.distantPast, sentAt = Date.distantPast, lastFrame: CFTimeInterval = 0
    /// The view's width just now, and until when a change of it counts as resizing. The words rewrap and the content
    /// changes height with every step of a resize (the window's edge, the side panel): while following, the end stays
    /// pinned to the bottom at once instead of being chased by the glide, and the held-back rule doesn't apply. That
    /// chase was the chat scrolling back and forth while the panel opened (17 Nov).
    private var width: CGFloat = 0, resizingUntil: CFTimeInterval = 0
    private var resizing: Bool { CACurrentMediaTime() < resizingUntil }
    /// The conversation's own coordinates: each message's place in it.
    static let space = "transcript"
    private var rowFrames: [String: CGRect] = [:]
    /// Scrolled up, reading: the message at the top of the view and how far down it the view's top edge is (a share of
    /// its height). A new width rewraps every message, so the same offset would show something else (17 Nov: the chat
    /// "scrolled by itself" while the side panel opened or its edge moved). Instead the view is put back on the same
    /// spot of the same message, in the same layout pass, as Claude keeps it.
    private var reading: (id: String, share: CGFloat)?
    /// Writes a place the follower moved the view to into SwiftUI's record of it (see ChatTranscript.position).
    var tell: ((CGFloat) -> Void)? { didSet { told = -1 } }
    private var told: CGFloat = -1
    /// Tests: the followers alive, scrolling up as a hand would, and what's at the top of the view now.
    static let testing = ProcessInfo.processInfo.environment["AL_TEST"] != nil
    nonisolated(unsafe) static var alive: [Weak] = []
    final class Weak { weak var f: Follower?; init(_ f: Follower) { self.f = f } }
    /// Scrolls up with real wheel events (as a trackpad would), until the view's top is above `y`.
    func letGo(to y: CGFloat) {
        guard let view = scrollView else { return }
        following = false
        let clip = view.contentView
        clip.scroll(to: CGPoint(x: 0, y: y)); view.reflectScrolledClipView(clip)
        tell?(y)
        following = false
    }
    var atTop: (id: String, share: CGFloat)? {
        guard let view = scrollView else { return nil }
        let y = view.contentView.bounds.minY
        guard let hit = rowFrames.first(where: { $0.value.minY <= y && $0.value.maxY > y }) else { return nil }
        return (hit.key, (y - hit.value.minY) / max(1, hit.value.height))
    }
    var isFollowing: Bool { following }
    func rowMoved(_ id: String, _ f: CGRect) {
        let old = rowFrames[id]
        rowFrames[id] = f
        if old != f, !following, resizing, reading?.id == id { putBack() }
    }
    /// The view's place, the content's height and the width when `reading` was last noted: a change of the place alone
    /// is you scrolling; a change of the height or width is the layout changing under you (a resize, something opening
    /// or closing), which puts you back where you were reading instead.
    private var noted = (y: CGFloat(-1), h: CGFloat(-1), w: CGFloat(-1))
    /// Notes the message you're reading (only when you, not a resize, moved the view).
    private func noteReading() {
        guard let view = scrollView else { return }
        let y = view.contentView.bounds.minY
        noted = (y, view.documentView?.frame.height ?? 0, view.contentView.bounds.width)
        guard let hit = rowFrames.first(where: { $0.value.minY <= y && $0.value.maxY > y }) else { reading = nil; return }
        reading = (hit.key, (y - hit.value.minY) / max(1, hit.value.height))
    }
    private func putBack() {
        guard let r = reading, let f = rowFrames[r.id], let view = scrollView, let doc = view.documentView else { return }
        let clip = view.contentView
        let maxY = max(0, doc.frame.height + view.contentInsets.bottom - clip.bounds.height)
        let y = min(max(0, (f.minY + r.share * f.height).rounded()), maxY)
        guard abs(clip.bounds.origin.y - y) > 0.5 else { return }
        moving = true
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: y)); view.reflectScrolledClipView(clip)
        tell?(y)
        moving = false
        heldY = y
    }
    /// Your send's glide: launched once the new rows are laid out, a quick ease-out (Glide.sendResponse).
    private var launch = false, response = Glide.response
    private var velocity: CGFloat = 0
    private var heldY: CGFloat?
    private var moving = false
    private var watching: NSObjectProtocol?
    func opened() { openedAt = Date(); following = true; note("OPENED"); if Self.testing { Self.alive.append(Weak(self)) }; wake?() }
    func sent() { sentAt = Date(); following = true; launch = true; note("SENT"); wake?() }
    func jumpToLatest() { following = true; wake?() }
    /// Starts the per-frame follow again (it sleeps once the view is settled: nothing to do, no timer waking the app).
    var wake: (() -> Void)?

    /// Hears the clip view move the moment it does (before the frame is drawn), so a move that isn't ours is put back
    /// before it can be seen (Mavis 16 Nov: caught a frame later, rows showed twice, offset).
    func watch(_ view: NSScrollView?) {
        if let events { NSEvent.removeMonitor(events) }
        events = nil
        if let view {
            view.window?.acceptsMouseMovedEvents = true
            events = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .mouseMoved, .mouseExited]) { [weak self, weak view] e in
                guard let self, let view, e.window === view.window, view.window != nil else { return e }
                // A chat kept in the pool but not on screen hears nothing (each kept chat used to answer every event).
                if MainActor.assumeIsolated({ view.isHiddenOrHasHiddenAncestor || view.inAwayChat }) { return e }
                if e.type == .mouseMoved || e.type == .mouseExited { MainActor.assumeIsolated { self.hover() }; return e }
                let p = view.convert(e.locationInWindow, from: nil)
                guard view.bounds.contains(p) else { return e }
                MainActor.assumeIsolated {
                    if e.type == .scrollWheel {
                        self.wheelAt = CACurrentMediaTime()
                        // Toward earlier messages: you've left the end, at once (not when SwiftUI notices).
                        if e.scrollingDeltaY > 0.5 { self.following = false; self.velocity = 0 }
                    } else {
                        self.clickedAt = CACurrentMediaTime()
                        self.clickedHeight = view.documentView?.frame.height ?? -1
                        self.noteReading()
                    }
                }
                return e
            }
        }
        // A mouse wheel's glide (SmoothScroll) is your hand on the view: toward earlier messages, you've left the end.
        if let gliding { NotificationCenter.default.removeObserver(gliding) }
        gliding = view.map { v in
            NotificationCenter.default.addObserver(forName: SmoothScroll.began, object: v, queue: .main) { [weak self] n in
                let up = n.userInfo?["up"] as? Bool ?? false
                MainActor.assumeIsolated { self?.wheelAt = CACurrentMediaTime(); if up { self?.following = false; self?.velocity = 0 } }
            }
        }
        if let watching { NotificationCenter.default.removeObserver(watching) }
        if let watchingDoc { NotificationCenter.default.removeObserver(watchingDoc) }
        watching = nil; watchingDoc = nil
        guard let clip = view?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        watching = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { if self?.moving == false { self?.restrain() }; self?.wake?(); self?.hover(); if ScrollMeter.on { ScrollMeter.shared.moved(view) } }
        }
        // The content's height changes in the same layout pass as a new width (the words rewrap): pinned to the end
        // right there, before anything is drawn. Heard only from the clip's bounds, the first frame of a panel opening
        // was drawn scrolled up and jumped back on the next (17 Nov).
        // The view gets shorter (the box grew: attachments, more lines): following, it stays at the end.
        if let watchingView { NotificationCenter.default.removeObserver(watchingView) }
        if let v = view {
            v.postsFrameChangedNotifications = true
            lastHeight = v.frame.height
            watchingView = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: v, queue: nil) { [weak self, weak v] _ in
                MainActor.assumeIsolated {
                    guard let self, let v else { return }
                    let shorter = v.frame.height < self.lastHeight - 0.5
                    self.lastHeight = v.frame.height
                    // Only the box growing (the view got shorter); a width change is the follower's own job.
                    guard shorter, self.following, let doc = v.documentView else { return }
                    let end = max(0, doc.frame.height - v.contentView.bounds.height)
                    if abs(v.contentView.bounds.origin.y - end) > 0.5 { v.contentView.scroll(to: NSPoint(x: 0, y: end)); v.reflectScrolledClipView(v.contentView) }
                }
            }
        }
        if let doc = view?.documentView {
            doc.postsFrameChangedNotifications = true
            watchingDoc = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: doc, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { if self?.moving == false { self?.restrain() }; self?.wake?() }
            }
        }
    }
    private var watchingDoc: NSObjectProtocol?, gliding: NSObjectProtocol?, watchingView: NSObjectProtocol?
    private var lastHeight: CGFloat = 0
    /// Where a row sits in the conversation (for keeping your place when earlier rows join above).
    func frame(of id: String) -> CGRect? { rowFrames[id] }
    /// The chat's one hover tracker: the row under the pointer (by the rows' known places), lit; checked on every mouse
    /// move and every scroll (rows pass under a still pointer).
    @MainActor func hover() {
        guard let view = scrollView, let window = view.window, let doc = view.documentView else { RowLights.shared.light(nil); return }
        let p = window.mouseLocationOutsideOfEventStream
        guard view.bounds.contains(view.convert(p, from: nil)) else { RowLights.shared.light(nil); return }
        let y = doc.convert(p, from: nil).y
        // MAVIS: the row keeps its tools while the pointer goes down into them (they hang under it).
        if MV.on, let cur = RowLights.shared.current, let f = rowFrames[cur], f.minY <= y, y < f.maxY + MV.MessageTools.reach {
            RowLights.shared.light(cur); return
        }
        RowLights.shared.light(rowFrames.first { $0.value.minY <= y && y < $0.value.maxY }?.key)
    }
    private var inJumpWindow: Bool {
        Date().timeIntervalSince(openedAt) < 0.6 || CACurrentMediaTime() < resizingUntil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    /// Notes a change of the view's width (see `width`).
    private func readWidth() {
        // The content's own width first: it's laid out at the new width (and grows taller as words rewrap) a beat before
        // the visible area reports it, and in that beat the end was left behind for one frame (19 Nov: 3,812 pt).
        guard let w = scrollView?.documentView?.frame.width ?? scrollView?.contentView.bounds.width, abs(w - width) > 0.5 else { return }
        if width > 0 { resizingUntil = CACurrentMediaTime() + 0.35 }
        width = w
    }
    /// AppKit pins a scroll view resting at its end when content grows, in one frame, ahead of the glide. While
    /// following, that move is put back and the spring glides there instead. A move of half the view or more is
    /// history arriving above: let through (Mavis 16 Nov, +905 pt).
    func restrain() {
        readWidth()
        guard let view = scrollView else { return }
        let clip = view.contentView, y = clip.bounds.origin.y
        // Something you clicked opened or closed: stop following, so the view keeps the message you were reading in
        // place (the branch below) instead of gliding to the new end by itself.
        if following, CACurrentMediaTime() - clickedAt < 0.8, let doc = view.documentView, clickedHeight >= 0, abs(doc.frame.height - clickedHeight) > 0.5 {
            following = false
            clickedHeight = -1
            note("CLICK changed layout: stop following")
        }
        // Resizing while following: the end stays on the bottom edge in the same pass that changed the layout, so no
        // frame is ever drawn away from it (waiting for the next screen frame showed the view 94 pt off the end).
        if following, !userMoving, CACurrentMediaTime() < resizingUntil, let doc = view.documentView {
            let endY = max(0, doc.frame.height + view.contentInsets.bottom - clip.bounds.height)
            if abs(y - endY) > 0.5 {
                moving = true
                clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: endY)); view.reflectScrolledClipView(clip)
                tell?(endY)
                moving = false
            }
            heldY = endY
            return
        }
        if !following, !moving, let doc = view.documentView {
            let layoutChanged = abs(doc.frame.height - noted.h) > 0.5 || abs(clip.bounds.width - noted.w) > 0.5
            if layoutChanged, !resizing, CACurrentMediaTime() - clickedAt < 0.8, noted.y >= 0 {
                // Something you clicked opened or closed: the view stays exactly where it was (clamped to the end), so
                // the line you clicked never moves; what opened grows below it. Measuring by a share of the message you
                // were reading moved the view whenever that message was the one changing (19 Nov: the scroll twitched).
                let maxY = max(0, doc.frame.height + view.contentInsets.bottom - clip.bounds.height)
                let keep = min(noted.y, maxY)
                if abs(y - keep) > 0.5 {
                    moving = true
                    clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: keep)); view.reflectScrolledClipView(clip)
                    tell?(keep)
                    moving = false
                }
                heldY = keep
                noted.h = doc.frame.height; noted.w = clip.bounds.width
            } else if (resizing || layoutChanged), let r = reading, rowFrames[r.id] != nil {
                putBack()
                noted = (clip.bounds.minY, doc.frame.height, clip.bounds.width)
            } else if reading == nil || abs(y - noted.y) > 0.5 { noteReading() }
        }
        guard following, !userMoving, !inJumpWindow, let held = heldY else { heldY = y; return }
        if y > held + 0.5, y - held < clip.bounds.height / 2 {
            moving = true
            clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: held)); view.reflectScrolledClipView(clip)
            moving = false
            note(String(format: "HELD back %.1f", y - held))
        } else if abs(y - held) > 0.5 { heldY = y }
    }
    /// Every screen frame: ride a critically damped spring to the bottom (no overshoot, keeps its speed as content
    /// keeps arriving). Jumps when the gap is over a screen, right after opening, or right after you send.
    /// Returns false once there's nothing left to do (settled at the end, or not following): the timer then sleeps.
    @discardableResult func frame(_ now: CFTimeInterval) -> Bool {
        // At most one 60 Hz frame per step: after a stall the glide carries on instead of lurching (Mavis 15 Nov).
        let dt = min(1.0 / 60, lastFrame == 0 ? 1.0 / 60 : now - lastFrame)
        lastFrame = now
        log(now, "")
        restrain()
        if launch, Date().timeIntervalSince(sentAt) > 1 { launch = false }     // nothing grew: no glide owed
        guard following, !userMoving, let view = scrollView, let doc = view.documentView else { velocity = 0; response = Glide.response; return userMoving }
        let clip = view.contentView
        let gap = doc.frame.height + view.contentInsets.bottom - clip.bounds.maxY
        guard gap > 0.5 else {
            velocity = 0; response = Glide.response
            // Settled: SwiftUI learns where the glide left the view (once), so it never puts it back somewhere older.
            let y = clip.bounds.origin.y
            if abs(y - told) > 0.5 { told = y; tell?(y) }
            return launch || Date().timeIntervalSince(sentAt) < 1 || inJumpWindow
        }
        // Your send: the view is simply at the new message, in one frame, as Claude Code's (19 Nov: the glide read as a
        // little scroll each time). The rows that land with it in the next moment (Thinking) are met the same way.
        if launch { launch = false; velocity = 0 }
        let justSent = Date().timeIntervalSince(sentAt) < 0.6
        let jump = gap > clip.bounds.height * 1.5 || inJumpWindow || justSent
        let step = jump ? (move: gap, velocity: CGFloat(0)) : Glide.step(gap: gap, velocity: velocity, dt: dt, response: response)
        velocity = step.velocity
        log(now, String(format: "FOLLOW gap=%.1f move=%.1f v=%.0f%@%@", gap, step.move, step.velocity, jump ? " JUMP" : "", response == Glide.sendResponse ? " SEND" : ""))
        moving = true
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + step.move)); view.reflectScrolledClipView(clip)
        moving = false
        heldY = clip.bounds.origin.y
        return true
    }
    /// Read from AppKit (SwiftUI's insets read doubled on macOS 27: Mavis).
    var liveFromEnd: CGFloat {
        guard let view = scrollView, let doc = view.documentView else { return 0 }
        return doc.frame.height + view.contentInsets.bottom - view.contentView.bounds.maxY
    }
    deinit {
        if let events { NSEvent.removeMonitor(events) }
        // Every observer goes with it (they outlived dropped chats).
        for o in [watching, watchingDoc, gliding, watchingView].compactMap({ $0 }) { NotificationCenter.default.removeObserver(o) }
    }
    func readEnds() {
        let isAway = liveFromEnd > 80 && !following
        if away != isAway { away = isAway }
    }

    // Diagnosis: `defaults write dev.agentlab.native agentLabScrollLog -bool YES`, then run a task and
    // `python3 native/tools/check-chat-run.py`. Log: ~/Library/Caches/Agent Lab/scroll-log.txt (emptied at launch).
    static let logging = UserDefaults.standard.bool(forKey: "agentLabScrollLog")
    static let logURL: URL = {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab/scroll-log.txt")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if logging { try? Data().write(to: u) }
        return u
    }()
    private var lastLogged: (y: CGFloat, h: CGFloat) = (-1, -1)
    func note(_ text: String) { log(CACurrentMediaTime(), text) }
    private func log(_ now: CFTimeInterval, _ note: String) {
        guard Self.logging, let view = scrollView, let doc = view.documentView else { return }
        let y = view.contentView.bounds.origin.y, h = doc.frame.height
        guard y != lastLogged.y || h != lastLogged.h || !note.isEmpty else { return }
        lastLogged = (y, h)
        let line = String(format: "%.3f y=%.1f h=%.1f clipH=%.1f following=%d touching=%d %@\n", now, y, h, view.contentView.bounds.height, following ? 1 : 0, touching ? 1 : 0, note)
        if let f = try? FileHandle(forWritingTo: Self.logURL) { f.seekToEndOfFile(); f.write(line.data(using: .utf8)!); try? f.close() }
    }
}

/// Finds the AppKit scroll view under the SwiftUI one and drives the follower from the screen's refresh.
private struct ScrollProbe: NSViewRepresentable {
    let follower: Follower
    func makeNSView(context: Context) -> NSView { Probe(follower: follower) }
    func updateNSView(_ view: NSView, context: Context) {}
    final class Probe: NSView {
        let follower: Follower
        private var link: CADisplayLink?
        init(follower: Follower) { self.follower = follower; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            follower.scrollView = enclosingScrollView
            follower.watch(window != nil ? enclosingScrollView : nil)
            enclosingScrollView?.verticalScrollElasticity = .none      // no bounce past the ends
            CapsuleScroller.install(in: enclosingScrollView)
            link?.invalidate(); link = nil
            if window != nil, !isHiddenOrHasHiddenAncestor { startLink() }
            follower.wake = { [weak self] in
                guard let self, self.link == nil, self.window != nil, !self.isHiddenOrHasHiddenAncestor else { return }
                self.startLink()
            }
        }
        /// A kept chat you've left (ChatHost.swift) is hidden: its follower doesn't run until you come back.
        override func viewDidHide() { super.viewDidHide(); link?.invalidate(); link = nil }
        override func viewDidUnhide() { super.viewDidUnhide(); if window != nil, link == nil { startLink() } }
        private func startLink() {
            guard link == nil else { return }
            let l = displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
            follower.note("PROBE window=\(window != nil) scroll=\(enclosingScrollView != nil)")
        }
        /// Settled: the timer stops (the app sleeps between frames); anything that changes the chat wakes it.
        @objc private func tick(_ l: CADisplayLink) { if !follower.frame(l.timestamp) { link?.invalidate(); link = nil } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Back to the latest message: shows once the end is out of sight and you're not following.
private struct JumpToLatest: View {
    @ObservedObject var follower: Follower
    var body: some View {
        let shown = follower.away
        Hover { h in
            if MV.on {
                // MAVIS: a 36 round button on box with the surface hairline; hover and press wash over it.
                Button { follower.jumpToLatest() } label: {
                    Icon("mvChevDown", MV.Size.icon).foregroundStyle(MV.Ink.t1).frame(width: MV.Profile.button, height: MV.Profile.button)
                        .background(Circle().fill(MV.Tone.box))
                        .overlay(Circle().strokeBorder(MV.Tone.line, lineWidth: MV.Stroke.surface)).contentShape(Circle())
                }.buttonStyle(MVStates(shape: Circle()))
            } else {
                Button { follower.jumpToLatest() } label: {
                    Icon("chev", 16).foregroundStyle(C.i12).frame(width: 32, height: 32)
                        .background(Circle().fill(h ? C.v4 : C.v3)).overlay(Circle().strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Circle())
                }.buttonStyle(.plain)
            }
        }
        .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8).allowsHitTesting(shown)
        .animation(shown ? .spring(response: 0.28, dampingFraction: 0.95) : .easeOut(duration: 0.14), value: shown)
        .tip("Jump to latest", edge: .leading).accessibilityLabel("Jump to latest message").accessibilityHidden(!shown)
    }
}

// MARK: Rows (Discord: face, name, time, then the words; no bubbles)

struct ChatRowView: View, Equatable {
    let agent: Agent?; let row: ChatRow; let prev: ChatRow?
    /// Words to light (find in chat): set only on rows with a match, so finding redraws those rows and no others.
    var find = ""
    static func == (a: Self, b: Self) -> Bool { a.agent == b.agent && a.row == b.row && a.prev?.id == b.prev?.id && a.prev?.at == b.prev?.at && a.find == b.find }
    var body: some View {
        // A day line breaks a group; the first row of a day says which day.
        let newDay = row.at.map { a in prev?.at.map { dayLabel($0) != dayLabel(a) } ?? true } ?? false
        VStack(alignment: .leading, spacing: 0) {
            // The day sits on the name column (8 + face 40 + 16), 24 above it like a new message, and the row's own 12 below.
            if newDay, let a = row.at {
                if MV.on {
                    // MAVIS (spec 9): the day as a centred stamp.
                    Text(dayLabel(a)).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3)
                        .frame(maxWidth: .infinity).padding(.top, MV.Space.section - MV.Space.labelGap).padding(.bottom, MV.Space.gridGap)
                } else {
                    Line(dayLabel(a), 12, .semibold, C.i10).padding(.leading, 64).padding(.top, Rhythm.inset * 2 + Rhythm.gap)
                }
            }
            switch row {
            case .you(let id, let text, let at, let pending, let queued, let steered, let images):
                if MV.on {
                    // MAVIS: your turn is a blue bubble on the right (22% of the accent), radius 20, padding 10 16.
                    // Pictures and files sit above the bubble, on the right (Claude's, ChatGPT's); the bubble holds only words.
                    let sent = SentFiles.cached(text)
                    let words = sent.words
                    if !images.isEmpty || !sent.files.isEmpty {
                        MVSentImages(paths: images + sent.files).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, MV.Space.sm)
                    }
                    if !words.isEmpty || queued || steered {
                    HStack(spacing: 0) {
                        Spacer(minLength: MV.Chat.bubbleLead)
                        HugWidth(ideal: HugWidth.width(of: words)) { VStack(alignment: .leading, spacing: MV.Space.labelGap) {
                            if !words.isEmpty {
                                MarkdownText(text: words.count > 1500 ? String(words.prefix(1200)) + "\n\n…\(words.count - 1200) more characters of context" : words, color: MV.Ink.t1)
                            }
                            if queued || steered { Text(queued ? "Queued" : "Sent while it worked").font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3) }
                        } }
                        .padding(.horizontal, MV.Chat.bubbleX)
                        .padding(.top, MV.Chat.bubbleY - HugWidth.lift).padding(.bottom, MV.Chat.bubbleY + HugWidth.lift)
                        .background(MVBubbleFill(lit: RowLights.shared.lit(row.id)))
                        // The tools when you hover it (MessageTools.swift): over the bubble's foot, at its right.
                        .overlay(alignment: .bottomTrailing) {
                            if !pending, !queued, !steered {
                                MVToolsSlot(rowId: row.id, mine: true, time: at, agentId: agent?.id ?? "", messageId: id, words: words)
                            }
                        }
                        .opacity(queued ? 0.6 : 1)
                    }
                    // MAVIS: no Fork / Go back buttons popping over your messages (the prototype has none).
                    .padding(.vertical, MV.Space.sm)
                    }
                } else {
                RowFrame(face: AnyView(Circle().fill(C.v4).frame(width: 40, height: 40).overlay(Icon("person", 20).foregroundStyle(C.i10))),
                         name: "You", time: queued ? "Queued" : steered ? "\(at.map(clock) ?? "") · sent while it worked" : at.map(clock) ?? "", mine: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !images.isEmpty { SentImages(paths: images) }
                        if !text.isEmpty {
                            MarkdownText(text: text.count > 1500 ? String(text.prefix(1200)) + "\n\n…\(text.count - 1200) more characters of context" : text, color: C.i12)
                                .opacity(queued ? 0.6 : 1)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !pending, !queued, !steered, let agent { GoBack(agentId: agent.id, messageId: id).padding(.top, Rhythm.inset).padding(.trailing, 8) }
                }
                }
            case .agent(let turn):
                if MV.on {
                    // MAVIS: the agent's words as plain text, no face or name, in a reading width.
                    TurnSlot(agentId: agent?.id ?? turn.by ?? "", turn: turn)
                        .frame(maxWidth: MV.Chat.readWidth, alignment: .leading)
                        // Hovered: the row lights barely and its tools hang under the words, at the left.
                        .background(MVRowLight(lit: RowLights.shared.lit(row.id)))
                        .overlay(alignment: .bottomLeading) {
                            if !turn.running, !turn.isEmpty {
                                MVToolsSlot(rowId: row.id, mine: false, time: turn.at, agentId: agent?.id ?? turn.by ?? "", messageId: turn.id, words: turn.text)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, MV.Space.sm).padding(.bottom, MV.Space.inset)
                } else {
                // An agent that was deleted since keeps its words, under a plain grey face.
                RowFrame(face: agent.map { AnyView(Avatar(agent: $0, size: 40, status: false)) } ?? AnyView(RoundedRectangle(cornerRadius: Avatar.radius(40), style: .continuous).fill(C.v4).frame(width: 40, height: 40)),
                         name: agent?.name ?? "Removed agent", time: turn.at.map(clock) ?? (turn.running ? "now" : "")) {
                    TurnSlot(agentId: agent?.id ?? turn.by ?? "", turn: turn)
                }
                }
            case .note(_, let text, _):
                NoteRow(text: text)
            }
        }
        .environment(\.findQuery, find)
    }
}

/// A line from the app in the chat's flow (handed to another agent, compacted), on the name column, quiet. "Handed to
/// Bram." opens Bram's chat. Watches nothing: the agent is looked up only when you click.
struct NoteRow: View {
    let text: String
    var body: some View {
        let handed = text.hasPrefix("Handed to ")
        HStack(spacing: 8) {
            Image(systemName: handed ? "arrow.turn.up.right" : text.hasPrefix("Compacted") ? "arrow.down.right.and.arrow.up.left" : "info.circle")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(C.i9).frame(width: 16)
            Text(text).font(F.font(13, .regular)).foregroundStyle(C.i10).lineLimit(2)
            if handed {
                Hover { h in
                    Button { open() } label: { Text("Open chat").font(F.font(12, .medium)).foregroundStyle(h ? C.i12 : C.i10).underline(h) }.buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 64).padding(.vertical, Rhythm.inset)
    }
    private func open() {
        guard let s = ConvoHub.shared.store else { return }
        let name = String(text.dropFirst("Handed to ".count)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if let a = s.agents.first(where: { $0.name == name }) { s.openChat(a.id) } else { s.toast = "\(name) is no longer here." }
    }
}

/// Face 40 at the left, name 16 semibold and the time, then the content (web: .ln).
/// The chat's vertical spacing: one inset per row edge, one gap between rows. Nothing else adds vertical space between rows.
enum Rhythm { static let inset: CGFloat = 12, gap: CGFloat = 0 }

/// Your messages sit on a faint neutral wash with more room around them, so you can tell your turns from everyone else's.
struct RowFrame<Content: View>: View {
    let face: AnyView; let name: String; let time: String; var mine = false
    /// The agent's words in its own chat: no face, no name, just the reply, starting where your words start (19 Nov:
    /// as Claude shows an answer).
    var bare = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if bare { Color.clear.frame(width: 40, height: 1) } else { face.frame(width: 40) }
            VStack(alignment: .leading, spacing: 2) {
                if !bare {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name).font(F.font(16, .semibold)).foregroundStyle(C.i12)
                        Text(time).font(F.font(12, .regular)).foregroundStyle(C.i10).monospacedDigit()
                    }
                }
                content()
            }

            .frame(maxWidth: 720, alignment: .leading)
            Spacer(minLength: 0)
        }
        // Vertical rhythm (8pt grid), the same for every row in every chat:
        //   each row owns 12 above and 12 below its content (your highlight fills exactly that band),
        //   and rows touch, so any message's content is 24 from the next one's.
        .padding(.horizontal, 8).padding(.vertical, Rhythm.inset)
        // Edge to edge: square, and out past the list's 16pt side inset to both sides of the pane.
        .background(Rectangle().fill(Color.white(mine ? 0.04 : 0)).padding(.horizontal, -16))
        .padding(.top, Rhythm.gap)
    }
}

/// A row's fill: yours rests a shade lighter; under the pointer any row lights a shade more (as Discord's), at once,
/// with no toolbar. Only this view redraws as the pointer comes and goes.
final class Lit: ObservableObject { @Published var on = false }
/// The row under the pointer, one at a time: the chat's tracker lights one and puts the last one out, so a move redraws
/// two thin fills and nothing else.
@MainActor final class RowLights {
    static let shared = RowLights()
    private var lits: [String: Lit] = [:]
    private(set) var current: String?
    func lit(_ id: String) -> Lit { if let l = lits[id] { return l }; let l = Lit(); lits[id] = l; return l }
    func light(_ id: String?) {
        guard id != current else { return }
        if let c = current { lits[c]?.on = false }
        current = id
        if let id { lit(id).on = true }
    }
}
private struct RowLightFill: View {
    @ObservedObject var lit: Lit
    var body: some View { Rectangle().fill(Color.white(lit.on ? 0.025 : 0)) }
}

// MARK: A turn (chat-rules §3), the same views in the same places from the first word to the last

/// Picks how a turn is drawn. A finished turn from before is plain values: it watches nothing, so streaming, a send
/// or any other change in the app never redraws it. Only a turn that's running, or whose words are still being
/// written out, watches the live words and your approvals (LiveTurn).
struct TurnSlot: View {
    let agentId: String; let turn: Turn
    var body: some View {
        if turn.running || LiveWords.shared.isLive(turn.id) { LiveTurn(agentId: agentId, turn: turn, work: ConvoHub.shared.work(agentId)) }
        else { TurnBody(agentId: agentId, turn: turn, shown: turn.text.count, approvals: []) }
    }
}
struct LiveTurn: View {
    @EnvironmentObject var s: Store
    @ObservedObject private var words = LiveWords.shared
    @Environment(\.chatConv) private var conv
    let agentId: String; let turn: Turn
    /// Commands it has running (a long one, or one left in the background): the line names them while nothing else runs.
    @ObservedObject var work: AgentWork
    var body: some View {
        // This conversation's run and asks only (an agent can work in its DM and a channel at once).
        let here = conv ?? agentId
        let run = s.runs.values.first { $0.agentId == agentId && ($0.conversation ?? agentId) == here }
        TurnBody(agentId: agentId, turn: turn, shown: words.count(turn),
                 approvals: turn.running ? s.approvals.filter { $0.agentId == agentId && ($0.conv ?? agentId) == here } : [],
                 activity: turn.running ? run?.activity : nil,
                 detail: turn.running ? run?.detail : nil,
                 command: turn.running && here == agentId ? work.commands.last?.line : nil)
    }
}

struct TurnBody: View {
    let agentId: String; let turn: Turn
    /// How many of its words show (LiveWords), and what waits for your OK while it runs.
    let shown: Int; let approvals: [Approval]
    /// While it runs: what the engine says it's on ("Preparing a command"), and a command still running.
    var activity: String? = nil
    var detail: String? = nil
    var command: String? = nil
    var body: some View {
        let running = turn.running
        let all = TurnFlow.pieces(steps: turn.steps, raw: turn.raw, shown: shown)
        let (opening, work, tail) = TurnFlow.split(all)
        let plan = turn.plan
        let current = turn.steps.last { !$0.done }
        let answering = !tail.isEmpty && current == nil
        let writingReport = running && current == nil && ReportTag.reports(turn.raw).last.map { !$0.finished } == true
        // The line shows while it works: from the instant you send, and whenever a plan or a step is under way.
        // It reads the turn's real steps, not only revealed ones, so it never drops out between a step starting and its
        // words showing (Mavis 15 Nov: the chat shrank and grew back). A plain answer streaming with no tools has none.
        let line = running && (all.isEmpty || !turn.steps.isEmpty || plan != nil)
        // Done with work: the opening sentence folds away with the steps, as the first thing inside the summary row.
        let folded = !running && !work.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            if !folded {
                ForEach(opening) { piece in if case .words(_, let text) = piece { MarkdownText(text: text, color: Color.white(0.82)) } }
            }
            if running, let plan {
                let rounds = turn.raw.contains("⟦plan") ? PlanTag.finishedRounds(turn.steps.map { (round: $0.round, finished: $0.done) }) : 0
                PlanCard(plan: PlanTag.progress(plan, finishedRounds: rounds, answering: answering))
            }
            if line {
                StatusLine(label: approvals.isEmpty ? Self.label(current: current, command: command, activity: activity, writingReport: writingReport, answering: answering) : "Waiting for your OK",
                           waiting: !approvals.isEmpty, started: turn.startedAt, work: work,
                           detail: approvals.isEmpty && current == nil && command == nil ? detail : nil)
            }
            if running { ForEach(Array(approvals.enumerated()), id: \.element.id) { i, p in ApprovalCard(p: p, primary: i == 0) } }
            if folded { FoldedWork(pieces: opening + work) }
            if !running {
                let changed = ChangedFiles.gather(turn.steps)
                if !changed.isEmpty { ChangedFiles(files: changed, review: turn.by == nil ? SidePanel.existing(agentId).map { p in { p.showChatChanges() } } : nil) }
            }
            // As Mavis final launch (AgentSteps.swift TurnView): the words after the last step stay out while it works
            // (the status line says "Writing"), and arrive with the reports in the one still swap when the turn ends.
            if !running {
                ForEach(tail) { piece in if case .words(_, let text) = piece { MarkdownText(text: text, color: Color.white(0.82)) } }
                // Once the turn is over nothing more is coming: a report never closed is as finished as it'll get.
                // A long report (heavy work) is a card that opens beside the chat, and opens there by itself once written;
                // anything shorter is simply part of the answer, shown in full.
                ForEach(Array(ReportTag.reports(turn.raw).enumerated()), id: \.offset) { i, r in
                    let report = ReportTag.Report(title: r.title, body: r.body, finished: true)
                    if report.long { ReportCard(report: report, id: Reports.id(turn.id, i)) }
                    else { MarkdownText(text: "### " + r.title + "\n\n" + r.body, color: Color.white(0.82)) }
                }
                if turn.stopped { InterruptedLine() }
                if let e = turn.error { Text(e).font(F.font(14, .regular)).foregroundStyle(FAIL_TEXT).fixedSize(horizontal: false, vertical: true) }
            }
        }
        // One still swap when it ends: no animation from anywhere carries across (Mavis 15 Nov: a cross-fade grew,
        // scrolled, then shrank the chat on every turn).
        .transaction(value: running) { $0.animation = nil; $0.disablesAnimations = true }
    }
}

extension TurnBody {
    /// The line's words, as Mavis's: the step under way; else a command still running; else the step being written
    /// ("Preparing a command"); else "Writing" (the answer) or "Thinking". It changes in place, never stalls on Thinking
    /// while something is running.
    static func label(current: Step?, command: String?, activity: String?, writingReport: Bool, answering: Bool) -> String {
        if let current { return StepWords.live(current) }
        if let command { return "Running " + command }
        if let a = activity, a.hasPrefix("Preparing") || a.hasPrefix("Couldn't reach") { return a }
        return writingReport ? "Writing the report" : answering ? "Writing" : "Thinking"
    }
}

/// The to-do card: the plan in plain words, ticked as it's done. Hugs its content (min 240).
struct PlanCard: View {
    let plan: PlanTag.Plan
    var body: some View {
        let current = (1...plan.items.count).first { !plan.done.contains($0) }
        VStack(alignment: .leading, spacing: MV.on ? MV.Space.xs : 10) {
            ForEach(Array(plan.items.enumerated()), id: \.offset) { i, item in
                let n = i + 1, done = plan.done.contains(n)
                HStack(spacing: MV.on ? MV.Space.gridGap : 10) {
                    StepMark(state: done ? "done" : n == current ? "running" : "pending")
                    Text(item).font(F.font(MV.on ? MV.Text.title : 14, .regular))
                        .foregroundStyle(MV.on ? (done ? MV.Ink.t3 : n == current ? MV.Ink.t1 : MV.Ink.t2) : done ? C.i9 : C.i12).lineLimit(2)
                }
                .frame(minHeight: MV.on ? MV.Chat.planRow : 0)
            }
        }
        .padding(.horizontal, MV.on ? MV.Space.headerLead : 16).padding(.vertical, MV.on ? MV.Space.inset : 14)
        .frame(minWidth: 240, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        // MAVIS: a card on box, radius 16, with the chat box's own hairline (the system's 8% white ring), so it reads as
        // a raised card, not a flat patch.
        .background(RoundedRectangle(cornerRadius: MV.on ? MV.Radius.card : R.card, style: .continuous).fill(MV.on ? MV.Tone.box : C.v2))
        .overlay {
            if MV.on { RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).strokeBorder(MV.Stroke.boxHover, lineWidth: MV.Stroke.boxRestWidth) }
            else { RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1) }
        }
        .animation(.easeOut(duration: 0.16), value: plan.done)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan: " + plan.items.enumerated().map { "\($0.element)\(plan.done.contains($0.offset + 1) ? ", done" : "")" }.joined(separator: "; "))
    }
}

/// done: a tick; running: a turning ring; pending: a dashed ring; failed: a cross.
struct StepMark: View {
    let state: String
    @State private var turn = false
    var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS (18 pt): done, a bold tick in a filled circle; working, a turning ring; to do, a dashed ring; failed, red.
    @ViewBuilder private var mavis: some View {
        Group {
            switch state {
            case "running":
                Circle().trim(from: 0, to: MV.Chat.ringArc).stroke(MV.Ink.t1, style: StrokeStyle(lineWidth: MV.Chat.markLine, lineCap: .round))
                    .rotationEffect(.degrees(turn ? MV.Chat.fullTurn : 0))
                    .onAppear { withAnimation(.linear(duration: MV.Chat.ringTurn).repeatForever(autoreverses: false)) { turn = true } }
                    .padding(MV.Stroke.list)
            case "pending": Circle().stroke(MV.Ink.t3, style: StrokeStyle(lineWidth: MV.Chat.markLine, dash: [MV.Stroke.boxTypingWidth, MV.Stroke.boxTypingWidth])).padding(MV.Stroke.list)
            case "failed": Circle().fill(MV.Accent.red).overlay(Icon("mvClose", MV.Size.iconSmall - MV.Space.sm).foregroundStyle(MV.Tone.box))
            default: Circle().fill(MV.Ink.t2).overlay(Icon("check", MV.Size.iconSmall - MV.Space.xs).fontWeight(.bold).foregroundStyle(MV.Tone.box))
            }
        }
        .frame(width: MV.Chat.mark, height: MV.Chat.mark)
    }
    @ViewBuilder private var classic: some View {
        Group {
            switch state {
            case "running":
                Circle().trim(from: 0, to: 0.7).stroke(C.i12, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turn = true } }
            case "pending": Circle().stroke(C.i9, style: StrokeStyle(lineWidth: 1.3, dash: [2, 2.2]))
            case "failed": Icon("x", 12).foregroundStyle(FAIL_TEXT)
            default: Icon("check", 14).foregroundStyle(C.i9)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// Four dots taking turns while it works.
struct WorkSpinner: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { c in
            let lit = Int(c.date.timeIntervalSinceReferenceDate / 0.12) % 4
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow { dot(lit == 0); dot(lit == 1) }
                GridRow { dot(lit == 3); dot(lit == 2) }
            }
            .frame(width: 14, height: 14)
        }
    }
    private func dot(_ on: Bool) -> some View { Circle().fill(C.i12.opacity(on ? 1 : 0.3)).frame(width: 4, height: 4) }
}

/// One small line while it works: spinner, the step under way (or "Thinking" / "Writing"), the time after 1 s. Its
/// arrow opens every step so far and the words in between, capped at 200, newest in view.
struct StatusLine: View {
    let label: String; let waiting: Bool; let started: Double?; let work: [Piece]
    /// Under the label, dim: what it's on right now (Claude Code's), so a long think or a big file never reads as stuck.
    var detail: String? = nil
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Button { if !work.isEmpty { withAnimation(StepMotion.animation(opening: !open)) { open.toggle() } } } label: {
                    HStack(spacing: 8) {
                        // MAVIS: no spinner; the words themselves shimmer while it works (as ChatGPT's "Thinking").
                        if !MV.on { WorkSpinner() }
                        // Changes in place, in one frame (a cross-fade drew old and new words over each other).
                        if MV.on && !waiting {
                            Shimmer(text: label, font: F.font(MV.Text.title, .regular))
                        } else {
                            Text(label).font(F.font(14, .regular)).foregroundStyle(waiting ? WAIT_TEXT : C.i10).lineLimit(1).truncationMode(.middle)
                        }
                        if let started { let d = Date().timeIntervalSince1970 - started / 1000; if d >= 1 { Text(StepWords.clock(d)).font(F.font(14, .regular)).monospacedDigit().foregroundStyle(C.i9) } }
                        if !work.isEmpty { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(StepInk.rest).rotationEffect(.degrees(open ? 90 : 0)) }
                    }
                    .frame(minHeight: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transaction { $0.animation = nil }
            }
            if let detail, !detail.isEmpty, !open {
                Text(detail).font(F.font(MV.on ? MV.Text.meta : 13, .regular)).foregroundStyle(MV.on ? MV.Ink.t3 : C.i9)
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: MV.on ? MV.Chat.readWidth : .infinity, alignment: .leading)
                    .transaction { $0.animation = nil }
            }
            if open {
                ScrollView(.vertical) { WorkList(pieces: work).background(CapsuleScrollers()) }
                    .scrollIndicators(.never).defaultScrollAnchor(.bottom)
                    .frame(maxHeight: 200).fixedSize(horizontal: false, vertical: true)
                    .transition(StepMotion.reveal)
            }
        }
    }
}

/// A finished turn's work as one line in everyday words ("Ran a few checks and made some changes"), opening in place
/// to every step and the words between.
struct FoldedWork: View {
    let pieces: [Piece]
    @State private var open = false
    var body: some View {
        let steps = pieces.flatMap { p -> [Step] in if case .steps(_, let s) = p { s } else { [] } }
        VStack(alignment: .leading, spacing: 8) {
            Hover { h in
                Button { withAnimation(StepMotion.animation(opening: !open)) { open.toggle() } } label: {
                    HStack(spacing: 5) {
                        // MAVIS: a plain count, never a made-up sentence about the work ("4 steps").
                        Text(MV.on ? "\(steps.count) \(steps.count == 1 ? "step" : "steps")" : StepWords.summary(steps)).font(F.font(14, .regular)).foregroundStyle(h || open ? StepInk.lit : StepInk.rest).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(h || open ? StepInk.lit : StepInk.rest)
                            .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 10)
                    }
                    .frame(minHeight: 22).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .tip(open ? "Hide the work" : "Show the work", edge: .top)
            if open { WorkList(pieces: pieces).transition(StepMotion.reveal) }
        }
    }
}

/// Steps and the words between them, in order (Mavis: FoldedWork opened): each run of steps on its own card, the words
/// between as the chat's own words, set in as far as a step's.
struct WorkList: View {
    let pieces: [Piece]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pieces) { piece in
                switch piece {
                case .steps(_, let steps): StepCardView(steps: steps)
                // MAVIS: the words between steps sit flush with the step cards' edge (and the answer under them).
                case .words(_, let text): MarkdownText(text: text, color: Color.white(0.82)).padding(.leading, MV.on ? 0 : StepInk.edge)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The full write-up behind an answer, as a card that opens.
struct ReportCard: View {
    @EnvironmentObject var s: Store
    let report: ReportTag.Report
    var id: String = ""
    @Environment(\.chatAgentId) private var agentId
    @Environment(\.chatConv) private var conv
    var body: some View {
        Hover { h in
            Button { open() } label: {
                HStack(spacing: 12) {
                    Icon("file", 20).foregroundStyle(C.i10).frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v3))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.title).font(F.font(14, .semibold)).foregroundStyle(C.i12).lineLimit(1)
                        Text(report.finished ? "Report · \(report.words) words" : "Writing the report · \(report.words) words").font(F.font(12, .regular)).foregroundStyle(C.i10).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Text("Open").font(F.font(13, .medium)).foregroundStyle(C.i12).padding(.horizontal, 12).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v4 : C.v3))
                }
                .padding(12).frame(maxWidth: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: R.card).fill(C.v2))
                .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(h ? C.v5 : C.v4, lineWidth: 1))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .accessibilityLabel("Report: \(report.title)")
    }
    /// Opens in its tab beside the chat (a thread you can close and come back to); with no side panel (a channel), as
    /// a sheet over the window.
    private func open() {
        if !id.isEmpty, let panel = s.panel(conv: conv, agentId: agentId) {
            Reports.shared.opened.insert(id)
            panel.showReport(id: id, report)
        } else { s.openReport = report }
    }
}

/// Reports beside the chat: their words by id (kept with their tabs across launches), and the ones already opened by
/// themselves (each long report opens once, when it's written, never again after you close it).
@MainActor final class Reports: ObservableObject {
    static let shared = Reports()
    @Published var body: [String: String] = [:]
    var opened: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "reportsOpened") ?? []) {
        didSet { UserDefaults.standard.set(Array(opened.suffix(500)), forKey: "reportsOpened") }
    }
    nonisolated static func id(_ turn: String, _ index: Int) -> String { "\(turn)#\(index)" }
}

/// A report in its tab: its title, Copy, and the full write-up, scrolling.
struct ReportTab: View {
    let id: String
    @ObservedObject private var reports = Reports.shared
    @EnvironmentObject var s: Store
    var body: some View {
        if let text = reports.body[id] {
            ScrollView(.vertical) {
                MarkdownText(text: text, color: Color.white(0.82))
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .overlay(alignment: .topTrailing) {
                CopyChip(text: text).padding(10)
            }
        } else {
            Line("This report is no longer here", 14, .medium, C.i10).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A report, read in full.
struct ReportSheet: View {
    @EnvironmentObject var s: Store
    let report: ReportTag.Report
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).contentShape(Rectangle()).onTapGesture { s.openReport = nil }
            VStack(spacing: 0) {
                HStack {
                    Line(report.title, 20, .semibold)
                    Spacer()
                    Hover { h in
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report.body, forType: .string) } label: {
                            Line("Copy", 14, .medium).padding(.horizontal, 12).frame(height: 32).background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v4 : C.v3))
                        }.buttonStyle(.plain)
                    }
                    Hover { h in
                        Button { s.openReport = nil } label: { Icon("x", 14).foregroundStyle(C.i10).frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : .clear)) }.buttonStyle(.plain)
                    }.tip("Close")
                }
                .padding(.horizontal, 24).frame(height: 64)
                .overlay(alignment: .bottom) { Rectangle().fill(C.divider).frame(height: 1) }
                ScrollView { MarkdownText(text: report.body, color: Color.white(0.82)).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .frame(width: 720).frame(maxHeight: 640)
            .background(C.v1).clipShape(RoundedRectangle(cornerRadius: R.card))
            .overlay(RoundedRectangle(cornerRadius: R.card).stroke(C.edgeControl, lineWidth: 1).padding(-0.5))
            .floatShadow()
        }
        .onExitCommand { s.openReport = nil }
    }
}

struct InterruptedLine: View {
    var body: some View {
        HStack(spacing: 8) {
            if !MV.on { RoundedRectangle(cornerRadius: 1.5).fill(C.i10).frame(width: 7, height: 7) }
            Text("Interrupted").font(F.font(MV.on ? MV.Text.title : 14, .regular)).foregroundStyle(MV.on ? MV.Chat.stopped : C.i10)
        }
        .frame(minHeight: 22).padding(.top, 4)
    }
}

struct BlurOn: ViewModifier { let r: CGFloat; func body(content: Content) -> some View { content.blur(radius: r) } }

// MARK: The box (fixed size: nothing appears above or below it while the agent works)

struct ChatComposer: View {
    @EnvironmentObject var s: Store
    @ObservedObject private var words = LiveWords.shared
    @StateObject private var dictation = Dictation()
    let agent: Agent
    @StateObject private var model = ComposerModel()
    @State private var permOpen = false
    /// What was in the box when you started talking: your words are added after it as you speak.
    @State private var before = ""
    // The chat box as it was (one row: +, your words, the stop slot), with Mavis final launch's two controls added in
    // the same style: beside the +, what the agent may do without asking; before the stop slot, talk (the mic writes
    // what you say into the box). The stop slot is always there, so the box never changes size when a run starts.
    @State private var boxHover = false
    var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS (spec 7): the shared chat box (MVChatBox), wired to this agent.
    var mavis: some View {
        let key = "agent:\(agent.id)"
        let busy = s.runs[key] != nil
        return MVChatBox(model: model, dictation: dictation,
                         placeholder: busy ? "Add to what \(agent.name) is doing\u{2026}" : "Message \(agent.name)",
                         busy: busy, modeAgent: agent, stop: { s.stop(key) }, talk: { talk() },
                         talkSend: { dictation.finish { heard in model.set(Self.join(before, heard), caretAtEnd: true); model.submit() } },
                         dropKey: key)
        .onAppear { connect(); takeRestore() }
        .onChange(of: agent.id) { _, _ in connect() }
        .onChange(of: s.restore[agent.id]) { _, _ in takeRestore() }
        .onDisappear { model.save() }
        .onChange(of: dictation.transcript) { _, heard in if dictation.active { model.set(Self.join(before, heard), caretAtEnd: true) } }
        .onChange(of: dictation.failure) { _, f in if let f { s.toast = f } }
    }
    var classic: some View {
        let key = "agent:\(agent.id)"
        let busy = s.runs[key] != nil
        return HStack(alignment: .bottom, spacing: Box.gap) {
            HStack(spacing: Box.pair) {
            Hover { h in
                Button {
                    guard Date().timeIntervalSince(PermCard.closedAt) > 0.3 else { return }
                    permOpen.toggle()
                } label: {
                    let mode = Mode.of(agent.permission)
                    let lit = h || permOpen
                    // Full access tints the whole button in its yellow (the way Delete's row washes red), not just the icon.
                    let fill: Color = mode.tint.map { $0.opacity(lit ? 0.16 : 0.10) } ?? (lit ? C.v4 : C.v3)
                    Image(systemName: mode.symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(mode.tint ?? (lit ? C.i12 : C.i10))
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(fill))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .tip("Mode: \(Mode.of(agent.permission).title)", "⌘⇧M", edge: .top)
            .accessibilityLabel("Mode, \(Mode.of(agent.permission).title)")
            ComposerButton(icon: "paperclip", label: "Add files, commands, plugins") { model.toggleMenu() }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !model.images.isEmpty || !model.files.isEmpty { AttachmentStrip(model: model).padding(.top, 6) }
                ZStack(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text(dictation.active ? "Listening…" : busy ? "Add to what @\(agent.name) is doing…" : "Message @\(agent.name), / for commands, @ for files")
                            .font(F.font(16, .regular)).foregroundStyle(C.i9).lineLimit(1).allowsHitTesting(false)
                    }
                    ComposerField(model: model).frame(height: model.height).padding(.horizontal, -Chip.room)
                }
                .padding(.vertical, 8)
            }
            .frame(minHeight: 40)
            // One control at the right, always there: the mic (talk; ✓ while you're talking keeps what you said), and while
            // the agent works, Stop in its place, as Claude's: just the square, no disc or box around it. The swap is
            // instant both ways.
            ZStack {
                if busy {
                    Hover { h in
                        Button { s.stop(key) } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(h ? C.i12 : Color.white(0.86)).frame(width: 14, height: 14)
                                .frame(width: 40, height: 40)
                                // The box's button under the pointer (as Claude Code's): the same fill and corners as its neighbours.
                                .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(h ? C.v4 : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .tip("Stop", "Esc", edge: .top).accessibilityLabel("Stop")
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Hover { h in
                        Button { talk() } label: {
                            Icon(dictation.active ? "check" : "mic", 20).foregroundStyle(C.v0)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(h || dictation.active ? C.i12 : Color.white)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .tip(dictation.active ? "Done talking" : "Talk to \(agent.name)", edge: .top)
                    .accessibilityLabel(dictation.active ? "Done talking" : "Talk to \(agent.name)")
                }
            }
            .frame(width: 40, height: 40)
            .transaction { $0.animation = nil }
        }
        .padding(Box.pad)
        .background(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if permOpen {
                PermCard(current: Mode.of(agent.permission), alwaysEdits: agent.alwaysEdits == true, open: $permOpen) { patch in
                    Task { do { try await s.updateAgent(agent.id, patch) } catch { s.toast = error.localizedDescription } }
                }
                .offset(x: Box.pad, y: -(PermCard.height(alwaysEdits: agent.alwaysEdits == true) + 8))
            }
        }
        // Raised off the window's foot, as Claude Code's box is: a lift of shadow and room under it.
        .shadow(color: .black.opacity(themeNow.dark ? 0.5 : 0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(themeNow.dark ? 0.35 : 0.06), radius: 12, y: 6)
        .modifier(ComposerOverlays(model: model))
        .zIndex(1)
        .padding(.horizontal, 16).padding(.bottom, Box.lift)
        .onAppear { connect(); takeRestore() }
        .onChange(of: agent.id) { _, _ in connect() }
        .onChange(of: s.restore[agent.id]) { _, _ in takeRestore() }
        .onDisappear { model.save() }
        .onChange(of: dictation.transcript) { _, heard in if dictation.active { model.set(Self.join(before, heard), caretAtEnd: true) } }
        .onChange(of: dictation.failure) { _, f in if let f { s.toast = f } }
    }
    /// Words put back for this box (going back to one of your messages, or a fork opening with it): into an empty box
    /// only (what you've typed since wins).
    func takeRestore() {
        guard let back = s.restore[agent.id], model.isEmpty else { return }
        model.set(back.text, caretAtEnd: true); model.images = back.images; model.save(); model.takeFocus()
        s.restore[agent.id] = nil
    }
    /// Ties the box to this agent: its draft, its commands, what sending and Esc do.
    func connect() {
        model.attach(.agent(agent.id), store: s)
        model.send = { [s, agent] text, images, files in s.sendMessage(agent.id, text, images: images, files: files) }
        model.escape = { [s, agent, dictation] in
            if dictation.active { dictation.cancel() } else if s.runs["agent:\(agent.id)"] != nil { s.stop("agent:\(agent.id)") }
        }
    }
    func talk() {
        if dictation.active {
            dictation.finish { heard in model.set(Self.join(before, heard), caretAtEnd: true) }
        } else {
            before = model.text
            dictation.start()
        }
    }
    static func join(_ a: String, _ b: String) -> String {
        let x = a.trimmingCharacters(in: .whitespaces), y = b.trimmingCharacters(in: .whitespaces)
        return x.isEmpty ? y : y.isEmpty ? x : x + " " + y
    }

}

/// The Mode card (Mavis final launch's, row for row): what the agent may do without asking. The current mode is lit;
/// click one or press 1–4. Closes on a choice, Esc or a click outside. When file changes are always allowed (from an
/// approval card), it says so under the modes, with a way to turn it off.
struct PermCard: View {
    let current: Mode; let alwaysEdits: Bool; @Binding var open: Bool
    /// Saves a change to the agent: ["permission": mode] or ["alwaysEdits": false].
    let save: ([String: Any]) -> Void
    @State private var inside = false
    @State private var monitor: Any?
    @MainActor static var closedAt = Date.distantPast
    static func height(alwaysEdits: Bool) -> CGFloat { 2 * ActionMenu.padding + 28 + 4 * 52 + 4 * 2 + (alwaysEdits ? 2 * 2 + 1 + 4 + 40 : 0) }
    var body: some View {
        // Drawn as the ⋯ menus are (ActionMenu): the same card, padding, row corner, icon and type sizes; hover is the
        // only fill, the current mode carries a check. Full access keeps its yellow the way Delete keeps its red: on the
        // icon and title, and as a faint wash when you point at it.
        VStack(alignment: .leading, spacing: 2) {
            Text("Mode").font(F.font(12, .medium)).foregroundStyle(C.i9).padding(.horizontal, 8).frame(height: 28)
            ForEach(Array(Mode.allCases.enumerated()), id: \.element) { i, m in
                Hover { h in
                    Button { choose(m) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: m.symbol).font(.system(size: 14)).foregroundStyle(m.tint ?? C.i12).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Line(m.title, 14, .medium, m.tint ?? C.i12)
                                    if m == .ask {
                                        Text("Default").font(F.font(11, .medium)).foregroundStyle(C.i10)
                                            .padding(.horizontal, 6).frame(height: 16).background(Capsule().fill(C.v4))
                                    }
                                }
                                Text(m.detail).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            ZStack(alignment: .trailing) {
                                if m == current { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(m.tint ?? C.i12) }
                                else { Text("\(i + 1)").font(F.font(12, .medium)).foregroundStyle(C.i9).monospacedDigit() }
                            }
                            .frame(width: 16, alignment: .trailing)
                        }
                        .padding(.horizontal, 8).frame(height: 52)
                        .background(ActionMenu.shape.fill(h ? (m.tint.map { $0.opacity(0.10) } ?? C.v3) : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .accessibilityLabel("\(m.title): \(m.detail)").accessibilityAddTraits(m == current ? .isSelected : [])
            }
            if alwaysEdits {
                Rectangle().fill(C.divider).frame(height: 1).padding(.vertical, 2).padding(.horizontal, 4)
                HStack(spacing: 8) {
                    Text("File changes are always allowed").font(F.font(12, .regular)).foregroundStyle(C.i10)
                    Spacer(minLength: 8)
                    SmallSecondaryButton(title: "Turn off") { save(["alwaysEdits": false]); open = false }
                }
                .padding(.horizontal, 8).frame(height: 40)
            }
        }
        .padding(ActionMenu.padding).frame(width: 300)
        .background(RoundedRectangle(cornerRadius: R.card, style: .continuous).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
        .containerShape(RoundedRectangle(cornerRadius: R.card, style: .continuous))
        .floatShadow()
        .onHover { inside = $0 }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { e in
                if e.type == .keyDown {
                    if e.keyCode == 53 { DispatchQueue.main.async { open = false }; return nil }
                    if let n = Int(e.charactersIgnoringModifiers ?? ""), (1...4).contains(n), e.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                        DispatchQueue.main.async { choose(Mode.allCases[n - 1]) }; return nil
                    }
                    return e
                }
                if !inside { PermCard.closedAt = Date(); DispatchQueue.main.async { if open { open = false } } }
                return e
            }
        }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
    }
    func choose(_ m: Mode) { save(["permission": m.rawValue]); open = false }
}


// MARK: The scrollbar: a thin capsule on its own, no track (as Claude Code draws it on a Mac), in our greys

/// A 6 pt capsule (8 pt while you point at or drag it) that floats over the content: no track, no slot, no room taken
/// from the column. It shows while you scroll and fades when you stop, as macOS's overlay scrollers do.
final class CapsuleScroller: NSScroller {
    static let rest = NSColor(srgbRed: 0x45 / 255.0, green: 0x45 / 255.0, blue: 0x45 / 255.0, alpha: 1)   // C.v6
    static let lit = NSColor(srgbRed: 0x87 / 255.0, green: 0x87 / 255.0, blue: 0x87 / 255.0, alpha: 1)    // C.i9
    private var pointing = false { didSet { if pointing != oldValue { needsDisplay = true } } }
    private var area: NSTrackingArea?

    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 14 }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnob() {
        let r = rect(for: .knob)
        guard r.height > 0, knobProportion < 1 else { return }
        let w: CGFloat = pointing ? 8 : 6
        let k = NSRect(x: bounds.maxX - 3 - w, y: r.minY + 2, width: w, height: max(w, r.height - 4))
        (pointing ? Self.lit : Self.rest).setFill()
        NSBezierPath(roundedRect: k, xRadius: w / 2, yRadius: w / 2).fill()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with event: NSEvent) { pointing = true }
    override func mouseExited(with event: NSEvent) { pointing = false }

    /// Puts the capsule on a scroll view (once).
    static func install(in view: NSScrollView?) {
        guard let view, !(view.verticalScroller is CapsuleScroller) else { return }
        view.scrollerStyle = .overlay
        view.verticalScroller = CapsuleScroller()
        view.hasVerticalScroller = true
        view.autohidesScrollers = true
    }
}

/// Drop in any SwiftUI ScrollView's content to give it the capsule.
struct CapsuleScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Finder() }
    func updateNSView(_ v: NSView, context: Context) {}
    final class Finder: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); CapsuleScroller.install(in: enclosingScrollView) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}


/// MAVIS chat box (spec 7), the one box for a chat with an agent and for a workspace channel: a 52 pill (radius 26) on
/// box with the 4 / 8 / 12% outline; paperclip, your words, then the mic, which turns into a white send once you type
/// (Stop while it works). Talking is a mode you can see: the outline turns blue, the words say "Listening…", a ✕ leaves
/// it and the white ✓ (the send button's look) keeps what you said. Under it, the Mode pill for the agent that answers.
struct MVChatBox: View {
    @EnvironmentObject var s: Store
    @ObservedObject var model: ComposerModel
    @ObservedObject var dictation: Dictation
    let placeholder: String
    let busy: Bool
    let modeAgent: Agent?
    let stop: () -> Void
    let talk: () -> Void
    /// Finish talking and send what you said at once (the white button while you talk).
    let talkSend: () -> Void
    /// Which chat this box belongs to: files dropped on that chat land here.
    let dropKey: String
    @State private var permOpen = false
    @State private var boxHover = false
    var body: some View {
        let has = !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.images.isEmpty || !model.files.isEmpty
        let shape = RoundedRectangle(cornerRadius: MV.Radius.chatBox, style: .continuous)
        let talking = dictation.active
        return VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            VStack(alignment: .leading, spacing: 0) {
            // Attachments along the box's top-left (ChatGPT's): flat tiles, their corners concentric with the box's.
            if !model.images.isEmpty || !model.files.isEmpty {
                MVAttachments(model: model).padding(.bottom, MV.Space.sm)       // 6 from the box's edges (its padding), 6 above the row
            }
            HStack(alignment: .bottom, spacing: MV.Space.rowGap) {
                MVRoundButton(icon: "mvClip", label: "Add files, commands, plugins") { model.toggleMenu() }
                VStack(alignment: .leading, spacing: MV.Space.sm) {
                    ZStack(alignment: .topLeading) {
                        if model.text.isEmpty {
                            Text(talking ? "Listening\u{2026}" : placeholder)
                                .font(F.font(MV.Text.chatInput, .regular)).foregroundStyle(talking ? MV.Accent.selectedText : MV.Ink.t3).lineLimit(1)
                                .frame(height: MV.Chat.inputLine).allowsHitTesting(false)
                        }
                        ComposerField(model: model).frame(height: model.height).padding(.horizontal, -Chip.room)
                    }
                    .padding(.vertical, MV.Space.labelGap)
                }
                .padding(.leading, MV.Space.sm)
                .frame(minHeight: MV.Size.chatButton)
                HStack(spacing: MV.Space.xs) {
                    if busy {
                        MVRoundButton(icon: "stop", label: "Stop", fill: MV.Tone.box2, action: stop)
                            .keyboardShortcut(".", modifiers: .command)
                    } else if talking {
                        // Stop: what you said stays in the box to edit. The white arrow sends it at once.
                        MVRoundButton(icon: "mvStopSquare", label: "Stop and keep the words", fill: MV.Tone.box2, action: talk)
                        MVRoundButton(icon: "mvSend", label: "Send", fill: Color.white, ink: MV.Ink.onWhite, action: talkSend)
                    } else if has {
                        MVRoundButton(icon: "mvSend", label: "Send", fill: Color.white, ink: MV.Ink.onWhite) { model.submit() }
                    } else {
                        MVRoundButton(icon: "mvMic", label: "Talk", fill: MV.Tone.box2, action: talk)
                    }
                }
                .padding(.leading, MV.Space.rowGap)
                .transaction { $0.animation = nil }
            }
            }
            .padding(MV.Space.sm)
            .frame(minHeight: MV.Size.chatBox)
            .background(shape.fill(MV.Tone.box))
            .overlay(shape.strokeBorder(talking ? MV.Chat.talking : boxHover ? MV.Stroke.boxHover : MV.Stroke.boxRest,
                                        lineWidth: talking ? MV.Stroke.boxTypingWidth : MV.Stroke.boxRestWidth))
            .onHover { boxHover = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.boxRect = $0 }
            .modifier(ComposerOverlays(model: model))
            .onReceive(NotificationCenter.default.publisher(for: MVDropZone.dropped)) { n in
                guard n.userInfo?["key"] as? String == dropKey, let paths = n.userInfo?["paths"] as? [String] else { return }
                model.add(paths)
            }
            if let agent = modeAgent { modePill(agent) }
        }
        .zIndex(1)
        .frame(maxWidth: MV.Chat.column)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MV.Space.section - MV.Space.xs).padding(.top, MV.Space.gridGap).padding(.bottom, MV.Space.headerLead)
    }
    private func modePill(_ agent: Agent) -> some View {
        HStack(spacing: MV.Space.xs) {
            Button {
                guard Date().timeIntervalSince(PermCard.closedAt) > 0.3 else { return }
                permOpen.toggle()
            } label: {
                HStack(spacing: MV.Space.xs) {
                    Text(Mode.of(agent.permission).title).font(F.font(MV.Text.control, .medium)).foregroundStyle(MV.Ink.t1)
                    Icon("mvChevDown", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2)
                }
                .padding(.leading, MV.Space.inset).padding(.trailing, MV.Space.labelGap).frame(height: MV.Size.pill)
                .background(Capsule().fill(MV.Tone.pill))
                .overlay(Capsule().strokeBorder(MV.Chat.pillEdge, lineWidth: MV.Chat.pillEdgeWidth))
                .contentShape(Capsule())
            }
            .buttonStyle(MVStates(shape: Capsule()))
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .tip("Mode: \(Mode.of(agent.permission).title)", "\u{2318}\u{21E7}M", edge: .top)
            .overlay(alignment: .bottomLeading) {
                if permOpen {
                    PermCard(current: Mode.of(agent.permission), alwaysEdits: agent.alwaysEdits == true, open: $permOpen) { patch in
                        Task { do { try await s.updateAgent(agent.id, patch) } catch { s.toast = error.localizedDescription } }
                    }
                    .offset(y: -(MV.Size.pill + MV.Size.chatBox + MV.Space.section - MV.Space.labelGap))
                    .fixedSize()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, MV.Space.xs)
    }
}


/// Words that shimmer while something works (ChatGPT's "Thinking"): the words in t3 with a soft band of t1 passing over
/// them from left to right, every 1.6 s. Reduce Motion: the words stay still in t2.
struct Shimmer: View {
    let text: String; let font: Font
    var base: Color = MV.Motion.shimmerBase; var band: Color = Color.white
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.chatActive) private var pageOn
    @Environment(\.chatActivity) private var chat
    var body: some View {
        let words = Text(text).font(font).lineLimit(1).truncationMode(.middle)
        if still {
            words.foregroundStyle(MV.Ink.t2)
        } else {
            // Driven by the display's own clock (TimelineView), never by a SwiftUI animation: the line it sits in turns
            // animations off (and is rebuilt every second), which froze the old animated shimmer on its first frame.
            // Paused where it can't be seen (a page or a chat you've left): no frame-rate work for nothing.
            TimelineView(.animation(minimumInterval: nil, paused: !pageOn || chat?.on == false)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t.truncatingRemainder(dividingBy: MV.Motion.shimmer) / MV.Motion.shimmer)
                words.foregroundStyle(base)
                    .overlay {
                        GeometryReader { g in
                            let band = g.size.width * MV.Motion.shimmerBand
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: self.band, location: 0.5), .init(color: .clear, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: band)
                                .offset(x: (phase * (g.size.width + band)) - band)
                        }
                        .mask(words)
                        .allowsHitTesting(false)
                    }
            }
        }
    }
}


/// Measures scrolling as you feel it: while a chat's view moves, every display frame's time is noted; when it rests,
/// one line goes to ~/Library/Logs/Agent Lab/scroll.log (frames, the median and worst gap, and how many frames took
/// longer than the display's own interval by half again). Costs one display link while scrolling, nothing at rest.
@MainActor final class ScrollMeter: NSObject {
    static let shared = ScrollMeter()
    /// Off unless asked for: `defaults write dev.agentlab.native scrollMeter -bool YES`.
    static let on = UserDefaults.standard.bool(forKey: "scrollMeter")
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var gaps: [CFTimeInterval] = []
    private var movedAt: CFTimeInterval = 0
    private var expected: CFTimeInterval = 1.0 / 60
    private weak var view: NSScrollView?
    func moved(_ v: NSScrollView?) {
        guard let v else { return }
        movedAt = CACurrentMediaTime()
        guard link == nil else { return }
        view = v; gaps.removeAll(); last = 0
        let l = v.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }
    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        if l.targetTimestamp > l.timestamp { expected = l.targetTimestamp - l.timestamp }
        if last > 0 { gaps.append(now - last) }
        last = now
        if CACurrentMediaTime() - movedAt > 0.35 { finish() }
    }
    private func finish() {
        link?.invalidate(); link = nil
        let g = gaps.dropLast(20)              // the frames after it came to rest
        guard g.count > 10 else { return }
        let s = g.sorted()
        let late = g.filter { $0 > expected * 1.5 }.count
        let line = String(format: "%@  frames %d  median %.1f ms  p95 %.1f ms  worst %.1f ms  late %d (%.0f%%)  display %.0f Hz  doc %d pt\n",
                          ISO8601DateFormatter().string(from: Date()), g.count, s[s.count / 2] * 1000, s[s.count * 95 / 100] * 1000, s.last! * 1000,
                          late, Double(late) / Double(g.count) * 100, 1 / expected, Int(view?.documentView?.frame.height ?? 0))
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Agent Lab")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("scroll.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}


/// Files dragged over a chat (Claude's drop): the chat dims under a dashed outline that says what happens, and what
/// you drop goes into that chat's box as attachments.
struct MVDropZone: ViewModifier {
    static let dropped = Notification.Name("agentlab.chatDrop")
    let key: String
    @State private var over = false
    func body(content: Content) -> some View {
        if MV.on {
            content
                .overlay {
                    if over {
                        let shape = RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous)
                        ZStack {
                            shape.fill(MV.Tone.page.opacity(MV.Chat.dropDim))
                            shape.strokeBorder(MV.Accent.blue, lineWidth: MV.Stroke.boxTypingWidth)
                            VStack(spacing: MV.Space.labelGap) {
                                Icon("mvClip", MV.Size.iconLarge).foregroundStyle(MV.Ink.t1)
                                    .frame(width: MV.Size.chatBox, height: MV.Size.chatBox).background(Circle().fill(MV.Tone.box2))
                                Text("Drop files to add them").font(F.font(MV.Text.name, .medium)).foregroundStyle(MV.Ink.t1)
                                Text("Pictures and files go into your message").font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Ink.t3)
                            }
                        }
                        .padding(MV.Space.headerLead)
                        .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $over) { providers in
                    let group = DispatchGroup(); var paths: [String] = []
                    for p in providers {
                        group.enter()
                        _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { paths.append(url.path) } }; group.leave() }
                    }
                    group.notify(queue: .main) {
                        NotificationCenter.default.post(name: Self.dropped, object: nil, userInfo: ["key": key, "paths": paths])
                    }
                    return true
                }
        } else {
            content
        }
    }
}

/// What you sent with a message, above the bubble: 120 pt tiles, radius 16, the 8% ring. A picture shows itself; any
/// other file its Quick Look thumbnail (a video's frame, a document's page), else its kind and name. A click opens it.
struct MVSentImages: View {
    let paths: [String]
    var body: some View {
        HStack(spacing: MV.Space.labelGap) {
            ForEach(paths, id: \.self) { p in MVSentTile(path: p) }
        }
    }
}
private struct MVSentTile: View {
    let path: String
    @State private var thumb: NSImage?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous)
        let name = (path as NSString).lastPathComponent, ext = (path as NSString).pathExtension.uppercased()
        Group {
            if let image = thumb ?? (Attachments.isImage(path) ? Thumbs.image(path) : nil) {
                Image(nsImage: image).resizable().scaledToFill()
                    .overlay(alignment: .bottomLeading) {
                        if !Attachments.isImage(path) {
                            Text(ext.isEmpty ? "File" : ext).font(F.font(MV.Text.tag, .medium)).foregroundStyle(MV.Ink.t1)
                                .padding(.horizontal, MV.Space.sm).frame(height: MV.Size.badge)
                                .background(Capsule().fill(MV.Tone.box.opacity(MV.Chat.dropDim))).padding(MV.Space.sm)
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: MV.Space.xs) {
                    Icon("mvFile", MV.Size.icon).foregroundStyle(MV.Ink.t2)
                    Spacer(minLength: 0)
                    Text(name).font(F.font(MV.Text.meta, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(2).truncationMode(.middle)
                    Text(ext.isEmpty ? "File" : ext).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3)
                }
                .padding(MV.Space.inset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(MV.Tone.box2)
            }
        }
        .frame(width: MV.Chat.sent, height: MV.Chat.sent).clipShape(shape)
        .overlay(shape.strokeBorder(MV.Chat.attachRing, lineWidth: MV.Stroke.list))
        .contentShape(shape)
        .help(name)
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        .task(id: path) {
            guard !Attachments.isImage(path) else { return }
            let req = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: MV.Chat.sent, height: MV.Chat.sent),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { thumb = rep.nsImage }
        }
    }
}

/// Attachments in the box (ChatGPT's): flat 96 pt tiles with the 8% ring, 6 in from the box's edges like its buttons,
/// their radius the box's minus that (concentric). ✕ sits on the corner like Discord's status dot: ringed in the
/// box's colour, cut into the tile. It shows on hover.
struct MVAttachments: View {
    @ObservedObject var model: ComposerModel
    var body: some View {
        HStack(spacing: MV.Space.sm) {
            ForEach(model.images, id: \.self) { p in
                MVAttachmentTile(remove: { model.remove(p) }) {
                    Group {
                        if let image = Thumbs.image(p) { Image(nsImage: image).resizable().scaledToFill() }
                        else { Icon("mvFile", MV.Size.icon).foregroundStyle(MV.Ink.t3) }
                    }
                    .frame(width: MV.Chat.attach, height: MV.Chat.attach)
                }
            }
            ForEach(model.files, id: \.self) { p in
                MVAttachmentTile(remove: { model.remove(p) }) {
                    VStack(alignment: .leading, spacing: MV.Space.xs) {
                        Icon(FileManager.default.isDirectory(p) ? "mvFolder" : "mvFile", MV.Size.icon).foregroundStyle(MV.Ink.t2)
                        Spacer(minLength: 0)
                        Text((p as NSString).lastPathComponent).font(F.font(MV.Text.meta, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1).truncationMode(.middle)
                        Text(((p as NSString).pathExtension.isEmpty ? "Folder" : (p as NSString).pathExtension.uppercased()))
                            .font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3)
                    }
                    .padding(MV.Space.inset)
                    .frame(width: MV.Chat.attach + MV.Chat.attach / 2, height: MV.Chat.attach, alignment: .topLeading)
                    .background(MV.Tone.box2)
                    .help(p)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
private struct MVAttachmentTile<V: View>: View {
    let remove: () -> Void
    @ViewBuilder let content: V
    @State private var hover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.chatBox - MV.Space.sm, style: .continuous)
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(MV.Chat.attachRing, lineWidth: MV.Stroke.list))
            .overlay(alignment: .topTrailing) {
                if hover {
                    Button(action: remove) {
                        Icon("mvClose", MV.Size.iconSmall - MV.Space.xs).foregroundStyle(MV.Ink.t1)
                            .frame(width: MV.Chat.attachRemove, height: MV.Chat.attachRemove)
                            .background(Circle().fill(MV.Tone.box2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(MVStates(shape: Circle()))
                    // Discord's status dot: a ring in the box's colour, centred on the corner's curve.
                    .background(Circle().fill(MV.Tone.box).padding(-MV.Stroke.dotRing))
                    .offset(x: MV.Chat.attachRemove / 4, y: -MV.Chat.attachRemove / 4)
                    .tip("Remove", edge: .top)
                }
            }
            .onHover { hover = $0 }
    }
}


/// Your words as the chat draws them (MAVIS): the blue bubble on the right, hugging its words, radius 22, 16 by 10.
struct MVBubble: View {
    let text: String
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: MV.Chat.bubbleLead)
            HugWidth(ideal: HugWidth.width(of: text)) { MarkdownText(text: text, color: MV.Ink.t1) }
                .padding(.horizontal, MV.Chat.bubbleX)
                .padding(.top, MV.Chat.bubbleY - HugWidth.lift).padding(.bottom, MV.Chat.bubbleY + HugWidth.lift)
                .background(RoundedRectangle(cornerRadius: MV.Chat.bubbleRadius, style: .continuous).fill(MV.Accent.bubble))
        }
        .padding(.vertical, MV.Space.sm)
    }
}


/// Pictures shown small (sent, attached): read once at a small size and kept, never decoded full size in a redraw.
@MainActor enum Thumbs {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(_ path: String) -> NSImage? {
        if let i = cache.object(forKey: path as NSString) { return i }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: MV.Chat.sent * 2,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: .zero)
        cache.setObject(img, forKey: path as NSString)
        return img
    }
}

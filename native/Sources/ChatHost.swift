// Keeps recently opened chats alive, so switching to one is attaching an already-built view, not building it again.
//
// SwiftUI throws a view away when you leave it (another chat, another page) and builds it from nothing when you come
// back: every row, every text view, the scroll position lost. That rebuild was the hitch you felt switching between
// chats and from Review to Messages (17 Nov: ~45 ms, three dropped frames, even after the transcript was made lazy).
// Here each chat lives in its own NSHostingView, kept in a small most-recently-used pool. Showing a chat moves its view
// into the window; leaving moves it out (out of the window it does no layout and draws nothing). Coming back keeps
// your scroll position, like Claude.
//
// Debug: `ChatViews.shared.keys` lists what's alive; tools/chatperf.swift times the switch.
import SwiftUI
import AppKit

@MainActor
final class ChatViews {
    static let shared = ChatViews()
    /// How many chats stay built. Each costs only its visible rows (the transcript is lazy) and, while hidden, nothing
    /// on a window resize (a hidden chat doesn't follow the pane's size until it's shown again).
    let limit = 8
    final class Kept { let view: NSHostingView<AnyView>; var token: Any; let same: (Any, Any) -> Bool
        init(_ v: NSHostingView<AnyView>, _ t: Any, _ same: @escaping (Any, Any) -> Bool) { view = v; token = t; self.same = same } }
    private var kept: [String: Kept] = [:]
    private(set) var keys: [String] = []                       // most recent last

    /// The kept view for `key`. Its content is set again only when `token` (what it shows: the agent, the channel)
    /// changed; everything else updates by itself, as any SwiftUI view does.
    func view<T: Equatable>(_ key: String, token: T, _ make: () -> AnyView) -> NSHostingView<AnyView> {
        keys.removeAll { $0 == key }; keys.append(key)
        if let k = kept[key] {
            if !k.same(k.token, token) { k.view.rootView = make(); k.token = token }
            return k.view
        }
        let v = NSHostingView(rootView: make())
        // A kept chat is its own AppKit view: it would take the window's title-bar inset as safe area and push its
        // header down (a channel's head sat ~20 pt low). Surfaces place themselves; no inset.
        v.safeAreaRegions = []
        v.sizingOptions = []                                    // the pane sizes the chat; the chat never sizes the window
        kept[key] = Kept(v, token) { ($0 as? T) == ($1 as? T) }
        // Over the limit: channels and workspace chats go first; a Messages chat ("dm:", often long and costly to build
        // again) only when nothing else is left (a full workspace pushed mavis v2's out: a 1 s pause coming back).
        while keys.count > limit { forget(keys.first { !$0.hasPrefix("dm:") && $0 != key } ?? keys[0]) }
        return v
    }
    /// Every kept chat (a new theme: they're built again in its colours when next shown).
    func forgetAll() { for k in keys { kept.removeValue(forKey: k)?.view.removeFromSuperview() }; keys = [] }
    /// A deleted agent or channel, or the oldest past the limit: drop its view.
    func forget(_ key: String) { keys.removeAll { $0 == key }; kept.removeValue(forKey: key)?.view.removeFromSuperview() }
}

/// Shows the kept view for `key`, built by `content` the first time. Chats you've opened stay in the window, hidden,
/// so the lazy transcript keeps its built rows and coming back is only unhiding.
struct ChatHost<Token: Equatable, Content: View>: NSViewRepresentable {
    @EnvironmentObject var s: Store
    /// False while the page holding it is kept behind another page: then even the shown chat is parked.
    @Environment(\.chatActive) private var active
    let key: String
    let token: Token
    @ViewBuilder let content: () -> Content

    /// The chat's place in the window. The chat in it is shown only once the place has its size and the chat has been
    /// laid out at that size: a chat built before the slot was sized drew one frame squeezed into a corner (19 Nov).
    final class Slot: NSView {
        override var isFlipped: Bool { true }
        weak var shown: NSView?
        /// Something covers the window (⌘K, a form, a report): the chat takes no clicks, so they reach what covers it.
        /// A kept chat is an AppKit view of its own, and SwiftUI's dimmed backdrop can't stop clicks reaching it.
        var covered = false
        override func hitTest(_ point: NSPoint) -> NSView? { covered ? nil : super.hitTest(point) }
        override func layout() {
            super.layout()
            guard let v = shown, bounds.width > 0, bounds.height > 0 else { return }
            if v.frame != bounds { v.frame = bounds; v.layoutSubtreeIfNeeded() }
            if v.isHidden { v.isHidden = false }
        }
    }
    func makeNSView(context: Context) -> Slot { Slot() }
    func updateNSView(_ slot: Slot, context: Context) {
        let store = s
        let v = ChatViews.shared.view(key, token: token) { AnyView(content().environmentObject(store).environmentObject(store.panes).environmentObject(store.railTip)) }
        if v.superview !== slot { v.isHidden = true; v.removeFromSuperview(); slot.addSubview(v) }
        // The chat in front stays drawn while its page is away (under the page's opacity): coming back is instant, and a
        // page in its browser never has to wake up (mavis v2's open page cost ~1 s). Only the others are parked.
        for other in slot.subviews where other !== v && !other.isHidden {
            other.isHidden = true; other.autoresizingMask = []          // parked: no layout while the window resizes
        }
        slot.covered = s.coversChats || !active          // away: drawn, but it takes no clicks
        // Away: still drawn, but it keeps its size (no relayout of a long chat on every frame of a window resize).
        slot.shown = active ? v : nil
        // ... and moved out of the visible area: its text's cursor zones stayed live over the page in front (an I-beam
        // everywhere). Still in the window, so a page in its browser keeps drawing.
        guard active else { v.autoresizingMask = []; v.setFrameOrigin(NSPoint(x: -(v.frame.width + slot.bounds.width + MV.Space.section), y: 0)); return }
        v.autoresizingMask = [.width, .height]
        if slot.bounds.width > 0, slot.bounds.height > 0 {
            if v.frame != slot.bounds { v.frame = slot.bounds; v.layoutSubtreeIfNeeded() }
            v.isHidden = false
        } else {
            v.isHidden = true; slot.needsLayout = true          // shown by the slot's layout, at its size
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Slot, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 600)
    }
}

/// What a channel's kept view shows: a change to any of these sets its content again.
struct ChannelToken: Equatable { let w: Workspace; let channel: Workspace.Channel; let members: [Agent] }

extension EnvironmentValues {
    /// Whether chats under here are on screen (Page keeps Messages built, hidden, behind other pages).
    @Entry var chatActive = true
}

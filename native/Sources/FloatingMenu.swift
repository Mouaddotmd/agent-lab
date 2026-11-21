// Menus that float over everything: each opens in its own small borderless window, a child of the app's window, placed
// from its anchor's place on screen.
//
// Drawn inside the window, a menu was painted above its neighbours but not hit above them: a row further down a list,
// a kept chat (its own NSHostingView, ChatHost.swift) or an overlay set to ignore clicks took the pointer, so the menu
// showed but nothing in it lit or clicked (17 Nov). A window of its own is first for the pointer wherever it sits, is
// never clipped by a scroll view or a pane, and moves with the app's window.
//
// One menu at a time. It closes on a choice, Esc, a click or scroll anywhere outside it, the window resizing, or the
// app going to the background. A click outside goes on to what it was on (one click closes the menu and does the
// thing), except a click on the menu's own anchor, which only closes it (else the ⋯ that opened it would reopen it).
import SwiftUI
import AppKit

enum MenuPlacement {
    /// Under the anchor, `gap` below it: its right edges lined up (`trailing`), or its left edges.
    case below(trailing: Bool, gap: CGFloat)
    /// To the right of the anchor, `gap` away, tops lined up.
    case beside(gap: CGFloat)
}

extension View {
    /// Shows `menu` in a floating window while `open` is true, placed from this view's bounds.
    /// `pop`: it springs open as the buttons' labels do (Tips.swift): there at once, a touch small, to full size with a
    /// slight bounce, growing out of the corner nearest what opened it. No fade.
    func floatingMenu<Menu: View>(_ open: Binding<Bool>, placement: MenuPlacement = .below(trailing: true, gap: 4), pop: Bool = false, @ViewBuilder menu: @escaping () -> Menu) -> some View {
        background(MenuAnchor(open: open, placement: placement, pop: pop, menu: { AnyView(menu()) }))
    }
}

private struct MenuAnchor: NSViewRepresentable {
    @EnvironmentObject var s: Store
    @Binding var open: Bool
    let placement: MenuPlacement
    let pop: Bool
    let menu: () -> AnyView

    final class Anchor: NSView {
        var pending: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let p = pending { pending = nil; DispatchQueue.main.async(execute: p) }
        }
    }
    final class Owner {}

    func makeCoordinator() -> Owner { Owner() }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ anchor: Anchor, context: Context) {
        let owner = context.coordinator
        guard open else { anchor.pending = nil; MenuWindow.shared.dismiss(owner: owner); return }
        let store = s, binding = $open, placement = placement, pop = pop
        let content = AnyView(menu().environmentObject(store).environmentObject(store.panes).environmentObject(store.railTip))
        let show = { [weak anchor] in
            guard let anchor else { return }
            MenuWindow.shared.present(from: anchor, owner: owner, placement: placement, pop: pop, content: content) { binding.wrappedValue = false }
        }
        if anchor.window == nil { anchor.pending = show } else { show() }
    }
    static func dismantleNSView(_ anchor: Anchor, coordinator: Owner) { MenuWindow.shared.dismiss(owner: coordinator) }
}

/// The one floating menu window.
@MainActor final class MenuWindow {
    static let shared = MenuWindow()
    /// Room around the card for its shadow (the window is clear there and lets clicks through to what's under it).
    static let margin: CGFloat = 36

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { MenuWindow.shared.dismiss() }
    }
    private var panel: Panel?
    private var host: SizingHost?
    private weak var owner: AnyObject?
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private var close: (() -> Void)?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    /// Sizes the open menu to its content now, keeping the edge by its button where it is (and on screen).
    private func fit() {
        guard let panel, let host else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var f = panel.frame
        guard abs(f.size.height - size.height) > 0.5 || abs(f.size.width - size.width) > 0.5 else { return }
        // A menu that opened above its button grows upward (its bottom stays by the button); one below grows down.
        let above = popState.from == .bottomLeading || popState.from == .bottomTrailing
        let top = f.maxY, bottom = f.minY
        f.size = size; f.origin.y = above ? bottom : top - size.height
        if let screen = panel.screen?.visibleFrame {
            if f.minY < screen.minY - Self.margin { f.origin.y = screen.minY - Self.margin }
            if f.maxY > screen.maxY + Self.margin { f.origin.y = screen.maxY + Self.margin - f.height }
        }
        panel.setFrame(f, display: true)
    }
    /// The menu open now (tests read it).
    var window: NSWindow? { panel }

    /// The pop's state: which corner it grows from, and whether it's at full size yet.
    final class Pop: ObservableObject { @Published var from: UnitPoint = .topTrailing; @Published var shown = true }
    private let popState = Pop()
    private struct Popping: View {
        @ObservedObject var pop: Pop
        let content: AnyView
        var body: some View {
            content
                .scaleEffect(pop.shown ? 1 : MenuWindow.popFrom, anchor: pop.from)
                .animation(MenuWindow.popFade) { $0.opacity(pop.shown ? 1 : 0) }       // the fade on its own, quicker clock
        }
    }
    /// The menu's opening: it starts a little smaller and clear, pops to full size with one small, soft overshoot (about
    /// 1.5%), and fades in over the first 0.1 s. Between the labels' lively pop (0.92, damping 0.55) and a flat fade
    /// (0.97, damping 0.92: too quiet to notice, 18 Nov). Closing is instant.
    static let popFrom: CGFloat = 0.92
    static let popScale = Animation.spring(response: 0.11, dampingFraction: 0.72)   // 2.5× quicker (was 0.28, 18 Nov)
    static let popFade = Animation.easeOut(duration: 0.04)

    func present(from anchor: NSView, owner: AnyObject, placement: MenuPlacement, pop: Bool = false, content: AnyView, close: @escaping () -> Void) {
        guard let parent = anchor.window else { return }
        let wrapped = AnyView(Popping(pop: popState, content: AnyView(content.fixedSize())).padding(Self.margin))
        if self.owner === owner, let host {               // already open: new content, same place
            host.rootView = wrapped
            self.close = close
            return
        }
        dismiss()
        self.owner = owner; self.anchor = anchor; self.parent = parent; self.close = close
        popState.shown = true
        let host = SizingHost(rootView: wrapped)
        // The menu's own content grows or shrinks (a section that opens): the window follows, its top edge staying put.
        host.onResize = { [weak self] in self?.fit() }
        host.sizingOptions = [.intrinsicContentSize]
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let card = CGSize(width: size.width - Self.margin * 2, height: size.height - Self.margin * 2)
        let at = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        // The screen it's on, to keep the menu on it (none for a window parked off screen, as the test tools use).
        let visible = parent.screen?.visibleFrame ?? CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6)
        var x: CGFloat, top: CGFloat, from: UnitPoint
        switch placement {
        case .below(let trailing, let gap):
            x = trailing ? at.maxX - card.width : at.minX
            top = at.minY - gap
            from = trailing ? .topTrailing : .topLeading
            if top - card.height < visible.minY + 8 {                                          // no room under: above
                top = at.maxY + gap + card.height
                from = trailing ? .bottomTrailing : .bottomLeading
            }
        case .beside(let gap):
            x = at.maxX + gap
            top = min(at.maxY, max(visible.minY + 8 + card.height, at.maxY))
            if top - card.height < visible.minY + 8 { top = visible.minY + 8 + card.height }
            from = .topLeading
        }
        x = min(max(x, visible.minX + 8), visible.maxX - 8 - card.width)
        let frame = NSRect(x: x - Self.margin, y: top - card.height - Self.margin, width: size.width, height: size.height)
        let panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.contentView = host
        // A menu you clicked open is there at once, at full size: no pop, no fade (19 Nov). Only what shows on hover
        // (labels, tips) pops.
        _ = pop; popState.from = from      // which way it opened: fit() grows it away from its button
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel; self.host = host

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] e in
            guard let self, let panel = self.panel else { return e }
            if e.type == .keyDown { if e.keyCode == 53 { self.dismiss(); return nil }; return e }
            if e.window === panel {
                // In the card: the menu's. In the clear margin around it: outside.
                let card = panel.contentView?.bounds.insetBy(dx: Self.margin, dy: Self.margin) ?? .zero
                if card.contains(e.locationInWindow) { return e }
                self.dismiss()
                return nil
            }
            if e.type == .scrollWheel { self.dismiss(); return e }
            if let anchor = self.anchor, let w = anchor.window, e.window === w,
               anchor.convert(anchor.bounds, to: nil).contains(e.locationInWindow) {
                self.dismiss()                               // its own ⋯: just close
                return nil
            }
            self.dismiss()
            return e
        }
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { _ in MainActor.assumeIsolated { MenuWindow.shared.dismiss() } },
            nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in MainActor.assumeIsolated { MenuWindow.shared.dismiss() } },
        ]
    }

    func dismiss(owner: AnyObject) { if self.owner === owner { dismiss() } }

    func dismiss() {
        ThemePicker.shared.close()        // its submenu goes with it
        guard let panel else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let parent = self.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil; host = nil; owner = nil; anchor = nil
        let close = self.close
        self.close = nil
        close?()
        if parent?.isVisible == true { parent?.makeKey() }
    }
}


/// A menu's content view that says when its size changes, so its window can follow.
final class SizingHost: NSHostingView<AnyView> {
    var onResize: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}

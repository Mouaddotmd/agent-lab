// Labels for buttons that are only an icon: rest on one and its name shows beside it, the rail's label (RailTipView)
// with the rail's timing and pop, everywhere in the app.
//
// - Rest on a button: after a short pause (RailTip.delay) its label pops out of the side facing the button: below a
//   button it grows down from its top edge, above it grows up from its bottom edge, beside it from the edge nearest.
// - Once a label is up, the next button you point at shows its own at once (RailTip.warm), as the folded sidebar does.
// - Leaving, clicking, scrolling or typing hides it at once; it doesn't come back until you leave and come back.
//
// The label is drawn in its own small window above the app's (as the floating menus are, FloatingMenu.swift), so no
// scroll view, pane or sibling can clip it, cover it or put it in the wrong place, and it never takes a click.
import SwiftUI
import AppKit

enum TipEdge { case top, bottom, leading, trailing }

extension View {
    /// Shows `title` (and a quieter `detail` line) beside this view when the pointer rests on it.
    func tip(_ title: String, _ detail: String? = nil, edge: TipEdge = .bottom) -> some View {
        modifier(TipModifier(title: title, detail: detail, edge: edge))
    }
}

private struct TipModifier: ViewModifier {
    let title: String; let detail: String?; let edge: TipEdge
    @State private var owner = Tips.Owner()
    func body(content: Content) -> some View {
        content
            .background(TipAnchor(owner: owner, title: title))
            .onHover { on in
                if on { Tips.shared.enter(owner, title: title, detail: detail, edge: edge) } else { Tips.shared.leave(owner) }
            }
            .onDisappear { Tips.shared.leave(owner) }
            .onChange(of: title) { _, t in Tips.shared.retitle(owner, t, detail) }
    }
}

/// Knows where its button is on screen.
private struct TipAnchor: NSViewRepresentable {
    let owner: Tips.Owner; let title: String
    final class View: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    func makeNSView(context: Context) -> View { let v = View(); owner.view = v; Tips.shared.register(title, owner); return v }
    func updateNSView(_ v: View, context: Context) { owner.view = v; Tips.shared.register(title, owner) }
}

@MainActor final class Tips {
    /// A button's label waits this long under the pointer (macOS's help tags take about a second); the rail is quicker.
    static let delay: Double = 0.9
    static let shared = Tips()
    final class Owner { weak var view: NSView? }

    /// What the window draws; `shown` drives the pop.
    final class Model: ObservableObject {
        @Published var title = ""
        @Published var detail: String?
        @Published var edge: TipEdge = .bottom
        @Published var shown = false
        @Published var serial = 0
    }
    private let model = Model()
    private var panel: NSPanel?
    private var host: NSHostingView<TipWindowView>?
    private weak var current: Owner?
    /// The button whose label a click (or scroll, or key) put away: it stays away until the pointer leaves it.
    private weak var silenced: Owner?
    private var pending: Task<Void, Never>?
    private var hidAt = Date.distantPast
    private var monitor: Any?
    /// Room around the label for its shadow.
    static let margin: CGFloat = 14
    /// From the button's edge to the label's.
    static let gap: CGFloat = 8

    /// The label up now (tests read it).
    var window: NSWindow? { model.shown ? panel : nil }
    var showing: String? { model.shown ? model.title : nil }

    func enter(_ owner: Owner, title: String, detail: String?, edge: TipEdge) {
        installMonitor()
        pending?.cancel(); pending = nil
        guard silenced !== owner else { return }
        let warm = model.shown || Date().timeIntervalSince(hidAt) < RailTip.warm
        if warm { show(owner, title, detail, edge); return }
        pending = Task { [weak self] in
            // Buttons wait as macOS's own help tags do; the rail keeps its quick label (RailTip).
            try? await Task.sleep(nanoseconds: UInt64(Self.delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.show(owner, title, detail, edge)
        }
    }

    func leave(_ owner: Owner) {
        if silenced === owner { silenced = nil }
        if current === owner { pending?.cancel(); pending = nil; hide() }
        else if current == nil { pending?.cancel(); pending = nil }
    }

    func retitle(_ owner: Owner, _ title: String, _ detail: String?) {
        guard current === owner, model.shown else { return }
        model.title = title; model.detail = detail
        place()
    }

    /// Tests find a button's label by its words (kept only when AL_TIP_TEST is set).
    static let testing = ProcessInfo.processInfo.environment["AL_TIP_TEST"] != nil
    private var registry: [String: Owner] = [:]
    func register(_ title: String, _ owner: Owner) { if Self.testing { registry[title] = owner } }
    func owner(_ title: String) -> Owner? { registry[title] }
    var labelFrame: CGRect? { panel.map { $0.frame.insetBy(dx: Self.margin, dy: Self.margin) } }
    var shownEdge: TipEdge { model.edge }

    /// For tests: show a button's label now, no pause.
    func showNow(_ owner: Owner, title: String, detail: String? = nil, edge: TipEdge) { show(owner, title, detail, edge) }

    private func show(_ owner: Owner, _ title: String, _ detail: String?, _ edge: TipEdge) {
        guard let anchor = owner.view, let parent = anchor.window, parent.isVisible, !anchor.isHiddenOrHasHiddenAncestor else { return }
        // Not over a floating menu that's open: the menu is what you're looking at.
        if MenuWindow.shared.window != nil { return }
        current = owner
        let panel = self.panel ?? makePanel()
        model.title = title; model.detail = detail; model.edge = edge
        model.shown = false
        if panel.parent !== parent { panel.parent?.removeChildWindow(panel); parent.addChildWindow(panel, ordered: .above) }
        guard place() else { hide(); return }
        panel.orderFront(nil)
        model.serial += 1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { model.shown = true; return }
        // Next frame, so the label's first frame is drawn small and clear before it pops.
        DispatchQueue.main.async { [model] in withAnimation(RailTip.pop) { model.shown = true } }
    }

    /// Puts the window beside the button, on the asked side, or the opposite one when there's no room on screen.
    @discardableResult private func place() -> Bool {
        guard let panel, let host, let anchor = current?.view, let parent = anchor.window else { return false }
        host.rootView = TipWindowView(model: model)          // the new words, measured now (not next pass)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let label = CGSize(width: size.width - Self.margin * 2, height: size.height - Self.margin * 2)
        let at = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6)
        func origin(_ e: TipEdge) -> CGPoint {
            switch e {
            case .bottom: CGPoint(x: at.midX - label.width / 2, y: at.minY - Self.gap - label.height)
            case .top: CGPoint(x: at.midX - label.width / 2, y: at.maxY + Self.gap)
            case .trailing: CGPoint(x: at.maxX + Self.gap + 2, y: at.midY - label.height / 2)
            case .leading: CGPoint(x: at.minX - Self.gap - 2 - label.width, y: at.midY - label.height / 2)
            }
        }
        var edge = model.edge
        var o = origin(edge)
        let fits = { (p: CGPoint) in CGRect(origin: p, size: label).insetBy(dx: 1, dy: 1).intersection(visible).size == CGRect(origin: p, size: label).insetBy(dx: 1, dy: 1).size }
        if !fits(o) {
            let flip: TipEdge = switch edge { case .bottom: .top; case .top: .bottom; case .leading: .trailing; case .trailing: .leading }
            if fits(origin(flip)) { edge = flip; o = origin(flip); model.edge = flip }
        }
        // Kept on screen along the side it runs (a label under a button at the window's edge slides in, never off).
        o.x = min(max(o.x, visible.minX + 6), visible.maxX - 6 - label.width)
        o.y = min(max(o.y, visible.minY + 6), visible.maxY - 6 - label.height)
        panel.setFrame(NSRect(x: o.x - Self.margin, y: o.y - Self.margin, width: size.width, height: size.height), display: true)
        return true
    }

    private func hide() {
        guard model.shown || panel?.isVisible == true else { current = nil; return }
        hidAt = Date()
        current = nil
        panel?.orderOut(nil)                                                  // gone at once: no fade
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { model.shown = false }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.hidesOnDeactivate = true
        let h = NSHostingView(rootView: TipWindowView(model: model))
        h.sizingOptions = [.intrinsicContentSize]
        p.contentView = h
        panel = p; host = h
        return p
    }

    /// A click, a scroll or a key puts the label away (you've acted; it would be in the way).
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] e in
            guard let self else { return e }
            self.pending?.cancel(); self.pending = nil
            if let c = self.current { self.silenced = c; self.hide() }
            return e
        }
    }
}

/// What the label window draws: the rail's label, popping out of the side that faces its button.
struct TipWindowView: View {
    @ObservedObject var model: Tips.Model
    var body: some View {
        RailTipView(tip: .init(id: "tip", title: model.title, detail: model.detail, frame: .zero))
            .scaleEffect(model.shown ? 1 : RailTip.popFrom, anchor: anchor)
            .padding(Tips.margin)
            .fixedSize()
    }
    /// The edge nearest the button: the label grows out of it.
    private var anchor: UnitPoint {
        switch model.edge {
        case .bottom: .top
        case .top: .bottom
        case .trailing: .leading
        case .leading: .trailing
        }
    }
}

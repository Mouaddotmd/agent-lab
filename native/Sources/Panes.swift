// Resizable panes: the sidebar, the list beside a workspace or Messages, and Right now. One model holds every width
// (kept between launches), one handle draws every divider.
//
// How a drag feels (Arc-style): the pane follows your pointer the whole way, with nothing holding it back. Past a
// limit it stretches like a rubber band, less the further you pull. When you let go it springs, with a little bounce,
// to where it belongs: back inside its limits, or for the sidebar, folded into the icon rail if you let go narrow.
// Double-click a divider for its default width.
import SwiftUI
import AppKit

/// A pane that can be resized: its default, its limits, and which side its divider is on.
struct PaneSpec {
    let key: String; let standard: CGFloat; let min: CGFloat; let max: CGFloat
    /// The divider is on the pane's right (the sidebar, a list) or its left (Right now).
    let growsRight: Bool
}

enum PaneID {
    static let sidebar = PaneSpec(key: "sidebar", standard: 280, min: 220, max: 400, growsRight: true)
    static let list = PaneSpec(key: "list", standard: 319, min: 240, max: 440, growsRight: true)
    static let now = PaneSpec(key: "now", standard: 360, min: 260, max: 480, growsRight: false)
}

@MainActor
final class Panes: ObservableObject {
    /// The icon-only sidebar (Discord's server column): 48 pt tiles, centred.
    static var rail: CGFloat { MV.on ? MV.Size.rail : 72 }   // MAVIS: room for its 56 pt tiles
    /// Let go of the sidebar narrower than this and it folds into the rail; wider, it opens to at least its minimum.
    static let foldAt: CGFloat = 160
    /// Below this width, mid-drag, the sidebar already shows as the rail.
    static let railBelow: CGFloat = 170
    /// Right now shows only while Home keeps at least this much room beside it.
    static let mainMin: CGFloat = 640
    /// The narrowest the window goes: the sidebar at its widest plus a usable panel. The sidebar never folds or shrinks
    /// for the window (ChatGPT keeps its sidebar too): the panel gives way, and clips anything that can't fit.
    static let windowMin: CGFloat = 720
    /// Let go, reset, or the window crossing a size: quick, with the faintest settle (about 1% overshoot), never a bounce.
    static var settle: Animation? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.92) }
    static var spring: Animation? { settle }

    /// The fold, as the sidebar narrows: the open sidebar fades out (fully gone by 180), nothing between 180 and 150,
    /// then the rail fades in (fully there by 110). Both read the width as drawn, every frame of a drag or a settle.
    static func openOpacity(_ w: CGFloat) -> Double { Double(min(max((w - 180) / 40, 0), 1)) }
    static func railOpacity(_ w: CGFloat) -> Double { Double(min(max((150 - w) / 40, 0), 1)) }

    @Published private(set) var widths: [String: CGFloat] = [:]
    /// Widths while a divider is being dragged: they follow the pointer (rubber-banded past the limits), unsaved.
    @Published private(set) var live: [String: CGFloat] = [:]
    @Published var sidebarFolded: Bool { didSet { UserDefaults.standard.set(sidebarFolded, forKey: "pane.sidebar.folded") } }
    /// The window's width, set by the root view through `resized`. Not published: a window drag changes it every frame,
    /// and publishing it redrew every view that reads a pane width (the whole window) on every frame of the drag
    /// (17 Nov: resizing fell to 20-30 fps). Views redraw only when something they show from it changes.
    private(set) var window: CGFloat = 1392
    /// The window changed size: tell views only if Right now shows/hides (with the spring) or the list has to give way.
    func resized(_ w: CGFloat) {
        guard w != window else { return }
        let showsBefore = showsNow, listBefore = list
        let showsAfter = w - sidebar - saved(PaneID.now) >= Panes.mainMin
        let listAfter = min(width(PaneID.list), max(200, w - sidebar - 360))
        if showsAfter != showsBefore { withAnimation(Panes.spring) { objectWillChange.send(); window = w } }
        else if listAfter != listBefore { objectWillChange.send(); window = w }
        else { window = w }
    }

    init() {
        sidebarFolded = UserDefaults.standard.bool(forKey: "pane.sidebar.folded")
        for p in [PaneID.sidebar, PaneID.list, PaneID.now] {
            let v = UserDefaults.standard.double(forKey: "pane." + p.key)
            widths[p.key] = v > 0 ? min(max(v, p.min), p.max) : p.standard
        }
    }
    /// The saved width (what the pane settles at).
    func saved(_ p: PaneSpec) -> CGFloat { widths[p.key] ?? p.standard }
    /// The width drawn now: the pointer's while dragging, else the saved one.
    func width(_ p: PaneSpec) -> CGFloat { live[p.key] ?? saved(p) }
    func set(_ p: PaneSpec, _ w: CGFloat) {
        let v = min(max(w, p.min), p.max)
        guard widths[p.key] != v else { return }
        widths[p.key] = v
        UserDefaults.standard.set(Double(v), forKey: "pane." + p.key)
    }

    // MARK: Dragging

    /// Where a drag starts from: what's on screen now.
    func dragStart(_ p: PaneSpec) -> CGFloat { p.key == PaneID.sidebar.key ? sidebar : width(p) }
    /// The pointer moved: the pane follows it exactly inside its range, and stretches past it.
    func drag(_ p: PaneSpec, to raw: CGFloat) {
        let lo = p.key == PaneID.sidebar.key ? Panes.rail : p.min
        let w = raw < lo ? lo - Panes.stretch(lo - raw) : raw > p.max ? p.max + Panes.stretch(raw - p.max) : raw
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { live[p.key] = w }
    }
    /// Let go: spring to where it belongs, and keep it.
    func dragEnd(_ p: PaneSpec) {
        guard let w = live[p.key] else { return }
        withAnimation(Panes.settle) {
            live[p.key] = nil
            if p.key == PaneID.sidebar.key {
                sidebarFolded = w < Panes.foldAt
                if !sidebarFolded { set(p, w) }
            } else {
                set(p, w)
            }
        }
    }
    func reset(_ p: PaneSpec) {
        withAnimation(Panes.settle) {
            live[p.key] = nil
            set(p, p.standard)
            if p.key == PaneID.sidebar.key { sidebarFolded = false }
        }
    }
    /// Past a limit the pane gives only a little: the further you pull, the less it moves, never more than 12 pt.
    static func stretch(_ d: CGFloat) -> CGFloat { (1 - 1 / (d * 0.35 / 12 + 1)) * 12 }

    // MARK: What shows

    /// The sidebar's width as drawn now: only you change it (drag, fold, reset), never the window's size.
    var sidebar: CGFloat {
        if MV.on { return Panes.rail }                  // MAVIS: the rail only, never the open sidebar
        if let w = live[PaneID.sidebar.key] { return w }
        return sidebarFolded ? Panes.rail : saved(PaneID.sidebar)
    }
    /// The sidebar shows as the rail (icons only, centred).
    var rail: Bool { sidebar < Panes.railBelow }
    /// The list beside a chat (Messages, a workspace's channels) as drawn: your width, but when the window is small it
    /// gives way first, so the chat keeps at least 360 (the list never below 200).
    var list: CGFloat { min(width(PaneID.list), max(200, window - sidebar - 360)) }
    /// Right now fits beside Home only when Home keeps its minimum width.
    var showsNow: Bool { window - sidebar - saved(PaneID.now) >= Panes.mainMin }
}

/// A divider you can drag. At rest: its 1 pt line (or nothing, where the panes meet without one). Pointing at it lights
/// the line and shows a small square button with a left-right arrow in its middle; the pointer becomes the resize
/// arrows. Drag to resize; double-click for the default. The hit area is 12 pt wide, centred on the line.
struct SplitHandle: View {
    @EnvironmentObject var panes: Panes
    let pane: PaneSpec
    var showsLine = true
    @State private var hover = false
    @State private var dragging = false
    @State private var start: CGFloat = 0
    var body: some View {
        let lit = hover || dragging
        ZStack {
            Rectangle().fill(dragging ? C.i10 : lit ? C.v6 : C.v4).frame(width: 1).opacity(showsLine || lit ? 1 : 0)
            if lit { ResizeKnob(active: dragging) }          // appears and goes at once: no fade
        }
        .frame(width: 12)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if !dragging { dragging = true; start = panes.dragStart(pane) }
                    panes.drag(pane, to: start + (pane.growsRight ? 1 : -1) * g.translation.width)
                }
                .onEnded { _ in dragging = false; panes.dragEnd(pane) }
        )
        .onTapGesture(count: 2) { panes.reset(pane) }
        .tip("Drag to resize", "Double-click to reset", edge: .trailing)
        .accessibilityElement()
        .accessibilityLabel("Resize")
        .accessibilityAction(named: "Reset size") { panes.reset(pane) }
    }
}

/// The handle's button: a 22 pt rounded square, raised like the app's controls, with a left-right arrow.
struct ResizeKnob: View {
    var active = false
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? C.v3 : C.v2)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(active ? C.v6 : C.v5, lineWidth: 1))
            .overlay(
                Path { p in
                    // ←→: a short shaft with a chevron at each end.
                    p.move(to: CGPoint(x: 6, y: 11)); p.addLine(to: CGPoint(x: 16, y: 11))
                    p.move(to: CGPoint(x: 8.5, y: 8.5)); p.addLine(to: CGPoint(x: 6, y: 11)); p.addLine(to: CGPoint(x: 8.5, y: 13.5))
                    p.move(to: CGPoint(x: 13.5, y: 8.5)); p.addLine(to: CGPoint(x: 16, y: 11)); p.addLine(to: CGPoint(x: 13.5, y: 13.5))
                }
                .stroke(active ? C.i12 : C.i10, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            )
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

// MARK: Rail labels (the folded sidebar's tiles name themselves, like Discord's server list)

/// The one label floating beside the rail. Rest on a tile and it shows after a short pause (sweeping the pointer down
/// the rail shows nothing); once one is up, the next tile you point at swaps in at once. Leaving hides it at once.
@MainActor
final class RailTip: ObservableObject {
    struct Tip: Equatable { let id: String; let title: String; let detail: String?; let frame: CGRect }
    @Published private(set) var tip: Tip?
    static let delay: Double = 0.35          // first label: long enough that a quick sweep shows nothing
    static let warm: Double = 0.25           // after a label goes, the next one within this window shows at once
    private var pending: Task<Void, Never>?
    private var hidAt = Date.distantPast

    func enter(_ t: Tip) {
        pending?.cancel()
        let quick = tip != nil || Date().timeIntervalSince(hidAt) < RailTip.warm
        if quick { show(t); return }
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(RailTip.delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.show(t)
        }
    }
    /// For renders and tests: show a label now, no pause.
    func showNow(_ t: Tip) { tip = t }
    func leave(_ id: String) {
        pending?.cancel(); pending = nil
        guard tip?.id == id else { return }
        hidAt = Date()
        tip = nil                                                   // gone at once: no fade
    }
    private func show(_ t: Tip) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { tip = t; return }
        withAnimation(RailTip.pop) { tip = t }
    }
    /// The label's pop: no fade at all, it's there at once, a touch small, and springs to size with a slight bounce
    /// (a stiff, quick spring: up in ~40 ms, one small overshoot, settled by ~140 ms).
    static let pop = Animation.spring(response: 0.13, dampingFraction: 0.55)
    /// How small a label starts before it springs to size.
    static let popFrom: CGFloat = 0.92
}

/// Where every rail tile is, for its label: each tile publishes its bounds; the window reads them where it draws.
struct RailAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}

/// The label itself: the name, and a quiet line under it when there's one; no pointer arrow.
struct RailTipView: View {
    let tip: RailTip.Tip
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tip.title).font(F.font(14, .semibold)).foregroundStyle(C.i12).lineLimit(1)
            if let d = tip.detail { Text(d).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.v3))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
        .shadow(color: .black.opacity(MV.on ? 0 : 0.5), radius: 8, y: 4)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

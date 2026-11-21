// The agent's own pointer (as Codex's computer use shows one): a drawn arrow on a clear layer over every screen that
// glides to what the agent is about to act on, presses with a small ring, and outlines its target. It only shows:
// your mouse never moves and your clicks pass straight through. It fades out a moment after the agent's last step.
import SwiftUI
import AppKit

@MainActor final class AgentCursor: ObservableObject {
    static let shared = AgentCursor()
    /// Where the arrow's tip is, in the layer's own points (top-left origin, across all screens).
    @Published fileprivate var at: CGPoint = .zero
    @Published fileprivate var shown = false
    @Published fileprivate var pressing = 0
    /// The target's frame, outlined while the agent acts on it.
    @Published fileprivate var target: CGRect?
    @Published fileprivate var label: String?
    private var window: NSWindow?
    private var hide: DispatchWorkItem?
    /// The layer's frame in screen coordinates (bottom-left origin): the union of every screen.
    private var space: CGRect = .zero

    private func ensure() {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        if window == nil {
            let w = NSWindow(contentRect: union, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.animationBehavior = .none
            w.contentView = NSHostingView(rootView: CursorLayer(cursor: self))
            window = w
        }
        if union != space { space = union; window?.setFrame(union, display: true) }
        window?.orderFrontRegardless()
    }
    /// A screen point (bottom-left origin) in the layer's top-left points.
    private func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - space.minX, y: space.maxY - p.y) }
    private func local(_ r: CGRect) -> CGRect { CGRect(x: r.minX - space.minX, y: space.maxY - r.maxY, width: r.width, height: r.height) }

    /// Glides to `point` (screen coordinates, bottom-left origin), outlining `frame` when given. Returns once it's there.
    func glide(to point: CGPoint, frame: CGRect? = nil, label: String? = nil) async {
        guard !NSScreen.screens.isEmpty else { return }
        ensure()
        hide?.cancel()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let dest = local(point)
        let far = hypot(dest.x - at.x, dest.y - at.y)
        if !shown {
            // It comes in from a short way off rather than appearing on the spot.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { at = CGPoint(x: dest.x - 40, y: dest.y + 30); target = nil }
            withAnimation(.easeOut(duration: 0.12)) { shown = true }
        }
        let time = reduce ? 0.0 : min(0.55, 0.22 + Double(max(far, 60)) / 3000)
        withAnimation(reduce ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: time)) {
            at = dest; self.target = frame.map(local); self.label = label
        }
        try? await Task.sleep(for: .seconds(time + 0.04))
    }
    /// A press where the arrow is: the ring.
    func press() async {
        withAnimation(nil) { pressing += 1 }
        try? await Task.sleep(for: .milliseconds(140))
    }
    /// Done for now: it fades a moment later (another step brings it straight back).
    func rest(after seconds: Double = 1.6) {
        hide?.cancel()
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.shown = false; self?.target = nil; self?.label = nil }
            // Then off the screen: a clear window over every display, left up, made macOS composite it over everything
            // you did in every app (the whole Mac felt laggy, 19 Nov). The next step puts it back (ensure()).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.hide == nil || self.hide?.isCancelled == false, !self.shown else { return }
                self.window?.orderOut(nil)
            }
        }
        hide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
}

private struct CursorLayer: View {
    @ObservedObject var cursor: AgentCursor
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let r = cursor.target {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(MARK_BLUE.opacity(0.9), lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MARK_BLUE.opacity(0.08)))
                    .frame(width: r.width + 6, height: r.height + 6)
                    .offset(x: r.minX - 3, y: r.minY - 3)
                    .transition(.opacity)
            }
            PressRing(count: cursor.pressing).offset(x: cursor.at.x - 14, y: cursor.at.y - 14)
            Arrow(label: cursor.label).offset(x: cursor.at.x, y: cursor.at.y)
        }
        .opacity(cursor.shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The arrow: the system pointer's shape in the app's blue, with a white rim and a soft drop, and its name tag.
private struct Arrow: View {
    let label: String?
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ArrowShape().fill(MARK_BLUE)
                .overlay(ArrowShape().stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)))
                .frame(width: 16, height: 22)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            if let label {
                Text(label).font(F.font(11, .medium)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(MARK_BLUE))
                    .padding(.top, 14)
            }
        }
    }
}

private struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.64))
        p.addLine(to: CGPoint(x: w * 0.52, y: h))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.93))
        p.addLine(to: CGPoint(x: w * 0.47, y: h * 0.58))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.58))
        p.closeSubpath()
        return p
    }
}

/// A ring that opens out and fades each time `count` goes up.
private struct PressRing: View {
    let count: Int
    @State private var grow = false
    var body: some View {
        Circle().stroke(MARK_BLUE, lineWidth: 2)
            .frame(width: 28, height: 28)
            .scaleEffect(grow ? 1.4 : 0.5)
            .opacity(grow ? 0 : (count == 0 ? 0 : 0.9))
            .onChange(of: count) { _, _ in
                grow = false
                withAnimation(.easeOut(duration: 0.35)) { grow = true }
            }
    }
}

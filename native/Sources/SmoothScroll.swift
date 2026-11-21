// A mouse wheel scrolls the way mouad.work does (its "smooth eased momentum scroll", ported one to one): each notch
// moves a target by the wheel's pixel delta, and every display frame the view moves 8.5% of the way there, stopping
// within 0.4 pt. Everything that scrolls up and down in the app gets it. A trackpad (precise deltas, its own momentum)
// is left exactly as macOS does it, as are Ctrl or Shift with the wheel, pages in the Browser, and Reduce Motion.
//
//   site:   target += deltaY (Chrome on a Mac: 40 px per wheel line); loop: current += (target - current) * 0.085,
//           done when |target - current| < 0.4; a scroll from anything else resets target = current = scrollY.
import AppKit
import QuartzCore

@MainActor final class SmoothScroll: NSObject {
    static let shared = SmoothScroll()
    /// The site's constants.
    static let ease: CGFloat = 0.085
    static let settle: CGFloat = 0.4
    /// Chrome's pixels per wheel line on a Mac (what mouad.work's deltaY is in Chrome).
    static let pixelsPerLine: CGFloat = 40
    /// Posted with the scroll view as object when a wheel turn starts moving it (the chat's follower listens).
    static let began = Notification.Name("agentlab.smoothScrollBegan")

    private var monitor: Any?
    private final class Run { weak var view: NSScrollView?; var target: CGFloat = 0; var current: CGFloat = 0; var link: CADisplayLink? }
    private var runs: [ObjectIdentifier: Run] = [:]

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            MainActor.assumeIsolated { SmoothScroll.shared.wheel(e) ? nil : e }
        }
    }

    /// The scroll view this wheel turn is moving, if it's one we smooth.
    func wheel(_ e: NSEvent, window given: NSWindow? = nil) -> Bool {
        // A trackpad or Magic Mouse sends precise deltas with its own momentum: macOS's scrolling, untouched, and a glide
        // still running on that view stops at once so the two never pull against each other.
        if e.hasPreciseScrollingDeltas || e.momentumPhase != [] || e.phase != [] {
            // Only when a glide is running: a hit test of the whole window on each of ~120 trackpad events a second
            // was paid for nothing.
            guard runs.values.contains(where: { $0.link != nil }) else { return false }
            if let window = e.window ?? given, let content = window.contentView,
               let hit = content.hitTest(content.superview?.convert(e.locationInWindow, from: nil) ?? e.locationInWindow),
               let view = scroller(from: hit) { stop(view) }
            return false
        }
        // A mouse whose driver already smooths the wheel (Logitech Options, Mos, …) sends fractional steps: smoothing them
        // again lags and stutters, so they're left as they come. A plain wheel sends whole lines.
        guard e.scrollingDeltaY == e.scrollingDeltaY.rounded() else { return false }
        guard e.momentumPhase == [], e.phase == [],
              !e.modifierFlags.contains(.control), !e.modifierFlags.contains(.shift),
              abs(e.scrollingDeltaY) > abs(e.scrollingDeltaX), e.scrollingDeltaY != 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window = e.window ?? given, let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(e.locationInWindow, from: nil) ?? e.locationInWindow),
              let view = scroller(from: hit) else { return false }
        let clip = view.contentView
        let id = ObjectIdentifier(view)
        let run = runs[id] ?? { let r = Run(); r.view = view; runs[id] = r; return r }()
        let y = clip.bounds.origin.y
        // Moved by anything else since (a trackpad, the chat following its end, a jump): start from where it is.
        if run.link == nil || abs(run.current - y) > 1 { run.current = y; run.target = y }
        // The site's deltaY: down is positive there; AppKit's wheel is positive upward. Flipped views grow downward.
        let dy = -e.scrollingDeltaY * Self.pixelsPerLine * (clip.isFlipped ? 1 : -1)
        run.target = min(max(run.target + dy, minY(view)), maxY(view))
        NotificationCenter.default.post(name: Self.began, object: view, userInfo: ["up": dy < 0])
        if run.link == nil {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            run.link = link
        }
        return true
    }

    /// The nearest enclosing scroll view that scrolls up and down (a sideways one inside it is passed over), never a
    /// web page's own (WKWebView scrolls itself).
    private func scroller(from view: NSView) -> NSScrollView? {
        var v: NSView? = view
        while let cur = v {
            if cur.className.hasPrefix("WK") { return nil }
            if let s = cur as? NSScrollView, let doc = s.documentView,
               doc.frame.height - s.contentView.bounds.height > 1, s.hasVerticalScroller || !s.hasHorizontalScroller || doc.frame.height > s.contentView.bounds.height + 1 {
                return s
            }
            v = cur.superview
        }
        return nil
    }
    private func minY(_ v: NSScrollView) -> CGFloat { -v.contentInsets.top }
    private func maxY(_ v: NSScrollView) -> CGFloat {
        max(minY(v), (v.documentView?.frame.height ?? 0) + v.contentInsets.bottom - v.contentView.bounds.height)
    }

    /// One display frame: the site's loop.
    @objc private func tick(_ link: CADisplayLink) {
        guard let (id, run) = runs.first(where: { $0.value.link === link }) else { link.invalidate(); return }
        guard let view = run.view else { link.invalidate(); runs[id] = nil; return }
        let clip = view.contentView
        // Content or size changed under it: the target stays inside the page.
        run.target = min(max(run.target, minY(view)), maxY(view))
        let d = run.target - run.current
        if abs(d) < Self.settle {
            run.current = run.target
            set(view, run.current)
            link.invalidate(); run.link = nil
            return
        }
        run.current += d * Self.ease
        set(view, run.current)
        _ = clip
    }
    private func set(_ view: NSScrollView, _ y: CGFloat) {
        let clip = view.contentView
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: y))
        view.reflectScrolledClipView(clip)
    }
    /// Ends a glide on `view` where it is.
    func stop(_ view: NSScrollView) {
        guard let run = runs[ObjectIdentifier(view)], let link = run.link else { return }
        link.invalidate(); run.link = nil
        run.current = view.contentView.bounds.origin.y; run.target = run.current
    }
    /// A wheel glide is moving this view now (the chat's follower treats it as your hand on it).
    func gliding(_ view: NSScrollView?) -> Bool {
        guard let view else { return false }
        return runs[ObjectIdentifier(view)]?.link != nil
    }
}

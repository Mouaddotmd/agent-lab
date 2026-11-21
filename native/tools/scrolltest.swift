// Mouse-wheel scrolling against mouad.work's curve: real line-based wheel events (as a mouse sends) into a real chat,
// the view's position read every display frame. Checks the glide follows current += (target - current) * 0.085 and
// lands exactly 40 pt per line; and that a trackpad's precise events are left to macOS.
import SwiftUI
import AppKit

@main struct ScrollTest {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let path = NSHomeDirectory() + "/Library/Application Support/Agent Lab/messages/a_dcdd5ea4.json"
        let msgs = try! JSONDecoder().decode([Message].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let store = Store()
        let agent = Agent(id: "a1", name: "mavis v2", job: "", look: nil, operator: "claude-code", model: nil, permission: "ask", cwd: NSHomeDirectory(), workspace: nil, pinned: nil, createdAt: 0, worktree: nil, branch: nil, last: nil, origin: nil)
        store.agents = [agent]; store.messages["a1"] = msgs
        let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        win.alphaValue = 0.02; win.orderFrontRegardless()
        let host = NSHostingView(rootView: ChatPane(agent: agent).environmentObject(store).environmentObject(store.panes))
        win.contentView = host
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        spin(1.0)
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        guard let scroll = all(host).compactMap({ $0 as? NSScrollView }).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) else { print("no scroll view"); exit(1) }
        let clip = scroll.contentView
        let mid = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        func wheel(lines: Int32, precise: Bool = false) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
            cg.location = CGPoint(x: win.frame.minX + mid.x, y: NSScreen.screens[0].frame.height - (win.frame.minY + mid.y))
            if precise { cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1) }
            return NSEvent(cgEvent: cg)!
        }
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
        // Start in the middle of the chat, at rest.
        clip.scroll(to: NSPoint(x: 0, y: 2000)); scroll.reflectScrolledClipView(clip); spin(0.2)
        let y0 = clip.bounds.origin.y
        let e = wheel(lines: 1)
        check(!e.hasPreciseScrollingDeltas, "a wheel notch arrives as a mouse's (no precise deltas), deltaY \(e.scrollingDeltaY)")
        let taken = SmoothScroll.shared.wheel(e, window: win)
        check(taken, "the chat takes the notch")
        var ys: [CGFloat] = [], t0 = CACurrentMediaTime()
        var trace: [String] = []
        while CACurrentMediaTime() - t0 < 1.6 { spin(1.0 / 240); let y = clip.bounds.origin.y; if ys.last != y { ys.append(y); trace.append(String(format: "%.0fms:%.1f", (CACurrentMediaTime() - t0) * 1000, y)) } }
        print("y0 \(y0) trace \(trace.prefix(12).joined(separator: " "))")
        let moved = (ys.last ?? y0) - y0
        let want = -e.scrollingDeltaY * SmoothScroll.pixelsPerLine
        check(abs(moved - want) < 0.5, String(format: "one notch moves %.1f pt (site: %.1f)", moved, want))
        // The curve: each frame covers 8.5% of what's left (first steps), as mouad.work's loop does.
        let steps = zip(ys.dropFirst(), ys).prefix(5).map { a, b in (a - b) / ((y0 + want) - b) }
        check(!steps.isEmpty && steps.allSatisfy { abs($0 - 0.085) < 0.002 }, "each frame closes 8.5% of the gap: " + steps.map { String(format: "%.4f", $0) }.joined(separator: " "))
        print(String(format: "frames to settle: %d (site at the same refresh: %d)", ys.count, Int((log(0.4 / abs(want)) / log(1 - 0.085)).rounded(.up))))
        // Several quick notches add up before the glide ends.
        let y1 = clip.bounds.origin.y
        for _ in 0..<3 { _ = SmoothScroll.shared.wheel(wheel(lines: 1), window: win); spin(0.03) }
        spin(1.6)
        check(abs((clip.bounds.origin.y - y1) - (-3 * SmoothScroll.pixelsPerLine)) < 1, String(format: "three quick notches up add up: %.1f pt", clip.bounds.origin.y - y1))
        // A trackpad is macOS's own scrolling.
        check(!SmoothScroll.shared.wheel(wheel(lines: -5, precise: true), window: win), "a trackpad's precise scroll is left to macOS")
        // A glide stops the moment a trackpad touches the view (they never pull against each other).
        _ = SmoothScroll.shared.wheel(wheel(lines: 3), window: win); spin(0.05)
        _ = SmoothScroll.shared.wheel(wheel(lines: -2, precise: true), window: win)
        let held = clip.bounds.origin.y; spin(0.3)
        check(abs(clip.bounds.origin.y - held) < 0.5 && !SmoothScroll.shared.gliding(scroll), "a trackpad scroll stops a glide where it is")
        // A wheel already smoothed by its driver (fractional steps) is passed through untouched.
        let frac = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
        frac.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.37)
        let fe = NSEvent(cgEvent: frac)!
        check(fe.hasPreciseScrollingDeltas || fe.scrollingDeltaY != fe.scrollingDeltaY.rounded() ? !SmoothScroll.shared.wheel(fe, window: win) : true, "a driver-smoothed fractional step is left alone (delta \(fe.scrollingDeltaY), precise \(fe.hasPreciseScrollingDeltas))")
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}

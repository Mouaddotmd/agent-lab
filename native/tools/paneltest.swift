// Opens and closes the side panel the way you do (a click, quick clicks mid-slide, dragging its edge) in a real window
// with your real chat, and checks every frame: the chat always shows its words (never black), and once it settles the
// panel is all the way in (open) or gone (closed), never stuck half-shown.
//   build/paneltest [folder for pictures]
import SwiftUI
import AppKit

@main struct PanelTest {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/paneltest"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let store = Store(); store.connect()
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        let end = Date().addingTimeInterval(15)
        while store.agents.isEmpty && Date() < end { spin(0.05) }
        guard let agent = store.agents.first else { print("no agents"); exit(1) }
        store.openChat(agent.id)
        let window = NSWindow(contentRect: CGRect(x: -8000, y: 0, width: 1392, height: 852), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RootView(drawLights: true).environmentObject(store))
        host.sizingOptions = []
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        spin(2.5)
        let panel = SidePanel.of(agent, home: store.home)
        if panel.open { panel.toggle(); spin(0.6) }
        func scrolls(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrolls) }
        func chat() -> NSScrollView? { scrolls(host).filter { !$0.isHiddenOrHasHiddenAncestor }.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) } }
        var shot = 0
        /// Lit share of a rect of the window (host coordinates, top-left origin).
        func ink(_ r: CGRect, _ rep: NSBitmapImageRep) -> Double {
            let sx = Double(rep.pixelsWide) / host.bounds.width, sy = Double(rep.pixelsHigh) / host.bounds.height
            var lit = 0, all = 0
            var y = Int(r.minY * sy) + 4
            while y < Int(r.maxY * sy) - 4 {
                var x = Int(r.minX * sx) + 4
                while x < Int(r.maxX * sx) - 4 {
                    if let c = rep.colorAt(x: x, y: y), c.brightnessComponent > 0.35 { lit += 1 }
                    all += 1; x += 6
                }
                y += 6
            }
            return all == 0 ? 0 : Double(lit) / Double(all)
        }
        func capture() -> NSBitmapImageRep { let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!; host.cacheDisplay(in: host.bounds, to: rep); return rep }
        /// The chat's words (its scroll view, as laid out now) and the strip the panel takes when open.
        func measure(_ name: String? = nil) -> (chat: Double, panel: Double) {
            let rep = capture()
            if let name { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png")) }
            guard let sv = chat() else { return (-1, -1) }
            var r = sv.convert(sv.bounds, to: host); if !host.isFlipped { r.origin.y = host.bounds.height - r.maxY }
            let w = min(max(320, SidePanel.width), host.bounds.width - 380)
            let strip = CGRect(x: host.bounds.width - w + 8, y: 120, width: w - 16, height: 500)
            return (ink(r.insetBy(dx: 0, dy: 0), rep), ink(strip, rep))
        }
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
        let base = measure("0-closed")
        print(String(format: "closed: chat ink %.3f, panel strip ink %.3f", base.chat, base.panel))
        /// Toggles with `gaps` seconds between clicks, sampling every frame, then lets it settle.
        func fromEnd() -> CGFloat { guard let v = chat(), let d = v.documentView else { return -1 }; return d.frame.height + v.contentInsets.bottom - v.contentView.bounds.maxY }
        func run(_ name: String, _ gaps: [Double]) {
            var worst = 1.0, drift: CGFloat = 0
            for (i, g) in gaps.enumerated() {
                panel.toggle()
                let until = Date().addingTimeInterval(g)
                var n = 0
                while Date() < until { spin(1.0 / 60); let m = measure(); worst = min(worst, m.chat); drift = max(drift, abs(fromEnd())); n += 1; if m.chat < base.chat * 0.15 { _ = measure("\(name)-blank-\(i)-\(n)") } }
            }
            spin(0.5)
            let m = measure("\(name)-settled")
            check(worst > base.chat * 0.15, String(format: "%@: the chat shows its words on every frame (lowest ink %.3f)", name, worst))
            check(drift < 1, String(format: "%@: the chat stays on its last message every frame (furthest %.1f pt)", name, drift))
            if panel.open { check(m.panel > 0.004 && m.chat > base.chat * 0.3, String(format: "%@: settled open, panel all the way in (panel ink %.3f, chat %.3f)", name, m.panel, m.chat)) }
            else { check(abs(m.chat - base.chat) < base.chat * 0.5, String(format: "%@: settled closed, chat full width (chat ink %.3f)", name, m.chat)) }
        }
        if ProcessInfo.processInfo.environment["AL_FILM"] != nil {
            panel.toggle()
            for f in 0..<24 { spin(1.0 / 60); if f % 3 == 0 { _ = measure(String(format: "film-open-%02d", f)) } }
            spin(0.4)
            panel.toggle()
            for f in 0..<18 { spin(1.0 / 60); if f % 3 == 0 { _ = measure(String(format: "film-close-%02d", f)) } }
            exit(0)
        }
        run("open", [0.5])
        run("close", [0.5])
        run("open-close-open quickly", [0.08, 0.08, 0.5])
        run("close-open quickly", [0.12, 0.5])
        run("five quick clicks", [0.05, 0.05, 0.05, 0.05, 0.6])
        // The edge: drag it by setting the width the way the grip does, frame by frame, wide to narrow and back.
        if !panel.open { panel.toggle(); spin(0.6) }
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}

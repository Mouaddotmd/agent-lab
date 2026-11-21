// Resizes a real window showing a chat (side panel open) step by step, as a drag does, and after every step checks
// that the chat still shows its words: the share of lit pixels in the transcript must not fall to nothing.
//   build/resizetest [folder for pictures]
import SwiftUI
import AppKit

@main struct ResizeTest {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/resizetest"
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
        if !panel.open { panel.toggle() }
        spin(1)
        func scrolls(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrolls) }
        func chat() -> NSScrollView? { scrolls(host).filter { !$0.isHiddenOrHasHiddenAncestor }.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) } }
        /// Share of pixels brighter than the background in the chat's visible area.
        func ink(_ name: String? = nil) -> Double {
            guard let sv = chat(), let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let name { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png")) }
            let r = sv.convert(sv.bounds, to: host)
            let sx = Double(rep.pixelsWide) / host.bounds.width, sy = Double(rep.pixelsHigh) / host.bounds.height
            var lit = 0, all = 0
            var y = Int(r.minY * sy) + 4
            while y < Int(r.maxY * sy) - 4 {
                var x = Int(r.minX * sx) + 4
                while x < Int(r.maxX * sx) - 20 {
                    if let c = rep.colorAt(x: x, y: host.isFlipped ? y : rep.pixelsHigh - y), c.brightnessComponent > 0.35 { lit += 1 }
                    all += 1; x += 6
                }
                y += 6
            }
            return all == 0 ? 0 : Double(lit) / Double(all)
        }
        let start = ink("0-start")
        if ProcessInfo.processInfo.environment["AL_READ"] != nil {
            // Scrolled up, reading: the same message must stay at the top, at the same spot in it, while the width changes.
            guard let f = Follower.alive.compactMap(\.f).first(where: { $0.scrollView === chat() }), let sv = chat(), let d = sv.documentView else { print("no follower"); exit(1) }
            f.letGo(to: d.frame.height * 0.45)
            spin(0.3)
            guard let first = f.atTop else { print("nothing at top"); exit(1) }
            print(String(format: "reading %@ at %.2f of it (view top %.0f of %.0f)", first.id, first.share, sv.contentView.bounds.minY, d.frame.height))
            var moved = 0, worstShare = 0.0, blanks = 0
            let widths = Array(stride(from: 1392.0, through: 1000.0, by: -8.0)) + Array(stride(from: 1000.0, through: 1392.0, by: 8.0))
            for w in widths {
                window.setContentSize(NSSize(width: w, height: 852)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                spin(1.0 / 60)
                guard let now = f.atTop else { moved += 1; continue }
                if now.id != first.id { moved += 1 } else { worstShare = max(worstShare, abs(now.share - first.share)) }
                if ink() < start * 0.15 { blanks += 1 }
            }
            spin(0.4)
            let end = f.atTop
            print(String(format: "steps where another message took the top: %d of %d · furthest drift inside it %.3f of its height · blank %d · following %d", moved, widths.count, worstShare, blanks, f.isFollowing ? 1 : 0))
            print(moved == 0 && worstShare < 0.03 && blanks == 0 && end?.id == first.id && !f.isFollowing ? "PASS" : "FAIL")
            exit(0)
        }
        if ProcessInfo.processInfo.environment["AL_ROWS"] != nil {
            let rows = store.rows(for: agent.id)
            for w in [1300.0, 1236.0, 1230.0, 1224.0, 1206.0] {
                window.setContentSize(NSSize(width: w, height: 852)); spin(0.3)
                let cw = (chat()?.contentView.bounds.width ?? 0) - 32
                var line = String(format: "window %.0f (column %.0f, document %.0f):", w, cw, chat()?.documentView?.frame.height ?? -1)
                var total = 0.0
                for (i, row) in rows.enumerated().suffix(40) {
                    let hc = NSHostingController(rootView: ChatRowView(agent: agent, row: row, prev: i > 0 ? rows[i - 1] : nil).environmentObject(store))
                    _ = hc.sizeThatFits(in: CGSize(width: cw + 40, height: 1e6))
                    let t0 = CACurrentMediaTime()
                    let h = hc.sizeThatFits(in: CGSize(width: cw, height: 1e6)).height
                    let ms = (CACurrentMediaTime() - t0) * 1000
                    if ms > 0.8 { line += String(format: " [row %d %.1fms %@]", i, ms, String(describing: row).prefix(40).description) }
                    total += h
                    if h > 1500 { line += String(format: " row %d=%.0f", i, h) }
                }
                line += String(format: " · rows add up to %.0f of %d rows", total, rows.count)
                print(line)
            }
            exit(0)
        }
        if let hold = ProcessInfo.processInfo.environment["AL_HOLD"].flatMap(Double.init) {
            window.setContentSize(NSSize(width: hold, height: 852))
            for t in [0.02, 0.1, 0.5, 1.5] { spin(t); let sv = chat()
                print(String(format: "at %.0f after +%.2fs: ink %.3f · y %.0f of %.0f", hold, t, ink("hold-\(t)"), sv?.contentView.bounds.minY ?? -1, sv?.documentView?.frame.height ?? -1)) }
            exit(0)
        }
        print(String(format: "start: ink %.3f", start))
        var worst = (ink: 1.0, width: 0.0), blanks = 0
        let widths = Array(stride(from: 1392.0, through: 980.0, by: -6.0)) + Array(stride(from: 980.0, through: 1392.0, by: 6.0))
        var times: [Double] = []
        for w in widths {
            let t = CACurrentMediaTime()
            window.setContentSize(NSSize(width: w, height: 852))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            times.append((CACurrentMediaTime() - t) * 1000)
            spin(1.0 / 60)
            let i = ink()
            if i < worst.ink { worst = (i, w) }
            if i < start * 0.15 { blanks += 1; if blanks <= 3 { _ = ink("blank-\(Int(w))") } }
        }
        spin(0.5)
        let after = ink("9-after")
        if let sv = chat(), let d = sv.documentView { print(String(format: "after: ink %.3f · y %.0f of %.0f (view %.0f)", after, sv.contentView.bounds.minY, d.frame.height, sv.contentView.bounds.height)) }
        let sorted = times.sorted()
        print(String(format: "resize step: median %.1f ms, 95th %.1f ms, worst %.1f ms", sorted[sorted.count / 2], sorted[sorted.count * 95 / 100], sorted.last ?? 0))
        print(String(format: "worst ink %.3f at width %.0f · blank frames %d of %d", worst.ink, worst.width, blanks, widths.count))
        print(blanks == 0 && after > start * 0.5 ? "PASS" : "FAIL")
        exit(0)
    }
}

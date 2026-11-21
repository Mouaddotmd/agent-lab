// Rests on icon buttons across the real app (chat open, side panel open) and checks each label: it waits the pause,
// sits on the asked side of its button, centred on it, inside the screen, says the right words; the next button shows
// its own at once; a click puts it away. Saves a picture of each, the label drawn where it sits.
//   AL_TIP_TEST=1 build/tiptest [folder]
import SwiftUI
import AppKit

@main struct TipTest {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/tiptest"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let store = Store(); store.connect()
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        let end = Date().addingTimeInterval(15)
        while store.agents.isEmpty && Date() < end { spin(0.05) }
        guard let agent = store.agents.first else { print("no agents"); exit(1) }
        store.openChat(agent.id)
        // On screen (the label keeps itself on the screen, so the window must be on one), far from the user's work.
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: CGRect(x: screen.minX + 20, y: screen.minY + 20, width: 1392, height: 852), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RootView(drawLights: true).environmentObject(store))
        host.sizingOptions = []
        window.contentView = host; window.alphaValue = 0.01; window.orderFrontRegardless()
        spin(2.5)
        let panel = SidePanel.of(agent, home: store.home)
        if !panel.open { panel.toggle() }
        spin(1)
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
        func snap(_ name: String) {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let w = Tips.shared.window, let v = w.contentView, let r2 = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: r2)
                let at = window.convertFromScreen(w.frame)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                r2.draw(in: at, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
        // The buttons this look has (MAVIS has no top bar: back and forward live in the Go menu).
        let cases: [(String, TipEdge)] = MV.on
            ? [("New agent (\u{2318}N)", .bottom), ("Today", .top), ("Add files, commands, plugins", .top), ("Talk", .top), ("Plugins and settings", .top)]
            : [("Collapse browser", .bottom), ("New agent", .bottom), ("Today", .bottom),
               ("Add files, commands, plugins", .top), ("New tab", .bottom), ("Back", .bottom), ("Plugins and settings", .top)]
        for (i, (title, edge)) in cases.enumerated() {
            guard let owner = Tips.shared.owner(title), let anchor = owner.view else { check(false, "\(title): button found"); continue }
            spin(0.4)                                                    // cold: the last label has gone a while ago
            Tips.shared.enter(owner, title: title, detail: nil, edge: edge)
            spin(0.2)
            check(Tips.shared.showing == nil, "\(title): nothing before the pause")
            spin(Tips.delay)                                              // a button's label waits Tips.delay (0.9 s)
            check(Tips.shared.showing == title, "\(title): label up after the pause (\(Tips.shared.showing ?? "none"))")
            if let f = Tips.shared.labelFrame {
                let a = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                let side: Bool
                switch Tips.shared.shownEdge {
                case .bottom: side = abs(a.minY - f.maxY - Tips.gap) < 1.5
                case .top: side = abs(f.minY - a.maxY - Tips.gap) < 1.5
                case .trailing: side = f.minX > a.maxX
                case .leading: side = f.maxX < a.minX
                }
                let centred = (Tips.shared.shownEdge == .top || Tips.shared.shownEdge == .bottom) ? abs(f.midX - a.midX) < 1.5 || f.maxX >= screen.maxX - 7 || f.minX <= screen.minX + 7 : abs(f.midY - a.midY) < 1.5
                check(side && centred, String(format: "%@: %@ its button, %.0f from it, centred (label %@, button %@)", title, "\(Tips.shared.shownEdge)", Tips.gap, NSStringFromRect(f), NSStringFromRect(a)))
                check(screen.contains(f), "\(title): inside the screen")
            }
            snap(String(format: "%02d-%@", i, title.replacingOccurrences(of: " ", with: "-")))
            Tips.shared.leave(owner)
            spin(0.1)
            check(Tips.shared.showing == nil, "\(title): leaving hides it")
        }
        // Warm: right after one goes, the next shows at once.
        if let a = Tips.shared.owner(MV.on ? "New agent (\u{2318}N)" : "New agent"), let b = Tips.shared.owner("Today") {
            Tips.shared.enter(a, title: "New agent", detail: nil, edge: .bottom); spin(0.7)
            Tips.shared.leave(a); Tips.shared.enter(b, title: "Today", detail: nil, edge: .bottom); spin(0.05)
            check(Tips.shared.showing == "Today", "next button over: shows at once")
            // A click puts it away and it doesn't come back while you stay.
            NSApp.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            spin(0.1)
            check(Tips.shared.showing == nil, "a click hides it")
            Tips.shared.enter(b, title: "Today", detail: nil, edge: .bottom); spin(0.6)
            check(Tips.shared.showing == nil, "and it stays hidden until you leave the button")
            Tips.shared.leave(b)
        }
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}

// Draws one of the app's menus open, in a real offscreen window with your real agents, and saves a picture.
//   AL_TEST_MENU=conv:<agent id>|ws:<workspace id>|head|rail:<workspace id> build/menushot out.png [messages|workspace|folded]
import SwiftUI
import AppKit
@main
struct MenuShot {
    @MainActor static func main() {
        let args = CommandLine.arguments
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let store = Store(); store.connect()
        let end = Date().addingTimeInterval(15)
        while store.agents.isEmpty && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let mode = args.count > 2 ? args[2] : "messages"
        if mode == "messages" { store.go(.messages) }
        if mode == "workspace" || mode == "folded", let w = store.workspaces.first { store.openSpace(w.id) }
        if mode == "folded" { store.panes.sidebarFolded = true }
        if let m = ProcessInfo.processInfo.environment["AL_TEST_MENU"], m.hasPrefix("rail:") { store.railMenu = String(m.dropFirst(5)) }
        let window = NSWindow(contentRect: CGRect(x: -8000, y: 0, width: 1392, height: 852), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RootView(drawLights: true).environmentObject(store).frame(width: 1392, height: 852))
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        // A floating menu is its own window: draw it over the picture where it sits.
        if let menu = MenuWindow.shared.window, let v = menu.contentView, let mrep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: mrep)
            let at = window.convertFromScreen(menu.frame)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            mrep.draw(in: NSRect(x: at.minX, y: at.minY, width: at.width, height: at.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[1]))
        print("wrote \(args[1]) · agents \(store.agents.map { "\($0.name)=\($0.id)" }) · workspaces \(store.workspaces.map { "\($0.name)=\($0.id)" })")
        exit(0)
    }
}

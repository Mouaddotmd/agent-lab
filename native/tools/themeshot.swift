// The real app (Home, then a chat) drawn in every theme, recoloured live the way the menu's preview does it.
//   build/themeshot <folder>
import SwiftUI
import AppKit

@main struct ThemeShot {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/themeshot"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let store = Store(); store.connect()
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        let end = Date().addingTimeInterval(15)
        while store.agents.isEmpty && Date() < end { spin(0.05) }
        let window = NSWindow(contentRect: CGRect(x: 30, y: 30, width: 1300, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0.02
        let host = NSHostingView(rootView: RootView(drawLights: true).environmentObject(store))
        host.sizingOptions = []
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        spin(2.0)
        if let a = store.agents.first { store.openChat(a.id) }
        spin(1.5)
        for p in Palettes.all {
            let t0 = CACurrentMediaTime(); Themes.shared.show(p); host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush(); let took = CACurrentMediaTime() - t0; spin(0.3)
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!; host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(p.id).png"))
            var resolved = ""
            window.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = NSColor(C.v0).usingColorSpace(.sRGB).map { String(format: "%02x%02x%02x", Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255)) } ?? "?" }
            print(String(format: "switch %.1f ms ", took * 1000) + "drew \(p.id) themeNow.v0 \(String(themeNow.v0, radix: 16)) token resolves to \(resolved) appearance \(window.effectiveAppearance.name.rawValue)")
        }
        exit(0)
    }
}

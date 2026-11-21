// The tools under a hovered message (MessageTools.swift), drawn in the real chat: the last of your messages lit, then
// the last answer, each caught mid-arrival and settled.
//   build/toolshot <folder>
import SwiftUI
import AppKit

@main struct ToolShot {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/toolshot"
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
        guard let a = store.agents.first(where: { !(store.messages[$0.id] ?? []).isEmpty }) ?? store.agents.first else { print("FAIL no agent"); exit(1) }
        store.openChat(a.id)
        spin(2.0)
        let rows = store.rows(for: a.id)
        let you = rows.last { if case .you = $0 { true } else { false } }?.id
        let turn = rows.last { if case .agent(let t) = $0 { !t.running } else { false } }?.id
        func shot(_ name: String) {
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!; host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
        for (name, id) in [("you", you), ("agent", turn)] {
            guard let id else { print("FAIL no \(name) row"); continue }
            RowLights.shared.light(id)
            spin(0.06); shot("\(name)-arriving")
            spin(0.5); shot("\(name)-settled")
            RowLights.shared.light(nil); spin(0.3)
            print("PASS drew \(name) (\(id))")
        }
        exit(0)
    }
}

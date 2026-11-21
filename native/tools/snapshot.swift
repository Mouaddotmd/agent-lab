// Renders a screen of the native app to PNG at 1×, with no window, for the pixel diff.
//   snapshot out.png [view]
import SwiftUI
import AppKit

@main
struct Snapshot {
    @MainActor static func main() {
        let args = CommandLine.arguments
        F.register(); SnapshotMode.on = true
        // SNAP_THEME=mavis.dark: render in that theme (and its layout) instead of the saved one.
        if let t = ProcessInfo.processInfo.environment["SNAP_THEME"], let p = Palettes.named(t) { themeNow = p }
        let store = Store()
        store.home = "/Users/you"                                  // the web reference's ?empty home
        // SNAP_ENGINE=1: load real agents from the engine (AGENT_LAB_DATA picks the folder) before drawing.
        if ProcessInfo.processInfo.environment["SNAP_ENGINE"] == "1" {
            store.connect()
            let until = Date().addingTimeInterval(10)
            while store.agents.isEmpty && store.engineProblem == nil && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            if let p = store.engineProblem { print("engine: \(p)") }
        }
        if args.count > 2, let k = Kind(rawValue: args[2]) { store.view = k }
        switch args.count > 3 ? args[3] : "" {
        case "settings": store.settingsOpen = true
        case "history": store.go(.discover); store.go(.agents); store.historyOpen = true
        case "search": store.searchOpen = true
        case "newagent": store.newAgentOpen = true
        case "workspace": store.openWorkspace = store.workspaces.first?.id
        default: break
        }
        let W = CGFloat(Double(ProcessInfo.processInfo.environment["SNAP_W"] ?? "") ?? 1392)
        store.panes.resized(W)
        if ProcessInfo.processInfo.environment["SNAP_FOLD"] == "1" { store.panes.sidebarFolded = true }
        if ProcessInfo.processInfo.environment["SNAP_OPEN"] == "1", let a = store.agents.first {
            store.openAgent = a.id
            let until = Date().addingTimeInterval(5)
            Task { await store.loadMessages(a.id) }
            while store.messages[a.id] == nil && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            // The box's menus fill from the engine: give them a moment.
            if ProcessInfo.processInfo.environment["SNAP_COMPOSER"] != nil {
                store.loadCatalog(a.id); store.loadPlugins(a.id)
                let more = Date().addingTimeInterval(8)
                while (store.catalogs[a.id] == nil || store.plugins[a.id] == nil) && Date() < more { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            }
        }
        if let t = ProcessInfo.processInfo.environment["SNAP_TIP"] { store.railTip.showNow(.init(id: t, title: t, detail: t == "Home" ? nil : "2 agents · 1 working", frame: .zero)) }
        // SNAP_WELCOME=account|claude|ready: that welcome page on its own.
        let welcomePage = ProcessInfo.processInfo.environment["SNAP_WELCOME"].flatMap { w in Welcome.Page.allCases.first { "\($0)" == w } }
        if let welcomePage { Welcome.shared.page = welcomePage }
        let view = Group {
            if welcomePage != nil { WelcomeView().environment(\.colorScheme, .dark) } else { RootView(drawLights: true) }
        }.environmentObject(store).frame(width: W, height: 852)
        let r = ImageRenderer(content: view); r.scale = CGFloat(Double(ProcessInfo.processInfo.environment["SCALE"] ?? "1") ?? 1)
        guard let cg = r.cgImage else { print("render failed"); exit(1) }
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
        print("wrote \(args[1]) \(cg.width)x\(cg.height)")
    }
}

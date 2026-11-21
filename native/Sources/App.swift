// Agent Lab (native). Snapshots for the pixel diff come from tools/snapshot.swift (no window).
import SwiftUI
import AppKit

@main
struct AgentLabApp: App {
    @StateObject private var store = Store()
    init() { F.register() }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .ignoresSafeArea()                 // the top bar is the window's top edge, like the web app
                .background(WindowSetup())
                .task { await AccessCheck.run() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1392, height: 852)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent") { store.newAgentOpen = true }.keyboardShortcut("n")
            }
            CommandMenu("Go") {
                Button("Back") { store.step(-1) }.keyboardShortcut("[").disabled(!store.canBack)
                Button("Forward") { store.step(1) }.keyboardShortcut("]").disabled(!store.canForward)
                // MAVIS has no top bar: History is here and on ⌘Y.
                Button("History") { store.settingsOpen = false; store.historyOpen.toggle() }.keyboardShortcut("y")
                Divider()
                Button("Search and Commands") { store.closeMenus(); store.searchOpen.toggle() }.keyboardShortcut("k")
                Divider()
                ForEach(Array(Kind.nav.enumerated()), id: \.offset) { i, k in
                    Button(k.info.title) { store.go(k) }
                }
            }
        }
    }
}

/// Your access, checked at launch and every six hours (Mavis final launch): an account turned off or signed out by the
/// service is noticed while Agent Lab is open, and the welcome's sign-in page comes back.
@MainActor enum AccessCheck {
    static func run() async {
        guard Account.configured else { return }
        while !Task.isCancelled {
            if Account.shared.session != nil {
                await Account.shared.recheck()
                if !Account.shared.allowed && !Welcome.shared.showing { AccountGate.lost() }
            }
            try? await Task.sleep(for: .seconds(6 * 3600))
        }
    }
}

/// Puts the real traffic lights where the web app draws them (20, 22) and makes the window black.
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = false
            w.backgroundColor = NSColor(C.v0)
            w.appearance = NSAppearance(named: themeNow.dark ? .darkAqua : .aqua)
            w.minSize = NSSize(width: Panes.windowMin, height: 560)
            place(w)
            for n in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { _ in place(w) }
            }
            // The lights move with the layout (MAVIS puts them on the rail), so a theme switch places them again.
            NotificationCenter.default.addObserver(forName: Themes.changed, object: nil, queue: .main) { _ in place(w) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
@MainActor private func place(_ w: NSWindow) {
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (i, k) in kinds.enumerated() {
        guard let b = w.standardWindowButton(k), let sup = b.superview else { continue }
        // The visible circle is 12 inside a 14 button: origin = circle origin − 1.
        let x: CGFloat = (MV.on ? MV.Shell.lightsX : 20) + CGFloat(i) * MV.Shell.lightsStep - 1
        let yFromTop: CGFloat = (MV.on ? MV.Shell.lightsY : 22) - 1
        b.setFrameOrigin(NSPoint(x: x, y: sup.frame.height - yFromTop - b.frame.height))
    }
}

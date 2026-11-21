// Opens an ActionMenu with .floatingMenu over a scrolling list and a kept NSHostingView (the two things that used to
// take its clicks), then sends the menu real mouse events: moving over a row, clicking it, Esc, and a click outside.
//   build/menuclick [out.png]
import SwiftUI
import AppKit

final class Log: ObservableObject { @Published var picked: [String] = []; @Published var open = true }

struct Harness: View {
    @ObservedObject var log: Log
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(0..<12) { i in
                        HStack { Text("Row \(i)"); Spacer()
                            if i == 0 {
                                Color.gray.frame(width: 28, height: 28)
                                    .floatingMenu($log.open) {
                                        ActionMenu(open: $log.open, width: 200, items: [
                                            .init(symbol: "pin", title: "Pin") { log.picked.append("Pin") },
                                            .init(symbol: "plus.square.on.square", title: "Duplicate") { log.picked.append("Duplicate") },
                                            .divider,
                                            .init(symbol: "trash", title: "Delete agent", danger: true) { log.picked.append("Delete") },
                                        ])
                                    }
                            }
                        }
                        .padding(12).frame(height: 80).background(Color.white.opacity(0.05)).onTapGesture { log.picked.append("row \(i)") }
                    }
                }
            }.frame(width: 300)
            Kept()
        }
        .frame(width: 900, height: 600).background(Color.black)
    }
}
/// Stands in for a kept chat: its own NSHostingView, right beside the list.
struct Kept: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSHostingView(rootView: Color.blue.opacity(0.2).onTapGesture { print("kept view got a click") }) }
    func updateNSView(_ v: NSView, context: Context) {}
}

@main struct MenuClick {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let store = Store(), log = Log()
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: Harness(log: log).environmentObject(store))
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        spin(1)
        var fails = 0
        if CommandLine.arguments.contains("--plain") {
            MenuWindow.shared.dismiss(); spin(0.3); window.makeKey()
            func s2(_ t: NSEvent.EventType) { NSApp.sendEvent(NSEvent.mouseEvent(with: t, location: NSPoint(x: 150, y: 300), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!) }
            s2(.leftMouseDown); spin(0.05); s2(.leftMouseUp); spin(0.4); print("plain click got \(log.picked)"); exit(0)
        }
        func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
        guard let menu = MenuWindow.shared.window else { print("FAIL menu didn't open"); exit(1) }
        check(menu.isVisible && menu.parent === window, "menu opens in its own window above the app's")
        let frame = menu.frame, m = MenuWindow.margin
        print("menu frame \(frame) · anchor row 0 right edge in window")
        // Row 2 (Duplicate): margin + padding 4 + row 40 + spacing 2 + half a row, from the card's top.
        let dupY = frame.height - m - 4 - 40 - 2 - 20
        let at = NSPoint(x: m + 60, y: dupY)
        func send(_ type: NSEvent.EventType, _ p: NSPoint, to w: NSWindow) {
            let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            NSApp.sendEvent(e)
        }
        send(.mouseMoved, at, to: menu); spin(0.3)
        if let out = CommandLine.arguments.dropFirst().first, let v = menu.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out)); print("wrote \(out)")
        }
        send(.leftMouseDown, at, to: menu); spin(0.05); send(.leftMouseUp, at, to: menu); spin(0.4)
        check(log.picked == ["Duplicate"], "click on Duplicate runs Duplicate (got \(log.picked))")
        check(MenuWindow.shared.window == nil && !log.open, "a choice closes the menu")
        // Open again; a click outside closes it and goes on to what it was on.
        log.open = true; spin(0.6)
        check(MenuWindow.shared.window != nil, "opens again")
        send(.leftMouseDown, NSPoint(x: 150, y: 300), to: window); spin(0.05); send(.leftMouseUp, NSPoint(x: 150, y: 300), to: window); spin(0.4)
        check(MenuWindow.shared.window == nil && !log.open, "a click outside closes it")
        // Esc.
        log.open = true; spin(0.6)
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: MenuWindow.shared.window?.windowNumber ?? 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        NSApp.sendEvent(esc); spin(0.3)
        check(MenuWindow.shared.window == nil && !log.open, "Esc closes it")
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}

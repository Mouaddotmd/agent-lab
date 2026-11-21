// Drives the message box in a real (offscreen) window with real key events and your real agents, printing what it
// does and saving pictures of each state. Never presses ↵ on words, so nothing is sent.
//   build/boxtest <folder for pictures>
import SwiftUI
import AppKit

@main
struct BoxTest {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/boxtest"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        F.register()
        let store = Store()
        store.connect()
        spin(until: { !store.agents.isEmpty || store.engineProblem != nil }, 15)
        guard let agent = store.agents.first(where: { $0.operator != "codex" }) ?? store.agents.first else { print("no agents"); exit(1) }
        store.openChat(agent.id)
        let window = NSWindow(contentRect: CGRect(x: -8000, y: 0, width: 1392, height: 852), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RootView(drawLights: true).environmentObject(store).frame(width: 1392, height: 852))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        spin(seconds: 2)
        func find(_ v: NSView) -> ComposerTextView? { if let t = v as? ComposerTextView { return t }; for s in v.subviews { if let t = find(s) { return t } }; return nil }
        guard let text = find(host), let model = text.model else { print("no box"); exit(1) }
        window.makeFirstResponder(text)
        spin(until: { store.catalogs[agent.id] != nil }, 20)
        print("agent: \(agent.name) (\(agent.operator ?? "claude-code")) · catalog: \(store.catalogs[agent.id]?.commands.count ?? -1) commands, \(store.catalogs[agent.id]?.models.count ?? -1) models")
        func key(_ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            text.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
            spin(seconds: 0.25)
        }
        func type(_ s: String) { text.insertText(s, replacementRange: text.selectedRange()); spin(seconds: 0.3) }
        func clear() { text.selectAll(nil); text.deleteBackward(nil); spin(seconds: 0.2) }
        func snap(_ name: String) {
            spin(seconds: 0.6)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
        func show(_ step: String) {
            let menu = model.menu.flatMap { PlusItem(rawValue: $0)?.title } ?? "-"
            print("\(step): “\(model.text.replacingOccurrences(of: "\n", with: "⏎"))” · \(model.suggestions.count) suggestions\(model.suggestions.isEmpty ? "" : " (lit: \(model.suggestions[safe: model.highlighted]?.label ?? "-"))") · menu \(menu)\(model.submenu.map { " / sub \($0)" } ?? "") · height \(Int(model.height))")
        }
        clear(); snap("1-box")
        type("first"); key("\r", 36, .shift); type("second"); show("⇧↵ new line")
        clear()
        type("/"); show("/"); snap("2-slash")
        key("", 125); key("", 125); show("↓↓")
        key("", 121); show("Page ↓"); key("n", 45, .control); show("⌃N"); key("p", 35, .control); show("⌃P")
        type("cont"); show("/cont")
        key("\t", 48); show("Tab completes")
        clear(); type("/mod"); key("\t", 48); show("/model + Tab → models"); snap("3-models")
        key("", 53); show("Esc"); clear()
        type("look at @"); spin(until: { !model.suggestions.isEmpty }, 10); show("@"); snap("4-mention")
        type("Sour"); show("@Sour")
        key("", 53); show("Esc closes list"); clear()
        model.toggleMenu(); show("+"); snap("5-menu")
        key("", 125); key("", 125); key("", 125); show("↓↓↓")
        key("", 124); spin(until: { store.plugins[agent.id] != nil }, 20); show("→ Plugins"); snap("6-plugins")
        key("", 125); show("↓ in Plugins")
        key("", 123); show("← back")
        key("", 126); show("↑"); key("\r", 36); show("↵ on Slash commands")
        key("", 53); clear()
        model.toggleMenu(); key("", 53); show("Esc closes menu")
        DraftStore.shared.remember("an earlier message")
        key("", 126); show("↑ history"); key("", 125); show("↓ back")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("pasted words", forType: .string)
        text.paste(nil); spin(seconds: 0.2); show("paste")
        model.add([NSHomeDirectory() + "/Desktop/Agent Lab/native/Assets/operators/codex.png", NSHomeDirectory() + "/Desktop/Agent Lab/README.md"]); show("attached"); snap("7-attached")
        model.remove(model.images.first ?? ""); model.remove(model.files.first ?? ""); clear()
        print("draft kept: “\(DraftStore.shared.draft("dm:" + agent.id).text)”")
        // The side panel: open, Files, a file, find.
        let panel = SidePanel.of(agent, home: store.home)
        // The chat must not move while the panel opens: sample how far its end is from the bottom, every frame.
        func scrolls(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrolls) }
        let chatScroll = scrolls(host).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
        func fromEnd() -> CGFloat { guard let v = chatScroll, let d = v.documentView else { return -1 }; return d.frame.height + v.contentInsets.bottom - v.contentView.bounds.maxY }
        var samples: [CGFloat] = [fromEnd()]
        panel.toggle()
        for _ in 0..<40 { spin(seconds: 1.0 / 60); samples.append(fromEnd()) }
        print(String(format: "chat while the panel opened: from end %.1f → max %.1f, final %.1f (0 = held at the end)", samples[0], samples.max() ?? -1, samples.last ?? -1))
        spin(seconds: 0.6)
        print("panel open: \(panel.open) · tabs \(panel.tabs.map(\.title)) · folder \(panel.folder)")
        snap("8-panel-files")
        let file = ["README.md", "package.json", "Package.swift"].map { (panel.folder as NSString).appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0) }
            ?? (try? FileManager.default.contentsOfDirectory(atPath: panel.folder))?.map { (panel.folder as NSString).appendingPathComponent($0) }.first { !FileManager.default.isDirectory($0) }
        if let file { panel.openFile(file); spin(seconds: 1.5); print("opened \(file) · tabs \(panel.tabs.map(\.title))"); snap("9-panel-file") }
        let code = NSHomeDirectory() + "/Desktop/Agent Lab/native/Sources/SidePanel.swift"
        var t = CACurrentMediaTime()
        panel.openFile(code)
        spin(until: { panel.doc(code).styled != nil }, 5)
        print(String(format: "opened SidePanel.swift (%d lines), read and coloured in %.0f ms", panel.doc(code).text?.split(separator: "\n").count ?? 0, (CACurrentMediaTime() - t) * 1000))
        spin(seconds: 0.5); print("tabs \(panel.tabs.map(\.title)) · front \(panel.selected ?? "-")"); snap("10-panel-code")
        for id in ["files", "file:" + code, "files", "file:" + code] {
            t = CACurrentMediaTime()
            panel.select(id)
            RunLoop.main.run(until: Date())
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            print(String(format: "switch to %@: %.1f ms", id == "files" ? "Files" : "the file", (CACurrentMediaTime() - t) * 1000))
        }
        panel.select("files"); spin(seconds: 0.2); snap("11-panel-back-to-files")
        panel.open = false
        exit(0)
    }
    @MainActor static func spin(seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    @MainActor static func spin(until done: () -> Bool, _ timeout: Double) {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
}

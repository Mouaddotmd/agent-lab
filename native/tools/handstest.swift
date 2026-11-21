// Drives an agent's hands (AgentHands.swift) the way engine/hands.js does, in a real window with the real side panel,
// against a local test page, and checks each step did what it says: open, read, type, click (a real, trusted click),
// select, keys, scroll, hover, wait, picture, script, console, links and back, close; the Terminal's shell (type, keys,
// read); and showing a file.
//   build/handstest [folder for pictures]
import SwiftUI
import AppKit

@main struct HandsTest {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/handstest"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        let store = Store(); store.connect()
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        let end = Date().addingTimeInterval(15)
        while store.agents.isEmpty && Date() < end { spin(0.05) }
        guard let agent = store.agents.first else { print("no agents"); exit(1) }
        // A clean start: no tabs kept from an earlier run of this test.
        UserDefaults.standard.removeObject(forKey: "browser.tabs." + agent.id)
        store.openChat(agent.id)
        let window = NSWindow(contentRect: CGRect(x: -8000, y: 0, width: 1392, height: 852), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RootView(drawLights: true).environmentObject(store))
        host.sizingOptions = []
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        spin(2.5)

        // The test pages.
        let dir = URL(fileURLWithPath: out).appendingPathComponent("site")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let page = """
        <!doctype html><html><head><title>Hands test</title></head><body style="height:3000px">
        <h1>Hands test</h1>
        <form id="f" onsubmit="event.preventDefault(); document.getElementById('sub').textContent = 'submitted ' + document.getElementById('q').value">
          <label for="q">Name</label> <input id="q" placeholder="Your name">
        </form>
        <button id="b" onclick="document.getElementById('out').textContent = 'clicked ' + document.getElementById('q').value + ' trusted=' + event.isTrusted">Say hello</button>
        <select id="s" onchange="document.getElementById('sel').textContent = 'chose ' + this.value"><option value="a">Apple</option><option value="b">Banana</option></select>
        <div id="h" onmouseenter="this.textContent = 'hovered'">Hover me</div>
        <p id="out"></p><p id="sub"></p><p id="sel"></p>
        <a href="two.html">Next page</a>
        <button onclick="setTimeout(() => { const p = document.createElement('p'); p.textContent = 'Late arrival'; document.body.appendChild(p); }, 800)">Later</button>
        <div style="position:absolute; top:2600px">Bottom marker</div>
        <script>console.log('page ready'); console.error('a test error');</script>
        </body></html>
        """
        try? page.write(to: dir.appendingPathComponent("one.html"), atomically: true, encoding: .utf8)
        try? "<!doctype html><title>Page two</title><p>Second page</p>".write(to: dir.appendingPathComponent("two.html"), atomically: true, encoding: .utf8)

        var fails = 0
        @MainActor func step(_ name: String, _ action: String, _ args: [String: Any] = [:], expect: [String] = [], refuse: Bool = false) -> String {
            var result = ""; var problem: String?
            var done = false
            Task { @MainActor in
                do { let v = try await AgentHands.perform(store, agent.id, action, args)
                     if let d = v as? [String: Any] { result = "image \(((d["image"] as? String) ?? "").count) chars; \(d["text"] as? String ?? "")" } else { result = "\(v)" } }
                catch { problem = error.localizedDescription }
                done = true
            }
            let until = Date().addingTimeInterval(60)
            while !done && Date() < until { spin(0.05) }
            let text = problem ?? result
            let ok = refuse ? problem != nil : (problem == nil && expect.allSatisfy { text.localizedCaseInsensitiveContains($0) })
            if !ok { fails += 1 }
            print("\(ok ? "PASS" : "FAIL") \(name): \(text.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(220))")
            return text
        }
        func shot(_ name: String) {
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!; host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }

        _ = step("no page yet", "read", refuse: true)
        _ = step("open", "open", ["url": dir.appendingPathComponent("one.html").path], expect: ["Hands test"])
        let read = step("read", "read", expect: ["Elements:", "input text", "button “Say hello”", "Next page"])
        func ref(_ words: String) -> Int? {
            for line in read.split(separator: "\n") where line.contains(words) {
                if let m = line.firstMatch(of: #/\[(\d+)\]/#) { return Int(m.1) }
            }
            return nil
        }
        _ = step("type by number", "type", ["ref": ref("Name") ?? -1, "value": "Mouad"], expect: ["Mouad"])
        _ = step("click (real)", "click", ["text": "Say hello"])
        _ = step("click landed, trusted", "eval", ["script": "document.getElementById('out').textContent"], expect: ["clicked Mouad", "trusted=true"])
        _ = step("type replaces", "type", ["selector": "#q", "value": "Ada", "submit": true])
        _ = step("Enter submits form", "eval", ["script": "document.getElementById('sub').textContent"], expect: ["submitted Ada"])
        _ = step("select", "select", ["selector": "#s", "value": "Banana"], expect: ["Banana"])
        _ = step("select landed", "eval", ["script": "return document.getElementById('sel').textContent"], expect: ["chose b"])
        _ = step("hover", "hover", ["text": "Hover me"])
        _ = step("hover landed", "eval", ["script": "document.getElementById('h').textContent"], expect: ["hovered"])
        _ = step("find", "find", ["query": "later"], expect: ["Later"])
        _ = step("click, then wait", "click", ["text": "Later"])
        _ = step("wait for text", "wait", ["text": "Late arrival", "seconds": 5], expect: ["is on the page"])
        _ = step("wait times out", "wait", ["text": "Never here", "seconds": 1], refuse: true)
        _ = step("scroll down", "scroll", ["direction": "down"], expect: ["Scrolled to"])
        _ = step("scroll bottom", "scroll", ["direction": "bottom"], expect: ["Scrolled to"])
        _ = step("press key", "press", ["key": "Home"])
        _ = step("picture", "screenshot", expect: ["image", "Hands test"])
        _ = step("console", "console", expect: ["page ready", "a test error"])
        _ = step("bad ref", "click", ["ref": 9999], refuse: true)
        _ = step("follow link", "click", ["text": "Next page"], expect: ["Page two"])
        _ = step("back", "navigate", ["action": "back"], expect: ["Hands test"])
        _ = step("tabs", "tabs", expect: ["(in front)", "Hands test"])
        _ = step("new tab", "open", ["url": dir.appendingPathComponent("two.html").path], expect: ["Page two"])
        _ = step("two tabs", "tabs", expect: ["Hands test", "Page two"])
        shot("browser")
        _ = step("close", "close", expect: ["Closed"])
        _ = step("terminal type", "terminalType", ["text": "echo hands-$((40+2))", "wait": 1.5], expect: ["hands-42"])
        _ = step("terminal key", "terminalKey", ["key": "ctrl-c"])
        _ = step("terminal read", "terminalRead", expect: ["hands-42"])
        shot("terminal")
        _ = step("show file", "show", ["file": dir.appendingPathComponent("two.html").path], expect: ["Showing"])
        _ = step("show missing file", "show", ["file": "/nope/nothing.txt"], refuse: true)
        _ = step("show changes", "show", ["pane": "changes"], expect: ["Changes"])
        _ = step("panes", "panes", expect: ["Browser", "Terminal", "Files open"])
        shot("panes")
        // The agent's browser is kept: closing the pane hides it, a restart brings back the same tabs.
        do {
            let p = SidePanel.of(agent, home: store.home)
            func ids(_ q: SidePanel) -> [String] { q.tabs.filter { $0.pane == .browser }.map(\.id) }
            func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
            let before = ids(p), frontBefore = p.front[.browser]
            p.closePane(.browser); spin(0.3)
            check(!p.isShowing(.browser) && ids(p) == before, "browser: × hides it and keeps its \(before.count) tabs")
            p.openPane(.browser); spin(0.3)
            check(p.isShowing(.browser) && ids(p) == before && p.front[.browser] == frontBefore, "browser: the globe brings back the same tabs, same one in front")
            p.saveBrowser()
            let again = SidePanel(agentId: agent.id, folder: p.folder)
            let urls = again.tabs.compactMap { t -> String? in if case .web(let id) = t.kind { return again.restored[id]?.lastPathComponent } else { return nil } }
            check(ids(again) == before && again.front[.browser] == frontBefore, "browser: after a restart the same tabs come back (\(ids(again).count))")
            check(urls.contains("one.html"), "browser: restored tabs keep their pages (\(urls.joined(separator: ", ")))")
        }
        // The Terminal: tabs like the Browser's, kept when the pane hides and after a restart (output and folder).
        do {
            let p = SidePanel.of(agent, home: store.home)
            func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
            func terms(_ q: SidePanel) -> [String] { q.tabs.filter { $0.pane == .terminal }.map(\.id) }
            p.openPane(.terminal); spin(1.5)
            p.newTerminal(); spin(1.5)
            let ids = terms(p)
            check(ids.count == 2, "terminal: + opens a second shell tab (\(ids.joined(separator: ", ")))")
            let second = p.tabs.first { if case .terminal(let k) = $0.kind { return k != "main" } else { return false } }
            if case .terminal(let k)? = second?.kind {
                let t = TerminalSession.of(p, key: k)
                for _ in 0..<40 where !t.live { spin(0.1) }
                t.agentType("cd /tmp && echo tab-two-\u{24}((6*7))\r"); spin(1.5)
                p.closePane(.terminal); spin(0.3)
                check(terms(p) == ids && !p.isShowing(.terminal), "terminal: × hides it and keeps both tabs, shells running")
                p.openPane(.terminal); spin(0.3)
                check(p.isShowing(.terminal) && terms(p) == ids, "terminal: its icon brings them back")
                t.save(); p.saveBrowser()
                let again = SidePanel(agentId: agent.id, folder: p.folder)
                check(terms(again) == ids, "terminal: after a restart the same tabs come back")
                let dir = NSHomeDirectory() + "/Library/Caches/Agent Lab/terminal/\(agent.id)-\(k)"
                let out = (try? String(contentsOfFile: dir + ".out", encoding: .utf8)) ?? ""
                let folder = (try? String(contentsOfFile: dir + ".dir", encoding: .utf8)) ?? ""
                check(out.contains("tab-two-42"), "terminal: its output is kept for the restart")
                check(folder.hasSuffix("/tmp") || folder.hasSuffix("/private/tmp"), "terminal: its folder is kept (\(folder))")
            } else { check(false, "terminal: second tab missing") }
        }
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}

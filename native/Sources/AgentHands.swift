// The agent's hands on its side panes (engine/hands.js asks, this does it): it opens, reads, clicks and types in the
// Browser pane's real pages, types into the Terminal's shell and reads its screen, and puts a file, Changes or the
// Terminal in front of you. Everything happens where you can watch it: the pane comes forward as the agent works.
// Clicks, hovers and keys are real events on the page when it's on screen (as yours would be), script events when not.
import SwiftUI
import AppKit
import WebKit

@MainActor enum AgentHands {
    private static var listening: NSObjectProtocol?

    static func start(_ store: Store) {
        guard listening == nil else { return }
        listening = NotificationCenter.default.addObserver(forName: .engineEvent, object: nil, queue: .main) { [weak store] n in
            guard n.userInfo?["type"] as? String == "lab-call", let store,
                  let id = n.userInfo?["id"] as? String, let agentId = n.userInfo?["agentId"] as? String,
                  let action = n.userInfo?["action"] as? String else { return }
            let args = n.userInfo?["args"] as? [String: Any] ?? [:]
            MainActor.assumeIsolated {
                Task { @MainActor in
                    var ok = true
                    var value: Any
                    do { value = try await perform(store, agentId, action, args) } catch { ok = false; value = error.localizedDescription }
                    _ = try? await store.engine.call("lab:reply", [id, ok, value])
                }
            }
        }
    }

    struct Problem: LocalizedError { let errorDescription: String?; init(_ s: String) { errorDescription = s } }

    /// One step of agent `agentId` (also what tools/handstest.swift drives).
    static func perform(_ store: Store, _ agentId: String, _ action: String, _ a: [String: Any]) async throws -> Any {
        // "a1@c_<ws>_<channel>": the agent answering in a channel works on that channel's panes, not its DM's.
        let parts = agentId.split(separator: "@", maxSplits: 1).map(String.init)
        // The channel's assistant is an agent too (store.assistants): its browser is the channel's, like anyone's.
        guard let agent = store.anyAgent(parts[0]) else { throw Problem("This chat has no side panes.") }
        let panel: SidePanel
        if parts.count == 2, let (w, ch) = store.channelOf(conv: parts[1]) {
            panel = store.channelPanel(w, ch.id)
        } else {
            panel = SidePanel.of(agent, home: store.home)
        }
        switch action {
        case "tabs": return tabsList(panel)
        case "panes": return panesList(panel)
        case "open": return try await open(panel, a)
        case "show": return try show(panel, a)
        case "terminalType", "terminalKey", "terminalRead": return try await terminal(panel, action, a)
        case let m where m.hasPrefix("mac"): return try await MacHands.perform(m, a)
        default:
            let page = try page(panel, a["tab"] as? String)
            return try await Hand(page: page, panel: panel).act(action, a)
        }
    }

    // MARK: Tabs

    private static func webTabs(_ panel: SidePanel) -> [(tab: PanelTab, id: String)] {
        panel.tabs.compactMap { t in if case .web(let id) = t.kind { (t, id) } else { nil } }
    }
    private static func tabsList(_ panel: SidePanel) -> String {
        let list = webTabs(panel)
        if list.isEmpty { return "No pages open. Use browser_open." }
        return list.map { t, id in
            let p = BrowserPage.of(panel, id)
            let front = panel.front[.browser] == t.id ? " (in front)" : ""
            return "\(id)\(front): \(p.title.isEmpty ? "Untitled" : p.title) — \(p.url?.absoluteString ?? "blank")"
        }.joined(separator: "\n")
    }
    private static func panesList(_ panel: SidePanel) -> String {
        var out = ["Showing: \(panel.open ? (panel.panes.map(\.title).joined(separator: ", ").nonEmpty ?? "nothing") : "hidden")"]
        let files = panel.tabs.compactMap { t -> String? in if case .file(let p) = t.kind { panel.relative(p) } else { nil } }
        if !files.isEmpty { out.append("Files open: " + files.joined(separator: ", ")) }
        out.append("Browser:\n" + tabsList(panel))
        return out.joined(separator: "\n")
    }
    /// The page of tab `id` (with or without "web:"), or the one in front, or the last opened.
    private static func page(_ panel: SidePanel, _ id: String?) throws -> BrowserPage {
        let list = webTabs(panel)
        let pick: (tab: PanelTab, id: String)?
        if let id, !id.isEmpty {
            let short = id.hasPrefix("web:") ? String(id.dropFirst(4)) : id
            guard let t = list.first(where: { $0.id == short }) else { throw Problem("No tab \(id). Open tabs:\n\(tabsList(panel))") }
            pick = t
        } else {
            pick = list.first(where: { $0.tab.id == panel.front[.browser] }) ?? list.last
        }
        guard let pick else { throw Problem("No page is open. Use browser_open first.") }
        if !panel.isFront(pick.tab.id) { panel.show(pick.tab) }
        return BrowserPage.of(panel, pick.id)
    }

    private static func open(_ panel: SidePanel, _ a: [String: Any]) async throws -> String {
        let typed = (a["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = BrowserPage.address(typed) else { throw Problem("Give an address or words to search for.") }
        let newTab = a["newTab"] as? Bool ?? true
        let page: BrowserPage
        if !newTab, let p = try? self.page(panel, nil) {
            page = p; p.load(url)
        } else {
            // An empty new tab in front becomes the page, as typing in it would.
            let start = panel.tabs.first { t in if case .start = t.kind { panel.front[.browser] == t.id } else { false } }
            panel.openWeb(url, replacing: start?.id)
            guard let tab = webTabs(panel).first(where: { $0.tab.id == panel.front[.browser] }) else { throw Problem("The tab didn't open.") }
            page = BrowserPage.of(panel, tab.id)
        }
        let hand = Hand(page: page, panel: panel)
        await hand.settle(load: true)
        if let p = page.problem { throw Problem("\(p.url.absoluteString) didn't open: \(p.reason)") }
        return "Opened in tab \(page.id): \(page.title.isEmpty ? "Untitled" : page.title) — \(page.web.url?.absoluteString ?? url.absoluteString)"
    }

    private static func show(_ panel: SidePanel, _ a: [String: Any]) throws -> String {
        if let f = a["file"] as? String, !f.isEmpty {
            let full = f.hasPrefix("/") ? f : f.hasPrefix("~") ? (f as NSString).expandingTildeInPath : (panel.folder as NSString).appendingPathComponent(f)
            guard FileManager.default.fileExists(atPath: full) else { throw Problem("There's no file at \(full).") }
            panel.openFile(full)
            return "Showing \(panel.relative(full)) in Files."
        }
        guard let name = a["pane"] as? String, let p = SidePanel.Pane(rawValue: name) else { throw Problem("Say which pane, or a file.") }
        if p == .changes { panel.showChatChanges() } else { panel.openPane(p) }
        return "Showing \(p.title)."
    }

    // MARK: Terminal

    private static func terminal(_ panel: SidePanel, _ action: String, _ a: [String: Any]) async throws -> String {
        panel.show(PanelTab(kind: .terminal("main")))
        let term = TerminalSession.of(panel)
        // A shell just opened needs a moment to start.
        for _ in 0..<60 where !term.live { try? await Task.sleep(for: .milliseconds(100)) }
        guard term.live else { throw Problem(term.problem ?? "The terminal's shell didn't start.") }
        switch action {
        case "terminalType":
            let text = a["text"] as? String ?? ""
            term.agentType(text + ((a["enter"] as? Bool ?? true) ? "\r" : ""))
            try? await Task.sleep(for: .seconds(min(max(num(a["wait"]) ?? 1.5, 0.2), 30)))
            return await term.screenText(40).nonEmpty ?? "(The screen is empty.)"
        case "terminalKey":
            let k = (a["key"] as? String ?? "").lowercased()
            let keys: [String: String] = ["ctrl-c": "\u{3}", "ctrl-d": "\u{4}", "ctrl-z": "\u{1a}", "ctrl-l": "\u{c}", "ctrl-a": "\u{1}", "ctrl-e": "\u{5}", "ctrl-u": "\u{15}",
                                          "enter": "\r", "return": "\r", "tab": "\t", "escape": "\u{1b}", "esc": "\u{1b}", "backspace": "\u{7f}", "space": " ",
                                          "up": "\u{1b}[A", "down": "\u{1b}[B", "right": "\u{1b}[C", "left": "\u{1b}[D"]
            term.agentType(keys[k] ?? (a["key"] as? String ?? ""))
            try? await Task.sleep(for: .milliseconds(600))
            return await term.screenText(40).nonEmpty ?? "(The screen is empty.)"
        default:
            return await term.screenText(Int(num(a["lines"]) ?? 60)).nonEmpty ?? "(The screen is empty.)"
        }
    }
}

/// One step on one page.
@MainActor private struct Hand {
    final class Seen { var size: CGSize = .zero }
    private let seen = Seen()
    private var size: CGSize { get { seen.size } nonmutating set { seen.size = newValue } }
    let page: BrowserPage
    let panel: SidePanel
    var web: BrowserWebView { page.web }
    typealias Problem = AgentHands.Problem

    func act(_ action: String, _ a: [String: Any]) async throws -> Any {
        prepare()
        switch action {
        case "navigate":
            switch a["action"] as? String {
            case "back": guard web.canGoBack else { throw Problem("There's no page to go back to.") }; web.goBack()
            case "forward": guard web.canGoForward else { throw Problem("There's no page to go forward to.") }; web.goForward()
            default: page.reload()
            }
            await settle(load: true)
            return "Now on: \(page.title) — \(web.url?.absoluteString ?? "")"
        case "read":
            let v = try await run(Scripts.read, ["full": a["full"] as? Bool ?? false])
            guard let d = v as? [String: Any] else { throw Problem("The page couldn't be read.") }
            let els = (d["elements"] as? String ?? "").nonEmpty ?? "(nothing to act on in view)"
            return "\(d["title"] as? String ?? "") — \(d["url"] as? String ?? "")\nScrolled \(d["scroll"] as? String ?? "0")\n\nElements:\n\(els)\n\nText:\n\(d["text"] as? String ?? "")"
        case "find":
            let v = try await run(Scripts.find, ["query": a["query"] as? String ?? ""])
            return (v as? String)?.nonEmpty ?? "Nothing on the page matches."
        case "click":
            let p = try await locate(a)
            let real = await mouse(at: p.at, clicks: (a["double"] as? Bool ?? false) ? 2 : 1)
            if !real { _ = try await run(Scripts.click, target(a)) }
            await settle(load: false)
            return "Clicked \(p.label).\(changedNote())"
        case "hover":
            let p = try await locate(a)
            // The real pointer moves there (for :hover styles), and the page hears it as script events too: WebKit only
            // sends mouseenter for a pointer it tracks itself.
            _ = await mouse(at: p.at, clicks: 0)
            _ = try await run(Scripts.hover, target(a))
            try? await Task.sleep(for: .milliseconds(300))
            return "Pointing at \(p.label)."
        case "type":
            let p = try await locate(a)
            _ = await mouse(at: p.at, clicks: 1)
            var args = target(a); args["value"] = a["value"] as? String ?? ""; args["append"] = a["append"] as? Bool ?? false
            let v = try await run(Scripts.type, args) as? [String: Any]
            if a["submit"] as? Bool == true { try await press("Enter"); await settle(load: false) }
            return "Typed into \(p.label)\((v?["value"] as? String).map { ". It now says “\($0)”" } ?? "").\(changedNote())"
        case "select":
            var args = target(a); args["value"] = a["value"] as? String ?? ""
            let v = try await run(Scripts.select, args) as? String
            await settle(load: false)
            return "Chose “\(v ?? "")”."
        case "press":
            try await press(a["key"] as? String ?? "")
            await settle(load: false)
            return "Pressed \(a["key"] as? String ?? "").\(changedNote())"
        case "scroll":
            var args: [String: Any] = ["direction": a["direction"] as? String ?? "down"]
            if let r = a["ref"] { args["ref"] = r }
            return try await run(Scripts.scroll, args) as? String ?? "Scrolled."
        case "wait":
            let secs = min(max(num(a["seconds"]) ?? 10, 0.2), 30)
            if let text = a["text"] as? String, !text.isEmpty {
                let end = Date().addingTimeInterval(secs)
                while Date() < end {
                    if (try? await run("return (document.body ? document.body.innerText : '').toLowerCase().includes(args.q)", ["q": text.lowercased()])) as? Bool == true { return "“\(text)” is on the page." }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                throw Problem("“\(text)” didn't show within \(Int(secs)) seconds.")
            }
            try? await Task.sleep(for: .seconds(secs))
            return "Waited \(secs)s."
        case "screenshot":
            return try await screenshot()
        case "eval":
            let s = (a["script"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = s.range(of: #"(^|[;\s{])return[\s(;]"#, options: .regularExpression) != nil ? s : "return (\n\(s)\n)"
            let v = try await run("const __v = await (async () => { \(body) })(); try { return JSON.stringify(__v === undefined ? null : __v, null, 1)?.slice(0, 20000) ?? 'null'; } catch (e) { return String(__v); }", [:], world: .page)
            return v as? String ?? "null"
        case "console":
            let v = try await run("return (window.__alLogs || []).slice(-80).join('\\n')", [:], world: .page)
            return (v as? String)?.nonEmpty ?? "The console is empty."
        case "close":
            panel.forceClose("web:" + page.id)
            return "Closed."
        default:
            throw Problem("Unknown step \(action).")
        }
    }

    /// The page is drawn at a real size even when its pane isn't showing (so layout, reading and pictures work).
    private func prepare() {
        if web.superview == nil && web.bounds.width < 10 { web.frame = NSRect(x: 0, y: 0, width: 1100, height: 800) }
    }

    /// After a step: waits for what it set off (a page loading) to finish.
    func settle(load: Bool) async {
        try? await Task.sleep(for: .milliseconds(load ? 300 : 350))
        let end = Date().addingTimeInterval(20)
        while Date() < end && web.isLoading { try? await Task.sleep(for: .milliseconds(150)) }
        if load || web.isLoading { try? await Task.sleep(for: .milliseconds(200)) }
    }
    private func changedNote() -> String {
        if let p = page.problem { return " The page failed to load: \(p.reason)" }
        return " Now on: \(page.title.isEmpty ? (web.url?.absoluteString ?? "") : page.title) — \(web.url?.absoluteString ?? "")"
    }

    private func target(_ a: [String: Any]) -> [String: Any] {
        var t: [String: Any] = [:]
        for k in ["ref", "selector", "text"] { if let v = a[k] { t[k] = v } }
        return t
    }
    /// Where the element is (its middle, in the page's points) and what it is, scrolled into view.
    private func locate(_ a: [String: Any]) async throws -> (at: CGPoint, label: String) {
        // (its size, for the agent's cursor to outline)
        guard let v = try await run(Scripts.locate, target(a)) as? [String: Any] else { throw Problem("That element couldn't be found.") }
        let x = (v["x"] as? Double) ?? 0, y = (v["y"] as? Double) ?? 0
        size = CGSize(width: (v["w"] as? Double) ?? 0, height: (v["h"] as? Double) ?? 0)
        return (CGPoint(x: x, y: y), v["label"] as? String ?? "it")
    }

    /// A real pointer on the page (the page is on screen in its window): moves there, and clicks `clicks` times.
    private func mouse(at p: CGPoint, clicks: Int) async -> Bool {
        guard let win = web.window, !web.isHiddenOrHasHiddenAncestor, web.bounds.width > 10 else { return false }
        let z = web.pageZoom * web.magnification
        let local = CGPoint(x: p.x * z, y: web.isFlipped ? p.y * z : web.bounds.height - p.y * z)
        guard web.bounds.contains(local) else { return false }
        let at = web.convert(local, to: nil)
        // The agent's cursor goes there first, so you see what it's about to do (your own pointer stays put).
        let sz = CGSize(width: size.width * z, height: size.height * z)
        let box = web.convert(NSRect(x: local.x - sz.width / 2, y: local.y - sz.height / 2, width: sz.width, height: sz.height), to: nil)
        await AgentCursor.shared.glide(to: win.convertPoint(toScreen: at), frame: sz.width > 0 ? win.convertToScreen(box) : nil)
        if clicks > 0 { await AgentCursor.shared.press() }
        AgentCursor.shared.rest()
        let t = ProcessInfo.processInfo.systemUptime
        func ev(_ type: NSEvent.EventType, _ count: Int) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: t, windowNumber: win.windowNumber, context: nil,
                               eventNumber: 0, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0)
        }
        if let e = ev(.mouseMoved, 0) { web.mouseMoved(with: e) }
        guard clicks > 0 else { return true }
        for n in 1...clicks {
            if let e = ev(.leftMouseDown, n) { web.mouseDown(with: e) }
            if let e = ev(.leftMouseUp, n) { web.mouseUp(with: e) }
        }
        return true
    }

    /// A key on the page: a real key press when the page is on screen, a script's otherwise.
    private func press(_ combo: String) async throws {
        let parts = combo.split(separator: "+").map { String($0) }
        guard let key = parts.last, !key.isEmpty else { throw Problem("Say which key.") }
        var flags: NSEvent.ModifierFlags = []
        for m in parts.dropLast() {
            switch m.lowercased() {
            case "meta", "cmd", "command": flags.insert(.command)
            case "ctrl", "control": flags.insert(.control)
            case "alt", "option": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        let named: [String: (UInt16, String)] = [
            "enter": (36, "\r"), "return": (36, "\r"), "tab": (48, "\t"), "escape": (53, "\u{1b}"), "esc": (53, "\u{1b}"),
            "backspace": (51, "\u{7f}"), "delete": (117, "\u{f728}"), "space": (49, " "),
            "arrowleft": (123, "\u{f702}"), "arrowright": (124, "\u{f703}"), "arrowdown": (125, "\u{f701}"), "arrowup": (126, "\u{f700}"),
            "pageup": (116, "\u{f72c}"), "pagedown": (121, "\u{f72d}"), "home": (115, "\u{f729}"), "end": (119, "\u{f72b}"),
        ]
        let lower = key.lowercased()
        if let win = web.window, !web.isHiddenOrHasHiddenAncestor, let k = named[lower] ?? (key.count == 1 ? (0, key) : nil) {
            if win.firstResponder !== web { win.makeFirstResponder(web) }
            let t = ProcessInfo.processInfo.systemUptime
            let chars = flags.contains(.shift) ? k.1.uppercased() : k.1
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: t, windowNumber: win.windowNumber, context: nil,
                                               characters: chars, charactersIgnoringModifiers: k.1, isARepeat: false, keyCode: k.0) else { continue }
                if type == .keyDown { web.keyDown(with: e) } else { web.keyUp(with: e) }
            }
            return
        }
        let names: [String: String] = ["enter": "Enter", "return": "Enter", "esc": "Escape", "escape": "Escape", "tab": "Tab", "backspace": "Backspace", "space": " "]
        _ = try await run(Scripts.key, ["key": names[lower] ?? key, "meta": flags.contains(.command), "ctrl": flags.contains(.control), "alt": flags.contains(.option), "shift": flags.contains(.shift)])
    }

    private func screenshot() async throws -> [String: Any] {
        let c = WKSnapshotConfiguration()
        if web.bounds.width > 1280 { c.snapshotWidth = 1280 }
        let image = try await web.takeSnapshot(configuration: c)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { throw Problem("The picture couldn't be taken.") }
        return ["image": jpeg.base64EncodedString(), "text": "\(page.title) — \(web.url?.absoluteString ?? "")"]
    }

    /// Runs a script's body (with `args`) on the page; its thrown errors come back as the step's problem.
    private func run(_ body: String, _ args: [String: Any], world: WKContentWorld? = nil) async throws -> Any? {
        guard web.url != nil else { throw Problem("The tab has no page yet. Use browser_open.") }
        let wrapped = "try { \(Scripts.lib)\n\(body) } catch (e) { return { __error: String(e && e.message || e) }; }"
        let v: Any?
        do { v = try await web.callAsyncJavaScript(wrapped, arguments: ["args": args], in: nil, contentWorld: world ?? .defaultClient) }
        catch { throw Problem(((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription) }
        if let d = v as? [String: Any], let e = d["__error"] as? String { throw Problem(e) }
        return v
    }
}

/// The page-side scripts. They run in the app's own world (out of the page's way) and number elements with
/// data-al-ref, which both the agent's numbers and these scripts use.
private enum Scripts {
    static let lib = #"""
    const SEL = 'a[href],button,input:not([type=hidden]),textarea,select,summary,[role=button],[role=link],[role=checkbox],[role=radio],[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=tab],[role=option],[role=switch],[role=combobox],[role=textbox],[role=searchbox],[role=slider],[role=treeitem],[contenteditable=""],[contenteditable=true],[onclick],[tabindex]:not([tabindex="-1"])';
    const vis = (el) => { const r = el.getBoundingClientRect(); if (r.width < 1 || r.height < 1) return false; const s = getComputedStyle(el); return s.visibility !== 'hidden' && s.display !== 'none' && parseFloat(s.opacity || '1') > 0.01; };
    const clean = (s) => String(s || '').replace(/\s+/g, ' ').trim();
    const words = (el) => {
      const by = el.getAttribute('aria-labelledby');
      const named = el.getAttribute('aria-label') || (by && by.split(/\s+/).map((i) => document.getElementById(i)?.innerText || '').join(' ')) || (el.labels && el.labels[0] && el.labels[0].innerText);
      const w = named || (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' ? '' : el.innerText) || el.getAttribute('placeholder') || el.title || el.getAttribute('alt') || el.querySelector?.('img[alt]')?.alt || (el.tagName === 'INPUT' && /submit|button/.test(el.type) ? el.value : '') || el.getAttribute('name') || '';
      return clean(w).slice(0, 100);
    };
    const kind = (el) => { const t = el.tagName.toLowerCase(), role = el.getAttribute('role'); if (t === 'input') return 'input ' + (el.type || 'text'); if (t === 'a') return 'link'; if (t === 'select' || t === 'textarea' || t === 'button') return t; if (el.isContentEditable) return 'editable text'; return role || t; };
    const label = (el) => kind(el) + (words(el) ? ' “' + words(el) + '”' : '');
    const find = (a) => {
      if (a.ref != null) { const el = document.querySelector('[data-al-ref="' + a.ref + '"]'); if (!el) throw new Error('There is no [' + a.ref + '] on the page now. Read the page again.'); return el; }
      if (a.selector) { const el = document.querySelector(a.selector); if (!el) throw new Error('Nothing on the page matches ' + a.selector + '.'); return el; }
      if (a.text) {
        const q = clean(a.text).toLowerCase(), all = [...document.querySelectorAll(SEL)].filter(vis);
        const hit = all.find((e) => words(e).toLowerCase() === q) || all.find((e) => words(e).toLowerCase().includes(q));
        if (hit) return hit;
        const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n;
        while ((n = w.nextNode())) if (n.textContent.toLowerCase().includes(q) && n.parentElement && vis(n.parentElement)) return n.parentElement;
        throw new Error('Nothing on the page says “' + a.text + '”.');
      }
      throw new Error('Say which element: its number from browser_read, a selector or its words.');
    };
    """#

    static let read = #"""
    const full = !!args.full;
    document.querySelectorAll('[data-al-ref]').forEach((e) => e.removeAttribute('data-al-ref'));
    const inView = (el) => { const r = el.getBoundingClientRect(); return r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth; };
    let n = 0; const lines = [];
    for (const el of document.querySelectorAll(SEL)) {
      if (!vis(el) || (!full && !inView(el)) || el.closest('[aria-hidden=true]')) continue;
      n += 1; el.setAttribute('data-al-ref', String(n));
      let d = '[' + n + '] ' + label(el);
      if (el.tagName === 'A') { const h = el.getAttribute('href'); if (h && !h.startsWith('javascript')) d += ' → ' + h.slice(0, 80); }
      if (el.type === 'password') d += ' (password: the user types this)';
      else if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && el.value && !/submit|button|checkbox|radio/.test(el.type)) d += ' = “' + String(el.value).slice(0, 80) + '”';
      if (el.checked || el.getAttribute('aria-checked') === 'true' || el.getAttribute('aria-selected') === 'true') d += ' (on)';
      if (el.disabled || el.getAttribute('aria-disabled') === 'true') d += ' (disabled)';
      if (el.getAttribute('aria-expanded')) d += el.getAttribute('aria-expanded') === 'true' ? ' (open)' : ' (closed)';
      if (el.tagName === 'SELECT') d += ' options: ' + [...el.options].slice(0, 20).map((o) => (o.selected ? '•' : '') + o.label).join(' | ');
      lines.push(d);
      if (n >= 400) break;
    }
    let text = (document.body ? document.body.innerText : '').replace(/[ \t ]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    const max = full ? 40000 : 12000;
    if (text.length > max) text = text.slice(0, max) + '\n… (more: read with full, or scroll)';
    const sc = document.scrollingElement || document.documentElement;
    return { title: document.title, url: location.href, text, elements: lines.join('\n'), scroll: Math.round(sc.scrollTop) + ' of ' + Math.max(0, Math.round(sc.scrollHeight - innerHeight)) + ' px' };
    """#

    static let find = #"""
    const q = clean(args.query).toLowerCase();
    let n = 0; document.querySelectorAll('[data-al-ref]').forEach((e) => { n = Math.max(n, +e.getAttribute('data-al-ref') || 0); });
    const out = [];
    for (const el of document.querySelectorAll(SEL)) {
      if (!vis(el)) continue;
      const hay = (words(el) + ' ' + (el.getAttribute('placeholder') || '') + ' ' + (el.value || '') + ' ' + (el.getAttribute('href') || '')).toLowerCase();
      if (!hay.includes(q)) continue;
      let r = el.getAttribute('data-al-ref');
      if (!r) { n += 1; r = String(n); el.setAttribute('data-al-ref', r); }
      out.push('[' + r + '] ' + label(el));
      if (out.length >= 40) break;
    }
    return out.join('\n');
    """#

    static let locate = #"""
    const el = find(args);
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height, label: label(el) };
    """#

    static let click = #"""
    const el = find(args);
    const r = el.getBoundingClientRect(), o = { bubbles: true, cancelable: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, button: 0 };
    el.dispatchEvent(new PointerEvent('pointerdown', o)); el.dispatchEvent(new MouseEvent('mousedown', o));
    if (el.focus) el.focus();
    el.dispatchEvent(new PointerEvent('pointerup', o)); el.dispatchEvent(new MouseEvent('mouseup', o));
    el.click();
    return true;
    """#

    static let hover = #"""
    const el = find(args);
    const r = el.getBoundingClientRect(), o = { bubbles: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
    for (const t of ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'pointermove', 'mousemove']) el.dispatchEvent(new (t.startsWith('pointer') ? PointerEvent : MouseEvent)(t, o));
    return true;
    """#

    static let type = #"""
    const el = find(args);
    const field = el.tagName === 'INPUT' || el.tagName === 'TEXTAREA';
    if (document.activeElement !== el) el.focus();
    if (!args.append) {
      if (field) { try { el.select(); } catch (e) {} }
      else if (el.isContentEditable) { const r = document.createRange(); r.selectNodeContents(el); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
    } else if (field) { try { const l = el.value.length; el.setSelectionRange(l, l); } catch (e) {} }
    let ok = args.value ? document.execCommand('insertText', false, args.value) : (args.append ? true : document.execCommand('delete'));
    const want = args.append ? null : args.value;
    if (field && (!ok || (want !== null && el.value !== want))) {
      const proto = el.tagName === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, want !== null ? want : el.value + args.value);
      el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: args.value }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    } else if (!field && !ok) {
      el.textContent = want !== null ? want : el.textContent + args.value;
      el.dispatchEvent(new InputEvent('input', { bubbles: true }));
    }
    return { value: el.type === 'password' ? '••••' : String(field ? el.value : el.innerText).slice(0, 200) };
    """#

    static let select = #"""
    const el = find(args);
    if (el.tagName !== 'SELECT') throw new Error(label(el) + ' is not a menu of options. Click it, then click the option.');
    const q = clean(args.value).toLowerCase(), opts = [...el.options];
    const o = opts.find((o) => o.value === args.value) || opts.find((o) => clean(o.label).toLowerCase() === q) || opts.find((o) => clean(o.label).toLowerCase().includes(q));
    if (!o) throw new Error('No option “' + args.value + '”. It has: ' + opts.map((o) => o.label).join(', '));
    el.value = o.value;
    el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true }));
    return o.label;
    """#

    static let scroll = #"""
    if (args.ref != null) { const el = find(args); el.scrollIntoView({ block: 'center', behavior: 'instant' }); return 'Scrolled to ' + label(el) + '.'; }
    const sc = document.scrollingElement || document.documentElement;
    // The page may scroll inside a box of its own: the biggest one that scrolls.
    let box = sc;
    if (sc.scrollHeight <= innerHeight + 2) {
      let best = 0;
      for (const el of document.querySelectorAll('body *')) {
        if (el.scrollHeight > el.clientHeight + 20 && /(auto|scroll)/.test(getComputedStyle(el).overflowY) && el.clientHeight * el.clientWidth > best) { best = el.clientHeight * el.clientWidth; box = el; }
      }
    }
    const h = box === sc ? innerHeight : box.clientHeight, before = box.scrollTop;
    const d = args.direction;
    if (d === 'top') box.scrollTop = 0; else if (d === 'bottom') box.scrollTop = box.scrollHeight;
    else box.scrollTop += (d === 'up' ? -1 : 1) * Math.round(h * 0.8);
    const max = Math.max(0, box.scrollHeight - h);
    return box.scrollTop === before ? 'It didn\'t move: already at the ' + (d === 'up' || d === 'top' ? 'top' : 'bottom') + '.' : 'Scrolled to ' + Math.round(box.scrollTop) + ' of ' + Math.round(max) + ' px.';
    """#

    static let key = #"""
    const el = document.activeElement || document.body;
    const o = { key: args.key, bubbles: true, cancelable: true, metaKey: args.meta, ctrlKey: args.ctrl, altKey: args.alt, shiftKey: args.shift };
    const go = el.dispatchEvent(new KeyboardEvent('keydown', o));
    el.dispatchEvent(new KeyboardEvent('keyup', o));
    if (go && args.key === 'Enter' && el.form && el.tagName === 'INPUT') { if (el.form.requestSubmit) el.form.requestSubmit(); else el.form.submit(); }
    return true;
    """#
}

/// A number from the engine (JSON) or a test, whatever its type.
private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? Double) ?? (v as? Int).map(Double.init) }

private extension String { var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }

// The Terminal tab: your login shell in the agent's folder, on a real pseudo-terminal (TermPTY), drawn by xterm.js in
// a web view. One shell per agent's panel; it keeps running while you look at other tabs or chats, and ends (a hang-up,
// as when a terminal window closes) when the tab closes. Commands the agent leaves running (engine/terminal.js) show
// beside the shell, each with its live output and Stop.
import SwiftUI
import AppKit
import WebKit
import Combine

// MARK: The tab

struct TerminalTab: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    var key = "main"
    var body: some View {
        TerminalBody(panel: panel, session: TerminalSession.of(panel, key: key), runs: TerminalRuns.shared)
            .task { await TerminalRuns.shared.load(panel.agentId, engine: s.engine) }
    }

    /// Opens the Terminal tab of `agentId`'s panel showing a command the agent left running (for the capsule above
    /// the message box, or a step in the chat). False when that agent has no panel yet.
    @MainActor @discardableResult static func showRun(agentId: String, runId: String) -> Bool {
        guard let panel = SidePanel.existing(agentId) else { return false }
        panel.show(PanelTab(kind: .terminal("main")))
        TerminalSession.of(panel, key: "main").select(runId)
        return true
    }
}

private struct TerminalBody: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    @ObservedObject var session: TerminalSession
    @ObservedObject var runs: TerminalRuns
    var body: some View {
        let list = runs.runs[panel.agentId] ?? []
        VStack(spacing: 0) {
            if !list.isEmpty { strip(list) }
            ZStack(alignment: .bottom) {
                TerminalHost(session: session, showing: panel.isFront(session.tabId))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let problem = session.problem {
                    VStack(spacing: 8) {
                        Line("Couldn't open the terminal", 14, .medium, C.i12)
                        Text(problem).font(F.font(12, .regular)).foregroundStyle(C.i10).multilineTextAlignment(.center)
                        SmallSecondaryButton(title: "Try again") { session.restart() }.padding(.top, 4)
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(C.v1)
                } else if session.screen == "shell", let code = session.exitCode {
                    bar("Process exited" + (code == 0 ? "" : " (\(code))"), button: "Restart") { session.restart() }
                } else if let run = list.first(where: { $0.id == session.screen }), run.state == "running" {
                    bar(run.command, button: "Stop") { Task { try? await s.engine.call("terminal:stop", [run.id]) } }
                }
            }
        }
    }

    /// A small bar at the bottom of the screen: what's there and the one thing to do about it.
    private func bar(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(text).font(F.font(13, .medium)).foregroundStyle(C.i10).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            SmallSecondaryButton(title: button, action: action)
        }
        .padding(.leading, 14).padding(.trailing, 8).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: R.card, style: .continuous).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: R.card, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
        .padding(10)
    }

    /// The shell and each command the agent left running; a click shows its screen.
    private func strip(_ list: [TerminalRuns.Run]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                chip(id: "shell", title: "Shell", running: session.exitCode == nil, run: nil)
                ForEach(list) { run in chip(id: run.id, title: run.command, running: run.state == "running", run: run) }
            }
            .padding(.horizontal, Box.pad)
        }
        .scrollIndicators(.never)
        .frame(height: Bar.height)
        .overlay(alignment: .bottom) { Rectangle().fill(C.divider).frame(height: 1) }
    }

    private func chip(id: String, title: String, running: Bool, run: TerminalRuns.Run?) -> some View {
        Hover { h in
            let on = session.screen == id
            return HStack(spacing: 6) {
                Circle().fill(running ? C.i12 : C.v6).frame(width: 6, height: 6)
                Text(title).font(id == "shell" ? F.font(13, .medium) : .system(size: 11.5, design: .monospaced))
                    .foregroundStyle(on ? C.i12 : C.i10).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180, alignment: .leading)
                // A finished command can be put away; a running one is stopped from its screen.
                if let run, run.state != "running" {
                    Button {
                        session.forget(run.id)
                        Task { try? await s.engine.call("terminal:forget", [run.id]) }
                    } label: {
                        Icon("x", 9).foregroundStyle(C.i10).frame(width: 16, height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).opacity(h || on ? 1 : 0).tip("Close")
                }
            }
            .padding(.leading, 10).padding(.trailing, run == nil || run?.state == "running" ? 10 : 4).frame(height: Bar.control)
            .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(on ? C.v4 : h ? C.v3 : .clear))
            .contentShape(Rectangle())
            .onTapGesture { session.select(id) }
            .help(run.map { "\($0.command) · \(Self.stateWords($0))" } ?? "Your shell")
        }
    }

    private static func stateWords(_ run: TerminalRuns.Run) -> String {
        switch run.state {
        case "running": "Running"
        case "stopped": "Stopped"
        default: run.code.map { $0 == 0 ? "Done" : "Failed (\($0))" } ?? "Done"
        }
    }
}

/// Puts the session's web view (made once, kept by the session) in the tab; it moves to the new place when the panel
/// is rebuilt (another chat and back), so the screen and its scrollback stay.
private struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    let showing: Bool
    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        session.attach(to: box)
        return box
    }
    func updateNSView(_ box: NSView, context: Context) {
        if session.web.superview !== box { session.attach(to: box) }
        session.setShowing(showing)
    }
}

// MARK: The session

/// One agent panel's terminal: the shell, its screen, and the screens of the commands the agent left running.
@MainActor final class TerminalSession: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published private(set) var exitCode: Int32?
    @Published private(set) var problem: String?
    /// The screen on show: "shell" or a run's id.
    @Published private(set) var screen = "shell"
    let web: TermWebView
    private let panel: SidePanel
    private(set) var pty: TermPTY?
    private var ready = false
    private var inFlight = false
    private var cols = 80, rows = 24
    private var showing = false
    private var watch: AnyCancellable?
    private var events: NSObjectProtocol?
    /// Runs already given a screen in the page.
    private var shown: Set<String> = []

    private static var sessions: [String: TerminalSession] = [:]
    /// The shell of Terminal tab `key` ("main" is the first) of an agent's panel.
    static func of(_ panel: SidePanel, key: String = "main") -> TerminalSession {
        let k = panel.agentId + "/" + key
        if let t = sessions[k] { return t }
        let t = TerminalSession(panel: panel, key: key)
        sessions[k] = t
        return t
    }
    let key: String
    /// Its tab's id in the panel.
    var tabId: String { PanelTab(kind: .terminal(key)).id }
    /// The tab's title: what the shell names itself, else the folder it's in.
    @Published private(set) var title = "Terminal"
    /// What the shell has written, kept (the last 256 KB) so the tab shows it again after the app restarts.
    private var history = Data()
    private static let keep = 256 << 10
    private var saving: NSObjectProtocol?
    private var restored = false

    /// Where this tab's output and folder are kept between launches.
    private var savedURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab/terminal")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(panel.agentId)-\(key)")
    }
    /// Writes the output so far and the shell's folder (on quit, and when the pane hides).
    func save() {
        try? history.write(to: savedURL.appendingPathExtension("out"))
        if let dir = currentFolder() { try? dir.write(to: savedURL.appendingPathExtension("dir"), atomically: true, encoding: .utf8) }
    }
    /// The folder the shell is in now.
    private func currentFolder() -> String? {
        guard let pid = pty?.pid else { return nil }
        var info = proc_vnodepathinfo()
        let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard n == Int32(MemoryLayout<proc_vnodepathinfo>.size) else { return nil }
        return withUnsafePointer(to: info.pvi_cdir.vip_path) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
    }

    private init(panel: SidePanel, key: String) {
        self.panel = panel; self.key = key
        let config = WKWebViewConfiguration()
        let content = WKUserContentController()
        for script in TermPage.scripts { content.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        config.userContentController = content
        web = TermWebView(frame: .zero, configuration: config)
        super.init()
        web.configuration.userContentController.add(WeakHandler(self), name: "term")
        web.session = self
        web.setValue(false, forKey: "drawsBackground")
        web.allowsMagnification = false
        web.allowsBackForwardNavigationGestures = false
        if TermPage.scripts.isEmpty { problem = "The terminal's screen files are missing from the app. Rebuild it." }
        else { web.loadHTMLString(TermPage.html, baseURL: nil) }
        // The shell lives as long as the tab: closing it hangs the shell up.
        let mine = PanelTab(kind: .terminal(key)).id
        watch = panel.$tabs.sink { [weak self] tabs in
            if !tabs.contains(where: { $0.id == mine }) { Task { @MainActor in self?.end() } }
        }
        saving = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        title = ((panel.folder as NSString).lastPathComponent).nonEmptyTitle ?? "Terminal"
        
        events = NotificationCenter.default.addObserver(forName: .terminalRunsChanged, object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo
            MainActor.assumeIsolated { self?.runsChanged(info) }
        }
    }

    func attach(to box: NSView) {
        web.removeFromSuperview()
        web.frame = box.bounds
        web.autoresizingMask = [.width, .height]
        box.addSubview(web)
    }

    /// The tab came to the front (the keyboard goes to the shell) or went behind (it lets go of the keyboard, so typing
    /// elsewhere never lands in the shell).
    func setShowing(_ on: Bool) {
        web.isHidden = !on
        guard on != showing else { return }
        showing = on
        if !on { save() }      // out of sight: what it shows is kept now, not only at quit
        if on {
            DispatchQueue.main.async { [self] in
                guard showing else { return }
                web.window?.makeFirstResponder(web)
                js("focusScreen()")
            }
        } else if let w = web.window, let r = w.firstResponder as? NSView, r === web || r.isDescendant(of: web) {
            w.makeFirstResponder(nil)
        }
    }

    func select(_ id: String) {
        screen = id
        js("show(\(Self.quote(id)))")
    }

    func forget(_ id: String) {
        TerminalRuns.shared.remove(panel.agentId, id)
        if screen == id { select("shell") }
        shown.remove(id)
        js("drop(\(Self.quote(id)))")
    }

    func restart() {
        pty?.onExit = nil; pty?.onOutput = nil
        pty?.hangUp(); pty = nil
        exitCode = nil; problem = nil; inFlight = false
        if !ready {
            if !TermPage.scripts.isEmpty { web.loadHTMLString(TermPage.html, baseURL: nil) } else { problem = "The terminal's screen files are missing from the app. Rebuild it." }
            return
        }
        js("resetShell()")
        spawn()
    }

    private func spawn() {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"; env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Agent Lab"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        for k in ["NSUnbufferedIO", "__CFBundleIdentifier", "XPC_SERVICE_NAME", "TERM_SESSION_ID"] { env[k] = nil }
        let shell = Self.loginShell
        env["SHELL"] = shell
        var isDir: ObjCBool = false
        // The folder it was in before a restart, else the agent's.
        let was = (try? String(contentsOf: savedURL.appendingPathExtension("dir"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = was.flatMap { FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue ? $0 : nil } ?? panel.folder
        let dir = FileManager.default.fileExists(atPath: wanted, isDirectory: &isDir) && isDir.boolValue ? wanted : NSHomeDirectory()
        do {
            let p = try TermPTY(shell: shell, args: ["-l"], folder: dir, cols: cols, rows: rows, env: env)
            p.onOutput = { [weak self] in DispatchQueue.main.async { self?.pump() } }
            p.onExit = { [weak self, weak p] code in
                DispatchQueue.main.async {
                    guard let self, let p, self.pty === p else { return }
                    self.pump()
                    self.exitCode = code
                }
            }
            pty = p
        } catch { problem = error.localizedDescription }
    }

    static var loginShell: String {
        if let s = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: s) { return s }
        if let pw = getpwuid(getuid()), let c = pw.pointee.pw_shell {
            let s = String(cString: c)
            if FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        return "/bin/zsh"
    }

    /// Sends the next piece of output to the screen. One piece is on its way at a time: the page says when it's taken
    /// it in, so a flood moves at the screen's pace (and the shell waits) instead of queueing up in the web view.
    private func pump() {
        guard ready, !inFlight, let pty else { return }
        let data = pty.take(192 << 10)
        guard !data.isEmpty else { return }
        history.append(data)
        if history.count > Self.keep { history = history.suffix(Self.keep * 3 / 4) }
        inFlight = true
        web.evaluateJavaScript("feed(\"\(data.base64EncodedString())\")") { [weak self] _, error in
            // The page didn't take it (it was reloading): carry on rather than stall.
            if error != nil { MainActor.assumeIsolated { self?.inFlight = false } }
        }
    }

    private func end() {
        let k = panel.agentId + "/" + key
        guard let t = Self.sessions[k], t === self else { return }
        Self.sessions[k] = nil
        // The tab was closed for good: what it kept goes too.
        try? FileManager.default.removeItem(at: savedURL.appendingPathExtension("out"))
        try? FileManager.default.removeItem(at: savedURL.appendingPathExtension("dir"))
        if let saving { NotificationCenter.default.removeObserver(saving) }
        pty?.onExit = nil; pty?.onOutput = nil
        pty?.hangUp(); pty = nil
        watch = nil
        if let events { NotificationCenter.default.removeObserver(events) }
        web.configuration.userContentController.removeScriptMessageHandler(forName: "term")
        web.removeFromSuperview()
    }

    // The page's messages: ready, typing, size, links, copy and paste.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let t = m["t"] as? String else { return }
        switch t {
        case "ready":
            ready = true
            cols = m["cols"] as? Int ?? 80; rows = m["rows"] as? Int ?? 24
            // Back after a restart: what the tab showed before, then a new shell where the old one was.
            if pty == nil, problem == nil, !restored {
                restored = true
                if let old = try? Data(contentsOf: savedURL.appendingPathExtension("out")), !old.isEmpty {
                    history = old
                    js("feed(\"\((old + Data("\r\n\u{1b}[2m— restored —\u{1b}[0m\r\n".utf8)).base64EncodedString())\")")
                }
            }
            if pty == nil, problem == nil { spawn() }
            shown = []
            runsChanged(nil)
            if screen != "shell" { js("show(\(Self.quote(screen)))") }
            if showing { js("focusScreen()") }
            pump()
        case "title":
            if let t = (m["s"] as? String)?.trimmingCharacters(in: .whitespaces), !t.isEmpty { title = t }
        case "ack":
            inFlight = false
            pump()
        case "input":
            if let d = m["d"] as? String { pty?.write(Data(d.utf8)) }
        case "binary":
            if let d = m["d"] as? String, let data = d.data(using: .isoLatin1) { pty?.write(data) }
        case "size":
            let c = m["cols"] as? Int ?? cols, r = m["rows"] as? Int ?? rows
            if c != cols || r != rows { cols = c; rows = r; pty?.resize(cols: c, rows: r) }
        case "link":
            if let s = m["url"] as? String, let url = URL(string: s) { BrowserTab.open(url, in: panel) }
        case "copy":
            if let s = m["s"] as? String, !s.isEmpty { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
        case "paste":
            paste()
        default: break
        }
    }

    // MARK: The agent's hands (AgentHands.swift)
    /// The shell is up and its screen can be read.
    var live: Bool { ready && pty != nil }
    /// Types into the shell as you would (the screen in front switches to it).
    func agentType(_ text: String) {
        if screen != "shell" { select("shell") }
        pty?.write(Data(text.utf8))
    }
    /// The shell's last `lines` lines.
    func screenText(_ lines: Int) async -> String {
        guard ready else { return "" }
        return ((try? await web.evaluateJavaScript("screenText(\(max(1, min(lines, 2000))))")) as? String) ?? ""
    }

    func copySelection() { js("copySelection()") }
    func paste() {
        guard screen == "shell", let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return }
        js("pasteText(\(Self.quote(s)))")
    }
    func clear() { js("clearScreen()") }
    func selectAll() { js("selectAllScreen()") }

    /// Brings the page up to date with the agent's runs: a screen for each, filled with what it printed so far, then
    /// live output as it comes.
    private func runsChanged(_ info: [AnyHashable: Any]?) {
        guard ready else { return }
        let agent = panel.agentId
        if let info, info["agentId"] as? String != agent { return }
        let runs = TerminalRuns.shared
        if let id = info?["id"] as? String, let text = info?["text"] as? String {
            if shown.contains(id) { js("feedText(\(Self.quote(id)), \(Self.quote(text)))") }
            return
        }
        for run in runs.runs[agent] ?? [] where !shown.contains(run.id) {
            shown.insert(run.id)
            js("addScreen(\(Self.quote(run.id)), \(Self.quote(runs.output[run.id] ?? "")))")
        }
    }

    private func js(_ code: String) { if ready { web.evaluateJavaScript(code, completionHandler: nil) } }
    /// `s` as a JavaScript string literal.
    static func quote(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}

/// The page's message handler without the page keeping its owner alive.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

/// The terminal's web view: ⌘C, ⌘V, ⌘K and ⌘A act on the terminal while it has the keyboard (ahead of the app's
/// menus, which would otherwise copy from or paste into the hidden text field xterm types through).
final class TermWebView: WKWebView {
    weak var session: TerminalSession?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let session, let r = window?.firstResponder as? NSView, r === self || r.isDescendant(of: self),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": session.copySelection(); return true
        case "v": session.paste(); return true
        case "k": session.clear(); return true
        case "a": session.selectAll(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
    // Only what makes sense for a terminal in the right-click menu (copy, paste), no Reload or Back.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.items.removeAll { item in
            let id = item.identifier?.rawValue ?? ""
            return ["Reload", "Back", "Forward", "Inspect", "Speech", "OpenLink", "DownloadLink"].contains { id.contains($0) }
        }
        super.willOpenMenu(menu, with: event)
    }
}

// MARK: Commands the agent left running

extension Notification.Name {
    /// The agent's runs changed or one printed something. userInfo: "agentId", and "id" + "text" for output.
    static let terminalRunsChanged = Notification.Name("agentlab.terminalRunsChanged")
}

/// Commands the agent left running (engine/terminal.js), by agent, with the last part of what each printed.
@MainActor final class TerminalRuns: ObservableObject {
    static let shared = TerminalRuns()
    struct Run: Identifiable, Equatable {
        let id: String; let command: String; var state: String; var code: Int?
        init(_ r: [String: Any]) {
            id = r["id"] as? String ?? ""; command = r["command"] as? String ?? ""
            state = r["state"] as? String ?? "running"; code = r["code"] as? Int
        }
    }
    @Published private(set) var runs: [String: [Run]] = [:]
    private(set) var output: [String: String] = [:]
    private var loaded: Set<String> = []
    /// How much of each run's output is kept for a screen opened later.
    private static let keep = 200_000

    private init() {
        NotificationCenter.default.addObserver(forName: .engineEvent, object: nil, queue: .main) { n in
            let ev = n.userInfo ?? [:]
            MainActor.assumeIsolated { TerminalRuns.shared.event(ev) }
        }
    }

    /// Commands still running, for a count elsewhere ("1 command running").
    func running(_ agentId: String) -> [Run] { (runs[agentId] ?? []).filter { $0.state == "running" } }

    /// The agent's runs as the engine has them (once per agent; events keep them current after that).
    func load(_ agentId: String, engine: Engine) async {
        guard loaded.insert(agentId).inserted else { return }
        guard let v = try? await engine.call("terminal:runs", [agentId]) as? [[String: Any]] else { loaded.remove(agentId); return }
        var list = runs[agentId] ?? []
        for r in v {
            let run = Run(r)
            guard !run.id.isEmpty, !list.contains(where: { $0.id == run.id }) else { continue }
            list.append(run)
            output[run.id] = r["tail"] as? String ?? ""
        }
        runs[agentId] = list.isEmpty ? nil : list
        NotificationCenter.default.post(name: .terminalRunsChanged, object: nil, userInfo: ["agentId": agentId])
    }

    func remove(_ agentId: String, _ id: String) {
        runs[agentId]?.removeAll { $0.id == id }
        if runs[agentId]?.isEmpty == true { runs[agentId] = nil }
        output[id] = nil
    }

    private func event(_ ev: [AnyHashable: Any]) {
        guard let type = ev["type"] as? String, type.hasPrefix("terminal-"), let agent = ev["agentId"] as? String else { return }
        if type == "terminal-run", let r = ev["run"] as? [String: Any] {
            let run = Run(r)
            guard !run.id.isEmpty else { return }
            var list = runs[agent] ?? []
            if let i = list.firstIndex(where: { $0.id == run.id }) { list[i] = run } else { list.append(run); output[run.id] = output[run.id] ?? "" }
            runs[agent] = list
            NotificationCenter.default.post(name: .terminalRunsChanged, object: nil, userInfo: ["agentId": agent])
        } else if type == "terminal-output", let id = ev["id"] as? String, let text = ev["data"] as? String {
            var o = (output[id] ?? "") + text
            if o.utf8.count > Self.keep { o = String(o.suffix(Self.keep / 2)) }
            output[id] = o
            NotificationCenter.default.post(name: .terminalRunsChanged, object: nil, userInfo: ["agentId": agent, "id": id, "text": text])
        }
    }
}

// MARK: The page

/// The terminal's page: xterm.js with its fit and links add-ons (copied into the app by build.sh, read once and run
/// before the page loads, so nothing comes from the network), in the app's colours.
enum TermPage {
    static let folder: URL? = {
        guard let r = Bundle.main.resourceURL?.appendingPathComponent("terminal"),
              FileManager.default.fileExists(atPath: r.appendingPathComponent("xterm.js").path) else { return nil }
        return r
    }()
    static let scripts: [String] = {
        guard let dir = folder else { return [] }
        let names = ["xterm.js", "addon-fit.js", "addon-web-links.js"]
        let texts = names.compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
        return texts.count == names.count ? texts : []
    }()
    static let css: String = folder.flatMap { try? String(contentsOf: $0.appendingPathComponent("xterm.css"), encoding: .utf8) } ?? ""

    static var html: String {
        var st = style, pg = page
        if MV.on {
            // MAVIS (prototype .term): #161616, 12 on an 18 line, inset 10 14 12.
            st = st.replacingOccurrences(of: "#0a0a0a", with: MV.Terminal.background)
                .replacingOccurrences(of: "inset: 8px 4px 4px 12px", with: MV.Terminal.inset)
            pg = pg.replacingOccurrences(of: "#0a0a0a", with: MV.Terminal.background)
                .replacingOccurrences(of: "fontSize: 12.5, lineHeight: 1.2", with: MV.Terminal.font)
        }
        return "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(css)\n\(st)</style></head><body><div id=\"wrap\"></div><script>\(pg)</script></body></html>"
    }

    static let style = #"""
    html, body { margin: 0; height: 100%; background: #0a0a0a; overflow: hidden; }
    #wrap { position: absolute; inset: 8px 4px 4px 12px; }
    .screen { position: absolute; inset: 0; visibility: hidden; }
    .screen.on { visibility: visible; }
    .xterm { height: 100%; }
    .xterm .xterm-viewport { background-color: #0a0a0a !important; }
    .xterm .scrollbar.vertical { width: 6px !important; }
    .xterm .scrollbar.vertical .slider { width: 6px !important; border-radius: 3px; }
    .xterm .scrollbar.horizontal { display: none !important; }
    """#

    static let page = #"""
    const post = (m) => window.webkit.messageHandlers.term.postMessage(m);
    const wrap = document.getElementById('wrap');
    // The app's greys, with quiet versions of the standard colours.
    const theme = {
      background: '#0a0a0a', foreground: '#ededed', cursor: '#ededed', cursorAccent: '#0a0a0a',
      selectionBackground: 'rgba(255,255,255,0.10)', selectionInactiveBackground: 'rgba(255,255,255,0.06)',
      scrollbarSliderBackground: 'rgba(255,255,255,0.10)', scrollbarSliderHoverBackground: 'rgba(255,255,255,0.16)',
      scrollbarSliderActiveBackground: 'rgba(255,255,255,0.22)',
      black: '#1f1f1f', red: '#d9706e', green: '#8fb98a', yellow: '#d2b56e', blue: '#7f9cc9', magenta: '#ae8cc4', cyan: '#7db5b3', white: '#a1a1a1',
      brightBlack: '#878787', brightRed: '#e68b88', brightGreen: '#a6cca1', brightYellow: '#e0c88a', brightBlue: '#99b3db',
      brightMagenta: '#c2a3d4', brightCyan: '#98c9c7', brightWhite: '#ededed',
    };
    const screens = {};
    let current = 'shell';
    let sent = { cols: 0, rows: 0 };
    function decode(b64) {
      if (Uint8Array.fromBase64) return Uint8Array.fromBase64(b64);
      const s = atob(b64), out = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
      return out;
    }
    function make(id, input) {
      const el = document.createElement('div');
      el.className = 'screen';
      wrap.appendChild(el);
      const t = new Terminal({
        fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace', fontSize: 12.5, lineHeight: 1.2, theme,
        scrollback: 5000, cursorBlink: input, cursorStyle: 'block', cursorInactiveStyle: 'outline', disableStdin: !input,
        macOptionIsMeta: true, macOptionClickForcesSelection: true, drawBoldTextInBrightColors: false,
      });
      const fit = new FitAddon.FitAddon();
      t.loadAddon(fit);
      t.loadAddon(new WebLinksAddon.WebLinksAddon((e, uri) => { e.preventDefault(); post({ t: 'link', url: uri }); }));
      t.open(el);
      if (input) {
        t.onData((d) => post({ t: 'input', d }));
        t.onTitleChange((s) => post({ t: 'title', s }));
        t.onBinary((d) => post({ t: 'binary', d }));
      }
      // The app takes ⌘C ⌘V ⌘K ⌘A first; should one reach the page, it does the same here. Other ⌘ keys are the app's.
      t.attachCustomKeyEventHandler((e) => {
        if (!e.metaKey) return true;
        if (e.type !== 'keydown') return false;
        const k = e.key.toLowerCase();
        if (k === 'c') copySelection();
        else if (k === 'v') post({ t: 'paste' });
        else if (k === 'k') t.clear();
        else if (k === 'a') t.selectAll();
        else return false;
        e.preventDefault();
        return false;
      });
      screens[id] = { t, fit, el };
      return screens[id];
    }
    function fitOn(id) {
      const s = screens[id];
      if (!s || wrap.clientWidth < 40 || wrap.clientHeight < 20) return;
      try { s.fit.fit(); } catch (e) {}
      if (id === 'shell' && (s.t.cols !== sent.cols || s.t.rows !== sent.rows)) {
        sent = { cols: s.t.cols, rows: s.t.rows };
        post({ t: 'size', cols: s.t.cols, rows: s.t.rows });
      }
    }
    function show(id) {
      current = id;
      if (!screens[id]) return;
      for (const k in screens) screens[k].el.classList.toggle('on', k === id);
      fitOn(id);
      screens[id].t.focus();
    }
    function focusScreen() { if (screens[current]) screens[current].t.focus(); }
    function feed(b64) { screens.shell.t.write(decode(b64), () => post({ t: 'ack' })); }
    function feedText(id, text) { if (screens[id]) screens[id].t.write(text.replace(/\r?\n/g, '\r\n')); }
    function addScreen(id, text) { const s = make(id, false); if (text) s.t.write(text.replace(/\r?\n/g, '\r\n')); if (current === id) show(id); }
    function drop(id) { const s = screens[id]; if (!s) return; s.t.dispose(); s.el.remove(); delete screens[id]; if (current === id) show('shell'); }
    function resetShell() { screens.shell.t.reset(); sent = { cols: 0, rows: 0 }; fitOn('shell'); }
    function copySelection() { const s = screens[current]?.t.getSelection(); if (s) post({ t: 'copy', s }); }
    function pasteText(text) { screens.shell?.t.paste(text); }
    // The shell's last lines as text (for the agent, AgentHands.swift).
    function screenText(n) {
      const b = screens.shell.t.buffer.active, out = [];
      for (let i = Math.max(0, b.length - n); i < b.length; i++) out.push(b.getLine(i)?.translateToString(true) ?? '');
      while (out.length && !out[out.length - 1].trim()) out.pop();
      return out.join('\n');
    }
    function clearScreen() { screens[current]?.t.clear(); }
    function selectAllScreen() { screens[current]?.t.selectAll(); }
    make('shell', true);
    show('shell');
    new ResizeObserver(() => fitOn(current)).observe(wrap);
    // The shell starts at the size it's drawn at (fonts first, so the cell size is right).
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => {
      fitOn('shell');
      const t = screens.shell.t;
      post({ t: 'ready', cols: t.cols, rows: t.rows });
    });
    """#
}

private extension String { var nonEmptyTitle: String? { isEmpty || self == "/" ? nil : self } }

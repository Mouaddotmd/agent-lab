// The agent's hands on the rest of the Mac (as Codex's computer use works): it reads an app through Accessibility (its
// windows, buttons, fields and text, numbered), and acts without your mouse — keyboard shortcuts and menus first, then
// pressing or filling an element directly. Keys go to that app alone, even in the background, so it never takes your
// keyboard or brings the app forward. Its cursor (AgentCursor) shows each step where it happens. A picture of a window
// needs Screen Recording; everything else needs Accessibility, asked for once.
import AppKit
import ApplicationServices
import ScreenCaptureKit

@MainActor enum MacHands {
    typealias Problem = AgentHands.Problem
    /// Elements from each app's latest read, by number.
    private static var refs: [pid_t: [Int: AXUIElement]] = [:]

    static func perform(_ action: String, _ a: [String: Any]) async throws -> Any {
        if action == "macApps" { return apps() }
        try trusted()
        let app = try find(a["app"] as? String ?? "", launch: action == "macOpen")
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1.5)
        defer { AgentCursor.shared.rest() }
        switch action {
        case "macOpen":
            try? await Task.sleep(for: .milliseconds(600))
            return "\(app.localizedName ?? "The app") is open\(app.isActive ? "" : " (behind your work)"). Read it with mac_read."
        case "macRead": return read(app, ax, full: a["full"] as? Bool ?? false)
        case "macPress":
            let el = try element(app, a)
            await point(at: el, label: nil)
            await AgentCursor.shared.press()
            try press(el)
            try? await Task.sleep(for: .milliseconds(350))
            return "Pressed \(describe(el))."
        case "macType":
            let text = a["text"] as? String ?? ""
            if a["ref"] != nil {
                let el = try element(app, a)
                await point(at: el, label: nil)
                AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                var settable: DarwinBoolean = false
                AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable)
                if settable.boolValue {
                    let before = (a["append"] as? Bool ?? false) ? (string(el, kAXValueAttribute) ?? "") : ""
                    AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, (before + text) as CFString)
                } else { type(text, to: app.processIdentifier) }
            } else {
                await pointAtFocus(ax, label: "Typing")
                type(text, to: app.processIdentifier)
            }
            if a["submit"] as? Bool == true { try key("return", to: app.processIdentifier) }
            try? await Task.sleep(for: .milliseconds(300))
            return "Typed “\(text.count > 80 ? String(text.prefix(80)) + "…" : text)” in \(app.localizedName ?? "the app")."
        case "macKey":
            let combo = a["keys"] as? String ?? ""
            await pointAtFocus(ax, label: Self.symbols(combo))
            for part in combo.split(separator: " ") { try key(String(part), to: app.processIdentifier); try? await Task.sleep(for: .milliseconds(80)) }
            try? await Task.sleep(for: .milliseconds(350))
            return "Pressed \(combo) in \(app.localizedName ?? "the app")."
        case "macMenu":
            let path = (a["path"] as? [Any])?.map { "\($0)" } ?? []
            try menu(ax, path)
            try? await Task.sleep(for: .milliseconds(400))
            return "Chose \(path.joined(separator: " > ")) in \(app.localizedName ?? "the app")."
        case "macScroll":
            if a["ref"] != nil {
                let el = try element(app, a)
                await point(at: el, label: nil)
                AXUIElementPerformAction(el, "AXScrollToVisible" as CFString)
                return "Scrolled \(describe(el)) into view."
            }
            let down = (a["direction"] as? String ?? "down") != "up"
            guard let win = mainWindow(ax), let f = frame(win) else { throw Problem("\(app.localizedName ?? "The app") has no window to scroll.") }
            let c = CGPoint(x: f.midX, y: f.midY)
            await AgentCursor.shared.glide(to: c, label: down ? "Scroll ↓" : "Scroll ↑")
            for _ in 0..<5 {
                let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: down ? -3 : 3, wheel2: 0, wheel3: 0)
                e?.location = CGPoint(x: f.midX, y: (NSScreen.screens.first?.frame.height ?? 0) - f.midY)
                e?.postToPid(app.processIdentifier)
            }
            return "Scrolled \(down ? "down" : "up") in \(app.localizedName ?? "the app")."
        case "macScreenshot": return try await picture(app)
        default: throw Problem("Unknown step \(action).")
        }
    }

    // MARK: Permission and apps

    private static func trusted() throws {
        if AXIsProcessTrusted() { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) { return }
        throw Problem("Agent Lab needs Accessibility to use other apps. The user has to turn it on in System Settings > Privacy & Security > Accessibility (it was just asked for), then you can try again.")
    }

    private static func apps() -> String {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .map { "\($0.localizedName ?? "?")\($0.isActive ? " (in front)" : "")\($0.isHidden ? " (hidden)" : "") — \($0.bundleIdentifier ?? "")" }
            .joined(separator: "\n")
    }

    private static func find(_ name: String, launch: Bool) throws -> NSRunningApplication {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { throw Problem("Say which app (its name, as mac_apps lists it).") }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if let a = running.first(where: { $0.localizedName?.lowercased() == q || $0.bundleIdentifier?.lowercased() == q })
            ?? running.first(where: { ($0.localizedName?.lowercased() ?? "").contains(q) }) { return a }
        guard launch else { throw Problem("\(name) isn't open. Open it with mac_open, or check mac_apps.") }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
            ?? ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
                .lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(name.hasSuffix(".app") ? name : name + ".app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url else { throw Problem("There's no app called \(name) on this Mac.") }
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        var opened: NSRunningApplication?
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in opened = app; done.signal() }
        _ = done.wait(timeout: .now() + 8)
        guard let opened else { throw Problem("\(name) didn't open.") }
        return opened
    }

    // MARK: Reading

    private static let acting: Set<String> = ["AXButton", "AXTextField", "AXTextArea", "AXSearchField", "AXSecureTextField", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXMenuButton", "AXComboBox", "AXLink", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXRow", "AXCell",
        "AXMenuItem", "AXSegmentedControl", "AXColorWell", "AXDateField", "AXStepper", "AXSwitch", "AXToolbarButton"]

    private static func read(_ app: NSRunningApplication, _ ax: AXUIElement, full: Bool) -> String {
        var lines: [String] = [], text: [String] = [], numbered: [Int: AXUIElement] = [:]
        var n = 0, visited = 0
        let windows = children(ax, kAXWindowsAttribute)
        let focus = mainWindow(ax)
        func walk(_ el: AXUIElement, _ depth: Int) {
            visited += 1
            guard depth < 40, visited < (full ? 8000 : 3000) else { return }
            let role = string(el, kAXRoleAttribute) ?? ""
            if acting.contains(role) || actions(el).contains("AXPress"), n < (full ? 800 : 300) {
                if role != "AXRow" && role != "AXCell" || !words(el).isEmpty {
                    n += 1; numbered[n] = el
                    lines.append("[\(n)] \(describe(el))")
                }
            } else if role == "AXStaticText" || role == "AXHeading", let v = string(el, kAXValueAttribute) ?? string(el, kAXTitleAttribute), !v.trimmingCharacters(in: .whitespaces).isEmpty {
                text.append(v)
            }
            for c in children(el, kAXChildrenAttribute) { walk(c, depth + 1) }
        }
        let order = focus.map { f in [f] + windows.filter { !CFEqual($0, f) } } ?? windows
        for w in order { walk(w, 0) }
        refs[app.processIdentifier] = numbered
        var body = text.joined(separator: "\n")
        let max = full ? 30_000 : 8_000
        if body.count > max { body = String(body.prefix(max)) + "\n… (more: read with full)" }
        let titles = order.compactMap { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
        return "\(app.localizedName ?? "App")\(app.isActive ? " (in front)" : " (in the background)") — windows: \(titles.isEmpty ? "none named" : titles.joined(separator: ", "))\n\nElements:\n\(lines.isEmpty ? "(nothing to act on: try mac_menu or mac_key)" : lines.joined(separator: "\n"))\n\nText:\n\(body)"
    }

    /// "button “Save”", "text field “To” = “ana@…”", "check box “Wrap” (on)".
    private static func describe(_ el: AXUIElement) -> String {
        let role = string(el, kAXRoleDescriptionAttribute) ?? (string(el, kAXRoleAttribute) ?? "element").replacingOccurrences(of: "AX", with: "")
        var d = role
        let w = words(el)
        if !w.isEmpty { d += " “\(w)”" }
        let r = string(el, kAXRoleAttribute) ?? ""
        if r != "AXSecureTextField", let v = value(el), !v.isEmpty, v != w { d += " = “\(v.count > 60 ? String(v.prefix(60)) + "…" : v)”" }
        if r == "AXSecureTextField" { d += " (password: the user types this)" }
        if bool(el, kAXEnabledAttribute) == false { d += " (disabled)" }
        if bool(el, kAXFocusedAttribute) == true { d += " (focused)" }
        return d
    }
    private static func words(_ el: AXUIElement) -> String {
        let t = string(el, kAXTitleAttribute) ?? string(el, kAXDescriptionAttribute) ?? string(el, kAXHelpAttribute) ?? string(el, "AXPlaceholderValue") ?? ""
        if !t.isEmpty { return String(t.prefix(80)) }
        // A row or cell: its first text.
        for c in children(el, kAXChildrenAttribute).prefix(6) {
            if let v = string(c, kAXValueAttribute) ?? string(c, kAXTitleAttribute), !v.isEmpty { return String(v.prefix(80)) }
        }
        return ""
    }
    private static func value(_ el: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success, let v else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue == "1" ? "on" : n.stringValue == "0" ? "off" : n.stringValue }
        return nil
    }

    private static func element(_ app: NSRunningApplication, _ a: [String: Any]) throws -> AXUIElement {
        let n = (a["ref"] as? NSNumber)?.intValue ?? (a["ref"] as? Int) ?? -1
        guard let el = refs[app.processIdentifier]?[n] else { throw Problem("There's no [\(n)] in \(app.localizedName ?? "that app") now. Read it again with mac_read.") }
        return el
    }

    // MARK: Acting

    private static func press(_ el: AXUIElement) throws {
        let have = actions(el)
        for act in ["AXPress", "AXConfirm", "AXPick", "AXOpen", "AXShowMenu"] where have.contains(act) {
            if AXUIElementPerformAction(el, act as CFString) == .success { return }
        }
        // Rows and cells: choosing one selects it.
        if AXUIElementSetAttributeValue(el, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success { return }
        if AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success { return }
        throw Problem("That element can't be pressed. Try its keyboard shortcut (mac_key) or a menu (mac_menu).")
    }

    private static func menu(_ ax: AXUIElement, _ path: [String]) throws {
        guard !path.isEmpty, var current = element(ax, kAXMenuBarAttribute) else { throw Problem("Give the menu path, like [\"File\", \"Export…\"].") }
        for (i, name) in path.enumerated() {
            let items = i == 0 ? children(current, kAXChildrenAttribute) : children(current, kAXChildrenAttribute).flatMap { children($0, kAXChildrenAttribute) }
            let q = name.lowercased().replacingOccurrences(of: "...", with: "…")
            guard let hit = items.first(where: { (string($0, kAXTitleAttribute) ?? "").lowercased() == q })
                ?? items.first(where: { (string($0, kAXTitleAttribute) ?? "").lowercased().hasPrefix(q) }) else {
                let names = items.compactMap { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
                throw Problem("No “\(name)” there. It has: \(names.joined(separator: ", "))")
            }
            if i == path.count - 1 {
                guard AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success else { throw Problem("“\(name)” couldn't be chosen (it may be dimmed).") }
            }
            current = hit
        }
    }

    /// Keys for one app only (posted to it, so your own typing elsewhere is untouched): "cmd+s", "return", "tab".
    private static func key(_ combo: String, to pid: pid_t) throws {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard let name = parts.last, let code = codes[name] ?? (name.count == 1 ? letterCode(name) : nil) else { throw Problem("Unknown key “\(combo)”.") }
        var flags: CGEventFlags = []
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "fn": flags.insert(.maskSecondaryFn)
            default: throw Problem("Unknown modifier “\(m)”.")
            }
        }
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.postToPid(pid)
        }
    }
    private static func type(_ text: String, to pid: pid_t) {
        let src = CGEventSource(stateID: .privateState)
        var chunk: [UniChar] = []
        func send() {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e?.postToPid(pid)
            }
            chunk = []
            usleep(8000)
        }
        for u in text.utf16 {
            if u == 10 { send(); try? key("return", to: pid); continue }
            chunk.append(u); if chunk.count >= 16 { send() }
        }
        send()
    }
    private static let codes: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "forwarddelete": 117, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "=": 24, "-": 27, "]": 30, "[": 33, "'": 39, ";": 41, "\\": 42, ",": 43, "/": 44, ".": 47, "`": 50]
    private static func letterCode(_ c: String) -> CGKeyCode? {
        let map: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
            "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46]
        return c.first.flatMap { map[$0] }
    }
    /// "cmd+shift+s" as "⌘⇧S", for the cursor's tag.
    static func symbols(_ combo: String) -> String {
        combo.split(separator: " ").map { part in
            part.lowercased().split(separator: "+").map { k -> String in
                switch k { case "cmd", "command", "meta": "⌘"; case "shift": "⇧"; case "alt", "option", "opt": "⌥"; case "ctrl", "control": "⌃"
                case "return", "enter": "↩"; case "tab": "⇥"; case "escape", "esc": "⎋"; case "delete", "backspace": "⌫"; case "space": "Space"
                case "up": "↑"; case "down": "↓"; case "left": "←"; case "right": "→"; default: k.uppercased() }
            }.joined()
        }.joined(separator: " ")
    }

    // MARK: The cursor

    /// The cursor to an element: its middle, its frame outlined.
    private static func point(at el: AXUIElement, label: String?) async {
        guard let f = frame(el) else { return }
        await AgentCursor.shared.glide(to: CGPoint(x: f.midX, y: f.midY), frame: f, label: label)
    }
    /// Keys go to what has the keyboard in that app: the cursor shows there, with the keys on its tag.
    private static func pointAtFocus(_ ax: AXUIElement, label: String) async {
        if let f = element(ax, kAXFocusedUIElementAttribute).flatMap(frame) ?? mainWindow(ax).flatMap(frame) {
            await AgentCursor.shared.glide(to: CGPoint(x: f.midX, y: f.midY), frame: nil, label: label)
            await AgentCursor.shared.press()
        }
    }

    // MARK: Picture

    private static func picture(_ app: NSRunningApplication) async throws -> [String: Any] {
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) }
        catch { throw Problem("Pictures of other apps need Screen Recording for Agent Lab: the user turns it on in System Settings > Privacy & Security > Screen Recording. Use mac_read meanwhile.") }
        guard let win = content.windows.filter({ $0.owningApplication?.processID == app.processIdentifier && $0.frame.width > 80 && $0.windowLayer == 0 })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { throw Problem("\(app.localizedName ?? "The app") has no window to take a picture of.") }
        let config = SCStreamConfiguration()
        let scale = min(1, 1400 / max(win.frame.width, 1))
        config.width = Int(win.frame.width * 2 * scale); config.height = Int(win.frame.height * 2 * scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: config)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { throw Problem("The picture couldn't be made.") }
        return ["image": jpeg.base64EncodedString(), "text": "\(app.localizedName ?? "App") — \(win.title ?? "window")"]
    }

    // MARK: Accessibility reading helpers

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }
    private static func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return (v as? NSNumber)?.boolValue
    }
    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    private static func children(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let list = v as? [AXUIElement] else { return [] }
        return list
    }
    private static func actions(_ el: AXUIElement) -> [String] {
        var v: CFArray?
        guard AXUIElementCopyActionNames(el, &v) == .success, let list = v as? [String] else { return [] }
        return list
    }
    private static func mainWindow(_ ax: AXUIElement) -> AXUIElement? {
        element(ax, kAXFocusedWindowAttribute) ?? element(ax, kAXMainWindowAttribute) ?? children(ax, kAXWindowsAttribute).first
    }
    /// An element's frame in screen coordinates (bottom-left origin, as AppKit's).
    private static func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success, let p, let s else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pos); AXValueGetValue(s as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        let top = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: pos.x, y: top - pos.y - size.height, width: size.width, height: size.height)
    }
}

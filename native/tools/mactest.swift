// Drives the agent's Mac hands (MacHands.swift) on TextEdit as engine/hands.js would: open in the background, read,
// type into the document, shortcuts, menus, pressing an element, scrolling, a picture. build/mactest
import SwiftUI
import AppKit

@main struct MacTest {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        var fails = 0
        @MainActor func step(_ name: String, _ action: String, _ args: [String: Any] = [:], expect: [String] = [], refuse: Bool = false) -> String {
            var out = "", problem: String?, done = false
            Task { @MainActor in
                do { let v = try await MacHands.perform(action, args); out = (v as? [String: Any]).map { "image \(($0["image"] as? String ?? "").count) chars \($0["text"] ?? "")" } ?? "\(v)" }
                catch { problem = error.localizedDescription }
                done = true
            }
            let end = Date().addingTimeInterval(30); while !done && Date() < end { spin(0.05) }
            let text = problem ?? out
            let ok = refuse ? problem != nil : problem == nil && expect.allSatisfy { text.localizedCaseInsensitiveContains($0) }
            if !ok { fails += 1 }
            print("\(ok ? "PASS" : "FAIL") \(name): \(text.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(260))")
            return text
        }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        _ = step("apps", "macApps", expect: [front])
        _ = step("not open", "macRead", ["app": "NoSuchAppHere"], refuse: true)
        _ = step("open TextEdit", "macOpen", ["app": "TextEdit"], expect: ["TextEdit"])
        spin(1)
        _ = step("new doc (shortcut)", "macKey", ["app": "TextEdit", "keys": "cmd+n"])
        spin(1)
        let r1 = step("read", "macRead", ["app": "TextEdit"], expect: ["Elements:"])
        _ = step("type into focus", "macType", ["app": "TextEdit", "text": "hello from the agent"])
        spin(0.5)
        _ = step("text arrived", "macRead", ["app": "TextEdit"], expect: ["hello from the agent"])
        _ = step("select all + delete", "macKey", ["app": "TextEdit", "keys": "cmd+a delete"])
        _ = step("menu", "macMenu", ["app": "TextEdit", "path": ["Format", "Make Plain Text"]])
        spin(0.6)
        let r2 = step("read after menu", "macRead", ["app": "TextEdit"])
        if let n = r2.split(separator: "\n").first(where: { $0.contains("OK") || $0.contains("Convert") })?.firstMatch(of: #/\[(\d+)\]/#).map({ Int($0.1)! }) {
            _ = step("press dialog button", "macPress", ["app": "TextEdit", "ref": n])
        } else { print("SKIP press: no dialog (\(r1.count) chars read)") }
        _ = step("bad ref", "macPress", ["app": "TextEdit", "ref": 9999], refuse: true)
        _ = step("bad menu", "macMenu", ["app": "TextEdit", "path": ["Nope"]], refuse: true)
        _ = step("scroll", "macScroll", ["app": "TextEdit", "direction": "down"], expect: ["Scrolled"])
        _ = step("picture", "macScreenshot", ["app": "TextEdit"])
        _ = step("close doc", "macKey", ["app": "TextEdit", "keys": "cmd+w"])
        spin(0.6)
        let r3 = step("read for don't save", "macRead", ["app": "TextEdit"])
        if let n = r3.split(separator: "\n").first(where: { $0.contains("Delete") || $0.contains("Don") })?.firstMatch(of: #/\[(\d+)\]/#).map({ Int($0.1)! }) {
            _ = step("don't save", "macPress", ["app": "TextEdit", "ref": n])
        }
        print("front app still \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "") (was \(front))")
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}

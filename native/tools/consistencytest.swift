// Every saved message must be drawn exactly the same however and whenever it's shown: right as the app opens (nothing
// loaded in the background yet), after everything has loaded, and in another launch. Renders each message's words the
// way the chat does (RichText) and writes what decides their look (text, links, chips, fonts, colours) as one line per
// message, then compares.
//   build/consistencytest <out.txt>      writes this launch's rendering; exits 1 if cold and warm differ
//   diff two out.txt files from two launches: they must be identical
import SwiftUI
import AppKit

@main struct ConsistencyTest {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/consistency.txt"
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); F.register()
        // Exactly what the app has before anything loads: the roots it starts with, the names known at launch.
        let store = Store()
        func spin(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Agent Lab/messages")
        var texts: [(String, String, String)] = []
        for f in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f), let list = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { continue }
            for m in list { if let t = m["text"] as? String, !t.isEmpty { texts.append((f.lastPathComponent, m["id"] as? String ?? "?", t)) } }
        }
        func render() -> [String] {
            texts.map { file, id, t in
                let segs = RichText.segments(t, color: Color.white(0.82))
                var parts: [String] = []
                for seg in segs {
                    let a: NSAttributedString
                    switch seg { case .prose(let x), .quote(let x): a = x; default: parts.append("\(seg)".prefix(80).description); continue }
                    a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { attrs, r, _ in
                        let link = (attrs[.link] as? URL)?.absoluteString ?? (attrs[.link] as? String) ?? ""
                        let chip = attrs[.commandChip] != nil ? "chip" : ""
                        let font = (attrs[.font] as? NSFont)?.fontName ?? ""
                        let color = (attrs[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB).map { String(format: "%.3f,%.3f,%.3f,%.3f", $0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) } ?? ""
                        parts.append("\(r.location)+\(r.length)|\(font)|\(color)|\(link)|\(chip)")
                    }
                    parts.append("#" + String(a.string.hashValue & 0))      // the words themselves are compared by length above
                }
                return "\(file) \(id) \(t.count) " + parts.joined(separator: " ")
            }
        }
        // As the app opens: the store loaded (its roots set), the saved index read, nothing rebuilt yet.
        store.connect()
        let end = Date().addingTimeInterval(20); while store.agents.isEmpty && Date() < end { spin(0.05) }
        let v0 = FileNames.shared.version
        let cold = render()
        // Then as the running app has it a moment later: the file index read again in the background.
        let wait = Date().addingTimeInterval(90); while FileNames.shared.version == v0 && Date() < wait { spin(0.2) }
        spin(0.5)
        RichText.clearCache()
        let warm = render()
        try? cold.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        let diffs = zip(cold, warm).enumerated().filter { $0.element.0 != $0.element.1 }
        print("\(texts.count) messages; known commands \(CommandTokens.names.count); index rebuilt: \(FileNames.shared.version != v0)")
        for d in diffs.prefix(8) {
            print("DIFF \(texts[d.offset].0) \(texts[d.offset].1): cold vs warm")
            let a = d.element.0.split(separator: " "), b = d.element.1.split(separator: " ")
            for (x, y) in zip(a, b) where x != y { print("  cold \(x)\n  warm \(y)"); break }
        }
        print(diffs.isEmpty ? "PASS cold and warm identical" : "FAIL \(diffs.count) messages differ between launch and loaded")
        exit(diffs.isEmpty ? 0 : 1)
    }
}

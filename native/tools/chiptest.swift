// Draws command chips offscreen the way a message draws them (ProseView's text view: Chip.room sides, ChipLayoutManager)
// and writes build/tests/chips.png, plus the pill's measured edges against its words.
import AppKit
import SwiftUI

@main struct ChipTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        themeNow = Palettes.all.first { $0.id == "mavis.dark" } ?? themeNow
        CommandTokens.learn(["advisor", "state-machine"])
        print("known advisor:", CommandTokens.names.contains("advisor"), CommandTokens.ranges(in: "/advisor"))
        let cases = ["/advisor", "/advisor ok", "/state-machine", "Usage: /advisor <fable|opus|sonnet|off>", "/list run then /advisor here"]
        var y: CGFloat = 10
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        canvas.wantsLayer = true; canvas.layer?.backgroundColor = NSColor(MV.Tone.page).cgColor
        for t in cases {
            let s = NSMutableAttributedString(string: t, attributes: [.font: RichText.font(RichText.size, .regular), .foregroundColor: NSColor(MV.Ink.t1), .paragraphStyle: RichText.style()])
            RichText.chips(s, size: RichText.size)
            let v = NSTextView(usingTextLayoutManager: false); v.frame = NSRect(x: 20, y: y, width: 480, height: 30)
            v.textContainer?.replaceLayoutManager(ChipLayoutManager())
            v.textContainerInset = .zero; v.textContainer?.lineFragmentPadding = Chip.room
            v.drawsBackground = false
            v.textStorage?.setAttributedString(s)
            canvas.addSubview(v)
            print("lm", v.layoutManager as Any, "chips attr", s.attribute(.commandChip, at: 0, effectiveRange: nil) as Any)
            if let lm = v.layoutManager, let tc = v.textContainer {
                lm.ensureLayout(for: tc)
                for r in CommandTokens.ranges(in: t) {
                    let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                    let b = lm.boundingRect(forGlyphRange: g, in: tc)
                    print("\(t.prefix(20)): words x \(Int(b.minX))…\(Int(b.maxX)) (container), origin \(v.textContainerOrigin)")
                }
            }
            y += 50
        }
        canvas.isFlipped ? () : ()
        let win = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = canvas
        let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(MV.Tone.page).setFill(); canvas.bounds.fill()
        for case let tv as NSTextView in canvas.subviews {
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.translateBy(x: tv.frame.minX, y: canvas.bounds.height - tv.frame.maxY)
            tv.displayIgnoringOpacity(tv.bounds, in: NSGraphicsContext.current!)
            NSGraphicsContext.current?.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/tests/chips.png"))
        print("wrote build/tests/chips.png")
    }
}

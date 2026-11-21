// Draws the web app's icons from the same SVG path data (24×24 box, round strokes), scaled to size.
import SwiftUI

enum IconShape {
    case path(String, stroke: CGFloat, join: CGLineJoin, cap: CGLineCap)
    case circle(cx: CGFloat, cy: CGFloat, r: CGFloat, stroke: CGFloat)
}

/// SVG path data → Path: M L H V C S Z, absolute and relative (the icons and the faces use these).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var p = Path(), cur = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint? = nil
        var tokens: [String] = [], num = ""
        func flush() { if !num.isEmpty { tokens.append(num); num = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" { flush(); tokens.append(String(ch)) }
            else if ch == "," || ch == " " || ch == "\n" { flush() }
            else if ch == "-" && !num.isEmpty && !(num.last == "e" || num.last == "E") { flush(); num = "-" }
            else if ch == "." && num.contains(".") { flush(); num = "." }
            else { num.append(ch) }
        }
        flush()
        var i = 0, cmd: Character = "M"
        func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = c; i += 1; if cmd == "Z" || cmd == "z" { p.closeSubpath(); cur = start; lastCtrl = nil; continue } }
            let rel = cmd.isLowercase, o = rel ? cur : .zero
            switch cmd.uppercased() {
            case "M": cur = CGPoint(x: o.x + n(), y: o.y + n()); start = cur; p.move(to: cur); cmd = rel ? "l" : "L"; lastCtrl = nil
            case "L": cur = CGPoint(x: o.x + n(), y: o.y + n()); p.addLine(to: cur); lastCtrl = nil
            case "H": cur.x = (rel ? cur.x : 0) + n(); p.addLine(to: cur); lastCtrl = nil
            case "V": cur.y = (rel ? cur.y : 0) + n(); p.addLine(to: cur); lastCtrl = nil
            case "C":
                let c1 = CGPoint(x: o.x + n(), y: o.y + n()), c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; lastCtrl = c2
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; lastCtrl = c2
            default: i += 1
            }
        }
        return p
    }
}

struct Icon: View {
    let name: String; var size: CGFloat = 16
    init(_ name: String, _ size: CGFloat = 16) { self.name = name; self.size = size }
    var body: some View {
        Canvas { ctx, _ in
            let s = size / 24
            for shape in IconData.all[name] ?? MavisIconData.all[name] ?? [] {
                switch shape {
                case let .path(d, stroke, join, cap):
                    ctx.stroke(SVGPath.parse(d).applying(.init(scaleX: s, y: s)), with: .foreground, style: StrokeStyle(lineWidth: stroke * s, lineCap: cap, lineJoin: join))
                case let .circle(cx, cy, r, stroke):
                    let rect = CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s)
                    ctx.stroke(Path(ellipseIn: rect), with: .foreground, style: StrokeStyle(lineWidth: stroke * s))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

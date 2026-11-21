import SwiftUI
import AppKit
import CoreText

// The Agent Lab system, value for value from the original stylesheet.
// Spacing 4 8 12 16 24 32 48 · type 1.25 from 14 · radius 4 8 12 16 · one primary per screen.

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black, b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let t = 1 - amount
        return Color(.sRGB, red: a.redComponent * amount + b.redComponent * t, green: a.greenComponent * amount + b.greenComponent * t, blue: a.blueComponent * amount + b.blueComponent * t)
    }
}

enum T {
    // layers
    static let ground = Color(hex: "#080807")
    static let side = Color(hex: "#0e0e0d")
    static let work = Color(hex: "#151514")
    // inks
    static let i1 = Color(hex: "#111110"), i2 = Color(hex: "#191918"), i3 = Color(hex: "#222221"), i4 = Color(hex: "#2a2a28")
    static let i5 = Color(hex: "#31312e"), i6 = Color(hex: "#3b3a37"), i7 = Color(hex: "#494844"), i9 = Color(hex: "#6f6d66")
    static let i10 = Color(hex: "#7c7b74"), i11 = Color(hex: "#b5b3ad"), i12 = Color(hex: "#eeeeec")
    // meaning
    static let wait = Color(hex: "#D97757"), waitText = Color(hex: "#EC9A7A"), waitTint = Color(.sRGB, red: 217 / 255, green: 119 / 255, blue: 87 / 255, opacity: 0.15)
    static let fail = Color(hex: "#E5484D"), failText = Color(hex: "#FF9592"), failTint = Color(.sRGB, red: 236 / 255, green: 70 / 255, blue: 71 / 255, opacity: 0.15)
    static let codeAdd = Color(hex: "#A9C49A"), codeDel = Color(hex: "#FF9592")
    static let waitEdge = Color(hex: "#EC9A7A").mix(.black, 0.34)
    static let failEdge = Color(hex: "#FF9592").mix(.black, 0.34)

    // type: 11.2 · 14 · 17.5 · 21.875 · 27.34 on 16 20 24 28 36 lines
    static let t1: CGFloat = 11.2, t2: CGFloat = 14, t3: CGFloat = 17.5, t4: CGFloat = 21.875, t5: CGFloat = 27.34

    static func registerFonts() {
        for name in ["Inter-Medium", "JetBrainsMono-Medium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
    static func font(_ size: CGFloat) -> Font { NSFont(name: "Inter-Medium", size: size) != nil ? .custom("Inter-Medium", fixedSize: size) : .system(size: size, weight: .medium) }
    static func mono(_ size: CGFloat) -> Font { NSFont(name: "JetBrainsMono-Medium", size: size) != nil ? .custom("JetBrainsMono-Medium", fixedSize: size) : .system(size: size, weight: .medium, design: .monospaced) }
}

/// Text on the type scale: size plus the line height the system sets for it.
struct TypeStyle: ViewModifier {
    var size: CGFloat
    var color: Color = T.i12
    var mono = false
    func body(content: Content) -> some View {
        let line: CGFloat = size <= T.t1 ? 16 : size <= T.t2 ? 20 : size <= T.t3 ? 24 : size <= T.t4 ? 28 : 36
        content.font(mono ? T.mono(size) : T.font(size)).foregroundStyle(color)
            .lineSpacing(max(0, line - size * 1.21))
            .tracking(size >= T.t5 ? -0.02 * size : size >= T.t4 ? -0.01 * size : -0.003 * size)
    }
}
extension View {
    func type(_ size: CGFloat = T.t2, _ color: Color = T.i12, mono: Bool = false) -> some View { modifier(TypeStyle(size: size, color: color, mono: mono)) }
    /// --drop: 0 1px 2px black/.5
    func drop() -> some View { shadow(color: .black.opacity(0.5), radius: 1, y: 1) }
    /// --lift: drop + 0 4px 4px -2px black/.5
    func lift() -> some View { shadow(color: .black.opacity(0.5), radius: 1, y: 1).shadow(color: .black.opacity(0.35), radius: 2, y: 3) }
    /// --float: drop + 0 8px 8px -4px black/.6
    func float() -> some View { shadow(color: .black.opacity(0.5), radius: 1, y: 1).shadow(color: .black.opacity(0.45), radius: 4, y: 6) }
    /// A filled shape with a hairline ring, the system's way of raising things.
    func surface(_ fill: Color, ring: Color, radius: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(ring, lineWidth: 0.5))
    }
    func hoverFill(_ normal: Color, _ hover: Color, radius: CGFloat, on: Bool = false, onFill: Color = T.i3) -> some View { modifier(HoverFill(normal: normal, hover: hover, radius: radius, on: on, onFill: onFill)) }
    func hairBottom() -> some View { overlay(alignment: .bottom) { Rectangle().fill(T.i5).frame(height: 0.5) } }
    func hairTop() -> some View { overlay(alignment: .top) { Rectangle().fill(T.i5).frame(height: 0.5) } }
}

struct HoverFill: ViewModifier {
    var normal: Color, hover: Color, radius: CGFloat, on: Bool, onFill: Color
    @State private var over = false
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(on ? onFill : over ? hover : normal))
            .onHover { h in withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)) { over = h } }
    }
}

struct Hair: View {
    var vertical = false
    var body: some View { Rectangle().fill(T.i5).frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5) }
}

// MARK: - Buttons: primary (ink), secondary, danger, round, icon

enum BtnKind { case primary, second, danger, ghost }

struct Btn: ButtonStyle {
    var kind: BtnKind = .second
    var raised = false   // inside a card: one step up
    var height: CGFloat = 32
    var pill = false
    func makeBody(configuration: Configuration) -> some View { Inner(kind: kind, raised: raised, height: height, pill: pill, configuration: configuration) }
    struct Inner: View {
        var kind: BtnKind, raised: Bool, height: CGFloat, pill: Bool
        let configuration: Configuration
        @State private var over = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let r: CGFloat = pill ? height / 2 : 8
            let (fill, ring, ink): (Color, Color, Color) = {
                switch kind {
                case .primary: return (over ? T.i12.mix(T.i1, 0.93) : T.i12, T.i12, T.i1)
                case .second: return raised ? (over ? T.i5 : T.i4, T.i7, T.i12) : (over ? T.i4 : T.i3, T.i6, T.i12)
                case .danger: return raised ? (over ? T.i5 : T.i4, T.i7, T.failText) : (over ? T.i4 : T.i3, T.i6, T.failText)
                case .ghost: return (over ? T.i3 : .clear, .clear, over ? T.i12 : T.i10)
                }
            }()
            HStack(spacing: 4) { configuration.label }
                .type(T.t2, ink)
                .tracking(-0.14)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: height)
                .surface(fill, ring: ring, radius: r)
                .drop()
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.6)
                .contentShape(Rectangle())
                .onHover { over = $0 }
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct IconBtn: ButtonStyle {
    var size: CGFloat = 32
    var on = false
    var radius: CGFloat = 8
    var hover: Color = T.i3
    func makeBody(configuration: Configuration) -> some View { Inner(size: size, on: on, radius: radius, hover: hover, configuration: configuration) }
    struct Inner: View {
        var size: CGFloat, on: Bool, radius: CGFloat, hover: Color
        let configuration: Configuration
        @State private var over = false
        var body: some View {
            configuration.label
                .foregroundStyle(over || on ? T.i12 : T.i10)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(over ? hover : .clear))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .contentShape(Rectangle())
                .onHover { over = $0 }
        }
    }
}

/// The 36px round action, Discord's message button.
struct RoundBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var over = false
        var body: some View {
            configuration.label
                .foregroundStyle(over ? T.i12 : T.i11)
                .frame(width: 36, height: 36)
                .background(Circle().fill(over ? T.i4 : T.i3)).overlay(Circle().strokeBorder(T.i6, lineWidth: 0.5)).drop()
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .contentShape(Circle())
                .onHover { over = $0 }
        }
    }
}

/// A plain row that fades its own fill in on hover and squeezes a little when pressed.
struct RowBtn: ButtonStyle {
    var radius: CGFloat = 8
    var on = false
    var normal: Color = .clear
    var hover: Color = T.i2
    var onFill: Color = T.i3
    var press: CGFloat = 1
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .hoverFill(normal, hover, radius: radius, on: on, onFill: onFill)
            .scaleEffect(configuration.isPressed ? press : 1)
    }
}

// MARK: - Icons, drawn as in the original (24 grid, 1.7 stroke)

enum Ic: String {
    case agents, memory, plug, plus, pen, home, search, chev, more, send, stop, x, check, panel, folder, trash, branch
}

struct Icon: View {
    var name: Ic
    var size: CGFloat = 16
    var weight: CGFloat = 1.7
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 24
            ctx.scaleBy(x: k, y: k)
            let style = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
            for (p, fill) in Icon.paths(name) {
                if fill { ctx.fill(p, with: .foreground) } else { ctx.stroke(p, with: .foreground, style: style) }
            }
        }
        .frame(width: size, height: size)
    }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
    static func poly(_ pts: [(CGFloat, CGFloat)], close: Bool = false) -> Path {
        var p = Path(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }; if close { p.closeSubpath() }; return p
    }
    static func paths(_ n: Ic) -> [(Path, Bool)] {
        switch n {
        case .agents:
            var a = Path(); a.move(to: .init(x: 2.5, y: 20)); a.addArc(center: .init(x: 9, y: 20), radius: 6.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            var b = Path(); b.move(to: .init(x: 16, y: 4.6)); b.addQuadCurve(to: .init(x: 16, y: 11.4), control: .init(x: 20.6, y: 8))
            b.move(to: .init(x: 18, y: 14.2)); b.addQuadCurve(to: .init(x: 21.5, y: 20), control: .init(x: 21.4, y: 15.8))
            return [(circle(9, 8, 3.5), false), (a, false), (b, false)]
        case .memory:
            var p = Path(); p.move(to: .init(x: 5, y: 4)); p.addLine(to: .init(x: 14, y: 4)); p.addQuadCurve(to: .init(x: 18, y: 8), control: .init(x: 18, y: 4))
            p.addLine(to: .init(x: 18, y: 20)); p.addLine(to: .init(x: 9, y: 20)); p.addQuadCurve(to: .init(x: 5, y: 16), control: .init(x: 5, y: 20)); p.closeSubpath()
            var q = Path(); q.move(to: .init(x: 5, y: 16)); q.addQuadCurve(to: .init(x: 9, y: 12), control: .init(x: 5, y: 12)); q.addLine(to: .init(x: 18, y: 12))
            return [(p, false), (q, false)]
        case .plug:
            var p = Path(); p.move(to: .init(x: 9, y: 3)); p.addLine(to: .init(x: 9, y: 8)); p.move(to: .init(x: 15, y: 3)); p.addLine(to: .init(x: 15, y: 8))
            p.move(to: .init(x: 6, y: 8)); p.addLine(to: .init(x: 18, y: 8)); p.addLine(to: .init(x: 18, y: 11))
            p.addArc(center: .init(x: 12, y: 11), radius: 6, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false); p.closeSubpath()
            p.move(to: .init(x: 12, y: 17)); p.addLine(to: .init(x: 12, y: 21))
            return [(p, false)]
        case .plus: return [(poly([(12, 5), (12, 19)]), false), (poly([(5, 12), (19, 12)]), false)]
        case .pen: return [(poly([(4, 20), (8, 20), (19, 9), (15, 5), (4, 16)], close: true), false), (poly([(13.5, 6.5), (17.5, 10.5)]), false)]
        case .home: return [(poly([(4, 11), (12, 4), (20, 11), (20, 20), (15, 20), (15, 14), (9, 14), (9, 20), (4, 20)], close: true), false)]
        case .search: return [(circle(11, 11, 6.5), false), (poly([(20, 20), (16, 16)]), false)]
        case .chev: return [(poly([(7, 10), (12, 15), (17, 10)]), false)]
        case .more: return [(circle(5, 12, 1.4), true), (circle(12, 12, 1.4), true), (circle(19, 12, 1.4), true)]
        case .send: return [(poly([(12, 19), (12, 5)]), false), (poly([(6, 11), (12, 5), (18, 11)]), false)]
        case .stop: return [(Path(roundedRect: CGRect(x: 7, y: 7, width: 10, height: 10), cornerRadius: 2), false)]
        case .x: return [(poly([(6, 6), (18, 18)]), false), (poly([(18, 6), (6, 18)]), false)]
        case .check: return [(poly([(5, 12.5), (9.5, 17), (19, 7.5)]), false)]
        case .panel: return [(Path(roundedRect: CGRect(x: 3.5, y: 4.5, width: 17, height: 15), cornerRadius: 2), false), (poly([(15, 4.5), (15, 19.5)]), false)]
        case .folder:
            var p = Path(); p.move(to: .init(x: 3.5, y: 7)); p.addQuadCurve(to: .init(x: 5.5, y: 5), control: .init(x: 3.5, y: 5)); p.addLine(to: .init(x: 10, y: 5)); p.addLine(to: .init(x: 12, y: 7))
            p.addLine(to: .init(x: 18.5, y: 7)); p.addQuadCurve(to: .init(x: 20.5, y: 9), control: .init(x: 20.5, y: 7)); p.addLine(to: .init(x: 20.5, y: 17)); p.addQuadCurve(to: .init(x: 18.5, y: 19), control: .init(x: 20.5, y: 19))
            p.addLine(to: .init(x: 5.5, y: 19)); p.addQuadCurve(to: .init(x: 3.5, y: 17), control: .init(x: 3.5, y: 19)); p.closeSubpath()
            return [(p, false)]
        case .trash: return [(poly([(5, 7), (19, 7)]), false), (poly([(10, 7), (10, 5), (14, 5), (14, 7)]), false), (poly([(7, 7), (8, 19), (16, 19), (17, 7)]), false)]
        case .branch:
            var p = Path(); p.move(to: .init(x: 7, y: 8)); p.addLine(to: .init(x: 7, y: 16)); p.move(to: .init(x: 17, y: 10)); p.addCurve(to: .init(x: 7, y: 16), control1: .init(x: 17, y: 14), control2: .init(x: 7, y: 12))
            return [(circle(7, 6, 2), false), (circle(7, 18, 2), false), (circle(17, 8, 2), false), (p, false)]
        }
    }
}

// MARK: - Small pieces

/// Operator tile: two letters on a raised square. Sizes: sm 24, normal 32, lg 40, xl 48.
struct OpTile: View {
    var op: String
    var size: CGFloat = 32
    static func abbr(_ op: String) -> String { ["claude-code": "CC", "codex": "Cx", "mavis": "Mv"][op] ?? "?" }
    var body: some View {
        let r: CGFloat = size <= 24 ? 4 : size >= 48 ? 12 : 8
        Text(OpTile.abbr(op)).type(size >= 48 ? T.t2 : T.t1, T.i11)
            .frame(width: size, height: size)
            .surface(T.i4, ring: T.i7, radius: r).drop()
            .help(Operators.name(op))
    }
}

struct Chip: View {
    var text: String
    var icon: Ic? = nil
    var action: (() -> Void)? = nil
    @State private var over = false
    var body: some View {
        let link = action != nil
        let content = HStack(spacing: 4) {
            if let icon { Icon(name: icon, size: 12) }
            Text(text).lineLimit(1)
        }
        .type(T.t1, link && over ? T.i12 : T.i11, mono: true)
        .padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(link && over ? T.i4 : T.i3)).overlay(Capsule().strokeBorder(T.i6, lineWidth: 0.5))
        if let action { Button(action: action) { content }.buttonStyle(.plain).onHover { over = $0 } } else { content }
    }
}

struct Tag: View {
    var text: String
    var body: some View {
        Text(text).type(T.t1, T.i11).lineLimit(1).padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(T.i3)).overlay(Capsule().strokeBorder(T.i6, lineWidth: 0.5))
    }
}

struct Badge: View {
    var text: String
    var fail = false
    var body: some View {
        Text(text).type(T.t1, fail ? T.failText : T.waitText).lineLimit(1).padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(fail ? T.failTint : T.waitTint)).overlay(Capsule().strokeBorder(fail ? T.failEdge : T.waitEdge, lineWidth: 0.5)).drop()
    }
}

struct Count: View {
    var n: Int
    var body: some View {
        Text("\(n)").type(T.t1, T.waitText).padding(.horizontal, 4).frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(T.waitTint)).overlay(Capsule().strokeBorder(T.waitEdge, lineWidth: 0.5))
    }
}

struct Meta: View {
    var text: String
    var color: Color = T.i10
    init(_ text: String, _ color: Color = T.i10) { self.text = text; self.color = color }
    var body: some View { Text(text).type(T.t1, color) }
}

/// The section heading with a hairline under it.
struct GroupHead: View {
    var title: String
    var n: Int?
    var hair = true
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).type(T.t1, T.i11).tracking(0.22)
            if let n { Meta("\(n)") }
            Spacer(minLength: 0)
        }
        .padding(.bottom, hair ? 8 : 0)
        .overlay(alignment: .bottom) { if hair { Hair() } }
    }
}

struct Empty: View {
    var title: String
    var sub: String?
    var body: some View {
        VStack(spacing: 0) {
            Text(title).type(T.t2, T.i12)
            if let sub { Text(sub).type(T.t2, T.i11) }
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}

struct Loading: View {
    var text: String
    @State private var on = false
    var body: some View {
        HStack(spacing: 0) { Text(text); Text("…").opacity(on ? 1 : 0.3) }.type(T.t2, T.i10)
            .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { on = true } }
    }
}

/// Three blinking dots and what the agent is doing.
struct Typing: View {
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        let ph = (t - Double(i) * 0.15).truncatingRemainder(dividingBy: 1.2) / 1.2
                        Circle().fill(T.i9).frame(width: 4, height: 4).opacity(ph < 0.4 ? 0.3 + ph / 0.4 * 0.7 : ph < 0.8 ? 1 - (ph - 0.4) / 0.4 * 0.7 : 0.3)
                    }
                }
            }
            Text(" \(text)").type(T.t1, T.i10).lineLimit(1)
        }
        .padding(.leading, 52).padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Toast: View {
    var text: String
    var error: Bool
    var body: some View {
        Text(text).type(T.t2, error ? T.failText : T.i12).multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 440)
            .background(Capsule().fill(T.i3)).overlay(Capsule().strokeBorder(T.i6, lineWidth: 0.5)).lift()
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

func clip(_ s: String?, _ n: Int = 90) -> String {
    let t = (s ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return t.count > n ? String(t.prefix(n - 1)) + "…" : t
}

func ago(_ ms: Double?) -> String {
    guard let ms else { return "" }
    let s = max(1, Int((Date().timeIntervalSince1970 * 1000 - ms) / 1000))
    if s < 60 { return "just now" }
    let m = Int((Double(s) / 60).rounded()); if m < 60 { return "\(m) min ago" }
    let h = Int((Double(m) / 60).rounded()); if h < 24 { return "\(h) h ago" }
    let d = Int((Double(h) / 24).rounded()); if d < 14 { return "\(d) d ago" }
    let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d")
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}

func since(_ ms: Double) -> String {
    let s = max(0, Int(Date().timeIntervalSince1970 - ms / 1000))
    return s < 60 ? "\(s) s" : s < 3600 ? "\(s / 60) min" : "\(s / 3600) h \((s % 3600) / 60) min"
}

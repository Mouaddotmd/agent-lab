import SwiftUI

// Drawn faces, so each agent reads as someone. Same drawing, palette and seeding as the original.

enum Faces {
    static let bg = ["#3A4436", "#47353F", "#2F3A45", "#45402F", "#3B3A47", "#44332F", "#34413F"]
    static let skin = ["#F1CDB0", "#E2B48F", "#C99A78", "#A8714F", "#8D5B3F", "#6B4430"]
    static let hair = ["#1F1A17", "#3B2A20", "#8A5A3B", "#C6613F", "#D9C7A8", "#6E6A63"]
    static let shirt = ["#D97757", "#7E9C8B", "#5D6B8C", "#9C6B85", "#A9B98A", "#B8A06A"]

    static func random() -> Look {
        Look(bg: bg.randomElement()!, skin: skin.randomElement()!, hair: hair.randomElement()!, style: Int.random(in: 0..<5), shirt: shirt.randomElement()!, glasses: Double.random(in: 0..<1) < 0.3)
    }
    /// Agents without a saved face get one from their id, the same one every time.
    static func seeded(_ id: String) -> Look {
        var h: UInt32 = 0
        for c in id.utf16 { h = h &* 31 &+ UInt32(c) }
        func at(_ a: [String], _ k: UInt32) -> String { a[Int((h >> k) % UInt32(a.count))] }
        return Look(bg: at(bg, 1), skin: at(skin, 4), hair: at(hair, 7), style: Int((h >> 10) % 5), shirt: at(shirt, 13), glasses: (h >> 16) % 10 < 3)
    }
    static func of(_ a: Agent) -> Look { a.look ?? seeded(a.id) }
}

struct FaceView: View {
    var look: Look
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 40
            ctx.scaleBy(x: k, y: k)
            ctx.clip(to: Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40)))
            let ink = Color(hex: "#151514")
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 40, height: 40)), with: .color(Color(hex: look.bg)))
            var shirt = Path()
            shirt.move(to: .init(x: 5, y: 44))
            shirt.addCurve(to: .init(x: 20, y: 30.5), control1: .init(x: 5, y: 35), control2: .init(x: 11.6, y: 30.5))
            shirt.addCurve(to: .init(x: 35, y: 44), control1: .init(x: 28.4, y: 30.5), control2: .init(x: 35, y: 35))
            shirt.closeSubpath()
            ctx.fill(shirt, with: .color(Color(hex: look.shirt)))
            let skin = Color(hex: look.skin), hair = Color(hex: look.hair)
            ctx.fill(Path(roundedRect: CGRect(x: 17, y: 24, width: 6, height: 7), cornerRadius: 2), with: .color(skin))
            ctx.fill(Path(ellipseIn: CGRect(x: 20 - 7.6, y: 19 - 8.6, width: 15.2, height: 17.2)), with: .color(skin))
            switch look.style {
            case 1: ctx.fill(FaceView.long, with: .color(hair))
            case 2:
                ctx.fill(Path(ellipseIn: CGRect(x: 16.4, y: 3, width: 7.2, height: 7.2)), with: .color(hair))
                ctx.fill(FaceView.crop, with: .color(hair))
            case 3:
                for (x, y) in [(13.0, 13.0), (15.5, 9.6), (19.5, 8.2), (23.6, 9.4), (26.6, 12.6), (12.6, 16.4), (27.4, 16.4), (17.5, 10.5), (22.0, 10.2)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.2, y: y - 3.2, width: 6.4, height: 6.4)), with: .color(hair))
                }
            case 4: ctx.fill(FaceView.short, with: .color(hair.opacity(0.9)))
            default: ctx.fill(FaceView.crop, with: .color(hair))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: 17.1 - 0.95, y: 19.4 - 0.95, width: 1.9, height: 1.9)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: 22.9 - 0.95, y: 19.4 - 0.95, width: 1.9, height: 1.9)), with: .color(ink))
            var mouth = Path()
            mouth.move(to: .init(x: 17.7, y: 23.1))
            mouth.addCurve(to: .init(x: 22.3, y: 23.1), control1: .init(x: 19, y: 24.1), control2: .init(x: 21, y: 24.1))
            ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            if look.glasses {
                var g = Path(ellipseIn: CGRect(x: 17 - 2.3, y: 19.2 - 2.3, width: 4.6, height: 4.6))
                g.addEllipse(in: CGRect(x: 23 - 2.3, y: 19.2 - 2.3, width: 4.6, height: 4.6))
                g.move(to: .init(x: 19.3, y: 19.2)); g.addLine(to: .init(x: 20.7, y: 19.2))
                ctx.stroke(g, with: .color(ink), lineWidth: 0.8)
            }
        }
        .clipShape(Circle())
    }

    static let crop: Path = {
        var p = Path()
        p.move(to: .init(x: 12.2, y: 18))
        p.addCurve(to: .init(x: 20, y: 7.7), control1: .init(x: 11.8, y: 11.4), control2: .init(x: 15.6, y: 7.7))
        p.addCurve(to: .init(x: 27.8, y: 18), control1: .init(x: 24.4, y: 7.7), control2: .init(x: 28.2, y: 11.4))
        p.addCurve(to: .init(x: 20, y: 13), control1: .init(x: 26.4, y: 14.6), control2: .init(x: 23.5, y: 13))
        p.addCurve(to: .init(x: 12.2, y: 18), control1: .init(x: 16.5, y: 13), control2: .init(x: 13.6, y: 14.6))
        p.closeSubpath()
        return p
    }()
    static let long: Path = {
        var p = Path()
        p.move(to: .init(x: 11.4, y: 19))
        p.addCurve(to: .init(x: 20, y: 7.7), control1: .init(x: 11.4, y: 11.5), control2: .init(x: 15.4, y: 7.7))
        p.addCurve(to: .init(x: 28.6, y: 19), control1: .init(x: 24.6, y: 7.7), control2: .init(x: 28.6, y: 11.5))
        p.addLine(to: .init(x: 28.6, y: 29)); p.addLine(to: .init(x: 24.9, y: 29)); p.addLine(to: .init(x: 24.9, y: 18))
        p.addCurve(to: .init(x: 15.1, y: 18), control1: .init(x: 23.2, y: 15), control2: .init(x: 16.8, y: 15))
        p.addLine(to: .init(x: 15.1, y: 29)); p.addLine(to: .init(x: 11.4, y: 29))
        p.closeSubpath()
        return p
    }()
    static let short: Path = {
        var p = Path()
        p.move(to: .init(x: 12.6, y: 16.8))
        p.addCurve(to: .init(x: 20, y: 8.4), control1: .init(x: 12.8, y: 11.2), control2: .init(x: 16, y: 8.4))
        p.addCurve(to: .init(x: 27.4, y: 16.8), control1: .init(x: 24, y: 8.4), control2: .init(x: 27.2, y: 11.2))
        p.addCurve(to: .init(x: 20, y: 13.8), control1: .init(x: 25.8, y: 14.8), control2: .init(x: 23.1, y: 13.8))
        p.addCurve(to: .init(x: 12.6, y: 16.8), control1: .init(x: 16.9, y: 13.8), control2: .init(x: 14.2, y: 14.8))
        p.closeSubpath()
        return p
    }()
}

/// The status mark in the avatar's corner: spinner, clay dot, white dot, red dot or a moon.
struct StatusMark: View {
    var state: AgentState
    var size: CGFloat
    var ground: Color
    var body: some View {
        let d = max(10, size * 0.3)
        ZStack {
            Circle().fill(ground).frame(width: d + 4, height: d + 4)
            Group {
                switch state {
                case .working:
                    TimelineView(.animation) { tl in
                        Circle().trim(from: 0, to: 0.75).stroke(T.i11, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                            .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
                            .padding(1)
                    }
                case .waiting: Circle().fill(T.wait)
                case .done: Circle().fill(T.i12)
                case .failed: Circle().fill(T.fail)
                case .ready:
                    Circle().fill(T.i9).mask {
                        Rectangle().overlay(Circle().offset(x: d * 0.3, y: -d * 0.2).blendMode(.destinationOut)).compositingGroup()
                    }
                    .rotationEffect(.degrees(-30))
                }
            }
            .frame(width: d - 4, height: d - 4)
        }
        .offset(x: 2, y: 2)
        .help(state.label)
    }
}

struct Avatar: View {
    var look: Look
    var size: CGFloat = 40
    var state: AgentState? = nil
    var ground: Color = T.work
    init(_ a: Agent, size: CGFloat = 40, state: AgentState? = nil, ground: Color = T.work) { look = Faces.of(a); self.size = size; self.state = state; self.ground = ground }
    init(look: Look, size: CGFloat = 40) { self.look = look; self.size = size }
    var body: some View {
        FaceView(look: look).frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) { if let state { StatusMark(state: state, size: size, ground: ground) } }
    }
}

/// The 72px ring around a crew member: grey, spinning, clay or red.
struct Halo: View {
    var state: AgentState
    var body: some View {
        ZStack {
            switch state {
            case .working:
                TimelineView(.animation) { tl in
                    Circle().trim(from: 0, to: 0.75).stroke(T.i11, lineWidth: 2)
                        .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360))
                }
            case .waiting: Circle().strokeBorder(T.wait, lineWidth: 2)
            case .failed: Circle().strokeBorder(T.fail, lineWidth: 2)
            default: Circle().strokeBorder(T.i5, lineWidth: 2)
            }
        }
        .frame(width: 72, height: 72)
    }
}

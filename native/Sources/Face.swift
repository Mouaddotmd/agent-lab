// The drawn faces, ported shape for shape from src/renderer/app.js (face, PAL, randLook). 40×40 box, clipped to a circle.
import SwiftUI

struct Look: Equatable {
    var bg: UInt32, skin: UInt32, hair: UInt32, shirt: UInt32, style: Int, glasses: Bool
    static let PAL = (
        bg: [0x3A4436, 0x47353F, 0x2F3A45, 0x45402F, 0x3B3A47, 0x44332F, 0x34413F] as [UInt32],
        skin: [0xF1CDB0, 0xE2B48F, 0xC99A78, 0xA8714F, 0x8D5B3F, 0x6B4430] as [UInt32],
        hair: [0x1F1A17, 0x3B2A20, 0x8A5A3B, 0xC6613F, 0xD9C7A8, 0x6E6A63] as [UInt32],
        shirt: [0xD97757, 0x7E9C8B, 0x5D6B8C, 0x9C6B85, 0xA9B98A, 0xB8A06A] as [UInt32])
    static func random() -> Look {
        Look(bg: PAL.bg.randomElement()!, skin: PAL.skin.randomElement()!, hair: PAL.hair.randomElement()!,
             shirt: PAL.shirt.randomElement()!, style: Int.random(in: 0..<5), glasses: Double.random(in: 0..<1) < 0.3)
    }
    /// The same face every time for an agent saved without one (web: seededLook).
    static func seeded(_ id: String) -> Look {
        var h: UInt32 = 0
        for c in id.utf16 { h = h &* 31 &+ UInt32(c) }
        func at(_ a: [UInt32], _ k: UInt32) -> UInt32 { a[Int((h >> k) % UInt32(a.count))] }
        return Look(bg: at(PAL.bg, 1), skin: at(PAL.skin, 4), hair: at(PAL.hair, 7), shirt: at(PAL.shirt, 13), style: Int((h >> 10) % 5), glasses: (h >> 16) % 10 < 3)
    }
    init(bg: UInt32, skin: UInt32, hair: UInt32, shirt: UInt32, style: Int, glasses: Bool) {
        self.bg = bg; self.skin = skin; self.hair = hair; self.shirt = shirt; self.style = style; self.glasses = glasses
    }
    init?(_ s: LookSpec?) {
        guard let s, let bg = Look.hex(s.bg), let skin = Look.hex(s.skin), let hair = Look.hex(s.hair), let shirt = Look.hex(s.shirt) else { return nil }
        self.init(bg: bg, skin: skin, hair: hair, shirt: shirt, style: s.style, glasses: s.glasses)
    }
    /// web: lookOf(a)
    static func of(_ a: Agent) -> Look { Look(a.look) ?? seeded(a.id) }
    var spec: LookSpec { LookSpec(bg: Look.str(bg), skin: Look.str(skin), hair: Look.str(hair), shirt: Look.str(shirt), style: style, glasses: glasses) }
    static func hex(_ s: String) -> UInt32? { UInt32(s.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) }
    static func str(_ v: UInt32) -> String { String(format: "#%06X", v) }
}

struct Face: View {
    let look: Look; var size: CGFloat = 40
    private static let crop = "M12.2 18c-.4-6.6 3.4-10.3 7.8-10.3s8.2 3.7 7.8 10.3c-1.4-3.4-4.3-5-7.8-5s-6.4 1.6-7.8 5z"
    var body: some View {
        Canvas { ctx, _ in
            let k = size / 40
            ctx.scaleBy(x: k, y: k)
            ctx.clip(to: Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40)))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 40, height: 40)), with: .color(Color(look.bg)))
            ctx.fill(SVGPath.parse("M5 44c0-9 6.6-13.5 15-13.5S35 35 35 44z"), with: .color(Color(look.shirt)))
            ctx.fill(Path(roundedRect: CGRect(x: 17, y: 24, width: 6, height: 7), cornerRadius: 2), with: .color(Color(look.skin)))
            ctx.fill(Path(ellipseIn: CGRect(x: 20 - 7.6, y: 19 - 8.6, width: 15.2, height: 17.2)), with: .color(Color(look.skin)))
            let hair = GraphicsContext.Shading.color(Color(look.hair))
            switch look.style {
            case 1: ctx.fill(SVGPath.parse("M11.4 19c0-7.5 4-11.3 8.6-11.3s8.6 3.8 8.6 11.3v10h-3.7V18c-1.7-3-8.1-3-9.8 0v11h-3.7z"), with: hair)
            case 2: ctx.fill(Path(ellipseIn: CGRect(x: 20 - 3.6, y: 6.6 - 3.6, width: 7.2, height: 7.2)), with: hair); ctx.fill(SVGPath.parse(Face.crop), with: hair)
            case 3:
                for (x, y) in [(13.0, 13.0), (15.5, 9.6), (19.5, 8.2), (23.6, 9.4), (26.6, 12.6), (12.6, 16.4), (27.4, 16.4), (17.5, 10.5), (22.0, 10.2)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.2, y: y - 3.2, width: 6.4, height: 6.4)), with: hair)
                }
            case 4:
                var c = ctx; c.opacity = 0.9
                c.fill(SVGPath.parse("M12.6 16.8c.2-5.6 3.4-8.4 7.4-8.4s7.2 2.8 7.4 8.4c-1.6-2-4.3-3-7.4-3s-5.8 1-7.4 3z"), with: hair)
            default: ctx.fill(SVGPath.parse(Face.crop), with: hair)
            }
            let ink = Color(0x151514)
            ctx.fill(Path(ellipseIn: CGRect(x: 17.1 - 0.95, y: 19.4 - 0.95, width: 1.9, height: 1.9)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: 22.9 - 0.95, y: 19.4 - 0.95, width: 1.9, height: 1.9)), with: .color(ink))
            ctx.stroke(SVGPath.parse("M17.7 23.1c1.3 1 3.3 1 4.6 0"), with: .color(ink), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            if look.glasses {
                let st = StrokeStyle(lineWidth: 0.8)
                ctx.stroke(Path(ellipseIn: CGRect(x: 17 - 2.3, y: 19.2 - 2.3, width: 4.6, height: 4.6)), with: .color(ink), style: st)
                ctx.stroke(Path(ellipseIn: CGRect(x: 23 - 2.3, y: 19.2 - 2.3, width: 4.6, height: 4.6)), with: .color(ink), style: st)
                ctx.stroke(SVGPath.parse("M19.3 19.2h1.4"), with: .color(ink), style: st)
            }
        }
        .frame(width: size, height: size)
    }
}

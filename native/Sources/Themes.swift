// Themes: the whole app recoloured, the same look in every one. Every colour token (C, Color.white, MARK_BLUE) is a
// live colour that reads the theme as it's drawn, so switching (or previewing on hover) recolours every window at once
// without rebuilding anything: what you typed, where you scrolled and the menu you're in all stay.
//
// The presets are mouad.work's (which came from Mavis Glass), value for value, in Light and Dark: Old Mac look,
// Modern, Balanced and Modern, Modern v2. "Agent Lab" is the app's own Vercel set (its dark is the look it always had).
import SwiftUI
import AppKit

/// One theme: the app's tokens, filled.
struct ThemePalette: Equatable, Identifiable {
    let id: String          // "agentlab.dark", "mod.light" …
    let name: String        // "Modern"
    let dark: Bool
    /// Frame (top bar, sidebar), panel (chat, menus), raised (the chat box, cards), hover, lines, outlines, strong lines.
    let v0, v1, v2, v3, v4, v5, v6: UInt32
    /// Quiet, faint and strong text.
    let i9, i10, i12: UInt32
    /// What thin lines and soft fills are made of (white on dark, the ink's cool grey on light).
    let ink: UInt32
    let primaryHover: UInt32
    /// Links and highlights (mouad.work's blue).
    let blue: UInt32
    var mode: String { dark ? "Dark" : "Light" }
}

/// The theme being drawn now (read by every live colour as it draws).
nonisolated(unsafe) var themeNow: ThemePalette = Palettes.saved()

enum Palettes {
    // mouad.work's variables, light then dark, before any preset changes them.
    private struct Vars {
        var chat: UInt32, plateA: UInt32, plateB: UInt32, card: UInt32, ctlA: UInt32, ctlB: UInt32
        var ink: UInt32, ink3: UInt32, ink4: UInt32, ctlRing: UInt32, rule: UInt32, hover: Double
    }
    private static let lightBase = Vars(chat: 0xf7f8fa, plateA: 0xf9fafb, plateB: 0xe1e4e8, card: 0xffffff, ctlA: 0xffffff, ctlB: 0xffffff,
                                        ink: 0x1b1e22, ink3: 0x666b71, ink4: 0xa8abb0, ctlRing: 0xbbbec2, rule: 0x172232, hover: 0.055)
    private static let darkBase = Vars(chat: 0x202327, plateA: 0x31343a, plateB: 0x282c30, card: 0x2e3237, ctlA: 0x44484e, ctlB: 0x3b3f44,
                                       ink: 0xeef0f3, ink3: 0x9a9fa6, ink4: 0x575b62, ctlRing: 0x3a3c40, rule: 0xd9e6f9, hover: 0.08)

    /// A mouad.work preset in the app's tokens: the toolbar plate is the frame, the chat surface the panel, cards are
    /// raised, controls and the site's hover tint are the fills, its ring the outline.
    private static func make(_ id: String, _ name: String, dark: Bool, _ edit: (inout Vars) -> Void) -> ThemePalette {
        var v = dark ? darkBase : lightBase
        edit(&v)
        if dark {
            return ThemePalette(id: id + ".dark", name: name, dark: true, v0: v.plateB, v1: v.chat, v2: v.card, v3: v.ctlB, v4: v.ctlA,
                           v5: mix(v.ctlA, v.ink, 0.12), v6: v.ink4, i9: mix(v.ink3, v.ink4, 0.35), i10: v.ink3, i12: v.ink,
                           ink: v.rule, primaryHover: mix(v.ink, 0x000000, 0.12), blue: 0x3592fa)
        }
        return ThemePalette(id: id + ".light", name: name, dark: false, v0: v.plateB, v1: v.chat, v2: v.card, v3: mix(v.chat, v.rule, v.hover),
                       v4: mix(v.chat, v.rule, v.hover * 1.7), v5: v.ctlRing, v6: v.ink4, i9: mix(v.ink3, v.ink4, 0.45), i10: v.ink3, i12: v.ink,
                       ink: v.rule, primaryHover: mix(v.ink, 0xffffff, 0.18), blue: 0x0a7aff)
    }

    // The app's own set: Vercel's greys (dark is the look Agent Lab always had; light is the same scale turned over).
    static let agentLabDark = ThemePalette(id: "agentlab.dark", name: "Agent Lab", dark: true, v0: 0x000000, v1: 0x0a0a0a, v2: 0x111111, v3: 0x1a1a1a,
                                      v4: 0x1f1f1f, v5: 0x2e2e2e, v6: 0x454545, i9: 0x878787, i10: 0xa1a1a1, i12: 0xededed,
                                      ink: 0xffffff, primaryHover: 0xd4d4d4, blue: 0x3592fa)
    static let agentLabLight = ThemePalette(id: "agentlab.light", name: "Agent Lab", dark: false, v0: 0xf5f5f5, v1: 0xffffff, v2: 0xfafafa, v3: 0xf2f2f2,
                                       v4: 0xebebeb, v5: 0xe0e0e0, v6: 0xc9c9c9, i9: 0x8f8f8f, i10: 0x666666, i12: 0x171717,
                                       ink: 0x000000, primaryHover: 0x383838, blue: 0x0a7aff)

    // MAVIS (docs/mavis-system.md §2): the new look. Two tones (page #1a1a1a, card #2a2a2a) on a #141414 frame,
    // one accent blue. The values are MV's (Sources/MavisSystem.swift), mapped onto the theme slots.
    static let mavisDark = ThemePalette(id: "mavis.dark", name: "MAVIS", dark: true, v0: 0x141414, v1: 0x1a1a1a, v2: 0x2a2a2a, v3: 0x333333,
                                   v4: 0x3a3a3a, v5: 0x2e2e2e, v6: 0x474747, i9: 0x9e9e9e, i10: 0xbdbdbd, i12: 0xe6e6e6,
                                   ink: 0xffffff, primaryHover: 0xd9d9d9, blue: 0x789aff)

    static let all: [ThemePalette] = {
        // Old Mac look (data-t=bal): "properly light first, with titanium clearly there".
        let bal: (Bool) -> ThemePalette = { d in make("bal", "Old Mac look", dark: d) { v in
            if d { v.plateA = 0x232528; v.plateB = 0x232528; v.ctlRing = 0x3a3c40; v.ctlA = 0x2d2f32; v.ctlB = 0x2d2f32; v.card = 0x2d2f32; v.chat = 0x1c1e21 }
            else { v.plateA = 0xfbfcfd; v.plateB = 0xe4e6e9; v.ctlRing = 0xb8bbbe; v.chat = 0xfbfbfd }
        } }
        // Modern (data-t=mod): "white first, with grey only as the second surface".
        func mod(_ v: inout Vars, _ d: Bool) {
            if d { v.plateA = 0x1d1e20; v.plateB = 0x1d1e20; v.ctlRing = 0x313235; v.ctlA = 0x2a2b2e; v.ctlB = 0x2a2b2e; v.card = 0x2a2b2e; v.chat = 0x141517; v.ink = 0xececee }
            else { v.plateA = 0xffffff; v.plateB = 0xf3f4f6; v.ctlRing = 0xdee0e3; v.chat = 0xffffff; v.ink3 = 0x62666d; v.hover = 0.05 }
        }
        let modern: (Bool) -> ThemePalette = { d in make("mod", "Modern", dark: d) { mod(&$0, d) } }
        // Balanced and Modern (data-t=mod, data-bar=bal): Modern with the Old Mac look's toolbar.
        let bm: (Bool) -> ThemePalette = { d in make("bm", "Balanced and Modern", dark: d) { v in
            mod(&v, d)
            if d { v.plateA = 0x232528; v.plateB = 0x232528; v.ctlRing = 0x3a3c40; v.ctlA = 0x2d2f32; v.ctlB = 0x2d2f32; v.ink = 0xeef0f3 }
            else { v.plateA = 0xfbfcfd; v.plateB = 0xe4e6e9; v.ctlRing = 0xb8bbbe }
        } }
        // Modern v2 (data-t=mod, data-bar=v2): Modern with a toolbar a touch less white (a half step above, in dark).
        let mv2: (Bool) -> ThemePalette = { d in make("mv2", "Modern v2", dark: d) { v in
            mod(&v, d)
            if d { v.plateA = 0x202125; v.plateB = 0x202125; v.ctlRing = 0x38393e; v.ctlA = 0x2c2d31; v.ctlB = 0x2c2d31 }
            else { v.plateA = 0xfbfcfd; v.plateB = 0xeef0f3; v.ctlRing = 0xd7d9dd }
        } }
        return [mavisDark, agentLabDark, bal(true), modern(true), bm(true), mv2(true),
                agentLabLight, bal(false), modern(false), bm(false), mv2(false)]
    }()

    static func named(_ id: String) -> ThemePalette? { all.first { $0.id == id } }
    static func saved() -> ThemePalette { named(UserDefaults.standard.string(forKey: "theme") ?? "") ?? agentLabDark }

    /// a → b by t, per channel (as the site's colour mixes).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ x: UInt32, _ s: UInt32) -> Double { Double((x >> s) & 255) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) + (ch(b, s) - ch(a, s)) * t).rounded()) << s }
        return m(16) | m(8) | m(0)
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}

extension Color {
    /// A token that reads the theme as it's drawn.
    static func live(_ key: KeyPath<ThemePalette, UInt32>, _ alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in NSColor(rgb: themeNow[keyPath: key], alpha: alpha) })
    }
    /// The theme's ink at an opacity: white on a dark theme, the ink's grey on a light one. Hairlines and soft fills
    /// (under 0.2) are a little stronger on light, where the same opacity of a dark ink reads fainter.
    static func ink(_ a: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            let t = themeNow
            return NSColor(rgb: t.ink, alpha: CGFloat(t.dark || a >= 0.2 ? a : min(a * 2.2, 0.3)))
        })
    }
}

/// The theme chosen, and the one shown while you hover a theme in the menu.
@MainActor final class Themes: ObservableObject {
    static let shared = Themes()
    @Published private(set) var chosen: ThemePalette = themeNow
    @Published private(set) var previewing: String?

    /// Shows `id` everywhere at once, until you choose or leave (nil puts the chosen one back).
    func preview(_ id: String?) {
        guard previewing != id else { return }
        previewing = id
        show(id.flatMap(Palettes.named) ?? chosen)
    }
    func choose(_ id: String) {
        guard let p = Palettes.named(id) else { return }
        chosen = p; previewing = nil
        UserDefaults.standard.set(id, forKey: "theme")
        show(p)
    }
    /// Bumped on every switch (the theme panel and anything else that wants to know).
    @Published private(set) var epoch = 0
    /// Which of the mode's two appearances the windows are on: a switch moves them to the other one, and that is what
    /// makes every live colour be worked out again, with nothing rebuilt (what you typed, scrolled or opened stays).
    private var alternate = false
    /// Draws every window in `p`.
    func show(_ p: ThemePalette) {
        guard p != themeNow || epoch == 0 else { return }
        themeNow = p
        alternate.toggle()
        let look = NSAppearance(named: p.dark ? (alternate ? .vibrantDark : .darkAqua) : (alternate ? .vibrantLight : .aqua))
        NSApp.appearance = NSAppearance(named: p.dark ? .darkAqua : .aqua)
        for w in NSApp.windows {
            w.appearance = look
            if w.isOpaque { w.backgroundColor = NSColor(rgb: p.v0) }
            w.invalidateShadow()
        }
        epoch += 1
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    static let changed = Notification.Name("agentlab.themeChanged")
}

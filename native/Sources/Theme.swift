// Agent Lab, native. Every value here is measured from the web app (src/renderer), which is the spec.
// Rule: if a number here differs from what Chrome renders, this file is wrong, not the web app.
import SwiftUI
import AppKit
import CoreText

extension Color {
    init(_ hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: a)
    }
    /// The theme's ink at an opacity (white on a dark theme): Themes.swift.
    static func white(_ a: Double) -> Color { .ink(a) }
}

/// The app's colour tokens. Each is live: it reads the theme being drawn (Themes.swift), so the same names give the
/// Vercel set Agent Lab always had, or any preset, in light or dark.
enum C {
    static let v0 = Color.live(\.v0)      // frame
    static let v1 = Color.live(\.v1)      // panel, cards' wells, buttons
    static let v2 = Color.live(\.v2)
    static let v3 = Color.live(\.v3)      // hover on buttons
    static let v4 = Color.live(\.v4)      // lines
    static let v5 = Color.live(\.v5)      // control outlines
    static let v6 = Color.live(\.v6)
    static let i9 = Color.live(\.i9)
    static let i10 = Color.live(\.i10)    // faint text, icons
    static let i12 = Color.live(\.i12)    // strong text
    /// Outlines, kept almost out of sight: a hair of the ink over whatever surface they sit on, so a card or field reads
    /// by its fill and the edge only confirms it. `edge` for surfaces (cards, the chat box, panels), `edgeControl` for
    /// things you type into or press (fields, buttons). `divider` for the 1 pt lines between rows and sections.
    static let edge = Color.ink(0.035)
    static let edgeControl = Color.ink(0.055)
    static let divider = Color.ink(0.05)
    static let sel = Color.ink(0.10)     // selected sidebar row
    static let rowHover = Color.ink(0.06)
    static let split = Color.live(\.v4, 0.6)
    static let primaryHover = Color.live(\.primaryHover)
    static let lightRed = Color(0xff5f57), lightYellow = Color(0xfebc2e), lightGreen = Color(0x28c840)
}

/// Corner, height and spacing scale (CSS: --rad-*, --h-*).
enum R {
    static let xs: CGFloat = 6, ctl: CGFloat = 10, card: CGFloat = 14, win: CGFloat = 16
    /// Concentric corners: a shape inset `pad` inside a shape of radius `outer` gets `outer - pad`, so both curves share a centre.
    static func inset(_ outer: CGFloat, by pad: CGFloat) -> CGFloat { max(outer - pad, 0) }
}

/// The chat box, on a 4 pt step: the controls inside keep the app's control corner (10), the box adds its padding to
/// that (10 + 8 = 18) so the two curves stay concentric. Controls that belong together sit `pair` apart; the words get
/// `gap` of room on each side.
enum Box {
    static let pad: CGFloat = 8          // 2 steps
    static let pair: CGFloat = 4         // 1 step
    static let gap: CGFloat = 12         // 3 steps
    static let inner: CGFloat = R.ctl
    static let corner: CGFloat = inner + pad
    /// The chat box's room above the window's foot (it floats, as Claude Code's does).
    static let lift: CGFloat = 28
}

/// Anthropic Sans Text, the same files the web app loads.
enum F {
    /// Chrome draws with -webkit-font-smoothing: antialiased (no stroke thickening). Match it.
    static func antialiased() { UserDefaults.standard.set(0, forKey: "AppleFontSmoothing") }
    static func register() {
        antialiased()
        let dirs: [URL] = [
            Bundle.main.resourceURL,
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("../../../src/renderer/fonts"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("src/renderer/fonts"),
            ProcessInfo.processInfo.environment["AGENTLAB_FONTS"].map { URL(fileURLWithPath: $0) },
        ].compactMap { $0 }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let otf = files.filter { $0.pathExtension == "otf" }
            if otf.isEmpty { continue }
            for f in otf { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
            return
        }
    }
    enum W { case regular, medium, semibold }
    static func font(_ size: CGFloat, _ w: W) -> Font {
        switch w {
        case .regular: return .custom("AnthropicSansText-Regular", fixedSize: size)
        case .medium: return .custom("AnthropicSansText-Medium", fixedSize: size)
        case .semibold: return .custom("AnthropicSansText-Semibold", fixedSize: size)
        }
    }
    /// The CSS line height for a size: round(1.25em + 2.5px) to the 4px grid (12/16 14/20 16/24 20/28 24/32 28/36).
    static func lh(_ size: CGFloat) -> CGFloat { (((1.25 * size + 2.5) / 4).rounded()) * 4 }
    /// The font's own content height (ascent + descent), which CSS centres inside the line box.
    static func content(_ size: CGFloat) -> CGFloat { size * 1.25 }
}

/// One line of text exactly as CSS lays it out: a line box of `lh`, glyphs centred in it.
struct Line: View {
    let text: String; let size: CGFloat; let weight: F.W; var color: Color = C.i12; var tracking: CGFloat = 0
    init(_ text: String, _ size: CGFloat, _ weight: F.W, _ color: Color = C.i12, tracking: CGFloat = 0) {
        self.text = text; self.size = size; self.weight = weight; self.color = color; self.tracking = tracking
    }
    @Environment(\.displayScale) private var scale
    var body: some View {
        // CSS centres the glyphs in the line box, then Chrome snaps the baseline down to the device-pixel grid.
        let lh = F.lh(size), top = (((lh - F.content(size)) / 2) * scale).rounded(.down) / scale
        Text(text).font(F.font(size, weight)).tracking(tracking).foregroundStyle(color)
            // Its natural width when there's room; in a tight space it ends in "…" instead of pushing its row (and
            // everything after it) out of the window.
            .lineLimit(1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            .padding(.top, top).frame(height: lh, alignment: .top)
    }
}

/// A paragraph with CSS line height: extra leading split above and below each line.
struct Para: View {
    let text: String; let size: CGFloat; let weight: F.W; var color: Color; var align: TextAlignment = .leading; var lh: CGFloat? = nil
    @Environment(\.displayScale) private var scale
    var body: some View {
        // SwiftUI lays each line at ceil(1.25 × size); CSS at `lh` with the glyphs centred (half-leading).
        // Spacing makes up the difference; the padding puts the first baseline where Chrome does (snapped down to device pixels).
        let l = lh ?? F.lh(size), natural = (1.25 * size).rounded(.up), top = (((l - F.content(size)) / 2) * scale).rounded(.down) / scale
        Text(text).font(F.font(size, weight)).foregroundStyle(color)
            .lineSpacing(l - natural).multilineTextAlignment(align)
            .padding(.top, top).padding(.bottom, l - natural - top)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// What floats over everything (menus, sheets, dialogs): a crisp 1 pt drop and one short shadow under it, never a big
    /// soft blur (a 20 pt blur ran past a menu's window and was cut off square over light pages, 19 Nov).
    /// MAVIS: nothing that pops up casts a shadow (menus, tips, cards): its edge is its outline.
    func floatShadow() -> some View {
        shadow(color: .black.opacity(MV.on ? 0 : 0.5), radius: 1, y: 1)
            .shadow(color: .black.opacity(MV.on ? 0 : 0.4), radius: 8, y: 6)
    }
}

/// A tab's own toolbar in the side panel (Browser's address bar, a file's actions, Changes' views): one height for all,
/// one control size inside it, its corners concentric with the panel's 40 pt header controls.
enum Bar {
    static let height: CGFloat = 48
    static let control: CGFloat = 32
    static let radius: CGFloat = 8
}

/// An icon in a tab's toolbar: quiet until you're on it, lit while it's on.
struct ToolIcon: View {
    let symbol: String; let label: String; var keys: String? = nil; var enabled = true; var on = false
    let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                    .foregroundStyle(!enabled ? C.v6 : h || on ? C.i12 : C.i10)
                    .frame(width: Bar.control, height: Bar.control)
                    .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(enabled && on ? C.v4 : enabled && h ? C.v3 : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(Press()).disabled(!enabled)
        }
        .tip(label, keys).accessibilityLabel(label)
    }
}

/// Words in a tab's toolbar (Find, Reveal, a view to pick): quiet until you're on it, lit while it's on.
struct ToolText: View {
    let title: String; var on = false
    let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Text(title).font(F.font(13, .medium)).foregroundStyle(on || h ? C.i12 : C.i10).lineLimit(1)
                    .padding(.horizontal, 10).frame(height: Bar.control)
                    .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(on ? C.v4 : h ? C.v3 : .clear))
                    .contentShape(Rectangle())
            }.buttonStyle(Press())
        }
    }
}

// The MAVIS system in code: every colour, size, gap, corner, stroke and curve the new look uses, by name.
// Spec: docs/mavis-system.md (sections 2–10 and 11b). Prototype: ~/Desktop/Agent Hub/mavis-window/mavis-window.html.
// Rule: views use these names, never their own numbers. tools/systemlint.py fails the build when a raw number or
// colour is added outside this file and the theme files. A value that isn't here goes into the spec first, then here.
import SwiftUI

enum MV {
    /// The MAVIS layout is on while the MAVIS theme is: the theme is the switch for the whole move (spec 14).
    static var on: Bool { themeNow.id.hasPrefix("mavis") }

    // MARK: Window shell (prototype: rail 72 with the lights on it, no top bar, surfaces float 12 down and 8 in)
    enum Shell {
        static let lightsX: CGFloat = 16, lightsY: CGFloat = 14, lightsStep: CGFloat = 20, light: CGFloat = 12
        static let railTop: CGFloat = 54          // first rail tile's top
        static let railGap: CGFloat = 8           // between rail tiles
        static let railDivider = CGSize(width: 32, height: 1)
        static let surfaceTop: CGFloat = 12       // the strip above the surfaces (prototype: panes at y 12)
        static let railBottom: CGFloat = 14
    }

    // MARK: Colour (spec 2). Dark only for now; a light set comes with mavis.light.
    enum Tone {
        static let frame = Color(0x141414)     // window behind the surfaces
        static let page = Color(0x1a1a1a)      // main surfaces; things that sit inside cards
        static let omni = Color(0x222222)      // address bar, profile bar
        static let box = Color(0x2a2a2a)       // cards, chatboxes
        static let toolbar = Color(0x2b2b2b)   // browser toolbar, pane bodies
        static let sel = Color(0x2f2f2f)       // selected row
        static let box2 = Color(0x333333)      // card hover, neutral chips, browser tab
        static let line = Color(0x3a3a3a)      // dividers inside panes
        static let hairline = Color(0x2e2e2e)  // the 0.5 pt edge of every surface
        static let listEdge = Color(0xffffff, 0.03)  // the list column's 1 pt outline (prototype .lpanel)
        static let term = Color(0x161616)      // terminal body
        static let pill = Color(0x1f1f1f)      // the pills under a chatbox (Mode, context)
    }
    enum Ink {
        static let t1 = Color(0xe6e6e6)        // primary text
        static let t2 = Color(0xbdbdbd)        // secondary text, idle icons
        static let t3 = Color(0x9e9e9e)        // meta text (4.5:1 on box and box2)
        static let onWhite = Color(0x141414)   // text and icons on the white button
    }
    enum Accent {
        static let blue = Color(0x789aff)      // unread, context ring, selected workspace, focus, your bubble (22%)
        static let bubble = Color(0x789aff, 0.22)
        static let red = Color(0xf2b8b5)
        /// Lines added and removed (+352 −1), as Claude's: Google's green and red on dark.
        static let added = Color(0x81c995), removed = Color(0xf28b82)
        static let doneText = Color(0x8fdcb4)
        static let doneFill = Color(0x8fdcb4, 0.14)
        static let statusOn = Color(0x34a853)
        static let badge = Color(0xe5483c)       // the red count (Discord's): needs you, unread replies
        static let statusIdle = Color(0x80868b)
        static let tagDesign = Color(0xc58af9), tagLaunch = Color(0xfdd663), tagBackend = Color(0x81c995)
        static let clay = Color(0xe8875f), clayTile = Color(0x4a2a1f)        // a Claude Code agent's face
        static let selected = Color(0x789aff, 0.16)                         // a selected list row
        static let selectedSolid = Color(0x262c3d)                          // that wash over the frame (for rings)
        static let selectedText = Color(0xc4d1ff)                           // words on a selected row
        static let onTag = Color(0x1f1f1f)
    }
    /// White washes (Chromium's interaction states).
    enum Wash {
        static let hover = Color(0xffffff, 0.07)    // small controls
        static let stHover = Color(0xffffff, 0.10)  // icon buttons, rail
        static let stPress = Color(0xffffff, 0.16)
        static let selectedRow = Color(0xffffff, 0.10)
    }

    // MARK: Strokes (spec 1, 7)
    enum Stroke {
        static let surface: CGFloat = 0.5                       // hairline in Tone.hairline
        static let list: CGFloat = 1                            // the list column's outline in Tone.listEdge
        static let boxRest = Color(0xffffff, 0.04), boxHover = Color(0xffffff, 0.08), boxTyping = Color(0xffffff, 0.12)
        static let boxRestWidth: CGFloat = 1, boxTypingWidth: CGFloat = 2
        static let focus: CGFloat = 2, focusGap: CGFloat = 2   // in Accent.blue
        static let dotRing: CGFloat = 3                         // status dot ring, in the colour under it
        static let idleRing: CGFloat = 2                        // an idle agent's hollow dot
    }

    // MARK: Corners (spec 4–8; Material 3 steps)
    enum Radius {
        static let window: CGFloat = 16
        static let surface: CGFloat = 14
        static let card: CGFloat = 16
        static let tile: CGFloat = 12        // agent tile, list row, avatar box
        static let list: CGFloat = 12        // the list column's top corners
        static let rail: CGFloat = 18        // rail buttons, workspace tiles, profile button
        static let homeBox: CGFloat = 24
        static let chatBox: CGFloat = 26
        static let tag: CGFloat = 5
        static let preview: CGFloat = 12
        // pills, chips, icon buttons, send: fully round (Capsule / Circle)
    }

    // MARK: Sizes (spec 4–8)
    enum Size {
        static let window = CGSize(width: 1280, height: 800)
        static let rail: CGFloat = 80, railButton: CGFloat = 56     // Discord-size tiles: a workspace's picture reads at a glance
        static let header: CGFloat = 44                 // chat, pane, browser tab strip and toolbar
        static let siteIconRadius: CGFloat = 3
        static let iconButton: CGFloat = 28, icon: CGFloat = 18, iconSmall: CGFloat = 16, iconLarge: CGFloat = 22
        static let pill: CGFloat = 28, chip: CGFloat = 24, tag: CGFloat = 20, badge: CGFloat = 18
        static let tile: CGFloat = 44, dot: CGFloat = 12, statusRing: CGFloat = 18, faceIcon: CGFloat = 24
        static let avatar: CGFloat = 36, avatarButton: CGFloat = 48
        static let chatBox: CGFloat = 52, chatButton: CGFloat = 40
        static let homeSend: CGFloat = 36, agentChip: CGFloat = 36
        static let listWidth: CGFloat = 304, listRow: CGFloat = 66
        static let fileRow: CGFloat = 32, agentRow: CGFloat = 60
        static let sideColumn: CGFloat = 392
        static let todayWidth: CGFloat = 316
        static let profileBar = CGSize(width: 355, height: 58)
        static let browserTab = CGSize(width: 176, height: 30), addressBar: CGFloat = 34
    }

    // MARK: Spacing (4 pt grid, 2 pt steps inside controls)
    enum Space {
        static let gutter: CGFloat = 8          // between surfaces and to the window edge
        static let inset: CGFloat = 12          // inside every card
        static let section: CGFloat = 24        // between sections
        static let labelGap: CGFloat = 8        // section label to its content
        static let cardGap: CGFloat = 12        // stacked cards
        static let gridGap: CGFloat = 10        // cards side by side
        static let rowGap: CGFloat = 2          // file rows
        static let xs: CGFloat = 4, sm: CGFloat = 6   // small steps inside cards
        static let headerEdge: CGFloat = 8      // last header button to the edge
        static let headerLead: CGFloat = 16     // chat header title from the edge (panes 14)
        static let paneLead: CGFloat = 14
        static let indent: CGFloat = 20         // per tree level
        static let edgeControl: CGFloat = 10    // Home chatbox controls from its edges
    }

    // MARK: Type (spec 3), Anthropic Sans 400 / 500
    enum Text {
        static let greeting: CGFloat = 30, greetingLine: CGFloat = 38, greetingTracking: CGFloat = -0.3
        static let listTitle: CGFloat = 24
        static let panelTitle: CGFloat = 18
        static let name: CGFloat = 15, nameLine: CGFloat = 22
        static let message: CGFloat = 14.5, messageLine: CGFloat = 23
        static let title: CGFloat = 14, titleLine: CGFloat = 20
        static let preview: CGFloat = 14, previewLine: CGFloat = 21
        static let body: CGFloat = 12.5, bodyLine: CGFloat = 18
        static let control: CGFloat = 12.5
        static let meta: CGFloat = 12
        static let footer: CGFloat = 13
        static let tag: CGFloat = 11.5
        static let mono: CGFloat = 12, monoLine: CGFloat = 18
        static let homeInput: CGFloat = 15.5, chatInput: CGFloat = 15
    }

    // MARK: Home (spec 6–7; prototype Home)
    enum Home {
        static let column: CGFloat = 720          // the greeting, chatbox and cards share it, centred
        static let sides: CGFloat = 40
        static let inputLine: CGFloat = 24        // the chatbox's one text line
        static let boxTop: CGFloat = 16, boxLead: CGFloat = 20
        static let playNudge: CGFloat = 1         // the play icon is optically left-heavy
        static let chipTile: CGFloat = 22, chipText: CGFloat = 13.5, chipInset: CGFloat = 7
        static let labelLine: CGFloat = 20, labelInset: CGFloat = 0     // flush with the cards under it
        static let tagPad: CGFloat = 7
        static let dotOffset: CGFloat = 4         // the status dot sits 4 past the tile's corner
    }
    // MARK: Browser pane (prototype .bp)
    enum Browser {
        static let disabled: Double = 0.45        // back / forward when they can't act
        static let site: CGFloat = 26             // the lock's circle in the address
        static let address: CGFloat = 13.5
        static let addressRadius: CGFloat = 17          // the address bar's ends (half its 34)
        static let addressLine: CGFloat = 18
        static let editing = Tone.box2                  // the bar and its rows while you type (Chrome lifts it a step)
        static let takeOver = Color(0x1a73e8)     // the take-over button (open question: move to Accent.blue?)
        static let tabText: CGFloat = 12
        static let tabMin: CGFloat = 40            // Chrome: tabs narrow to this, never scroll away
        static let tabTitleMin: CGFloat = 72       // narrower: icon only
        static let tabCloseMin: CGFloat = 96, tabCloseAlways: CGFloat = 140
        static let separator: CGFloat = 16
        static let tabGap: CGFloat = 6             // between tabs, and before + (prototype strip gap)
        static let closeSlot: CGFloat = 20         // a tab's ✕, always inside the tab
        static let fadeFrom: CGFloat = 0.7         // the title fades out over its last 30%
        static let maxTabs = 15                    // + stops here; a page opened past it loads in the tab in front
    }

    // MARK: Terminal pane (prototype .term), as CSS for the xterm page
    enum Terminal {
        static let background = "#161616"
        static let inset = "inset: 10px 14px 12px 14px"
        static let font = "fontSize: 12, lineHeight: 1.5"
    }

    // MARK: Files pane (prototype .ftree / .fr)
    enum Files {
        static let row: CGFloat = 32, rowGap: CGFloat = 2
        static let indent: CGFloat = 20, lead: CGFloat = 8, trail: CGFloat = 12
        static let text: CGFloat = 13
        static let chevron: CGFloat = 16
        static let treePad = EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8)
        static let badgeAdded = Color(0x81c995), badgeChanged = Color(0xfdd663)
        static let badgeText: CGFloat = 11, badgePad: CGFloat = 5
    }

    // MARK: Resizing (the gaps between surfaces are the handles)
    enum Resize {
        static let grip: CGFloat = 4, gripLength: CGFloat = 24
        static let sideMin: CGFloat = 320, chatMin: CGFloat = 380, sideDefault: CGFloat = 460
        static let listMin: CGFloat = 240, listMax: CGFloat = 440
    }

    // MARK: The browser's new-tab box over a page (Arc's)
    enum Launcher {
        static let width: CGFloat = 560
        static let top: CGFloat = 0.2           // of the pane's height
        static let dim: Double = 0.3            // the page under it
        static let lead: CGFloat = 16           // the field row's inset
    }

    // MARK: Profile bar (prototype .up)
    enum Profile {
        static let radius: CGFloat = 18
        static let dot: CGFloat = 10
        static let button: CGFloat = 36, buttonRadius: CGFloat = 8
    }

    // MARK: Lists beside a chat (Messages, a workspace's sidebar)
    enum List {
        static let header: CGFloat = 52           // the title row
    }

    // MARK: Pages nobody designed (spec 11b): Discover, Usage, Plugins, Profile
    enum Pages {
        static let cardIcon: CGFloat = 36
    }

    // MARK: Workspace (prototype .ws-h, .cat, .sb-row, .crumb, .crew, .start)
    enum Workspace {
        static let categoryColors = [Color(0xc58af9), Color(0x81c995), Color(0xfdd663)]   // in category order
        /// What a category can be coloured (right-click it): Google's pastel set on dark, the first three the defaults.
        static let tagColors: [(name: String, hex: String)] = [("Purple", "#c58af9"), ("Green", "#81c995"), ("Yellow", "#fdd663"),
            ("Blue", "#8ab4f8"), ("Red", "#f28b82"), ("Orange", "#fcad70"), ("Pink", "#ff8bcb"), ("Cyan", "#78d9ec"), ("Grey", "#bdbdbd")]
        /// A category's colour: its own, else the default for its place.
        static func color(_ c: WorkspaceCategory?, at i: Int) -> Color {
            if let hex = c?.color, let own = Color(cssHex: hex) { return own }
            return categoryColors[i % categoryColors.count]
        }
        static let agentsColor = Color(0xbdbdbd)
        static let tile: CGFloat = 26
        static let headTile: CGFloat = 40         // the workspace head's picture: as tall as its two lines
        static let tag: CGFloat = 22, catHeader: CGFloat = 30, lineOpacity: Double = 0.7
        static let row: CGFloat = 36
        static let selectedIcon = Color(0x9db5ff)
        static let smallButton: CGFloat = 24, headButton: CGFloat = 32
        static let swatch: CGFloat = 12           // the colour dots in a category's Colour menu
        static let tagLit: CGFloat = 1.3          // a category's tag on hover: brightness(1.3) saturate(1.3)
        static let pressed: Double = 0.7          // a category's bare + and arrow while pressed
        static let moreHover = Tone.line          // ⋯ under the pointer: a step lighter than the row's own hover
        static let moreMinRadius: CGFloat = 10    // ⋯ never squarer than this (rounder than the bare sum)
        static let moreOnSelected = Color(0x789aff, 0.3)   // ⋯ on a selected row: the row's blue, stronger
        static let divider = Color(0xffffff, 0.05)  // between rows in a card (prototype .card .row+.row)
    /// CSS brightness(1.3) saturate(1.3): each channel ×1.3, then saturation ×1.3.
    static func lit(_ c: Color) -> Color {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
        let k = MV.Workspace.tagLit
        let b = NSColor(srgbRed: min(1, n.redComponent * k), green: min(1, n.greenComponent * k), blue: min(1, n.blueComponent * k), alpha: n.alphaComponent)
        return Color(nsColor: NSColor(hue: b.hueComponent, saturation: min(1, b.saturationComponent * k), brightness: b.brightnessComponent, alpha: b.alphaComponent))
    }
        static let pathGap: CGFloat = 5, pathIcon: CGFloat = 12
        static let crew: CGFloat = 30, crewFace: CGFloat = 22, crewRadius: CGFloat = 7
        static let startTitle: CGFloat = 28, startTracking: CGFloat = -0.2
        static let ledeSpacing: CGFloat = 8, ledeWidth: CGFloat = 600
        static let chipLead: CGFloat = 9, chipsTop: CGFloat = 14, startBottom: CGFloat = 22
    }

    // MARK: Chat (spec 9)
    enum Chat {
        static let bubbleLead: CGFloat = 96       // your bubble never starts closer than this to the left
        static let bubbleX: CGFloat = 16, bubbleY: CGFloat = 10, bubbleRadius: CGFloat = 22   // a one-line bubble is a full pill
        static let readWidth: CGFloat = 640       // the agent's words
        static let sides: CGFloat = 32            // transcript padding left and right
        static let column: CGFloat = 720          // the conversation and its box never grow wider; centred in the surface
        static let inputLine: CGFloat = 24        // the box's line height; placeholder and typed words share it
        static let pillEdge = Color(0x262626)     // Mode pill outline: one quiet step off its fill, below the surface hairline
        static let pillEdgeWidth: CGFloat = 1
        static let talking = Accent.blue                // the box's 2 pt outline while you talk
        static let attach: CGFloat = 96                 // an attachment tile in the box
        static let attachInset: CGFloat = 10            // from the box's edges: its radius is the box's minus this
        static let attachRing = Color(0xffffff, 0.08)
        static let attachRemove: CGFloat = 20
        static let sent: CGFloat = 120                  // a sent picture, above your bubble
        static let dropDim: Double = 0.55               // the chat under a file you're dropping: still readable
        static let stopped = Accent.red                 // "Interrupted": the soft red
        static let mark: CGFloat = 18, markLine: CGFloat = 1.6   // a plan step's mark
        static let ringArc: CGFloat = 0.7, ringTurn: Double = 0.9, fullTurn: Double = 360
        static let planRow: CGFloat = 28
        static let selection = Color(0x789aff, 0.32)    // selected words in the chat
    }
    // MARK: Approval card (an agent asking for your OK, inside its turn): the prototype's .card on box
    enum Approval {
        static let width: CGFloat = 360            // hugs its words up to this
        static let ring = Color(0xffffff, 0.04)    // .card's inset 1 pt ring
        static let ringWidth: CGFloat = 1
        static let padding: CGFloat = 14
        static let button: CGFloat = 32
        static let buttonPad: CGFloat = 14, chevron: CGFloat = 26
    }
    enum Today {
        static let top: CGFloat = 16, sides: CGFloat = 16
    }

    // MARK: Menus (spec 11): today's menus, on system values. Same items and behaviour.
    enum Menu {
        static let radius: CGFloat = 14
        static let fill = Tone.page
        static let item: CGFloat = 36, itemPadding: CGFloat = 16, itemText: CGFloat = 13.5
        static let itemHover = Wash.stHover
        static let padding: CGFloat = 8            // above the first item and below the last
        static let headerText: CGFloat = 12        // section heading, t3
        static let divider = Tone.line, dividerGap: CGFloat = 6
        static let width: CGFloat = 240            // default; content can widen it
        // Shadow: Material level 2 (menus float): 0 4 8 3 black 15% + 0 1 3 black 30%, plus the surface hairline.
        static let shadowA = (color: Color(0x000000, 0.15), radius: CGFloat(8), y: CGFloat(4))
        static let shadowB = (color: Color(0x000000, 0.30), radius: CGFloat(3), y: CGFloat(1))
    }

    // MARK: Motion (spec 12, Material 3). Hover and press are instant: no animation.
    enum Motion {
        static let open = Animation.timingCurve(0.05, 0.7, 0.1, 1, duration: 0.3)    // panes and panels opening
        static let close = Animation.timingCurve(0.3, 0, 0.8, 0.15, duration: 0.2)  // and closing
        static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.25)
        // Browser tab hover, as Chrome's (GlowHoverController): 200 ms ease-out in, 200 ms ease-in out (quadratic).
        // The one hover that fades; the separators beside the tab fade with it.
        static let shimmer: Double = 1.3               // one pass of the working words' shimmer
        static let shimmerBand: CGFloat = 0.5          // its bright band, as a share of the words' width
        static let shimmerBase = Color(0x5c5c5c)       // the working words under the band: quiet, so the band reads
        static let badge: CGFloat = 20, badgeText: CGFloat = 11.5, badgePad: CGFloat = 6, badgeRing: CGFloat = 3
        static let tabHoverIn = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.2)
        static let tabHoverOut = Animation.timingCurve(0.55, 0.085, 0.68, 0.53, duration: 0.2)
    }
}

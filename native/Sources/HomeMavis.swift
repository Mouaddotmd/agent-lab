// Home in the MAVIS look (spec 6 and 7; prototype: Home). Two surfaces: Home (greeting, chatbox, Jump back in) and
// Today (brief, Waiting for you, Your agents). Same data and actions as HomePage: your agents, their runs and
// approvals; sending opens the chat. Every value is MV's.
import SwiftUI

struct MavisHome: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    @State private var ask = ""
    @State private var pickId: String?
    @State private var pickOpen = false
    @FocusState private var typing: Bool
    @State private var boxHover = false

    var scope: [Agent] { s.agents.sorted { lastAt($0) > lastAt($1) } }
    var pick: Agent? { scope.first { $0.id == pickId } ?? scope.first }

    var body: some View {
        HStack(spacing: MV.Space.gutter) {
            main.mvSurface()
            if panes.showsNow { MavisToday().frame(width: MV.Size.todayWidth).mvSurface() }
        }
    }

    // MARK: Home surface: greeting, chatbox, Jump back in, centred in a 720 column

    var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("Hello, \(s.handle).").foregroundStyle(MV.Ink.t1)
                Text("What should your agents do?").foregroundStyle(MV.Ink.t2)
            }
            .font(F.font(MV.Text.greeting, .medium)).tracking(MV.Text.greetingTracking)
            .lineSpacing(MV.Text.greetingLine - MV.Text.greeting)
            chatbox.padding(.top, MV.Space.section)
            if !scope.isEmpty { jumpBackIn.padding(.top, MV.Space.section) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: MV.Home.column)
        .padding(.horizontal, MV.Home.sides)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var chatbox: some View {
        let has = !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shape = RoundedRectangle(cornerRadius: MV.Radius.homeBox, style: .continuous)
        return VStack(alignment: .leading, spacing: MV.Space.inset) {
            ZStack(alignment: .leading) {
                if ask.isEmpty { Text("Ask \(pick?.name ?? "an agent") to fix, build, review or research something…").foregroundStyle(MV.Ink.t3) }
                if !SnapshotMode.on {
                    TextField("", text: $ask).textFieldStyle(.plain).foregroundStyle(MV.Ink.t1).focused($typing).onSubmit(submit)
                }
            }
            .font(F.font(MV.Text.homeInput, .regular))
            .frame(height: MV.Home.inputLine)
            HStack(spacing: 0) {
                agentChip
                Spacer(minLength: 0)
                // Attach (prototype .rbtn): opens the agent's chat, where files go in.
                Button { if let p = pick { s.openChat(p.id) } } label: {
                    Icon("mvClip", MV.Size.icon).foregroundStyle(MV.Ink.t2)
                        .frame(width: MV.Size.homeSend, height: MV.Size.homeSend).contentShape(Circle())
                }
                .buttonStyle(MVStates(shape: Circle())).tip("Add files", edge: .top).accessibilityLabel("Add files")
                .padding(.trailing, MV.Space.labelGap)     // its own room before send
                Button(action: submit) {
                    Icon("mvPlay", MV.Size.icon).offset(x: MV.Home.playNudge)
                        .foregroundStyle(has ? MV.Ink.onWhite : MV.Ink.t1)
                        .frame(width: MV.Size.homeSend, height: MV.Size.homeSend)
                        .background(Circle().fill(has ? Color.white : MV.Tone.page))
                        .contentShape(Circle())
                }.buttonStyle(MVStates(shape: Circle())).tip("Send", "↵", edge: .top).accessibilityLabel("Send")
            }
        }
        .padding(.top, MV.Home.boxTop).padding(.leading, MV.Home.boxLead)
        .padding(.trailing, MV.Space.edgeControl).padding(.bottom, MV.Space.edgeControl)
        .background(shape.fill(MV.Tone.box))
        .overlay(shape.strokeBorder(typing ? MV.Stroke.boxTyping : boxHover ? MV.Stroke.boxHover : MV.Stroke.boxRest,
                                    lineWidth: typing ? MV.Stroke.boxTypingWidth : MV.Stroke.boxRestWidth))
        .onHover { boxHover = $0 }
        .overlayPreferenceValue(PickAnchor.self) { anchor in
            GeometryReader { g in
                if pickOpen, let anchor, let pick {
                    let chip = g[anchor]
                    PickMenu(scope: scope, chosen: pick.id, open: $pickOpen) { pickId = $0 }.offset(x: chip.minX, y: chip.maxY + MV.Space.sm)
                }
            }
        }
        .zIndex(1)
    }

    /// The agent this box talks to: 36 tall, 10 from the box's edge like the send button, its tile inset 7.
    var agentChip: some View {
        Hover { h in
            Button {
                if let _ = pick { pickOpen.toggle() } else { s.newAgentOpen = true }
            } label: {
                HStack(spacing: MV.Space.labelGap) {
                    if let pick { Avatar(agent: pick, size: MV.Home.chipTile, ring: MV.Tone.box, status: false) }
                    else { Icon("plus", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2) }
                    Text(pick?.name ?? "Make an agent").font(F.font(MV.Home.chipText, .regular)).foregroundStyle(MV.Ink.t1)
                    if pick != nil { Icon("mvChevDown", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2) }
                }
                .padding(.leading, MV.Home.chipInset).padding(.trailing, MV.Space.inset)
                .frame(height: MV.Size.agentChip)
                .background(Capsule().fill(h ? MV.Wash.hover : .clear))
                .contentShape(Capsule())
            }.buttonStyle(.plain)
        }
        .anchorPreference(key: PickAnchor.self, value: .bounds) { $0 }
        .padding(.leading, -MV.Space.edgeControl)
    }

    func submit() {
        let t = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = pick else { s.newAgentOpen = true; return }
        guard !t.isEmpty else { return }
        ask = ""
        s.openChat(p.id)
        s.sendMessage(p.id, t)
    }

    // MARK: Jump back in: the three most recent agents as cards

    var jumpBackIn: some View {
        VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            HStack {
                Text("Jump back in")
                Spacer(minLength: 0)
                Hover { h in
                    Button { s.go(.messages) } label: { Text("See all chats").foregroundStyle(h ? MV.Ink.t1 : MV.Ink.t3) }.buttonStyle(.plain)
                }
            }
            .font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3)
            .frame(height: MV.Home.labelLine).padding(.horizontal, MV.Home.labelInset)
            HStack(alignment: .top, spacing: MV.Space.gridGap) {
                ForEach(scope.prefix(3)) { a in JumpCard(agent: a) }
            }
        }
    }
}

/// One Jump back in card: where it lives (a tag), its state, its name, what it's doing.
struct JumpCard: View {
    @EnvironmentObject var s: Store
    let agent: Agent
    var body: some View {
        let ws = s.workspaces.first { $0.id == agent.workspace }
        let state = s.state(of: agent)
        Hover { h in
            Button { s.openChat(agent.id) } label: {
                VStack(alignment: .leading, spacing: MV.Space.xs) {
                    HStack(spacing: 0) {
                        MVTag(text: ws?.name ?? "Personal", color: ws?.color.flatMap(Color.init(cssHex:)) ?? MV.Accent.tagDesign)
                        Spacer(minLength: 0)
                        Text(MavisToday.stateWord(state)).font(F.font(MV.Text.body, .regular))
                            .foregroundStyle(state == "done" ? MV.Ink.t1 : MV.Ink.t3)
                    }
                    Text(agent.name).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1)
                        .padding(.top, MV.Space.sm)
                    Text(agent.job ?? "No job yet").font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3)
                        .lineLimit(2).lineSpacing(MV.Text.bodyLine - MV.Text.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(MV.Space.inset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(h ? MV.Tone.box2 : MV.Tone.box))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// A category tag: solid colour, dark text, 20 tall, radius 5.
struct MVTag: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(F.font(MV.Text.tag, .medium)).foregroundStyle(MV.Accent.onTag)
            .padding(.horizontal, MV.Home.tagPad).frame(height: MV.Size.tag)
            .background(RoundedRectangle(cornerRadius: MV.Radius.tag).fill(color))
    }
}

/// The profile bar (prototype .up): 355 × 58 at the window's corner (8 in), radius 18, omni with a 1 pt white 7% ring;
/// the avatar (36 in a 48 button lined up with the rail), name and what's running, then notifications and settings.
/// Beside Messages and a workspace it's open; elsewhere only the avatar shows, same size, same place.
struct MVProfileBar: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    /// Open, the bar ends where the list beside it ends: it keeps its 355 at the default list width and follows the
    /// list when you drag it, so it never slides under the surface.
    private var openWidth: CGFloat { MVListGap.width(panes) + MV.Size.profileBar.width - MV.Size.listWidth }
    var body: some View {
        let open = s.view == .messages || s.openWorkspace != nil
        let working = s.agents.filter { s.state(of: $0) == "working" }.count
        let shape = RoundedRectangle(cornerRadius: MV.Profile.radius, style: .continuous)
        HStack(spacing: MV.Space.gridGap) {
            Button { s.go(.profile) } label: {
                Circle().fill(MV.Tone.box2).frame(width: MV.Size.avatar, height: MV.Size.avatar)
                    .overlay(Icon("person", MV.Size.iconLarge - MV.Space.xs).foregroundStyle(MV.Ink.t2))
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(MV.Accent.statusOn).frame(width: MV.Profile.dot, height: MV.Profile.dot)
                            .background(Circle().fill(open ? MV.Tone.omni : MV.Tone.frame).padding(-MV.Stroke.dotRing))
                            .offset(x: MV.Stroke.dotRing, y: MV.Stroke.dotRing)
                    }
                    .frame(width: MV.Size.avatarButton, height: MV.Size.avatarButton)
                    .contentShape(RoundedRectangle(cornerRadius: MV.Radius.rail, style: .continuous))
            }
            .buttonStyle(MVStates(shape: RoundedRectangle(cornerRadius: MV.Radius.rail, style: .continuous)))
            .tip(s.handle, edge: .top).accessibilityLabel("Your profile")
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.handle).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1)
                    Text(working == 0 ? "No agents working" : "\(working) \(working == 1 ? "agent" : "agents") working")
                        .font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3).lineLimit(1)
                }
                Spacer(minLength: 0)
                MVSquareButton(icon: "mvBell", label: "Today") { s.go(.agents) }
                MVSquareButton(icon: "mvGear", label: "Plugins and settings") { s.historyOpen = false; s.settingsOpen.toggle() }
            }
        }
        .padding(.leading, MV.Space.xs).padding(.trailing, MV.Space.sm)
        .frame(width: open ? openWidth : MV.Size.avatarButton + MV.Space.gutter, height: MV.Size.profileBar.height, alignment: .leading)
        .background(shape.fill(open ? MV.Tone.omni : .clear))
        .overlay(shape.strokeBorder(open ? MV.Wash.hover : .clear, lineWidth: MV.Stroke.boxRestWidth).allowsHitTesting(false))
        .padding(.leading, MV.Space.gutter).padding(.bottom, MV.Space.gutter)
    }
}

/// A 36 pt square icon button, radius 8 (the profile bar's bell and gear).
struct MVSquareButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Profile.buttonRadius, style: .continuous)
        Button(action: action) {
            Icon(icon, MV.Size.icon).foregroundStyle(MV.Ink.t2)
                .frame(width: MV.Profile.button, height: MV.Profile.button).contentShape(shape)
        }
        .buttonStyle(MVStates(shape: shape))
        .tip(label, edge: .top).accessibilityLabel(label)
    }
}

extension View {
    /// Applies AppKit-backed modifiers only in the live app (the snapshot tools render offscreen and can't draw them).
    @ViewBuilder func unlessSnapshot<V: View>(_ live: (Self) -> V) -> some View {
        if SnapshotMode.on { self } else { live(self) }
    }
}

/// Hugs its content (a chat bubble): as wide as `ideal` (the words' own width, measured), never wider than it's offered;
/// the words wrap past that. The chat's text views fill whatever width they get, so the width is measured, not asked.
struct HugWidth: Layout {
    var ideal: CGFloat? = nil
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let v = subviews.first else { return .zero }
        let want = ideal ?? v.sizeThatFits(.unspecified).width
        let w = min(want, proposal.width ?? want)
        return CGSize(width: w, height: v.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
    /// The widest line of `text` in the chat's font: what a bubble around it needs (plus a hair so it never wraps).
    static func width(of text: String) -> CGFloat {
        let font = RichText.font(RichText.size, .regular)
        // As it's drawn: commands and skills as chips (heavier, with their room), so a one-word command never wraps.
        let widest = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> CGFloat in
            let s = NSMutableAttributedString(string: String(line), attributes: [.font: font])
            RichText.chips(s, size: RichText.size)
            return s.size().width               // a chip's pill reaches into the bubble's padding on both sides, evenly
        }.max() ?? 0
        return ceil(widest) + MV.Stroke.list            // one point of slack so it never wraps
    }
    /// How far AppKit sets a message's words below the middle of their fixed 23 pt line (it puts the extra height
    /// above the glyphs): a bubble moves its words up by this so they sit in its middle.
    static let lift: CGFloat = {
        let f = RichText.font(RichText.size, .regular)
        return max(0, (MV.Text.messageLine - (f.ascender - f.descender)) / 2).rounded()
    }()
}

/// A MAVIS resize gap (Chrome's side-panel handle): the 8 pt gap between two surfaces is the handle. Pointing at it
/// shows a small grip (a 4 × 24 capsule in t3, t2 while dragging) and the resize cursor, at once (no fade). Dragging
/// follows the pointer with no animation; double-click puts the default back.
struct MVResizeGap: View {
    let axis: Axis
    let drag: (CGFloat) -> Void
    let end: () -> Void
    var reset: (() -> Void)? = nil
    @State private var hover = false
    @State private var dragging = false
    var body: some View {
        let horizontal = axis == .horizontal
        ZStack {
            Color.clear
            if hover || dragging {
                Capsule().fill(dragging ? MV.Ink.t2 : MV.Ink.t3)
                    .frame(width: horizontal ? MV.Resize.grip : MV.Resize.gripLength, height: horizontal ? MV.Resize.gripLength : MV.Resize.grip)
            }
        }
        .frame(width: horizontal ? MV.Space.gutter : nil, height: horizontal ? nil : MV.Space.gutter)
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
        .contentShape(Rectangle())
        .pointerStyle(horizontal ? .columnResize : .rowResize)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    dragging = true
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { drag(horizontal ? g.translation.width : g.translation.height) }
                }
                .onEnded { _ in dragging = false; end() }
        )
        .onTapGesture(count: 2) { reset?() }
        .accessibilityElement().accessibilityLabel("Resize")
    }
}

/// MAVIS interaction states (prototype: every control's ::after): hover lays white 10% over whatever the control shows
/// (selected or not), pressing lays white 16%. Instant, clipped to the control's shape.
struct MVStates<S: Shape>: ButtonStyle {
    let shape: S
    var hoverable = true
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(configuration.isPressed ? MV.Wash.stPress : hover && hoverable ? MV.Wash.stHover : .clear).allowsHitTesting(false))
            .onHover { hover = $0 }
    }
}

/// The MAVIS face of an agent (prototype .ag): a 44 tile, radius 12. Claude Code agents are the clay tile with the bot,
/// others the grey tile with the prompt. Its status: an 18 ring in the colour under it, holding a 12 green dot (live)
/// or a 12 hollow grey ring (idle).
struct MVFace: View {
    let agent: Agent; let live: Bool; var under: Color = MV.Tone.frame; var size: CGFloat = MV.Size.tile
    /// Unread replies: the red count in the corner instead of the status ring.
    var badge: Int = 0
    var body: some View {
        let claude = (agent.operator ?? "claude-code").hasPrefix("claude")
        RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
            .fill(claude ? MV.Accent.clayTile : MV.Tone.box)
            .frame(width: size, height: size)
            .overlay(Icon(claude ? "mvBot" : "mvPrompt", MV.Size.faceIcon).foregroundStyle(claude ? MV.Accent.clay : MV.Ink.t2))
            .overlay(alignment: .bottomTrailing) {
                if badge > 0 {
                    MVCountBadge(count: badge, ring: under).offset(x: MV.Home.dotOffset, y: MV.Home.dotOffset)
                } else {
                    // Every face has a status (Discord's): green working, a grey ring at rest.
                    ZStack {
                        Circle().fill(under)
                        if live { Circle().fill(MV.Accent.statusOn).frame(width: MV.Size.dot, height: MV.Size.dot) }
                        else { Circle().strokeBorder(MV.Accent.statusIdle, lineWidth: MV.Stroke.idleRing).frame(width: MV.Size.dot, height: MV.Size.dot) }
                    }
                    .frame(width: MV.Size.statusRing, height: MV.Size.statusRing)
                    .offset(x: MV.Home.dotOffset, y: MV.Home.dotOffset)
                }
            }
            .accessibilityElement().accessibilityLabel(agent.name)
    }
}

/// The agent tile with its status dot (44, radius 12, dot 12 with a 3 pt ring in the colour under it).
struct MVAgentTile: View {
    let agent: Agent; let live: Bool; var under: Color = MV.Tone.box
    var body: some View {
        // Home's tiles (prototype .lv-av): the page tone with the agent's icon in t2, dot ring in the card's colour.
        let claude = (agent.operator ?? "claude-code").hasPrefix("claude")
        RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous).fill(MV.Tone.page)
            .frame(width: MV.Size.tile, height: MV.Size.tile)
            .overlay(Icon(claude ? "mvBot" : "mvPrompt", MV.Size.iconLarge).foregroundStyle(MV.Ink.t2))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(live ? MV.Accent.statusOn : MV.Accent.statusIdle)
                    .frame(width: MV.Size.dot, height: MV.Size.dot)
                    .background(Circle().fill(under).padding(-MV.Stroke.dotRing))
                    .offset(x: MV.Home.dotOffset, y: MV.Home.dotOffset)
            }
            .accessibilityElement().accessibilityLabel(agent.name)
    }
}

// MARK: Today

struct MavisToday: View {
    @EnvironmentObject var s: Store
    @State private var day = 0

    static func stateWord(_ state: String) -> String {
        switch state {
        case "needs": "Waiting"
        case "working": "Working"
        case "failed": "Stopped"
        case "done": "Done"
        default: "Free"
        }
    }

    var body: some View {
        let waiting = s.agents.filter { s.state(of: $0) == "needs" }
        let working = s.agents.filter { s.state(of: $0) == "working" }
        let finished = s.agents.filter { a in
            guard a.last?.state == "done", let at = a.last?.at else { return false }
            return Calendar.current.isDateInToday(Date(timeIntervalSince1970: at / 1000))
        }
        VStack(alignment: .leading, spacing: 0) {
            header
            brief(waiting: waiting.count, working: working.count).padding(.top, MV.Space.inset)
            if !waiting.isEmpty {
                label("Waiting for you", count: waiting.count).padding(.top, MV.Space.section)
                VStack(spacing: MV.Space.cardGap) {
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { i, a in WaitingCard(agent: a, actions: i == 0) }
                }
            }
            if !s.agents.isEmpty {
                label("Your agents", count: nil).padding(.top, MV.Space.section)
                VStack(spacing: 0) {
                    ForEach(Array(s.agents.prefix(5).enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Rectangle().fill(MV.Workspace.divider).frame(height: MV.Stroke.list) }
                        AgentLine(agent: a)
                    }
                }
                .padding(.vertical, MV.Space.xs).padding(.horizontal, MV.Space.inset)
                .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(MV.Tone.box))
            }
            Spacer(minLength: 0)
            if !finished.isEmpty {
                HStack(spacing: MV.Space.labelGap) {
                    Icon("check", MV.Size.iconSmall)
                    Text("\(finished.count) finished today").font(F.font(MV.Text.footer, .regular))
                    Spacer(minLength: 0)
                    Icon("mvChevRight", MV.Size.iconSmall)
                }
                .foregroundStyle(MV.Ink.t2).frame(height: MV.Size.chatButton).padding(.horizontal, MV.Space.inset)
            }
        }
        .padding(.top, MV.Today.top).padding(.horizontal, MV.Today.sides).padding(.bottom, MV.Space.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var header: some View {
        let date = Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date()
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today").font(F.font(MV.Text.panelTitle, .medium)).foregroundStyle(MV.Ink.t1)
                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3)
            }
            Spacer(minLength: 0)
            MVIconButton(icon: "mvBack", label: "Previous day") { day -= 1 }
            MVIconButton(icon: "mvFwd", label: "Next day") { day += 1 }
        }
    }

    func brief(waiting: Int, working: Int) -> some View {
        let text = waiting > 0
            ? "\(waiting == 1 ? "One thing needs" : "\(waiting) things need") you. \(working > 0 ? "\(working) working, everything else is on track." : "Everything else is on track.")"
            : working > 0 ? "\(working) \(working == 1 ? "agent is" : "agents are") working. Nothing needs you right now." : "All quiet. Your agents are ready when you are."
        return HStack(alignment: .top, spacing: MV.Space.gridGap) {
            Icon("mvSparkle", MV.Size.icon).foregroundStyle(MV.Ink.t2)
            Text(text).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t2).lineSpacing(MV.Text.bodyLine - MV.Text.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MV.Space.inset)
        .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(MV.Tone.box))
    }

    func label(_ text: String, count: Int?) -> some View {
        HStack(spacing: MV.Space.labelGap) {
            Text(text).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3)
            if let count {
                Text("\(count)").font(F.font(MV.Text.meta, .medium)).foregroundStyle(MV.Ink.t1)
                    .frame(minWidth: MV.Size.badge, minHeight: MV.Size.badge).background(Circle().fill(MV.Tone.box))
            }
        }
        .frame(height: MV.Home.labelLine).padding(.bottom, MV.Space.labelGap)
    }
}

/// Waiting for you: tile left, name and tag on the first line, the ask under it; the first card has Later / Review.
struct WaitingCard: View {
    @EnvironmentObject var s: Store
    let agent: Agent; let actions: Bool
    @State private var later = false
    var body: some View {
        let ws = s.workspaces.first { $0.id == agent.workspace }
        let ask = s.approvalsFor(agent.id).first
        if !later {
            Hover { h in
                VStack(alignment: .trailing, spacing: MV.Space.inset) {
                    HStack(alignment: .top, spacing: MV.Space.inset) {
                        MVAgentTile(agent: agent, live: s.state(of: agent) == "working", under: h ? MV.Tone.box2 : MV.Tone.box)
                        VStack(alignment: .leading, spacing: MV.Space.xs) {
                            HStack(spacing: MV.Space.labelGap) {
                                Text(agent.name).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3).lineLimit(1)
                                Spacer(minLength: 0)
                                MVTag(text: ws?.name ?? "Personal", color: ws?.color.flatMap(Color.init(cssHex:)) ?? MV.Accent.tagDesign)
                            }
                            Text(ask?.about ?? ask?.line ?? "Waiting for your OK").font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(2)
                        }
                    }
                    if actions {
                        HStack(spacing: MV.Space.sm) {
                            MVPill(title: "Later", primary: false) { later = true }
                            MVPill(title: "Review", primary: true) { s.openChat(agent.id) }
                        }
                    }
                }
                .padding(MV.Space.inset)
                .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(h ? MV.Tone.box2 : MV.Tone.box))
                .contentShape(Rectangle())
                .onTapGesture { s.openChat(agent.id) }
            }
        }
    }
}

/// Your agents: one row per agent, tile and dot, name, what it's doing, time or Assign.
struct AgentLine: View {
    @EnvironmentObject var s: Store
    let agent: Agent
    var body: some View {
        let state = s.state(of: agent)
        let run = s.runs["agent:\(agent.id)"]
        Hover { h in
            HStack(spacing: MV.Space.inset) {
                MVAgentTile(agent: agent, live: state == "working", under: h ? MV.Tone.box2 : MV.Tone.box)
                VStack(alignment: .leading, spacing: MV.Space.rowGap) {
                    Text(agent.name).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1)
                    if state == "working" {
                        Shimmer(text: run?.activity ?? "Working", font: F.font(MV.Text.body, .regular), base: MV.Ink.t3, band: MV.Ink.t1)
                    } else {
                        Text(MavisToday.stateWord(state)).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t2).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if state == "working", let t = run?.startedAt {
                    Text(Date(timeIntervalSince1970: t / 1000), style: .relative).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3).monospacedDigit()
                } else if state == "idle" {
                    MVPill(title: "Chat", primary: false, filled: true) { s.openChat(agent.id) }
                }
            }
            .padding(.vertical, MV.Space.labelGap).padding(.horizontal, MV.Space.labelGap)
            .background(RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous).fill(h ? MV.Tone.box2 : .clear))
            .padding(.horizontal, -MV.Space.labelGap)
            .contentShape(Rectangle())
            .onTapGesture { s.openChat(agent.id) }
        }
    }
}

/// A 40 pt round button inside a chatbox: clear, or a fill (box2 mic, white send); hover and press lay their wash
/// over it (prototype .rbtn).
struct MVRoundButton: View {
    let icon: String; let label: String; var fill: Color? = nil; var ink: Color = MV.Ink.t2; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                TabIcon(name: icon == "mvMic" ? "mvMicrophone" : icon, size: MV.Size.icon).foregroundStyle(fill == nil ? (h ? MV.Ink.t1 : MV.Ink.t2) : ink == MV.Ink.t2 ? MV.Ink.t1 : ink)
                    .frame(width: MV.Size.chatButton, height: MV.Size.chatButton)
                    .background(Circle().fill(fill ?? .clear))
                    .contentShape(Circle())
            }.buttonStyle(MVStates(shape: Circle()))
        }
        .tip(label, edge: .top).accessibilityLabel(label)
    }
}

/// A 24 pt status chip in a header: green for Done, box2 for everything else.
struct MVChip: View {
    let text: String; var done = false
    var body: some View {
        Text(text).font(F.font(MV.Text.meta, .medium)).foregroundStyle(done ? MV.Accent.doneText : MV.Ink.t2)
            .padding(.horizontal, MV.Space.gridGap).frame(height: MV.Size.chip)
            .background(Capsule().fill(done ? MV.Accent.doneFill : MV.Tone.box2))
    }
}

/// A 28 pt pill: the white primary, or ghost text, or a page-tone fill on a card. The prototype gives these no hover.
struct MVPill: View {
    let title: String; let primary: Bool; var filled = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(F.font(MV.Text.control, .medium))
                .foregroundStyle(primary ? MV.Ink.onWhite : MV.Ink.t2)
                .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.pill)
                .background(Capsule().fill(primary ? Color.white : filled ? MV.Tone.page : .clear))
                .contentShape(Capsule())
        }.buttonStyle(MVStates(shape: Capsule(), hoverable: false))
    }
}

/// A 28 pt round icon button with an 18 pt icon (header buttons, arrows): lit (on) sits on white 10%; hover and press
/// lay their wash over that (prototype .ib).
struct MVIconButton: View {
    let icon: String; let label: String; var on = false; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                TabIcon(name: icon, size: MV.Size.icon).foregroundStyle(on || h ? MV.Ink.t1 : MV.Ink.t2)
                    .frame(width: MV.Size.iconButton, height: MV.Size.iconButton)
                    .background(Circle().fill(on ? MV.Wash.stHover : .clear))
                    .contentShape(Circle())
            }.buttonStyle(MVStates(shape: Circle()))
        }
        .tip(label).accessibilityLabel(label)
    }
}

extension Color {
    /// "#c58af9" or "c58af9" → a colour (workspace colours are stored as CSS hex).
    init?(cssHex: String) {
        let h = cssHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(v)
    }
}


/// The red count (Discord's): white 11.5 semibold on red, 20 tall, a pill once it's two digits, ringed in the colour
/// under it so it sits cut into the picture's corner.
struct MVCountBadge: View {
    let count: Int; let ring: Color
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)").font(F.font(MV.Motion.badgeText, .semibold)).foregroundStyle(Color.white).monospacedDigit()
            .padding(.horizontal, MV.Motion.badgePad).frame(minWidth: MV.Motion.badge, minHeight: MV.Motion.badge)
            .background(Capsule().fill(MV.Accent.badge))
            .background(Capsule().fill(ring).padding(-MV.Motion.badgeRing))
            .fixedSize()
            .accessibilityLabel("\(count) new")
    }
}


/// MAVIS ⋯ (shown on a row's hover): a square button `inset` in from the row's top and right edges, its corner
/// concentric with the row's (ConcentricRectangle on macOS 26, the same sum before), so inner and outer corners agree.
/// The MV states on hover and press; lit while its menu is open.
struct MVMoreButton: View {
    let open: Bool; let corner: CGFloat; let inset: CGFloat; var size: CGFloat = MV.Size.iconButton
    /// On a selected (blue) row: its blue, stronger, and a pale-blue icon, instead of grey.
    var selected = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        let r = max(MV.Workspace.moreMinRadius, corner - inset)
        let shape: AnyShape = {
            if #available(macOS 26.0, *) { return AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(r)), isUniform: true)) }
            return AnyShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        }()
        Button(action: action) {
            // Only the button under the pointer lights: its own tone (a step over the row's hover) and a white icon.
            Icon("more", MV.Size.icon).foregroundStyle(selected ? (open || hover ? Color.white : MV.Accent.selectedText) : open || hover ? MV.Ink.t1 : MV.Ink.t2)
                .frame(width: size, height: size)
                .background(shape.fill(open || hover ? (selected ? MV.Workspace.moreOnSelected : MV.Workspace.moreHover) : .clear))
                .contentShape(shape)
        }
        .buttonStyle(MVStates(shape: shape, hoverable: false))
        .onHover { hover = $0 }
        .tip("More").accessibilityLabel("More")
    }
}

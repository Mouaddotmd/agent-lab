// The tools under a message you hover (MAVIS; prototype .mt in mavis-window.html): when it was sent, then what you
// can do with it. Yours: Copy, Edit (back to before it, your words in the box, as Claude Code's). The agent's: Copy,
// Try again (the same message sent again), Branch from here (a new chat through this answer). In a channel only Copy
// (a channel has no going back).
//
// Shown by the chat's one hover tracker (RowLights, lit by Follower.hover), never a listener per row. It arrives as the
// prototype's does: a 28 dot at its corner stretches into the pill on a quick spring, its contents a beat behind; it
// leaves faster, with no bounce.
import SwiftUI
import AppKit

struct MVMessageTools: View {
    @EnvironmentObject var s: Store
    @ObservedObject var lit: Lit
    /// Yours (anchored at the bubble's right) or the agent's (at the words' left).
    let mine: Bool
    let time: String?
    let agentId: String
    let messageId: String
    let words: String
    /// A DM: going back, trying again and branching work; a channel has Copy only.
    let canRewind: Bool

    private typealias T = MV.MessageTools
    @State private var visible = false
    @State private var grown = false
    @State private var itemsIn = false
    @State private var width: CGFloat = T.dot
    @State private var copied = false

    var body: some View {
        let anchor: UnitPoint = mine ? .trailing : .leading
        HStack(spacing: 0) {
            if let time { item(0) { Text(time).font(F.font(T.time, .regular)).monospacedDigit().foregroundStyle(MV.Ink.t3).padding(.leading, T.timeLead).padding(.trailing, T.timeTrail) } }
            ForEach(Array(tools.enumerated()), id: \.offset) { i, t in
                item(i + (time == nil ? 0 : 1)) { ToolButton(tool: t, copied: copied) }
            }
        }
        .padding(.horizontal, T.pad)
        .frame(height: T.height)
        .fixedSize()
        .background(Capsule().fill(T.fill))
        .overlay(Capsule().strokeBorder(T.ring, lineWidth: MV.Stroke.boxRestWidth).allowsHitTesting(false))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The morph: a dot at the corner, stretched to the pill's width.
        .mask(alignment: mine ? .trailing : .leading) { Capsule().frame(width: grown ? width : T.dot) }
        // Solid from its first frame (no fade): the dot grows into the pill, the mask uncovering its contents.
        .scaleEffect(visible && !grown ? T.startScale : 1, anchor: anchor)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .onAppear { if lit.on { arrive() } }
        .onChange(of: lit.on) { _, on in on ? arrive() : leave() }
        .accessibilityHidden(!visible)
    }

    private struct Tool { let icon: String; let label: String; let action: () -> Void }
    private var tools: [Tool] {
        var out = [Tool(icon: "mvCopy", label: "Copy") { copy() }]
        guard canRewind else { return out }
        if mine {
            out.append(Tool(icon: "mvEdit", label: "Edit") { s.rewind(agentId, messageId) })
        } else {
            out.append(Tool(icon: "mvReload", label: "Try again") { s.retry(agentId, messageId) })
            out.append(Tool(icon: "mvBranch", label: "Branch from here") { s.branch(agentId, messageId) })
        }
        return out
    }

    /// Each piece fades in from the corner side, in order, once the pill has room.
    private func item<V: View>(_ i: Int, @ViewBuilder _ v: () -> V) -> some View {
        v().offset(x: itemsIn ? 0 : (mine ? T.itemShift : -T.itemShift))
            .animation(itemsIn ? .easeOut(duration: T.itemTime).delay(T.itemDelay + Double(i) * T.itemStep) : nil, value: itemsIn)
    }

    private func arrive() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { grown = false; itemsIn = false; visible = true }
        DispatchQueue.main.async {
            guard lit.on else { return }
            withAnimation(.spring(response: T.response, dampingFraction: T.damping)) { grown = true }
            itemsIn = true
        }
    }
    /// Gone at once (Discord's): one pill at a time, never two while the pointer crosses rows quickly.
    private func leave() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { visible = false; grown = false; itemsIn = false }
    }
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(words, forType: .string)
        // The tick on the click, not when the clipboard answers; back to Copy after a moment.
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + T.copied) { copied = false }
    }

    private struct ToolButton: View {
        let tool: Tool; let copied: Bool
        var body: some View {
            let done = copied && tool.label == "Copy"
            Button(action: tool.action) {
                Icon(done ? "mvCheck" : tool.icon, T.icon)
                    .foregroundStyle(done ? MV.Accent.added : MV.Ink.t2)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .id(done)
                    .frame(width: T.button, height: T.button).contentShape(Circle())
            }
            .buttonStyle(Squeeze())
            .animation(.spring(response: T.pressBack, dampingFraction: T.damping), value: done)
            .tip(done ? "Copied" : tool.label, edge: .bottom)
            .accessibilityLabel(tool.label)
        }
    }
    /// The hover and press wash of every MAVIS button, plus a squeeze on the press that springs back.
    private struct Squeeze: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(Circle().fill(configuration.isPressed ? MV.Wash.stPress : .clear))
                .modifier(Hovered())
                .scaleEffect(configuration.isPressed ? T.press : 1)
                .animation(configuration.isPressed ? .easeOut(duration: T.exitTime) : .spring(response: T.pressBack, dampingFraction: T.damping), value: configuration.isPressed)
        }
    }
    private struct Hovered: ViewModifier {
        @State private var on = false
        func body(content: Content) -> some View {
            content.background(Circle().fill(on ? MV.Wash.stHover : .clear)).onHover { on = $0 }
        }
    }
}

/// The agent's row lit while hovered: 2.5% white, 8 past its words, radius 12 (prototype).
struct MVRowLight: View {
    @ObservedObject var lit: Lit
    var body: some View {
        RoundedRectangle(cornerRadius: MV.MessageTools.rowRadius, style: .continuous)
            .fill(lit.on ? MV.MessageTools.rowLight : .clear)
            .padding(-MV.MessageTools.rowSpread)
            .allowsHitTesting(false)
    }
}

/// Your bubble's fill, a touch brighter while hovered.
struct MVBubbleFill: View {
    @ObservedObject var lit: Lit
    var body: some View {
        RoundedRectangle(cornerRadius: MV.Chat.bubbleRadius, style: .continuous)
            .fill(lit.on ? MV.MessageTools.bubbleLit : MV.Accent.bubble)
    }
}

/// Where the tools hang, per kind of row: yours over your bubble's foot (its top 10 into it, at its right); the agent's
/// 4 under its words, 4 out to the left. Only for messages that are done (not sending, queued or still being written).
struct MVToolsSlot: View {
    @Environment(\.chatConv) private var conv
    let rowId: String; let mine: Bool; let time: Double?
    let agentId: String; let messageId: String; let words: String
    var body: some View {
        // A channel's conversation is "c_<workspace>_<channel>"; a DM's is the agent's id.
        let dm = !(conv ?? agentId).hasPrefix("c_") && !agentId.isEmpty
        MVMessageTools(lit: RowLights.shared.lit(rowId), mine: mine, time: time.map(clock), agentId: agentId,
                       messageId: messageId, words: words, canRewind: dm)
            // Where it is, for the hover tracker (the pointer on the tools keeps their row lit).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Follower.space)) } action: { RowLights.shared.tools[rowId] = $0 }
            // Placed from the message's bottom corner (the overlay's), without taking room: yours moved down so only its
            // top 10 sits on the bubble; the agent's a full pill plus 4 down and 4 out to the left.
            .offset(x: mine ? 0 : -MV.MessageTools.out,
                    y: mine ? MV.MessageTools.height - MV.MessageTools.overlap : MV.MessageTools.height + MV.MessageTools.below)
    }
}

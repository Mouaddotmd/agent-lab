// A side chat: ask the agent about its chat without adding to it (/btw, or Side chat by the tabs). It's drawn as the
// chat is (the same rows, faces, names and times, the same box) so it reads as one more conversation with the agent;
// the agent answers from its own copy of the session, only looking. Kept with the agent.
import SwiftUI
import AppKit

struct SideChatTab: View {
    @ObservedObject var panel: SidePanel
    let sideId: String
    var body: some View {
        SideChatView(model: ConvoHub.shared.side(panel.agentId, sideId), panel: panel)
            .environment(\.chatAgentId, panel.agentId)
    }
}

private struct SideChatView: View {
    @EnvironmentObject var s: Store
    @ObservedObject var model: SideChatModel
    let panel: SidePanel
    @State private var earlier: [SideDoc] = []
    var body: some View {
        let agent = s.agents.first { $0.id == model.agentId }
        VStack(spacing: 0) {
            if model.missing {
                Line("This side chat was closed", 14, .medium, C.i10).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let msgs = model.doc?.messages ?? []
                        if msgs.isEmpty && !model.running { intro }
                        ForEach(msgs) { m in if MV.on { mavisRow(m) } else { row(m, agent) } }
                        if model.running, let agent { if MV.on { mavisLive() } else { live(agent) } }
                    }
                    .padding(.horizontal, MV.on ? MV.Chat.sides : 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.never)
                SideBox(model: model, agentName: agent?.name ?? "it")
            }
        }
        .task { await loadEarlier() }
    }

    /// Empty: what this is, and the earlier side chats to open again.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Line("Ask on the side", 16, .semibold)
                Text("What it did, why, what's left. Answers here stay out of the chat.")
                    .font(F.font(14, .regular)).foregroundStyle(C.i10).fixedSize(horizontal: false, vertical: true)
            }
            if !earlier.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Line("Earlier", 12, .semibold, C.i9).padding(.leading, 8).padding(.bottom, 2)
                    ForEach(earlier) { d in EarlierRow(doc: d) { open(d) } }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
    }

    /// MAVIS: drawn exactly as the chat is: your words in the blue bubble, the agent's as plain words under their work.
    @ViewBuilder private func mavisRow(_ m: SideDoc.Msg) -> some View {
        if m.role == "user" {
            MVBubble(text: m.text)
        } else {
            VStack(alignment: .leading, spacing: MV.Space.labelGap) {
                if let steps = m.steps, !steps.isEmpty { FoldedWork(pieces: [.steps(id: m.id, steps: steps.map(\.step))]) }
                if m.role == "error" {
                    Text(m.text).font(F.font(MV.Text.title, .regular)).foregroundStyle(MV.Accent.red).fixedSize(horizontal: false, vertical: true)
                } else if !m.text.isEmpty {
                    MarkdownText(text: Tags.strip(m.text), color: Color.white(0.82))
                }
                if m.role == "stopped" { InterruptedLine() }
            }
            .frame(maxWidth: MV.Chat.readWidth, alignment: .leading)
            .padding(.vertical, MV.Space.sm)
        }
    }
    private func mavisLive() -> some View {
        let steps = (model.reply?.steps ?? []).map(\.step)
        let words = model.draft ?? model.reply?.text ?? ""
        return VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            if !words.isEmpty { MarkdownText(text: Tags.strip(words), color: Color.white(0.82)) }
            StatusLine(label: steps.last(where: { !$0.done }).map(StepWords.live) ?? (words.isEmpty ? "Thinking" : "Writing"),
                       waiting: false, started: model.reply?.at, work: steps.isEmpty ? [] : [.steps(id: "live", steps: steps)])
        }
        .frame(maxWidth: MV.Chat.readWidth, alignment: .leading)
        .padding(.vertical, MV.Space.sm)
        .transaction { $0.animation = nil }
    }
    @ViewBuilder private func row(_ m: SideDoc.Msg, _ agent: Agent?) -> some View {
        let time = m.at.map(clock) ?? ""
        if m.role == "user" {
            RowFrame(face: AnyView(Circle().fill(C.v4).frame(width: 40, height: 40).overlay(Icon("person", 20).foregroundStyle(C.i10))),
                     name: "You", time: time, mine: true) {
                MarkdownText(text: m.text, color: C.i12)
            }
        } else {
            RowFrame(face: face(agent), name: agent?.name ?? "Agent", time: time) {
                VStack(alignment: .leading, spacing: 8) {
                    if let steps = m.steps, !steps.isEmpty { FoldedWork(pieces: [.steps(id: m.id, steps: steps.map(\.step))]) }
                    if m.role == "error" {
                        Text(m.text).font(F.font(14, .regular)).foregroundStyle(FAIL_TEXT).fixedSize(horizontal: false, vertical: true)
                    } else if !m.text.isEmpty {
                        MarkdownText(text: Tags.strip(m.text), color: Color.white(0.82))
                    }
                    if m.role == "stopped" { InterruptedLine() }
                }
            }
        }
    }

    /// The answer being written: as a turn in the chat is, the status line under its words so far.
    private func live(_ agent: Agent) -> some View {
        let steps = (model.reply?.steps ?? []).map(\.step)
        let words = model.draft ?? model.reply?.text ?? ""
        return RowFrame(face: face(agent), name: agent.name, time: "now") {
            VStack(alignment: .leading, spacing: 8) {
                if !words.isEmpty { MarkdownText(text: Tags.strip(words), color: Color.white(0.82)) }
                StatusLine(label: steps.last(where: { !$0.done }).map(StepWords.live) ?? (words.isEmpty ? "Thinking" : "Writing"),
                           waiting: false, started: model.reply?.at, work: steps.isEmpty ? [] : [.steps(id: "live", steps: steps)])
            }
            .transaction { $0.animation = nil }
        }
    }

    private func face(_ agent: Agent?) -> AnyView {
        agent.map { AnyView(Avatar(agent: $0, size: 40, status: false)) }
            ?? AnyView(RoundedRectangle(cornerRadius: Avatar.radius(40), style: .continuous).fill(C.v4).frame(width: 40, height: 40))
    }

    private func open(_ d: SideDoc) {
        _ = ConvoHub.shared.side(model.agentId, d.id)
        panel.show(PanelTab(kind: .side(id: d.id, title: d.title)))
    }
    private func loadEarlier() async {
        let all = (try? await ConvoHub.shared.store?.engine.call("convo:sides", [model.agentId], as: [SideDoc].self)) ?? []
        earlier = Array(all.filter { $0.id != model.id && ($0.count ?? 0) > 0 }.prefix(6))
    }
}

/// An earlier side chat: its first question and when.
private struct EarlierRow: View {
    let doc: SideDoc; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 13)).foregroundStyle(C.i10).frame(width: 18)
                    Text(doc.title).font(F.font(14, .regular)).foregroundStyle(C.i12).lineLimit(1)
                    Spacer(minLength: 8)
                    if let at = doc.at { Text(ago(Date(timeIntervalSince1970: at / 1000))).font(F.font(12, .regular)).foregroundStyle(C.i9) }
                }
                .padding(.horizontal, 8).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(h ? C.v3 : .clear))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// The side chat's box: the chat's box (same shell, corner, padding, type and 40 pt controls), with Send in the slot
/// the mic has there, and Stop in it while an answer is written. ↵ asks, Esc stops.
private struct SideBox: View {
    @ObservedObject var model: SideChatModel
    let agentName: String
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var boxHover = false
    var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS: the chat's box (52 pill, radius 26, the 4 / 8 / 12% outline), your words, then the white send (Stop while
    /// it answers).
    private var mavis: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shape = RoundedRectangle(cornerRadius: MV.Radius.chatBox, style: .continuous)
        return HStack(alignment: .bottom, spacing: MV.Space.rowGap) {
            TextField("", text: $text, prompt: Text("Ask \(agentName) on the side").foregroundStyle(MV.Ink.t3), axis: .vertical)
                .textFieldStyle(.plain).font(F.font(MV.Text.chatInput, .regular)).foregroundStyle(MV.Ink.t1).lineLimit(1...8)
                .focused($focused)
                .onSubmit { send() }
                .onExitCommand { if model.running { model.stop() } }
                .padding(.vertical, MV.Space.labelGap + MV.Space.xs).padding(.leading, MV.Space.inset)
                .frame(maxWidth: .infinity, minHeight: MV.Size.chatButton, alignment: .leading)
            Group {
                if model.running { MVRoundButton(icon: "stop", label: "Stop (Esc)", fill: MV.Tone.box2) { model.stop() } }
                else if !empty { MVRoundButton(icon: "mvSend", label: "Ask", fill: Color.white, ink: MV.Ink.onWhite) { send() } }
                else { MVRoundButton(icon: "mvSend", label: "Ask", fill: MV.Tone.box2) {}.opacity(MV.Browser.disabled).allowsHitTesting(false) }
            }
            .transaction { $0.animation = nil }
        }
        .padding(MV.Space.sm)
        .frame(minHeight: MV.Size.chatBox)
        .background(shape.fill(MV.Tone.box))
        .overlay(shape.strokeBorder(focused ? MV.Stroke.boxTyping : boxHover ? MV.Stroke.boxHover : MV.Stroke.boxRest,
                                    lineWidth: focused ? MV.Stroke.boxTypingWidth : MV.Stroke.boxRestWidth))
        .onHover { boxHover = $0 }
        .overlay(alignment: .topLeading) {
            if let p = model.problem {
                Text(p).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Accent.red).lineLimit(2).padding(.leading, MV.Space.headerLead).offset(y: -MV.Space.section)
            }
        }
        .frame(maxWidth: MV.Chat.column).frame(maxWidth: .infinity)
        .padding(.horizontal, MV.Space.section - MV.Space.xs).padding(.top, MV.Space.gridGap).padding(.bottom, MV.Space.headerLead)
        .onAppear { focused = true }
    }
    private var classic: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: Box.gap) {
            TextField("", text: $text, prompt: Text("Ask \(agentName) on the side").foregroundStyle(C.i9), axis: .vertical)
                .textFieldStyle(.plain).font(F.font(16, .regular)).foregroundStyle(C.i12).lineLimit(1...8)
                .focused($focused)
                .onSubmit { send() }
                .onExitCommand { if model.running { model.stop() } }
                .padding(.vertical, 10).padding(.leading, 8)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            ZStack {
                if model.running {
                    Hover { h in
                        Button { model.stop() } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(h ? C.i12 : Color.white(0.86)).frame(width: 14, height: 14)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(h ? C.v4 : .clear))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .tip("Stop", "Esc", edge: .top).accessibilityLabel("Stop")
                } else {
                    ComposerButton(icon: "arrow.up", label: "Ask") { send() }
                        .opacity(empty ? 0.4 : 1).allowsHitTesting(!empty)
                }
            }
            .frame(width: 40, height: 40)
            .transaction { $0.animation = nil }
        }
        .padding(Box.pad)
        .background(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if let p = model.problem {
                Text(p).font(F.font(12, .regular)).foregroundStyle(FAIL_TEXT).lineLimit(2).padding(.leading, 16).offset(y: -22)
            }
        }
        .shadow(color: .black.opacity(themeNow.dark ? 0.5 : 0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(themeNow.dark ? 0.35 : 0.06), radius: 12, y: 6)
        .padding(.horizontal, 16).padding(.bottom, Box.lift)
        .onAppear { focused = true }
    }
    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !model.running else { return }
        model.ask(t); text = ""; focused = true
    }
}

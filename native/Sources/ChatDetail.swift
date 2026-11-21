// What a step did, opened: the whole command, what came back, what it changed. And a turn's changes together at its
// end. In the chat's greys: the work card's well, monospace, quiet. A change isn't a state, so no greens or reds: lines
// in sit on a light wash with "+", lines out are quieter with "−".
import SwiftUI
import AppKit

/// Opening and closing work in the chat: a quick glide that settles without overshoot, shorter on the way out (Mavis
/// final launch: StepMotion). What opens fades in as what's under it slides down.
enum StepMotion {
    static let open = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
    static let close = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    /// MAVIS: steps open and close at once (no slide or fade).
    static func animation(opening: Bool) -> Animation? { MV.on || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : opening ? open : close }
    static let reveal = AnyTransition.opacity
}

/// The work's inks (Mavis final launch: StepInk), in the app's greys: verbs and summaries quiet, what a step acted on
/// clear, the card barely there.
enum StepInk {
    static let rest = C.i9
    static let lit = C.i10
    static let cardFill = Color.white(0.03)
    static let cardEdge = Color.white(0.05)
    /// Words inside a card sit in as far as a step's words.
    static let edge: CGFloat = 14
}

/// A run of steps on its card (Mavis: StepsOpen + StepLines): one line each, split by the card's own faint line;
/// finished steps in a row that read the same are one line that says how many.
struct StepCardView: View {
    let steps: [Step]
    @State private var opened: String?
    @Environment(\.displayScale) private var scale
    var body: some View {
        let lines = StepLineGroup.from(steps)
        let shape = RoundedRectangle(cornerRadius: R.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                if i > 0 { (MV.on ? MV.Workspace.divider : StepInk.cardEdge).frame(height: 1 / scale) }
                StepRow(line: line, opened: opened == line.id) {
                    let opening = opened != line.id
                    withAnimation(StepMotion.animation(opening: opening)) { opened = opening ? line.id : nil }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // MAVIS: flat on box, radius 16, no edge; rows parted by the cards' 5% line.
        .background(MV.on ? AnyShapeStyle(MV.Tone.box) : AnyShapeStyle(StepInk.cardFill), in: MV.on ? AnyShape(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous)) : AnyShape(shape))
        .overlay { if !MV.on { shape.strokeBorder(StepInk.cardEdge, lineWidth: 1 / scale) } }
        .clipShape(MV.on ? AnyShape(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous)) : AnyShape(shape))
    }
}

/// One line in a card: a step, or several in a row that would read exactly the same.
struct StepLineGroup: Identifiable {
    var steps: [Step]
    var id: String { steps[0].id }
    var step: Step { steps[0] }
    static func from(_ all: [Step]) -> [StepLineGroup] {
        var out: [StepLineGroup] = []
        for st in all {
            let plain = st.done && !st.failed && (st.diff ?? []).isEmpty
            if plain, let last = out.last, last.step.verb == st.verb, last.step.line == st.line, last.step.done, !last.step.failed, (last.step.diff ?? []).isEmpty {
                out[out.count - 1].steps.append(st)
            } else { out.append(StepLineGroup(steps: [st])) }
        }
        return out
    }
}

/// A step as a line (Mavis: StepRow): the verb quiet, what it acted on clear, one size, no icons; how much a change
/// changed, and "Failed" when it didn't work. With something to show it opens in place to what ran and came back.
struct StepRow: View {
    let line: StepLineGroup
    let opened: Bool
    let toggle: () -> Void
    @State private var hovered = false
    /// The DM it's in: a helper's step opens the helper's own transcript in the side panel instead.
    @Environment(\.chatAgentId) private var agentId
    @Environment(\.chatConv) private var conv
    private var step: Step { line.step }
    private var helper: Bool { step.verb == "Start a helper for" && agentId != nil }
    private var running: Bool { !step.done }
    private var quiet: Color { hovered || opened ? StepInk.lit : StepInk.rest }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { if helper { openHelper() } else if step.opens { toggle() } } label: {
                HStack(spacing: 6) {
                    // Steps saved before their wording changed read as they would now ("Ran a script on the page" → "Checked").
                    let verb = step.verb == "Run" && step.line == "a script on the page" ? "Check" : step.verb
                    let object = verb == "Check" && step.verb == "Run" ? "the page" : StepWords.object(step.verb, step.line)
                    Text(running ? StepWords.ing(verb) : StepWords.past(verb)).foregroundStyle(running ? C.i10 : quiet).lineLimit(1).fixedSize()
                    if !object.isEmpty { Text(object).foregroundStyle(C.i12).lineLimit(1).truncationMode(.middle) }
                    if line.steps.count > 1 { Text("\u{00B7} \(line.steps.count) times").foregroundStyle(quiet).lineLimit(1).fixedSize() }
                    if let diff = step.diff, !diff.isEmpty { ChangeCount(files: diff) }
                    if step.failed { Text("Failed").foregroundStyle(FAIL_TEXT).fixedSize() }
                    if helper { Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(quiet) }
                    else if step.opens {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(quiet)
                            .rotationEffect(.degrees(opened ? 90 : 0)).frame(width: 10)
                    }
                }
                .font(F.font(14, .regular))
                .padding(.horizontal, StepInk.edge)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .contentShape(Rectangle())
                .transaction { $0.animation = nil }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(helper || step.opens)
            .onHover { hovered = $0 }
            .help(helper ? "Open this helper's work" : "")
            if opened {
                StepDetail(step: step).padding(.horizontal, StepInk.edge).padding(.top, 2).padding(.bottom, 14)
                    .transition(StepMotion.reveal)
            }
        }
    }
    private func openHelper() {
        guard let agentId, let s = ConvoHub.shared.store, let panel = s.panel(conv: conv, agentId: agentId) else { return }
        let tab = PanelTab(kind: .helper(id: step.id, title: step.line))
        if panel.agentId != agentId { panel.owners[tab.id] = agentId }
        panel.show(tab)
    }
}

/// A step opened (Mavis: StepDetail + StepOutput): exactly what ran and what came back, flat on the card, no box inside
/// the box. The command clear, its output quiet, a faint line between; how it ended last. Copy shows as you point.
struct StepDetail: View {
    let step: Step
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if step.verb == "Thought" {
                MarkdownText(text: step.detail ?? "", color: C.i10)
            } else if let diff = step.diff, !diff.isEmpty {
                ForEach(diff, id: \.self) { DiffBlock(change: $0) }
            } else {
                let out = Self.trim(Self.plain(step.output ?? ""), lines: 40)
                StepOutput(command: (step.detail ?? "").isEmpty ? nil : step.detail, output: out,
                           outcome: step.failed ? "Didn\u{2019}t work" : (step.verb == "Run" && step.done && out.isEmpty ? "No output" : nil), failed: step.failed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// Terminal colour codes out, carriage-return redraws kept to their last state.
    static func plain(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\u{1B}\[[0-?]*[ -/]*[@-~]|\u{1B}\][^\u{07}]*(\u{07}|\u{1B}\\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        if t.contains("\r") { t = t.split(separator: "\n", omittingEmptySubsequences: false).map { $0.split(separator: "\r", omittingEmptySubsequences: false).last.map(String.init) ?? "" }.joined(separator: "\n") }
        return t
    }
    static func trim(_ text: String, lines: Int) -> String {
        let all = text.components(separatedBy: "\n")
        guard all.count > lines else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return all.prefix(lines).joined(separator: "\n") + "\n\u{2026} \(all.count - lines) more lines"
    }
}

/// What ran and what came back (Mavis: StepOutput).
struct StepOutput: View {
    let command: String?; let output: String; let outcome: String?; let failed: Bool
    @State private var hover = false
    @State private var copied = false
    @Environment(\.displayScale) private var scale
    private let mono = Font.system(size: 12.5, design: .monospaced)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let command {
                Text(command).font(mono).foregroundStyle(C.i12).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).padding(.trailing, 26)
            }
            if command != nil, !output.isEmpty { StepInk.cardEdge.frame(height: 1 / scale) }
            if !output.isEmpty {
                ScrollView(.horizontal) {
                    Text(output).font(mono).lineSpacing(3).foregroundStyle(StepInk.lit).textSelection(.enabled).fixedSize().padding(.trailing, 8)
                }.scrollIndicators(.never)
            }
            if let outcome { Text(outcome).font(F.font(12, .regular)).foregroundStyle(failed ? FAIL_TEXT : StepInk.rest) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command ?? output, forType: .string)
                copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12)).foregroundStyle(StepInk.lit)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).opacity(hover || copied ? 1 : 0)
            .help(command == nil ? "Copy" : "Copy the command").accessibilityLabel(command == nil ? "Copy" : "Copy the command")
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// `+12 −3`, quiet.
struct ChangeCount: View {
    let files: [FileChange]
    var body: some View {
        let added = files.reduce(0) { $0 + $1.added }, removed = files.reduce(0) { $0 + $1.removed }
        if added + removed > 0 {
            (Text("+\(added)").foregroundStyle(MV.on ? MV.Accent.added : C.i10) + Text(" −\(removed)").foregroundStyle(MV.on ? MV.Accent.removed : C.i9))
                .font(F.font(12, .medium)).monospacedDigit()
        }
    }
}

/// Monospace in a quiet well, scrolling past `maxHeight` (from the end when `tail`), with copy on hover.
struct MonoBlock: View {
    let text: String; var copy: String? = nil; var maxHeight: CGFloat = 200; var tail = false
    @State private var hover = false
    var body: some View {
        let shown = text.count > 24_000 ? "…" + String(text.suffix(24_000)) : text
        ScrollViewReader { reader in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(shown).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(C.i10).lineSpacing(2)
                        .textSelection(.enabled).fixedSize().padding(.horizontal, 10).padding(.vertical, 8)
                    Color.clear.frame(height: 0).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: maxHeight).fixedSize(horizontal: false, vertical: true)
            .onAppear { if tail { reader.scrollTo("end", anchor: .bottom) } }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white(0.04)))
        .overlay(alignment: .topTrailing) { if hover, let copy { CopyChip(text: copy).padding(4) } }
        .onHover { hover = $0 }
    }
}

struct CopyChip: View {
    let text: String
    @State private var copied = false
    var body: some View {
        Hover { h in
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Text(copied ? "Copied" : "Copy").font(F.font(11, .medium)).foregroundStyle(h ? C.i12 : C.i10)
                    .padding(.horizontal, 8).frame(height: 22).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(C.v4))
            }.buttonStyle(.plain)
        }
    }
}

/// One file's change, its name on top with how much changed and Open.
struct DiffBlock: View {
    let change: FileChange; var maxHeight: CGFloat = 260
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(change.name).font(F.font(12, .medium)).foregroundStyle(C.i12).lineLimit(1)
                if change.change == "created" { Text("new").font(F.font(11, .regular)).foregroundStyle(C.i9) }
                if change.change == "deleted" { Text("deleted").font(F.font(11, .regular)).foregroundStyle(C.i9) }
                ChangeCount(files: [change])
                Spacer(minLength: 0)
                if FileManager.default.fileExists(atPath: change.path) {
                    Hover { h in
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: change.path)) } label: {
                            Text("Open").font(F.font(11, .medium)).foregroundStyle(h ? C.i12 : C.i10)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10).frame(height: 28)
            Rectangle().fill(C.divider).frame(height: 1)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(change.lines.enumerated()), id: \.offset) { _, line in
                        if line.k == "~" {
                            Text("⋯").font(.system(size: 11, design: .monospaced)).foregroundStyle(C.i9).padding(.leading, 10).frame(height: 18)
                        } else {
                            HStack(spacing: 6) {
                                Text(line.k == "+" ? "+" : line.k == "-" ? "−" : " ").foregroundStyle(line.k == "+" ? C.i10 : C.i9).frame(width: 8)
                                Text(line.t.isEmpty ? " " : line.t).foregroundStyle(line.k == "+" ? C.i12 : line.k == "-" ? C.i9 : C.i10)
                                    .strikethrough(line.k == "-", color: C.i9.opacity(0.5)).fixedSize()
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(.horizontal, 10).frame(minHeight: 18, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(line.k == "+" ? Color.white(0.05) : .clear)
                        }
                    }
                }
                .padding(.vertical, 4).textSelection(.enabled)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: maxHeight).fixedSize(horizontal: false, vertical: true)
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A finished turn's changes, together: "Changed 3 files +40 −12", each file opening to its change.
struct ChangedFiles: View {
    let files: [FileChange]
    /// Opens this chat's changes in the side panel (DMs).
    var review: (() -> Void)? = nil
    @State private var open: String?
    @State private var all = false
    /// The turn's changes, one per file (edits to the same file run together).
    static func gather(_ steps: [Step]) -> [FileChange] {
        var out: [FileChange] = []
        for change in steps.filter({ !$0.failed }).flatMap({ $0.diff ?? [] }) {
            if let i = out.firstIndex(where: { $0.path == change.path }) {
                out[i].lines += [.init(k: "~", t: "")] + change.lines
                if change.change == "deleted" { out[i].change = "deleted" }
            } else { out.append(change) }
        }
        return out
    }
    var body: some View {
        let shown = all ? files : Array(files.prefix(5))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // MAVIS: the Changes icon (the same one as the Changes pane), not a pen.
                Icon(MV.on ? "mvDiff" : "pen", 14).foregroundStyle(C.i10)
                Text(files.count == 1 ? "Changed 1 file" : "Changed \(files.count) files").font(F.font(13, .medium)).foregroundStyle(C.i12)
                ChangeCount(files: files)
                Spacer(minLength: 0)
                if let review { Hover { h in Button(action: review) { Text("Review").font(F.font(12, .medium)).foregroundStyle(h ? C.i12 : C.i10) }.buttonStyle(.plain) }.tip("Open this chat's changes in the side panel") }
            }
            .padding(.horizontal, 12).frame(height: 36)
            ForEach(shown, id: \.path) { f in
                Rectangle().fill(C.divider).frame(height: 1)
                Hover { h in
                    Button { open = open == f.path ? nil : f.path } label: {
                        HStack(spacing: 8) {
                            Text(f.name).font(F.font(13, .regular)).foregroundStyle(h ? C.i12 : C.i10).lineLimit(1)
                            Text(((f.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                                .font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.head)
                            Spacer(minLength: 8)
                            if f.change == "created" { Text("new").font(F.font(11, .regular)).foregroundStyle(C.i9) }
                            ChangeCount(files: [f])
                            Icon("chev", 10).foregroundStyle(C.i9).rotationEffect(.degrees(open == f.path ? 0 : -90))
                        }
                        .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if open == f.path { DiffBlock(change: f).padding(.horizontal, 8).padding(.bottom, 8) }
            }
            if files.count > 5 {
                Rectangle().fill(C.divider).frame(height: 1)
                Button(all ? "Show less" : "Show all \(files.count)") { all.toggle() }
                    .buttonStyle(.plain).font(F.font(12, .medium)).foregroundStyle(C.i10).padding(.horizontal, 12).frame(height: 30)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1))
    }
}

/// The pictures that came with a message.
struct SentImages: View {
    let paths: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(paths, id: \.self) { p in
                Group {
                    if let image = NSImage(contentsOfFile: p) { Image(nsImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "photo").foregroundStyle(C.i10) }
                }
                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: R.ctl))
                .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edge, lineWidth: 1))
                .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
            }
        }
    }
}

/// Over one of your messages in a DM, on hover: go back to just before it. It and everything after leave the chat;
/// your words come back to the box; Claude puts the files back as they were.
struct GoBack: View {
    @EnvironmentObject var s: Store
    let agentId: String; let messageId: String
    @State private var hover = false
    @State private var asking = false
    var body: some View {
        let busy = s.runs["agent:\(agentId)"] != nil
        ZStack(alignment: .topTrailing) {
            Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity, minHeight: 44).allowsHitTesting(false)
            if (hover || asking) && !busy && s.openAgent == agentId {
                HStack(spacing: Box.pair) {
                // Fork: a new chat with this agent that keeps everything before this message, the message in its box.
                Hover { h in
                    Button { s.fork(agentId, messageId) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .semibold))
                            Text("Fork").font(F.font(12, .medium))
                        }
                        .foregroundStyle(h ? C.i12 : C.i10).padding(.horizontal, 10).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v4 : C.v3))
                    }.buttonStyle(.plain)
                }
                .help("A new agent like this one, its chat everything before this message, with this message in its box to change")
                Hover { h in
                    Button { asking = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                            Text("Go back to here").font(F.font(12, .medium))
                        }
                        .foregroundStyle(h ? C.i12 : C.i10).padding(.horizontal, 10).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v4 : C.v3))
                    }.buttonStyle(.plain)
                }
                .help("Take this message and everything after it out of the chat, and put it back in the box")
                .popover(isPresented: $asking, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Go back to this message?").font(F.font(14, .semibold)).foregroundStyle(C.i12)
                        Text("It and everything after it leave the chat, and it goes back in the box. Files the agent changed since are put back (Claude Code; Codex keeps them).")
                            .font(F.font(12, .regular)).foregroundStyle(C.i10).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("Cancel") { asking = false }.keyboardShortcut(.cancelAction)
                            Button("Go back") { asking = false; s.rewind(agentId, messageId) }.keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(16).frame(width: 300)
                }
                }
            }
        }
        .onHover { hover = $0 }
    }
}

// A conversation with one agent (web: dmView, composer, approvalCard) and its row in Messages (web: convRow).
import SwiftUI
import AppKit

/// What an agent may do without asking: Mavis final launch's four modes (engine.js MODES holds what each allows).
enum Mode: String, CaseIterable, Identifiable {
    case read, ask, auto, full
    var id: String { rawValue }
    /// The saved value, with the old three levels read as their modes (plans only → read, edits freely → auto).
    static func of(_ p: String?) -> Mode { ["plan": .read, "edits": .auto][p ?? ""] ?? Mode(rawValue: p ?? "") ?? .ask }
    var title: String { switch self { case .read: "Read only"; case .ask: "Ask first"; case .auto: "Auto"; case .full: "Full access" } }
    var detail: String {
        switch self {
        case .read: "Looks and answers, changes nothing"
        case .ask: "Asks before every change it makes"
        case .auto: "Edits and runs commands for you"
        case .full: "Acts like you, with network access"
        }
    }
    var symbol: String { switch self { case .read: "eye"; case .ask: "hand.raised"; case .auto: "checkmark.shield"; case .full: "bolt.shield" } }
    /// Full access is the one mode in colour (Apple yellow), as in Mavis.
    var tint: Color? { self == .full ? Color(0xffd60a) : nil }
}
let PERMS: [String: String] = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0.rawValue, $0.title) } + [("plan", Mode.read.title), ("edits", Mode.auto.title)])
let MODEL_NAMES = ["opus": "Opus", "sonnet": "Sonnet", "haiku": "Haiku"]
let STATE_LABEL = ["needs": "Waiting for you", "working": "Working", "failed": "Failed", "done": "Done", "idle": "Ready"]
let WAIT_TEXT = Color(0x52a8ff), FAIL_TEXT = Color(0xff6166), WAIT = Color(0x0070f3)
/// mouad.work's blue (dark), for names and links in the chat's words: the same tone as the site's marked words.
let MARK_BLUE = Color.live(\.blue)

/// Made once (a new formatter per time label, twice per message, cost every redraw).
private let clockFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
private let dayFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f }()
func clock(_ ms: Double) -> String { clockFormat.string(from: Date(timeIntervalSince1970: ms / 1000)) }
func dayLabel(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    return dayFormat.string(from: d)
}
/// web: shortAgo
func shortAgo(_ ms: Double) -> String {
    let s = max(1, Date().timeIntervalSince1970 - ms / 1000)
    if s < 60 { return "now" }; let m = s / 60; if m < 60 { return "\(Int(m.rounded()))m" }
    let h = m / 60; if h < 24 { return "\(Int(h.rounded()))h" }; let d = h / 24; if d < 7 { return "\(Int(d.rounded()))d" }
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}

/// One message: face and name with time, or a continuation (web: .ln).
struct MessageLine: View {
    @EnvironmentObject var s: Store
    let agent: Agent; let m: Message; let cont: Bool; var draft = false
    var mine: Bool { m.role == "user" }
    var body: some View {
        Hover { h in
            HStack(alignment: .top, spacing: 16) {
                Group {
                    if cont { Text(m.at.map(clock) ?? "").font(F.font(11, .regular)).foregroundStyle(C.i9).opacity(h ? 1 : 0).frame(height: 24) }
                    else if mine { Circle().fill(C.v4).frame(width: 40, height: 40).overlay(Icon("person", 20).foregroundStyle(C.i10)) }
                    else { Avatar(agent: agent, size: 40, status: false) }
                }
                .frame(width: 40)
                VStack(alignment: .leading, spacing: 0) {
                    if !cont {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(mine ? "You" : agent.name).font(F.font(16, .semibold)).foregroundStyle(C.i12)
                            Text(draft ? "now" : m.at.map(clock) ?? "").font(F.font(12, .regular)).foregroundStyle(C.i10)
                        }
                    }
                    MarkdownText(text: mine && m.text.count > 1500 ? String(m.text.prefix(1200)) + "\n\n…\(m.text.count - 1200) more characters of context" : m.text, color: mine ? C.i12 : Color.white(0.686))
                        .frame(maxWidth: 680, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 4)
            .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? Color.white(0.02) : .clear))
            .padding(.top, cont ? 0 : 16)
        }
    }
}

/// Paragraphs, lists, **bold**, `code` and fenced code blocks (web: md()).
struct MarkdownText: View {
    let text: String; let color: Color
    /// Words found in the chat light up where they appear (ChatFind).
    @Environment(\.findQuery) private var find
    /// Drawn again when what decides its look changes (commands known, the file index), never differently by timing.
    @ObservedObject private var epoch = TextEpoch.shared
    var body: some View {
        // The app draws with AppKit text (MessageText.swift); offscreen renders (ImageRenderer can't draw AppKit views)
        // keep the SwiftUI blocks below, which look the same.
        if SnapshotMode.on {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Markdown.blocks(text).enumerated()), id: \.offset) { _, b in block(b) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(RichText.segments(text, color: color, lit: find).enumerated()), id: \.offset) { _, seg in segment(seg) }
            }
        }
    }
    @ViewBuilder func segment(_ seg: RichSegment) -> some View {
        switch seg {
        case .prose(let a): ProseView(text: a).padding(.horizontal, -Chip.room)     // room for a chip's fill, words unmoved
        case .quote(let a): ProseView(text: a).padding(.horizontal, -Chip.room).padding(.leading, 12).overlay(alignment: .leading) { Capsule().fill(C.v5).frame(width: 3) }
        case .rule: block(.rule)
        case .code(let body): block(.code(body))
        case .table(let h, let r): block(.table(header: h, rows: r))
        }
    }
    @ViewBuilder func block(_ b: MDBlock) -> some View {
        switch b {
        case .paragraph(let t):
            prose(t)
        case .heading(let level, let t):
            Text(MarkdownText.inline(t, size: level <= 2 ? 18 : 16, base: C.i12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .padding(.top, level <= 2 ? 8 : 4)
        case .item(let depth, let number, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if let number { Text("\(number).").font(F.font(16, .medium)).foregroundStyle(C.i10).monospacedDigit() }
                    else { Text(depth == 0 ? "•" : "◦").font(F.font(16, .medium)).foregroundStyle(C.i9) }
                }
                .frame(minWidth: 14, alignment: .trailing)
                prose(t)
            }
            .padding(.leading, CGFloat(depth) * 22 + 2)
        case .quote(let t):
            prose(t, base: C.i10)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(C.v5).frame(width: 3) }
        case .rule:
            Rectangle().fill(C.divider).frame(height: 1).padding(.vertical, 4)
        case .code(let body):
            ScrollView(.horizontal) { Text(body).font(.system(size: 13, design: .monospaced)).foregroundStyle(C.i12).lineSpacing(4).padding(.horizontal, 12).padding(.vertical, 10) }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v2))
                .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edge, lineWidth: 1))
                .textSelection(.enabled)
        case .table(let header, let rows):
            MDTable(header: header, rows: rows)
        }
    }
    func prose(_ t: String, base: Color? = nil) -> some View {
        Text(MarkdownText.inline(t, size: 16, base: base ?? color, weight: .regular)).lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
    /// Inline marks styled by hand (the app's font has no automatic bold): **bold** is semibold and brighter, `code` is the
    /// text's own font a touch heavier, links are blue on a soft blue underline. A half-written mark is closed first, so it never flashes as raw asterisks.
    static func inline(_ s: String, size: CGFloat, base: Color, weight: F.W) -> AttributedString {
        var a = (try? AttributedString(markdown: InlineMarks.closed(s), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        a.font = F.font(size, weight); a.foregroundColor = base
        for run in a.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { a[run.range].font = F.font(size, .semibold); a[run.range].foregroundColor = C.i12 }
            // `code`: the text's own font, a touch heavier and brighter. Links: mouad.work's blue on a soft underline of it
            // (MessageText.inline).
            if intent.contains(.code) {
                // Text draws a code mark in monospace whatever its font: the mark goes, the look stays.
                a[run.range].inlinePresentationIntent = intent.subtracting(.code)
                a[run.range].font = F.font(size, weight == .semibold ? .semibold : .medium); a[run.range].foregroundColor = C.i12
            }
            if run.link != nil {
                a[run.range].foregroundColor = MARK_BLUE
                a[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: MARK_BLUE.opacity(0.3))
            }
        }
        // Bare addresses are links too (RichText.autolink).
        let plain = String(a.characters)
        for m in RichText.detector?.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) ?? [] {
            guard let url = m.url, url.scheme == "http" || url.scheme == "https", let r = Range(m.range, in: a), a[r].link == nil else { continue }
            a[r].link = url; a[r].foregroundColor = MARK_BLUE
            a[r].underlineStyle = Text.LineStyle(pattern: .solid, color: MARK_BLUE.opacity(0.3))
        }
        return a
    }
}

/// A Markdown table: a header row, then rows on hairlines, in a quiet card.
struct MDTable: View {
    let header: [String]; let rows: [[String]]
    var body: some View {
        // Fits the column, its cells wrapping (as Claude's): a table that scrolled sideways caught every swipe that
        // started over it, and the chat stopped under your fingers.
        grid
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v2))
            .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edge, lineWidth: 1))
            .textSelection(.enabled)
    }
    var grid: some View {
        let n = max(header.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow { ForEach(0..<n, id: \.self) { c in cell(c < header.count ? header[c] : "", head: true) } }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                Divider().overlay(C.v4)
                GridRow { ForEach(0..<n, id: \.self) { c in cell(c < r.count ? r[c] : "", head: false) } }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }
    func cell(_ t: String, head: Bool) -> some View {
        Text(MarkdownText.inline(t, size: 14, base: head ? C.i12 : Color.white(0.82), weight: head ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
    }
}

/// Three blinking dots (web: .typing i)
struct Typing: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { t in
            let phase = Int(t.date.timeIntervalSinceReferenceDate / 0.15)
            HStack(spacing: 4) { ForEach(0..<3) { i in Circle().fill(C.i9).frame(width: 4, height: 4).opacity((phase - i) % 8 < 4 ? 1 : 0.3) } }
        }
    }
}

/// What the agent needs your OK for, inside its turn (Mavis final launch: PromptPanel), drawn in Agent Lab's own look.
/// The question in plain words, the exact command on a quiet well only when the words don't already say it, what the
/// step can do, then the answers as numbered rows. File changes and commands can be allowed for the rest of the
/// request, so a bulk job asks once; deleting, sending and sharing ask every time. fn + a number answers the first card.
struct ApprovalCard: View {
    @EnvironmentObject var s: Store
    let p: Approval; let primary: Bool
    struct Choice { let label: String; let detail: String?; let decision: String }
    var choices: [Choice] {
        let whole = ["write", "host"].contains(p.risk ?? "host")
        var out = [Choice(label: "Allow", detail: whole ? "For the rest of this request" : nil, decision: whole ? "turn" : "allow"),
                   Choice(label: "Don\u{2019}t allow", detail: nil, decision: "deny")]
        if whole { out.append(Choice(label: "Just this step", detail: nil, decision: "allow")) }
        if p.risk == "write" {
            out.append(Choice(label: "Always allow file changes", detail: "Until you change it in this agent\u{2019}s settings", decision: "always"))
        }
        return out
    }
    var body: some View {
        if let questions = p.questions, !questions.isEmpty { QuestionCard(p: p, questions: questions) } else { ask }
    }
    /// The main answer (the white Allow): for the rest of the request when a step can be, else this step.
    private var main: Choice { choices[0] }
    /// What Allow's arrow offers besides it.
    private var more: [Choice] { choices.filter { $0.decision != main.decision && $0.decision != "deny" } }
    @ViewBuilder private var ask: some View {
        if MV.on { mavisAsk } else { classicAsk }
    }
    /// MAVIS: the prototype's card (box, radius 16, the 4% inner ring): the question at 14.5 in t1, the command on a
    /// page-tone well when the words don't say it, then the answers as 32 pt pills on the right: Don't allow on box2,
    /// Allow white (as the box's send). It hugs its words, up to 360.
    private var mavisAsk: some View {
        let words = ApprovalWords.parse(tool: p.tool, verb: p.verb, line: p.line, command: p.command, about: p.about)
        let shape = RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous)
        let card = VStack(alignment: .leading, spacing: MV.Space.cardGap) {
            Text(words.title).font(F.font(MV.Text.message, .regular)).foregroundStyle(MV.Ink.t1)
                .lineSpacing(MV.Text.messageLine - MV.Text.message - MV.Space.xs)
                .fixedSize(horizontal: false, vertical: true)
            if let command = words.command {
                Text(ApprovalWords.tidy(command)).font(.system(size: MV.Text.meta, design: .monospaced)).foregroundStyle(MV.Ink.t2)
                    .lineLimit(2).truncationMode(.tail)
                    .padding(.horizontal, MV.Space.gridGap).padding(.vertical, MV.Space.labelGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous).fill(MV.Tone.page))
                    .help(command)
            }
            ForEach(p.diff ?? [], id: \.self) { DiffBlock(change: $0, maxHeight: 160) }
            HStack(spacing: MV.Space.labelGap) {
                if let risk = ApprovalWords.risk[p.risk ?? ""], ["delete", "send", "share"].contains(p.risk ?? "") {
                    Text(risk).font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3).lineLimit(1)
                }
                Spacer(minLength: 0)
                MVCardPill(label: "Don\u{2019}t allow") { s.answer(p.id, "deny") }.tip("Don\u{2019}t allow", "fn 2", edge: .top)
                MVCardPill(label: "Allow", primary: true, more: more.map { c in (c.label, { s.answer(p.id, c.decision) }) }) { s.answer(p.id, main.decision) }
                    .tip("Allow", main.detail.map { "\($0) \u{00B7} fn 1" } ?? "fn 1", edge: .top)
            }
        }
        .padding(MV.Approval.padding)
        .background(shape.fill(MV.Tone.box))
        .overlay(shape.strokeBorder(MV.Approval.ring, lineWidth: MV.Approval.ringWidth).allowsHitTesting(false))
        return ViewThatFits(in: .horizontal) {
            card.fixedSize()
            card.frame(width: MV.Approval.width, alignment: .leading)
        }
        .frame(maxWidth: MV.Approval.width, alignment: .leading)
        .help(p.line ?? "")
        .background(primary ? FnKeys(count: 2) { s.answer(p.id, $0 == 0 ? main.decision : "deny") } : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Needs your OK: \(words.title)")
    }
    @ViewBuilder private var classicAsk: some View {
        let words = ApprovalWords.parse(tool: p.tool, verb: p.verb, line: p.line, command: p.command, about: p.about)
        // In the chat box's own shell: what it wants in plain words, the exact command in a well, then the answers on one
        // row, Allow the one white button (as the box's send is). Steps that always ask say what they can do.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(words.title).font(F.font(14, .medium)).foregroundStyle(C.i12).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let command = words.command {
                    Text(ApprovalWords.tidy(command)).font(.system(size: 12, design: .monospaced)).foregroundStyle(C.i10)
                        .lineLimit(2).truncationMode(.tail).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v1))
                        .help(command)
                }
                // An edit: the change itself, so you see what you'd allow.
                ForEach(p.diff ?? [], id: \.self) { DiffBlock(change: $0, maxHeight: 160) }
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 10)
            HStack(spacing: 8) {
                if let risk = ApprovalWords.risk[p.risk ?? ""], ["delete", "send", "share"].contains(p.risk ?? "") {
                    Text(risk).font(F.font(12, .regular)).foregroundStyle(C.i9).padding(.leading, 6).lineLimit(1)
                }
                Spacer(minLength: 0)
                CardButton(label: "Don\u{2019}t allow", tip: "fn 2") { s.answer(p.id, "deny") }
                CardButton(label: "Allow", primary: true, tip: main.detail.map { "\($0) \u{00B7} fn 1" } ?? "fn 1",
                           more: more.map { c in (c.label, { s.answer(p.id, c.decision) }) }) { s.answer(p.id, main.decision) }
            }
        }
        .padding(Box.pad + 2)
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
        .background(primary ? FnKeys(count: 2) { s.answer(p.id, $0 == 0 ? main.decision : "deny") } : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Needs your OK: \(words.title)")
    }
}

/// MAVIS approval answers: 32 pt pills, radius full. Allow is white with dark words (the send button's look) and, when it
/// has more choices, a chevron of its own inside the pill; Don't allow is box2. MV states (10% / 16%).
struct MVCardPill: View {
    let label: String; var primary = false
    var more: [(String, () -> Void)] = []
    let action: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(label).font(F.font(MV.Text.footer, .medium))
                    .padding(.leading, MV.Approval.buttonPad).padding(.trailing, more.isEmpty ? MV.Approval.buttonPad : MV.Space.xs)
                    .frame(height: MV.Approval.button).contentShape(Rectangle())
            }
            .buttonStyle(MVStates(shape: Rectangle()))
            if !more.isEmpty {
                Menu {
                    ForEach(Array(more.enumerated()), id: \.offset) { _, m in Button(m.0, action: m.1) }
                } label: {
                    Icon("mvChevDown", MV.Size.iconSmall).frame(width: MV.Approval.chevron, height: MV.Approval.button).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More ways to allow")
            }
        }
        .foregroundStyle(primary ? MV.Ink.onWhite : MV.Ink.t1)
        .background(primary ? Color.white : MV.Tone.box2)
        .clipShape(Capsule())
    }
}

/// The card's answers: 32 tall, the app's control corner. The primary is white (as the box's send); its arrow, when it
/// has more choices, opens them.
struct CardButton: View {
    let label: String; var primary = false; var tip: String? = nil
    var more: [(String, () -> Void)] = []
    let action: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Hover { h in
                Button(action: action) {
                    Text(label).font(F.font(13, .medium)).padding(.leading, 12).padding(.trailing, more.isEmpty ? 12 : 6)
                        .frame(height: Bar.control).contentShape(Rectangle())
                        .background(h ? (primary ? C.primaryHover : C.v5) : .clear)
                }.buttonStyle(.plain)
            }
            if !more.isEmpty {
                Menu {
                    ForEach(Array(more.enumerated()), id: \.offset) { _, m in Button(m.0, action: m.1) }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                        .frame(width: 24, height: Bar.control).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More ways to allow")
            }
        }
        .foregroundStyle(primary ? C.v1 : C.i12)
        .background(primary ? C.i12 : C.v4)
        .clipShape(RoundedRectangle(cornerRadius: R.ctl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).strokeBorder(primary ? .clear : C.edgeControl, lineWidth: 1))
        .tip(label, tip, edge: .top)
    }
}

/// The agent asks you something (Claude Code's AskUserQuestion): each question with its options to pick, something
/// else in your own words, then Answer.
struct QuestionCard: View {
    @EnvironmentObject var s: Store
    let p: Approval; let questions: [Approval.Question]
    @State private var picked: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]
    var answers: [String: [String]] {
        var out: [String: [String]] = [:]
        for q in questions {
            var v = Array(picked[q.question] ?? [])
            if let o = other[q.question]?.trimmingCharacters(in: .whitespaces), !o.isEmpty { v.append(o) }
            out[q.question] = v
        }
        return out
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(questions.count == 1 ? "A question for you" : "A few questions for you").font(F.font(12, .medium)).foregroundStyle(C.i9)
                Spacer(minLength: 8)
                CardClose(help: "Skip") { s.answer(p.id, "note", "The user skipped these questions.") }
            }
            ForEach(questions, id: \.self) { q in
                VStack(alignment: .leading, spacing: 4) {
                    if !q.header.isEmpty { Text(q.header).font(F.font(11, .medium)).foregroundStyle(C.i9) }
                    Text(q.question).font(F.font(14, .medium)).foregroundStyle(C.i12).fixedSize(horizontal: false, vertical: true).padding(.bottom, 2)
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                        let on = picked[q.question]?.contains(o.label) == true
                        ChoiceRow(number: i + 1, label: (on ? "✓ " : "") + o.label, detail: o.about.isEmpty ? nil : o.about) {
                            var set = picked[q.question] ?? []
                            if q.multiple { if on { set.remove(o.label) } else { set.insert(o.label) } } else { set = on ? [] : [o.label]; other[q.question] = nil }
                            picked[q.question] = set
                        }
                    }
                    TextField("", text: Binding(get: { other[q.question] ?? "" }, set: { other[q.question] = $0; if !$0.isEmpty, !q.multiple { picked[q.question] = [] } }),
                              prompt: Text("Something else…").foregroundStyle(C.i9))
                        .textFieldStyle(.plain).font(F.font(13, .regular)).foregroundStyle(C.i12)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white(0.05)))
                }
            }
            HStack {
                Spacer()
                let ready = questions.allSatisfy { !(answers[$0.question] ?? []).isEmpty }
                Hover { h in
                    Button { s.answer(p.id, "answers", answers) } label: {
                        Text("Answer").font(F.font(13, .medium)).foregroundStyle(ready ? C.v1 : C.i9).padding(.horizontal, 14).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: R.ctl).fill(ready ? (h ? C.primaryHover : C.i12) : C.v4))
                    }.buttonStyle(.plain).disabled(!ready)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.v3))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
    }
}

/// One answer: its number on a small key cap, the label, and under it what choosing it means. Lights at once under the
/// pointer. Inner radius 8 = the card's 14 less its 6 inset.
struct ChoiceRow: View {
    let number: Int; let label: String; let detail: String?; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(number)").font(F.font(12, .medium)).monospacedDigit().foregroundStyle(C.i10)
                        .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white(0.08)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(F.font(14, .regular)).foregroundStyle(C.i12).frame(minHeight: 20)
                        if let detail { Text(detail).font(F.font(12, .regular)).foregroundStyle(C.i10) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(h ? Color.white(0.07) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The card's quiet ✕.
struct CardClose: View {
    let help: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Icon("x", 10).foregroundStyle(h ? C.i12 : C.i10).frame(width: 20, height: 20)
                    .background(Circle().fill(h ? Color.white(0.08) : .clear)).contentShape(Circle().inset(by: -4))
            }.buttonStyle(.plain).tip(help).accessibilityLabel(help)
        }
    }
}

/// fn + 1…9 answers the card that's up (Mavis: Talk.swift), so plain digits still type in the message box.
struct FnKeys: NSViewRepresentable {
    let count: Int; let pick: (Int) -> Void
    func makeNSView(context: Context) -> NSView { Watcher(self) }
    func updateNSView(_ v: NSView, context: Context) { (v as? Watcher)?.keys = self }
    final class Watcher: NSView {
        var keys: FnKeys; private var monitor: Any?
        init(_ k: FnKeys) { keys = k; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.window === self.window, !MainActor.assumeIsolated({ self.inAwayChat }), e.modifierFlags.contains(.function),
                      let n = Int(e.charactersIgnoringModifiers ?? ""), n >= 1, n <= self.keys.count else { return e }
                self.keys.pick(n - 1); return nil
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
struct DangerButton: View {
    let title: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Line(title, 14, .medium, FAIL_TEXT).padding(.horizontal, 16).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? Color(0xe5484d, 0.16) : C.v1))
                    .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}
struct ComposerButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                Group {
                    // Our own drawn icons by name; anything else is an SF Symbol (the + menu's paperclip, at the mode button's size).
                    if IconData.all[icon] != nil { Icon(icon, 22) } else { Image(systemName: icon).font(.system(size: 17, weight: .regular)) }
                }
                .foregroundStyle(h ? C.i12 : C.i10).frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: Box.inner, style: .continuous).fill(h ? C.v4 : C.v3)).contentShape(Rectangle())
            }.buttonStyle(.plain).tip(label, edge: .top).accessibilityLabel(label)
        }
    }
}

// MARK: More: rename, workspaces it's in, delete (web: agent-edit)

struct AgentMenu: View {
    @EnvironmentObject var s: Store
    let agent: Agent; var size: CGFloat = 32
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false
    var body: some View {
        Menu {
            Button("Rename…") { newName = agent.name; renaming = true }
            // The same agent can be in any number of workspaces: a tick for each one it's in.
            if !s.workspaces.isEmpty {
                Menu("Workspaces") {
                    ForEach(s.workspaces) { w in
                        let on = w.members?.contains(agent.id) == true
                        Toggle(w.name, isOn: Binding(get: { on }, set: { v in Task { await s.setMember(agent.id, w.id, v) } }))
                    }
                }
            }
            Button("Open folder") { NSWorkspace.shared.open(URL(fileURLWithPath: agent.cwd ?? s.home)) }
            Divider()
            Button("Delete \(agent.name)…", role: .destructive) { deleting = true }
        } label: {
            Icon("more", 18).foregroundStyle(C.i10).frame(width: size, height: size).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More").accessibilityLabel("More for \(agent.name)")
        .alert("Rename \(agent.name)", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { return }
                Task { do { try await s.updateAgent(agent.id, ["name": n]) } catch { s.toast = error.localizedDescription } }
            }
        }
        .confirmationDialog("Delete \(agent.name)?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { Task { await s.deleteAgent(agent.id) } }
        } message: { Text("Its conversation goes with it. Your files stay as they are.") }
    }
}

// MARK: Messages list row (web: convRow)

struct ConvRow: View {
    @EnvironmentObject var s: Store
    let agent: Agent
    /// Its ⋯ menu is open (the list draws this row above the others while it is).
    @Binding var menuOpen: Bool
    @State private var deleting = false
    @State private var rowHover = false
    /// The row's corner, and how far in the ⋯ sits from its corner: the button's corner follows (concentric).
    static let corner: CGFloat = R.ctl, inset: CGFloat = 6
    var body: some View {
        if MV.on { mavisRow } else { classicRow }
    }
    /// MAVIS (prototype Messages list): 66 tall, radius 12, padding 10 12; the 44 face with its status ring; name 15/22
    /// and the time on one line, the last line 14/21 under it. Selected: a 16% blue wash, white name, pale-blue words.
    /// No ⋯ (right-click still opens the menu) and no third line.
    var mavisRow: some View {
        let st = s.state(of: agent), on = s.openAgent == agent.id, t = lastAt(agent)
        let shape = RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
        return Button { s.openChat(agent.id) } label: {
            HStack(spacing: MV.Space.inset) {
                MVFace(agent: agent, live: st == "working" || st == "needs", under: on ? MV.Accent.selectedSolid : MV.Tone.frame,
                       badge: s.unreadReplies(agent.id) + (st == "needs" ? s.approvalsFor(agent.id).count : 0))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: MV.Space.sm) {
                        // Long words fade out at their end (as the workspace's title), never "…".
                        MVFadeText(text: agent.name, font: F.font(MV.Text.name, .medium), color: on ? Color.white : MV.Ink.t1)
                        Spacer(minLength: 0)
                        if t > 0 { Text(shortAgo(t)).font(F.font(MV.Text.footer, .regular)).foregroundStyle(on ? MV.Accent.selectedText : MV.Ink.t3).monospacedDigit()
                            .opacity(rowHover || menuOpen ? 0 : 1) }          // ⋯ takes its place on hover
                    }
                    .frame(height: MV.Text.nameLine)
                    Group {
                        if st == "working" {
                            Shimmer(text: statusLine(st), font: F.font(MV.Text.preview, .regular), base: on ? MV.Ink.t3 : MV.Ink.t3, band: on ? Color.white : MV.Ink.t1)
                        } else {
                            MVFadeText(text: statusLine(st), font: F.font(MV.Text.preview, .regular),
                                       color: st == "failed" ? MV.Accent.red : on ? MV.Accent.selectedText : MV.Ink.t2)
                        }
                    }
                    .frame(height: MV.Text.previewLine)
                }
            }
            .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.listRow)
            .background(shape.fill(on ? MV.Accent.selected : .clear))
            .overlay(shape.fill(rowHover || menuOpen ? MV.Wash.stHover : .clear).allowsHitTesting(false))
            .contentShape(shape)
        }
        // The row's hover is the whole row's, ⋯ included (the button's own hover dropped it as you reached ⋯).
        .buttonStyle(MVStates(shape: shape, hoverable: false))
        // On hover, ⋯ in the time's place, 8 in from the row's top and right, concentric with it; its menu floats from it.
        .overlay(alignment: .topTrailing) {
            ZStack {
                if rowHover || menuOpen { MVMoreButton(open: menuOpen, corner: MV.Radius.tile, inset: MV.Space.labelGap, selected: on) { menuOpen.toggle() } }
            }
            .frame(width: MV.Size.iconButton, height: MV.Size.iconButton)
            .unlessSnapshot { $0.floatingMenu($menuOpen, pop: true) { AgentActions(agent: agent, open: $menuOpen) { deleting = true } } }
            .padding(.top, MV.Space.labelGap).padding(.trailing, MV.Space.labelGap)
        }
        .containerShape(shape)
        .onHover { rowHover = $0 }
        // AppKit hooks (right-click) can't be drawn offscreen: snapshots leave them out.
        .unlessSnapshot { $0.onRightClick { menuOpen = true } }
        .confirmationDialog("Delete \(agent.name)?", isPresented: $deleting) {
            Button("Delete agent", role: .destructive) { Task { await s.deleteAgent(agent.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its conversation and notes go with it. Your files stay as they are.") }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityLabel("Open \(agent.name)")
    }
    var classicRow: some View {
        let st = s.state(of: agent), on = s.openAgent == agent.id, t = lastAt(agent)
        let model = agent.model.map { MODEL_NAMES[$0] ?? $0 }
        let ws = s.workspaces.filter { $0.members?.contains(agent.id) == true }.map(\.name).first
        let facts = [model, ws ?? ((agent.cwd ?? s.home) as NSString).lastPathComponent, PERMS[agent.permission ?? "ask"]].compactMap { $0 }.joined(separator: " · ")
        return Hover { h in
            HStack(alignment: .top, spacing: 12) {
                Avatar(agent: agent, size: 40, ring: on ? C.v4 : h ? C.v3 : C.v0).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(agent.name).font(F.font(14, .semibold)).foregroundStyle(C.i12).lineLimit(1)
                        if agent.pinned == true {
                            Image(systemName: "pin.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(C.i10).rotationEffect(.degrees(45))
                                .accessibilityLabel("Pinned")
                        }
                    }
                    Text(statusLine(st)).font(F.font(14, .regular)).foregroundStyle(st == "needs" ? WAIT_TEXT : st == "failed" ? FAIL_TEXT : Color.white(0.686)).lineLimit(1)
                    Text(facts).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1)
                }
                Spacer(minLength: 0)
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 8) {
                        if t > 0 { Text(shortAgo(t)).font(F.font(12, .regular)).foregroundStyle(C.i10).monospacedDigit() }
                        if st == "needs" || st == "working" { Circle().fill(st == "needs" ? WAIT : Color(0xe0a100)).frame(width: 8, height: 8) }
                    }
                    .padding(.top, 2).opacity(h || menuOpen ? 0 : 1)
                }
            }
            .padding(12).frame(minHeight: 80, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(on ? C.v4 : h || menuOpen ? C.v3 : .clear))
            // On hover, ⋯ in the time's place: its top and right edges `inset` in from the row's, its corner concentric
            // with the row's (the container shape below), the same on every row. The menu floats from that spot.
            .overlay(alignment: .topTrailing) {
                ZStack {
                    if h || menuOpen { MoreButton(open: menuOpen, corner: Self.corner, inset: Self.inset) { menuOpen.toggle() } }
                }
                .frame(width: MoreButton.size, height: MoreButton.size)
                .floatingMenu($menuOpen, pop: true) { AgentActions(agent: agent, open: $menuOpen) { deleting = true } }
                .padding(.top, Self.inset).padding(.trailing, Self.inset)
            }
            .containerShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { s.openChat(agent.id) }
            .onRightClick { menuOpen = true }
            .confirmationDialog("Delete \(agent.name)?", isPresented: $deleting) {
                Button("Delete agent", role: .destructive) { Task { await s.deleteAgent(agent.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Its conversation and notes go with it. Your files stay as they are.") }
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityLabel("Open \(agent.name)")
    }
    /// web: statusLine
    func statusLine(_ st: String) -> String {
        if st == "needs", let p = s.approvalsFor(agent.id).first { return "Wants to \((p.verb ?? "").lowercased()) \(p.line ?? "")" }
        if st == "working" { return s.runs["agent:\(agent.id)"]?.activity ?? "Working" }
        if st == "failed" { return "Stopped with an error" }
        if let last = s.messages[agent.id]?.last(where: { $0.role == "assistant" }) { return String(last.text.prefix(100)) }
        if let j = agent.job, !j.isEmpty { return String(j.prefix(100)) }
        return "Ready when you are"
    }
}

/// ⋯ : 28 square, its corner concentric with the row it sits in (ConcentricRectangle on macOS 26, the same sum before).
struct MoreButton: View {
    let open: Bool; let corner: CGFloat; let inset: CGFloat; let action: () -> Void
    static let size: CGFloat = 28
    var body: some View {
        Hover { h in
            Button(action: action) {
                Icon("more", 18).foregroundStyle(h || open ? C.i12 : C.i10)
                    .frame(width: Self.size, height: Self.size)
                    .background(shape.fill(open ? C.v5 : h ? C.v4 : .clear))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
        }
        .tip("More").accessibilityLabel("More")
    }
    /// Concentric with the row where it touches the row's corner; the corners away from the row's edge take the same
    /// radius (a corner far from the container's would otherwise come out square).
    private var shape: AnyShape {
        let r = max(R.xs, corner - inset)
        if #available(macOS 26.0, *) { return AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(r)), isUniform: true)) }
        return AnyShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}

/// What you can do to an agent, from its ⋯: pin (or unpin), duplicate, delete.
struct AgentActions: View {
    @EnvironmentObject var s: Store
    let agent: Agent; @Binding var open: Bool
    let delete: () -> Void
    var body: some View {
        ActionMenu(open: $open, width: 200, items: [
            .init(symbol: agent.pinned == true ? "pin.slash" : "pin", title: agent.pinned == true ? "Unpin" : "Pin") {
                Task { do { try await s.updateAgent(agent.id, ["pinned": agent.pinned != true]) } catch { s.toast = error.localizedDescription } }
            },
            .init(symbol: "pencil", title: "Edit agent") { s.editingAgent = agent.id },
            .init(symbol: "plus.square.on.square", title: "Duplicate") { Task { await s.duplicateAgent(agent.id) } },
            // Pass the chat to another agent: its chat opens with the picker (ChatView: HandOffMenu).
            .init(symbol: "arrow.turn.up.right", title: "Hand off…") { s.openChat(agent.id); s.handingOff = agent.id },
            .divider,
            .init(symbol: "trash", title: "Delete agent", danger: true) { delete() },
        ])
    }
}

/// A menu in the app's own style (the agent picker's surface): rows of an icon and a label, dividers, red for what
/// can't be undone. Rows are concentric with the menu (ConcentricRectangle in its container shape). Shown with
/// `.floatingMenu`, which closes it on Esc or a click outside; a choice closes it here.
struct ActionMenu: View {
    struct Item: Identifiable {
        let id = UUID()
        var symbol = ""; var title = ""; var detail: String? = nil; var danger = false; var on: Bool? = nil
        var action: () -> Void = {}
        var isDivider = false
        static var divider: Item { Item(isDivider: true) }
        init(symbol: String, title: String, detail: String? = nil, danger: Bool = false, on: Bool? = nil, action: @escaping () -> Void) {
            self.symbol = symbol; self.title = title; self.detail = detail; self.danger = danger; self.on = on; self.action = action
        }
        private init(isDivider: Bool) { self.isDivider = isDivider }
    }
    @Binding var open: Bool
    var width: CGFloat = 240
    let items: [Item]
    static let padding: CGFloat = 4
    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                if item.isDivider { Rectangle().fill(C.divider).frame(height: 1).padding(.vertical, 2).padding(.horizontal, 4) }
                else { row(item) }
            }
        }
        .padding(Self.padding).frame(width: width)
        .background(RoundedRectangle(cornerRadius: R.card, style: .continuous).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
        .containerShape(RoundedRectangle(cornerRadius: R.card, style: .continuous))
        .floatShadow()
    }
    private func row(_ item: Item) -> some View {
        let ink = item.danger ? FAIL_TEXT : C.i12
        return Hover { h in
            Button { open = false; item.action() } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.symbol).font(.system(size: 14)).foregroundStyle(ink).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Line(item.title, 14, .medium, ink)
                        if let d = item.detail { Text(d).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let on = item.on { Switch(on: on) }
                }
                .padding(.horizontal, 8).frame(minHeight: 40)
                .background(Self.shape.fill(h ? (item.danger ? Color(0xe5484d, 0.12) : C.v3) : .clear)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
    /// A row's corner: concentric with the menu's (its corner less the padding).
    static var shape: AnyShape {
        if #available(macOS 26.0, *) { return AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(R.card - padding)), isUniform: true)) }
        return AnyShape(RoundedRectangle(cornerRadius: R.card - padding, style: .continuous))
    }
}

/// A right-click on the view (and only a right-click: everything else goes through to it).
struct RightClick: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> Catcher { Catcher(action) }
    func updateNSView(_ v: Catcher, context: Context) { v.action = action }
    final class Catcher: NSView {
        var action: () -> Void
        init(_ a: @escaping () -> Void) { action = a; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) { action() }
    }
}

extension View {
    func onRightClick(_ action: @escaping () -> Void) -> some View { overlay(RightClick(action: action)) }
}

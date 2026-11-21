// Checks the chat's rules without a window (Sources/ChatCore.swift, ChatTurns.swift). One line per check; exits 1 on a
// failure. Ported from Mavis's self-test (MavisSelfTest.swift) plus the reducer's own cases.
//   build/chattest
import Foundation
import CoreGraphics

@main
struct ChatTest {
    nonisolated(unsafe) static var failed = 0
    static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        print(ok ? "ok   \(name)" : "FAIL \(name) \(detail())"); if !ok { failed += 1 }
    }
    static func msg(_ id: String, _ role: String, _ text: String, turn: String? = nil, at: Double = 0, verb: String? = nil, tool: String? = nil, round: Int? = nil, done: Bool? = nil) -> Message {
        Message(id: id, role: role, text: text, verb: verb, at: at, turn: turn, ch: nil, toolId: tool, round: round, done: done, failed: nil)
    }
    static func main() {
        // Words arrive (chat-rules §2)
        let t = "Hello there friend, how are you"
        let a = WordReveal.advance(t, after: 0, budget: 10, streaming: true).end
        check("reveal ends on a whole word", a == t.count || Array(t)[a] == " ", "\(a)")
        check("a growing last word waits", WordReveal.advance("one two thr", after: 8, budget: 99, streaming: true).end == 8)
        check("a finished last word shows", WordReveal.advance("one two thr", after: 8, budget: 99, streaming: false).end == 11)
        let bare = (1...20).map { WordReveal.advance("Intro\n- item one more", after: 5, budget: Double($0), streaming: true).end }
        check("a list marker never shows without its word", !bare.contains(7) && bare.contains(12), "\(bare)")
        check("a long word still shows once saved up", WordReveal.advance("see https://example.com/a/very/long/path/that/goes/on/and/on ok", after: 4, budget: WordReveal.longWord, streaming: true).end > 4)
        // A reply that lands all at once flows out: about a line per step at most, done within three seconds, slowing gently at the end.
        let burst = String(repeating: "word ", count: 400)
        var shown = 0, rate = WordReveal.floor, budget = 0.0, steps = 0, biggest = 0
        while shown < burst.count && steps < 1000 {
            rate = WordReveal.pace(rate, backlog: burst.count - shown)
            budget = min(budget + rate * WordReveal.tick, WordReveal.cap(rate))
            let r = WordReveal.advance(burst, after: shown, budget: budget, streaming: false)
            biggest = max(biggest, r.end - shown); shown = r.end; budget = r.budget; steps += 1
        }
        check("a 2,000-char burst never shows more than a line in one step", biggest <= 70, "\(biggest)")
        check("a 2,000-char burst is out within 3 s", Double(steps) * WordReveal.tick <= 3.0, "\(Double(steps) * WordReveal.tick) s")
        check("speed eases up, never leaps", WordReveal.pace(WordReveal.floor, backlog: 2000) < 600)
        check("words on screen stay when the text changes", LiveWords.shared("Hello there friend", "Hello there pal", upTo: 18) == 12)

        // Inline marks cut off mid-span keep their style
        check("an open bold span is closed", InlineMarks.closed("**Notes: Mavis") == "**Notes: Mavis**", InlineMarks.closed("**Notes: Mavis"))
        check("an open code span is closed", InlineMarks.closed("open `Mavis final") == "open `Mavis final`")
        check("closed spans are left alone", InlineMarks.closed("**a** and `b`") == "**a** and `b`")
        check("stars inside code don't count", InlineMarks.closed("`a ** b` c") == "`a ** b` c")

        // A to-do list written as text becomes the card
        let listed = Checklist.asPlan("To-do list:\n- [ ] List the files\n- [x] Read the README\n- [ ] Count TODOs\n\nI'll start with the files.")
        check("a written checklist becomes the plan", PlanTag.parse(listed)?.items == ["List the files", "Read the README", "Count TODOs"] && PlanTag.parse(listed)?.done == [2], listed)
        check("no checklist or its heading shows", !Tags.strip(listed).contains("[ ]") && !Tags.strip(listed).contains("To-do") && Tags.strip(listed).contains("I'll start"), Tags.strip(listed))
        check("ordinary lists are left alone", Checklist.asPlan("- one\n- two") == "- one\n- two")

        // The approval card's words (Mavis: ApprovalText)
        let cd = ApprovalWords.run("cd ~; ls -A | head -80; for d in \"Desktop/Mavis final launch\" \"Desktop/Agent Lab\"; do echo; echo \"=== $d\"; ls -lA \"$d\"; done")
        check("a long command names what it runs", cd.title == "Run ls and head?" && cd.command != nil, cd.title)
        check("a short command is the question", ApprovalWords.run("npm test") == .init(title: "Run \u{201C}npm test\u{201D}?", command: nil))
        check("cd says only where", ApprovalWords.run("cd app && npm test").title == "Run \u{201C}npm test\u{201D}?")
        check("a file change names its file", ApprovalWords.parse(tool: "Edit", verb: "Edit", line: "refund.js", command: nil).title == "Edit refund.js?")
        check("links read as their site", ApprovalWords.parse(tool: "WebFetch", verb: "Open", line: "https://www.apple.com/mac", command: nil).title == "Open Apple?")

        // Hidden lines
        let raw = "I'll check it. ⟦plan: Find it | Fix it | Test it⟧ Working. ⟦done: 1⟧ More."
        let plan = PlanTag.parse(raw)
        check("plan parses", plan?.items == ["Find it", "Fix it", "Test it"] && plan?.done == [1], "\(String(describing: plan))")
        check("tags never show", !Tags.strip(raw).contains("⟦"), Tags.strip(raw))
        check("a closed report leaves a paragraph break", Tags.strip("Built.⟦report: R⟧ body ⟦/report⟧Shall I ship it?") == "Built.\n\nShall I ship it?", Tags.strip("Built.⟦report: R⟧ body ⟦/report⟧Shall I ship it?"))
        check("a half-written tag never shows", Tags.strip("Done. ⟦pla") == "Done.")
        let rep = ReportTag.reports("Answer. ⟦report: Audit⟧ # Findings\nmany words")
        check("an open report is still arriving", rep.count == 1 && !rep[0].finished && rep[0].title == "Audit")

        // Plan progress
        let p3 = PlanTag.Plan(items: ["a", "b", "c"], done: [])
        check("nothing ticked before work", PlanTag.progress(p3, finishedRounds: 0, answering: false).done.isEmpty)
        check("one tick per finished round", PlanTag.progress(p3, finishedRounds: 1, answering: false).done == [1])
        check("the last item waits for the answer", PlanTag.progress(p3, finishedRounds: 5, answering: false).done == [1, 2])
        check("Claude's own ticks lead", PlanTag.progress(PlanTag.Plan(items: ["a", "b", "c"], done: [2]), finishedRounds: 0, answering: false).done == [1, 2])
        check("a batch is one round", PlanTag.finishedRounds([(1, true), (1, true), (2, false)]) == 1)
        check("never skips running work", PlanTag.finishedRounds([(1, true), (2, false), (3, true)]) == 1)

        // The follower's spring (chat-rules §5)
        let first = Glide.step(gap: 142, velocity: 0, dt: 1.0 / 60)
        check("glide eases in", first.move < 10, "\(first.move)")
        var moved: CGFloat = 0, v: CGFloat = 0, over = false
        for _ in 0..<120 { let s = Glide.step(gap: 142 - moved, velocity: v, dt: 1.0 / 60); moved += s.move; v = s.velocity; if moved > 142.01 { over = true } }
        check("glide never overshoots and arrives", !over && abs(moved - 142) < 0.5, "\(moved)")
        check("glide never moves up", Glide.step(gap: 0, velocity: 50, dt: 1.0 / 60).move <= 0.0001)
        // Your send: fast first, settling, like OpenBot (about 75% after 0.1 s, there by about 0.3 s, never past it).
        var sm: CGFloat = 0, sv = Glide.launch(gap: 600), at01: CGFloat = 0, at035: CGFloat = 0, sover = false
        for f in 1...60 { let s = Glide.step(gap: 600 - sm, velocity: sv, dt: 1.0 / 60, response: Glide.sendResponse); sm += s.move; sv = s.velocity
            if sm > 600.01 { sover = true }; if f == 6 { at01 = sm }; if f == 21 { at035 = sm } }
        check("a send glide starts fast", at01 / 600 > 0.68 && at01 / 600 < 0.85, "\(at01 / 600)")
        check("a send glide settles by 0.35 s", at035 / 600 > 0.98 && !sover, "\(at035 / 600)")

        // The reducer (ChatTurns.swift)
        let ms = [
            msg("u1", "user", "fix it", at: 1000),
            msg("a1", "assistant", "I'll look. ⟦plan: Find | Fix⟧", turn: "u1", at: 1100),
            msg("t1", "tool", "app.js", turn: "u1", at: 1200, verb: "Read", tool: "x1", round: 1, done: true),
            msg("t2", "tool", "npm test", turn: "u1", at: 1300, verb: "Run", tool: "x2", round: 2, done: true),
            msg("a2", "assistant", "Fixed the null check. ⟦done: 2⟧", turn: "u1", at: 1400),
        ]
        let rows = Transcript.build(ms, run: nil, draft: nil, pending: []).rows
        check("one row for you, one for the turn", rows.count == 2, "\(rows.map(\.id))")
        if case .agent(let turn)? = rows.last {
            let pieces = TurnFlow.pieces(steps: turn.steps, raw: turn.raw, shown: turn.text.count)
            let (opening, work, tail) = TurnFlow.split(pieces)
            check("opening, work, tail in order", opening.count == 1 && work.count == 1 && tail.count == 1, "\(pieces)")
            if case .words(_, let w)? = tail.first { check("the answer is the words after the work", w == "Fixed the null check.", w) }
            check("summary in everyday words", StepWords.summary(turn.steps) == "Looked at a file and ran a quick check", StepWords.summary(turn.steps))
            // One look: a finished turn draws the same pieces from history as when it was written live.
            check("one look, live or history", TurnFlow.pieces(steps: turn.steps, raw: turn.raw, shown: Int.max) == pieces)
        } else { check("turn row", false) }

        // Running with a draft: the words stream on the end of the same turn.
        let run = Run(key: "agent:x", agentId: "x", startedAt: 0, activity: "Writing", turn: "u1")
        let live = Transcript.build(Array(ms.prefix(3)), run: run, draft: "Now running the tests", pending: []).rows
        if case .agent(let turn)? = live.last { check("the draft streams into the running turn", turn.running && turn.text.hasSuffix("Now running the tests"), turn.text) }

        // Sending: shows at once, keeps its row when the engine confirms it.
        let p = PendingSend(id: "p1", agentId: "x", text: "hello", at: 5000, queued: false, channel: nil)
        let before = Transcript.build(ms, run: nil, draft: nil, pending: [p]).rows
        check("a send shows at once with Thinking", before.suffix(2).map(\.id) == ["you-p1", "turn-p1"], "\(before.map(\.id))")
        let confirmed = ms + [msg("u2", "user", "hello", at: 5100)]
        let (_, claimed) = Transcript.build(confirmed, run: nil, draft: nil, pending: [p])
        check("the engine's copy is matched by exact text", claimed["u2"] == "p1")
        let after = Transcript.build(confirmed, run: Run(key: "agent:x", agentId: "x", startedAt: 0, activity: nil, turn: "u2"), draft: nil, pending: [], aliases: claimed).rows
        check("a confirmed send keeps its row id (no remount)", after.suffix(2).map(\.id) == ["you-p1", "turn-p1"], "\(after.map(\.id))")
        let q = PendingSend(id: "q1", agentId: "x", text: "and this", at: 6000, queued: true, channel: nil)
        let queued = Transcript.build(ms, run: nil, draft: nil, pending: [q]).rows
        if case .you(_, _, _, _, let isQueued, _, _)? = queued.last { check("a message sent while it works waits, marked Queued", isQueued) }

        // Older history without turn ids belongs to the message before it.
        let old = [msg("u1", "user", "hi"), msg("a1", "assistant", "hello")]
        check("older messages group by order", Transcript.build(old, run: nil, draft: nil, pending: []).rows.count == 2)
        // A stop leaves an Interrupted turn.
        let stopped = Transcript.build([msg("u1", "user", "go"), msg("e1", "error", "Stopped.", turn: "u1")], run: nil, draft: nil, pending: []).rows
        if case .agent(let t)? = stopped.last { check("a stopped turn is marked", t.stopped) } else { check("a stopped turn has a row", false) }

        // Channels: one message, two tagged agents. Each answer is its own turn under it, named for its agent, in the
        // order they started; a DM's turns stay unnamed.
        func by(_ m: Message, _ b: String) -> Message { var x = m; x.by = b; return x }
        let ch = [msg("u1", "user", "@nova @rex check this"), by(msg("a1", "assistant", "Looking.", turn: "u1"), "nova"),
                  by(msg("b1", "assistant", "On it.", turn: "u1"), "rex"), by(msg("a2", "assistant", "All good.", turn: "u1"), "nova")]
        let chRows = Transcript.build(ch, live: [], pending: []).rows
        let turnsBy = chRows.compactMap { r -> (String, String)? in if case .agent(let t) = r { return (t.by ?? "", t.raw) } else { return nil } }
        check("a channel message gets one turn per tagged agent", turnsBy.map(\.0) == ["nova", "rex"], "\(turnsBy)")
        check("each agent's lines stay in its own turn", turnsBy.first?.1 == "Looking.\n\nAll good.")
        check("channel turns have distinct ids", Set(chRows.map(\.id)).count == chRows.count)
        // Both still running: two live turns, each with its own streaming words.
        var r1 = Run(key: "agent:nova", agentId: "nova", startedAt: 1, activity: nil, turn: "u1"); r1.by = "nova"
        var r2 = Run(key: "agent:rex", agentId: "rex", startedAt: 2, activity: nil, turn: "u1"); r2.by = "rex"
        let liveRows = Transcript.build([ch[0]], live: [(r2, "Rex typing"), (r1, "Nova typing")], pending: []).rows
        let liveTurns = liveRows.compactMap { r -> Turn? in if case .agent(let t) = r { return t } else { return nil } }
        check("two agents stream at once, in the order they started", liveTurns.map(\.by) == ["nova", "rex"] && liveTurns.allSatisfy(\.running) && liveTurns.map(\.raw) == ["Nova typing", "Rex typing"], "\(liveTurns.map(\.raw))")
        // A channel post nobody answered yet shows without a "Thinking" row (nobody may be tagged).
        let post = PendingSend(id: "p1", agentId: "c_w_general", text: "note for later", at: 0, queued: false, channel: "general")
        check("a channel post promises no reply", Transcript.build([], live: [], pending: [post]).rows.count == 1)

        // Markdown blocks: the structure an organized answer is drawn from.
        let md = Markdown.blocks("The run failed: X can't be reached.\n\n## What happened\n- **Cause:** the API times out.\n- **Results:** none.\n  still the same item\n    - nested\n\n1. Draft only.\n2) Approve each.\n\n> a quote\n\n---\n| Model | Score |\n|---|---:|\n| Opus | 66% |\n\n```swift\nlet x = 1\n```\nLast line")
        check("markdown: paragraph, heading, items, quote, rule, table, code, paragraph", md.count == 12, "\(md)")
        if md.count == 12 {
            check("markdown: heading level", md[1] == .heading(level: 2, text: "What happened"))
            check("markdown: bold lead-in bullet keeps its marks", md[2] == .item(depth: 0, number: nil, text: "**Cause:** the API times out."))
            check("markdown: an indented line continues its item", md[3] == .item(depth: 0, number: nil, text: "**Results:** none.\nstill the same item"))
            check("markdown: nested item", md[4] == .item(depth: 2, number: nil, text: "nested"))
            check("markdown: numbered items, both styles", md[5] == .item(depth: 0, number: 1, text: "Draft only.") && md[6] == .item(depth: 0, number: 2, text: "Approve each."))
            check("markdown: table", md[9] == .table(header: ["Model", "Score"], rows: [["Opus", "66%"]]))
            check("markdown: code fence", md[10] == .code("let x = 1") || md.contains(.code("let x = 1")))
        }
        check("markdown: a fence still being written is code so far", Markdown.blocks("Look:\n```\nlet a") == [.paragraph("Look:"), .code("let a")])
        check("markdown: half-written bold never shows raw", !String(((try? AttributedString(markdown: InlineMarks.closed("**Cau"), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString("**")).characters).contains("*"))

        // A turn with its to-do card never also shows a to-do list written as text.
        let doubled = Transcript.build([msg("u1", "user", "check it"), msg("a1", "assistant", "I'll check it.\n⟦plan: List files | Read the README⟧", turn: "u1"),
                                        msg("a2", "assistant", "To-do list:\n- [x] List files\n- [ ] Read the README\nStill going.", turn: "u1")], run: nil, draft: nil, pending: []).rows
        if case .agent(let t)? = doubled.last { check("a written checklist is dropped when the card exists", !t.raw.contains("[x]") && !t.raw.contains("[ ]") && !t.raw.contains("To-do list") && t.raw.contains("Still going.") && t.raw.contains("⟦plan"), t.raw) }

        // Reports: only a long one (heavy work) is its own page; shorter ones are part of the answer.
        do {
            let small = ReportTag.reports("Done. ⟦report: Quick check⟧ " + Array(repeating: "word", count: 691).joined(separator: " ") + " ⟦/report⟧")
            let big = ReportTag.reports("Done. ⟦report: Deep audit⟧ " + Array(repeating: "word", count: 1500).joined(separator: " ") + " ⟦/report⟧")
            check("a 691-word report shows in the chat", small.count == 1 && !small[0].long)
            check("a 1,500-word report opens beside the chat", big.count == 1 && big[0].long)
        }

        // Continue after a stop: the turn carries on with the stopped turn's plan, ticked where it left off.
        do {
            let ms = [msg("u1", "user", "deep run"), msg("a1", "assistant", "On it. ⟦plan: Survey | Sizes | Duplicates | Sum up⟧", turn: "u1"),
                      msg("e1", "error", "Stopped.", turn: "u1"), msg("u2", "user", "continue"),
                      msg("a2", "assistant", "Picking up.", turn: "u2")]
            let rows = Transcript.build(ms, run: nil, draft: nil, pending: []).rows
            let turns = rows.compactMap { r -> Turn? in if case .agent(let t) = r { t } else { nil } }
            check("a new request after a stop never shows the old plan", turns.count == 2 && turns[1].plan == nil, "\(turns.map { $0.plan?.items.count ?? 0 })")
            let live = Transcript.build(ms.dropLast() + [msg("u3", "user", "open the speed stream")], run: nil, draft: nil, pending: []).rows
                .compactMap { r -> Turn? in if case .agent(let t) = r { t } else { nil } }
            check("a request sent after a stop starts with no card", live.allSatisfy { $0.id == "u1" || $0.plan == nil }, "\(live.map { $0.plan?.items.count ?? 0 })")
            let ms2 = ms + [msg("a3", "assistant", "⟦done: 1⟧ ⟦done: 2⟧ Next.", turn: "u2")]
            let t2 = Transcript.build(ms2, run: nil, draft: nil, pending: []).rows.compactMap { r -> Turn? in if case .agent(let t) = r { t } else { nil } }
            check("its ticks land on the carried plan", t2.last?.plan?.done == [1, 2], "\(String(describing: t2.last?.plan?.done))")
            let ms3 = [msg("u1", "user", "plan"), msg("a1", "assistant", "⟦plan: A | B⟧ ⟦done: 1⟧ ⟦done: 2⟧ Done.", turn: "u1"), msg("u2", "user", "thanks"), msg("a2", "assistant", "Sure.", turn: "u2")]
            let t3 = Transcript.build(ms3, run: nil, draft: nil, pending: []).rows.compactMap { r -> Turn? in if case .agent(let t) = r { t } else { nil } }
            check("a finished plan isn't carried", t3.last?.plan == nil)
        }
        print(failed == 0 ? "PASS" : "\(failed) FAILED")
        exit(failed == 0 ? 0 : 1)
    }
}

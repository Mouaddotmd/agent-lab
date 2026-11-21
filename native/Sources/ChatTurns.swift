// The chat's model: the engine's messages for one agent, folded into one ordered list of rows, each with one stable id
// (Mavis chat-rules §1). One function builds it (`Transcript.build`), from plain values, so it can be tested without a
// window: given the same messages it always returns the same rows.
import SwiftUI

/// A message you sent that the engine hasn't confirmed yet, or one waiting for the agent to finish (queued).
struct PendingSend: Identifiable, Equatable {
    let id: String; let agentId: String; let text: String; let at: Double; var queued: Bool; var channel: String?
    var images: [String] = []
}

/// An agent's reply to one message of yours: its words, its work, how it ended.
struct Turn: Identifiable, Equatable {
    let id: String                      // the id of your message that started it (in a channel: that id · the agent)
    var by: String? = nil               // the agent answering, in a channel (a DM's agent is the chat's own)
    var raw = ""                        // everything it wrote, tags and all
    var steps: [Step] = []
    var at: Double?                     // when its first line arrived
    var running = false
    var startedAt: Double?              // its run's start, while it runs
    var stopped = false
    var error: String?
    /// A plan it's carrying on with (its ⟦plan⟧ and the ticks so far) from a turn of its that stopped before finishing:
    /// "continue" shows the same to-do card, ticked where it left off.
    var carried: String?
    /// Its plan: its own, else the one it carries on with.
    var plan: PlanTag.Plan? { PlanTag.parse(raw) ?? carried.flatMap { PlanTag.parse($0 + "\n" + raw) } }
    var text: String { Tags.strip(raw) }
    var isEmpty: Bool { raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && steps.isEmpty && !stopped && error == nil }
}

enum ChatRow: Identifiable, Equatable {
    case you(id: String, text: String, at: Double?, pending: Bool, queued: Bool, steered: Bool = false, images: [String] = [])
    case agent(Turn)
    /// A line from the app in the chat's flow: "Handed to Bram.", "Compacted the conversation".
    case note(id: String, text: String, at: Double?)
    var id: String {
        switch self {
        case .you(let id, _, _, _, _, _, _): return "you-" + id
        case .agent(let t): return "turn-" + t.id
        case .note(let id, _, _): return "note-" + id
        }
    }
    var at: Double? { switch self { case .you(_, _, let at, _, _, _, _): at; case .agent(let t): t.at; case .note(_, _, let at): at } }
}

enum Transcript {
    /// Messages, the run in progress, its streaming draft and your unconfirmed sends → rows.
    /// - Every reply line belongs to the turn its message names (`turn`); older messages without one belong to the
    ///   message of yours before them.
    /// - A send shows at once; once the engine has the same text after it, the engine's row takes over the same id.
    /// `aliases` maps an engine message id to the id its row was first shown under (a send's temporary id), so a
    /// confirmed send keeps its row: no remount, no flicker. `claimed` returns the new matches for the caller to keep.
    static func build(_ messages: [Message], run: Run?, draft: String?, pending: [PendingSend], aliases: [String: String] = [:]) -> (rows: [ChatRow], claimed: [String: String]) {
        build(messages, live: run.map { [($0, draft)] } ?? [], pending: pending, aliases: aliases)
    }
    /// `live`: the runs writing into this conversation now, each with its streaming words. In a channel several agents
    /// can answer one message: each answer is its own turn (your message's id · the agent's id), after your message,
    /// in the order they started.
    static func build(_ messages: [Message], live: [(run: Run, draft: String?)], pending: [PendingSend], aliases: [String: String] = [:]) -> (rows: [ChatRow], claimed: [String: String]) {
        var rows: [ChatRow] = []
        var turns: [String: Turn] = [:]
        var under: [String: [String]] = [:]          // your message's id → its turns, in order
        var lastYou: String?
        var claimed: [String: String] = [:]
        // Your sends the engine already has: match by exact text, once each, oldest first, never before you sent it.
        var pend = pending.filter { !$0.queued }.sorted { $0.at < $1.at }
        for m in messages where m.role == "user" && aliases[m.id] == nil {
            if let i = pend.firstIndex(where: { $0.text == m.text && $0.at - 2000 <= (m.at ?? 0) }) { claimed[m.id] = pend[i].id; pend.remove(at: i) }
        }
        func name(_ id: String) -> String { aliases[id] ?? claimed[id] ?? id }
        /// The turn a line belongs to, created on first use.
        func turn(_ parent: String?, by: String?) -> String? {
            guard let parent else { return nil }
            let id = by.map { "\(parent)·\($0)" } ?? parent
            if turns[id] == nil { turns[id] = Turn(id: id, by: by); under[parent, default: []].append(id) }
            return id
        }
        func turnFor(_ m: Message) -> String? { turn(m.turn.map(name) ?? lastYou, by: m.by) }
        for m in messages {
            switch m.role {
            case "user":
                let id = name(m.id)
                lastYou = id
                rows.append(.you(id: id, text: m.text, at: m.at, pending: false, queued: false, steered: m.steered == true, images: m.images ?? []))
            case "assistant":
                guard let t = turnFor(m) else { continue }
                if !turns[t]!.raw.isEmpty { turns[t]!.raw += "\n\n" }
                turns[t]!.raw += turns[t]!.raw.contains("⟦plan") ? Checklist.withoutChecklist(m.text) : Checklist.asPlan(m.text)
                turns[t]!.at = turns[t]!.at ?? m.at
            case "tool":
                guard let t = turnFor(m) else { continue }
                let raw = turns[t]!.raw, n = turns[t]!.steps.count
                turns[t]!.steps.append(Step(id: m.toolId ?? m.id, verb: m.verb ?? "", line: m.text, round: m.round ?? (n + 1),
                                            done: m.done ?? true, failed: m.failed ?? false, offset: raw.isEmpty ? 0 : raw.count + 2,
                                            detail: m.detail, output: m.output, diff: m.diff))
                turns[t]!.at = turns[t]!.at ?? m.at
            case "thinking":
                // A thought it shared: one quiet step in the work (one with no words adds nothing to read).
                guard let t = turnFor(m), !m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let raw = turns[t]!.raw
                turns[t]!.steps.append(Step(id: m.id, verb: "Thought", line: "for \(m.seconds ?? 1)s", round: max(1, turns[t]!.steps.last?.round ?? 1),
                                            done: true, failed: false, offset: raw.isEmpty ? 0 : raw.count + 2, detail: m.text))
            case "note":
                rows.append(.note(id: m.id, text: m.text, at: m.at))
            case "error":
                guard let t = turnFor(m) else { continue }
                if m.text == "Stopped." { turns[t]!.stopped = true } else { turns[t]!.error = m.text }
                turns[t]!.at = turns[t]!.at ?? m.at
            default: break
            }
        }
        // The runs in progress: their turns are running, with the words still streaming on the end.
        for (run, draft) in live.sorted(by: { ($0.run.startedAt ?? 0) < ($1.run.startedAt ?? 0) }) {
            guard let t = turn(run.turn.map(name) ?? lastYou, by: run.by) else { continue }
            turns[t]!.running = true
            turns[t]!.startedAt = run.startedAt
            if let d = draft, !d.isEmpty { if !turns[t]!.raw.isEmpty { turns[t]!.raw += "\n\n" }; turns[t]!.raw += turns[t]!.raw.contains("⟦plan") ? Checklist.withoutChecklist(d) : Checklist.asPlan(d) }
        }
        // Place each turn after its message of yours.
        var out: [ChatRow] = []
        for r in rows {
            out.append(r)
            if case .you(let id, _, _, _, _, _, _) = r {
                for t in under[id] ?? [] { if let turn = turns[t], !turn.isEmpty || turn.running { out.append(.agent(turn)) } }
            }
        }
        // A turn with no plan of its own carries on with its agent's last unfinished one when it ticks steps of it
        // (⟦done: N⟧): "continue" after a stop.
        var open: [String: (tags: String, stopped: Bool)] = [:]
        for i in out.indices {
            guard case .agent(var t) = out[i] else { continue }
            let key = t.by ?? ""
            if let own = PlanTag.parse(t.raw) {
                open[key] = own.done.count < own.items.count ? (Self.planTags(t.raw), t.stopped || t.error != nil || t.running) : nil
                continue
            }
            // Only a turn that ticks the old plan's steps carries it: a new request after a stop is its own work, and showing
            // the old card until the new one arrived read as the wrong plan (19 Nov).
            if let o = open[key], t.raw.contains("⟦done") {
                t.carried = o.tags
                out[i] = .agent(t)
                if let p = t.plan { open[key] = p.done.count < p.items.count ? (Self.planTags(o.tags + "\n" + t.raw), t.stopped || t.error != nil || t.running) : nil }
            } else if !t.isEmpty {
                open[key] = nil
            }
        }
        // Sends not confirmed yet: yours at once, with "Thinking" under it in a DM (the agent row the engine will fill).
        // In a channel nobody may be tagged, so nothing is promised.
        for p in pending.sorted(by: { $0.at < $1.at }) where pend.contains(p) || p.queued {
            out.append(.you(id: p.id, text: p.text, at: p.at, pending: true, queued: p.queued))
            if !p.queued && p.channel == nil { out.append(.agent(Turn(id: p.id, running: true))) }
        }
        return (out, claimed)
    }
    /// A turn's plan tag and tick tags, nothing else.
    static func planTags(_ raw: String) -> String {
        let ns = raw as NSString, all = NSRange(location: 0, length: ns.length)
        let plan = PlanTag.planLine.matches(in: raw, range: all).map { ns.substring(with: $0.range) }
        let done = PlanTag.doneLine.matches(in: raw, range: all).map { ns.substring(with: $0.range) }
        return (plan + done).joined(separator: " ")
    }
}

/// The live turn's words as they come onto the screen (chat-rules §2): its own small model, so a step redraws only the
/// turn being written, never the transcript. A turn first seen finished shows whole.
@MainActor final class LiveWords: ObservableObject {
    static let shared = LiveWords()
    @Published private(set) var shown: [String: Int] = [:]
    private var text: [String: String] = [:]
    private var live = Set<String>()
    private var grewAt: [String: Date] = [:]
    private var running = Set<String>()
    private var writers: [String: Task<Void, Never>] = [:]
    private var rates: [String: Double] = [:]          // kept between bursts, so the speed never restarts from zero

    /// How much of a turn's words show now.
    func count(_ turn: Turn) -> Int { live.contains(turn.id) ? min(shown[turn.id] ?? 0, turn.text.count) : turn.text.count }
    /// A turn this session has watched being written (its words may still be coming onto the screen).
    func isLive(_ id: String) -> Bool { live.contains(id) }
    /// Words still being written out on screen.
    func writing(_ turn: Turn) -> Bool { live.contains(turn.id) && (shown[turn.id] ?? 0) < turn.text.count }

    /// The rows changed: start or keep revealing every running turn.
    func update(_ rows: [ChatRow]) {
        for case .agent(let t) in rows {
            if t.running { live.insert(t.id); running.insert(t.id) } else { running.remove(t.id) }
            guard live.contains(t.id) else { continue }
            let new = t.text, old = text[t.id] ?? ""
            if new.count > old.count { grewAt[t.id] = Date() }
            text[t.id] = new
            let now = shown[t.id] ?? 0
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || t.stopped {
                writers[t.id]?.cancel(); writers[t.id] = nil; set(t.id, new.count); continue
            }
            // What's on screen stays on screen: if the words changed, keep everything they still share and carry on
            // from there (never wipe and retype; 17 Nov: words vanished and typed back in when a block was saved).
            if !new.hasPrefix(String(old.prefix(now))) { set(t.id, Self.shared(old, new, upTo: now)) }
            write(t.id)
        }
    }
    nonisolated static func shared(_ a: String, _ b: String, upTo n: Int) -> Int {
        var k = 0
        for (x, y) in zip(a, b) { if k >= n || x != y { break }; k += 1 }
        return k
    }
    private func set(_ id: String, _ n: Int) { if shown[id] != n { shown[id] = n } }
    private func write(_ id: String) {
        guard writers[id] == nil, (shown[id] ?? 0) < (text[id]?.count ?? 0) else { return }
        writers[id] = Task { @MainActor [weak self] in
            var rate = self?.rates[id] ?? WordReveal.floor, budget = 0.0
            while let self, !Task.isCancelled, let t = self.text[id] {
                let now = self.shown[id] ?? 0
                guard now < t.count else { break }
                // A word counts as still growing only for half a second after the text last grew: a reply that pauses
                // for tools never leaves its last word held back (Mavis: "…startup items and", stuck).
                let still = self.running.contains(id) && Date().timeIntervalSince(self.grewAt[id] ?? .distantPast) < 0.5
                rate = WordReveal.pace(rate, backlog: t.count - now); self.rates[id] = rate
                budget = min(budget + rate * WordReveal.tick, WordReveal.cap(rate))
                let step = WordReveal.advance(t, after: now, budget: budget, streaming: still)
                if step.end > now { self.set(id, step.end); budget = step.budget }
                try? await Task.sleep(nanoseconds: WordReveal.tickNanos)
            }
            self?.writers[id] = nil
        }
    }
}

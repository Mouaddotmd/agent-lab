// End-to-end checks of the engine link, in a throwaway data folder:
//   agents (create, restart, rename, move, delete), workspaces (create, remove), and one real chat round trip.
//   AGENT_LAB_DATA=/tmp/x build/enginetest [--chat]
import SwiftUI
import AppKit

@main
struct EngineTest {
    @MainActor static func wait(_ s: Double = 10, _ ok: () -> Bool) { let t = Date().addingTimeInterval(s); while !ok() && Date() < t { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
    @MainActor static func run<T>(_ s: Double = 15, _ f: @escaping () async throws -> T) -> T {
        var out: Result<T, Error>?
        Task { do { out = .success(try await f()) } catch { out = .failure(error) } }
        wait(s) { out != nil }
        switch out { case .success(let v): return v; case .failure(let e): fail(e.localizedDescription); case nil: fail("timed out") }
    }
    static func fail(_ m: String) -> Never { print("FAIL: \(m)"); exit(1) }
    static func ok(_ m: String) { print("ok   \(m)") }
    @MainActor static func main() {
        // Never your real agents: without AGENT_LAB_DATA it runs in a fresh folder of its own.
        if ProcessInfo.processInfo.environment["AGENT_LAB_DATA"] == nil {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("agentlab-enginetest-\(UUID().uuidString.prefix(8))").path
            try? FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
            setenv("AGENT_LAB_DATA", scratch, 1)
            print("data: \(scratch)")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lab-chat-\(UUID().uuidString.prefix(6))").path
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        // Agents
        let a = Store(); a.connect(); run { await a.load() }
        if let p = a.engineProblem { fail(p) }
        let juno = run { try await a.createAgent(name: "Juno", job: "Reviews pull requests", look: .seeded("x"), operator: "claude-code", model: "sonnet", permission: "plan", cwd: tmp) }
        guard a.agents.contains(where: { $0.id == juno.id }) else { fail("new agent not listed") }
        ok("create agent")
        run { try await a.updateAgent(juno.id, ["name": "Juno 2"]) }
        guard a.agents.first(where: { $0.id == juno.id })?.name == "Juno 2" else { fail("rename") }
        ok("rename agent")
        // Workspaces
        let w = run { try await a.createWorkspace(name: "Payments", about: "Checkout work", color: "#4073D4", path: nil) }
        guard a.workspaces.contains(where: { $0.id == w.id }), w.path == nil else { fail("workspace not listed") }
        ok("create workspace (no folder)")
        guard w.channels.map(\.name) == ["general"], w.members == [] else { fail("a new workspace starts with #general and nobody in it") }
        ok("new workspace has #general")
        run { await a.setMember(juno.id, w.id, true) }
        guard a.workspaces.first(where: { $0.id == w.id })?.members == [juno.id] else { fail("invite") }
        ok("invite agent into workspace")
        let inWs = run { try await a.createAgent(name: "Atlas", job: "", look: .random(), operator: "codex", model: nil, permission: "ask", cwd: tmp, workspace: w.id) }
        guard a.workspaces.first(where: { $0.id == w.id })?.members == [juno.id, inWs.id] else { fail("agent made in workspace isn't a member") }
        ok("create agent inside workspace: it's a member")
        // The same agent in a second workspace, then out of it again
        let w2 = run { try await a.createWorkspace(name: "Growth", about: "", color: "#17866B", path: nil) }
        run { await a.setMember(juno.id, w2.id, true) }
        guard a.workspaces.filter({ $0.members?.contains(juno.id) == true }).count == 2 else { fail("one agent, two workspaces") }
        run { await a.setMember(juno.id, w2.id, false) }
        guard a.workspaces.first(where: { $0.id == w2.id })?.members == [] else { fail("remove member") }
        ok("same agent in two workspaces, then removed from one")
        // Channels: add one, rename it
        var cats = a.workspaces.first { $0.id == w.id }!.categories!
        cats[0].channels.append(.init(id: "eng", name: "engineering"))
        run { await a.saveChannels(a.workspaces.first { $0.id == w.id }!, cats) }
        guard a.workspaces.first(where: { $0.id == w.id })?.channels.map(\.name) == ["general", "engineering"] else { fail("add channel") }
        ok("add #engineering")
        // A post in a workspace with no agents: saved in the channel, nobody runs. (With agents, the channel's own agent,
        // else the first, answers untagged posts: not run here, it would start a model.)
        let empty = a.workspaces.first { $0.id == w2.id }!
        a.sendToChannel(empty, "general", "Notes for the team, no tags")
        wait(5) { (a.messages[empty.conv("general")] ?? []).count == 1 }
        guard (a.messages[empty.conv("general")] ?? []).first?.text == "Notes for the team, no tags" else { fail("untagged post") }
        // No agents given: the channel's own assistant answers, on a run of the channel's own (never an agent's DM key).
        guard a.runs.keys.allSatisfy({ $0.hasPrefix("ch:") }) else { fail("channel run used an agent's key") }
        for k in a.runs.keys { a.stop(k) }
        wait(10) { a.runs.isEmpty }
        ok("untagged post is saved; the channel's assistant answers on the channel's own run")
        // Workspace picture: a big HEIC from the system, made square and small
        guard let pic = WsPic.encode(URL(fileURLWithPath: "/Library/User Pictures/Animals/Owl.heic")), pic.count < 400_000, WsPic.decode(pic) != nil else { fail("picture encode") }
        let pw = run { try await a.createWorkspace(name: "Design", about: "", color: "#8B5ADE", path: nil, image: pic) }
        guard pw.image == pic else { fail("picture not saved on create (\(pic.count) chars)") }
        ok("create workspace with picture (\(pic.count / 1024) KB)")
        run { try await a.updateWorkspace(pw.id, ["name": "Design team", "image": NSNull()]) }
        guard let pw2 = a.workspaces.first(where: { $0.id == pw.id }), pw2.image == nil, pw2.name == "Design team" else { fail("edit workspace / remove picture") }
        run { try await a.updateWorkspace(pw.id, ["image": pic]) }
        guard a.workspaces.first(where: { $0.id == pw.id })?.image == pic else { fail("set picture on edit") }
        ok("edit workspace: rename, remove picture, set picture")
        // Restart: everything is still there
        a.engine.stop(); wait(0.6) { false }
        let b = Store(); b.connect(); run { await b.load() }
        guard b.agents.first(where: { $0.id == juno.id })?.name == "Juno 2", b.workspaces.contains(where: { $0.id == w.id }), b.agents.count == 2,
              b.workspaces.first(where: { $0.id == pw.id })?.image == pic else { fail("not saved across restart") }
        ok("everything saved across restart")
        // Chat (real run, plan mode, empty folder)
        if CommandLine.arguments.contains("--chat") {
            b.openChat(juno.id)
            run { await b.send(juno.id, "Reply with just the word: ok") }
            wait(120) { (b.messages[juno.id] ?? []).contains { $0.role == "assistant" || $0.role == "error" } && b.runs["agent:\(juno.id)"] == nil }
            let m = b.messages[juno.id] ?? []
            guard m.first?.role == "user" else { fail("your message wasn't saved") }
            guard let reply = m.last(where: { $0.role == "assistant" }) else { fail("no reply: \(m.last?.text ?? "nothing")") }
            ok("chat round trip, reply: \(reply.text.prefix(40))")
            guard m.allSatisfy({ $0.role == "user" || $0.turn == m.first?.id }) else { fail("reply lines missing their turn id") }
            ok("every reply line carries its turn")
            // A run with a tool: the step carries its id and round, and is marked finished.
            try? "a".write(toFile: tmp + "/one.txt", atomically: true, encoding: .utf8)
            try? "b".write(toFile: tmp + "/two.txt", atomically: true, encoding: .utf8)
            let before = (b.messages[juno.id] ?? []).count
            run { await b.send(juno.id, "Read one.txt and two.txt in this folder with your Read tool, then tell me what they contain in one sentence.") }
            wait(180) { b.runs["agent:\(juno.id)"] == nil && (b.messages[juno.id] ?? []).count > before + 1 }
            wait(3) { false }
            run { await b.loadMessages(juno.id) }
            let turn2 = Array((b.messages[juno.id] ?? []).dropFirst(before))
            let tools = turn2.filter { $0.role == "tool" }
            for t in turn2 { print("     \(t.role) turn=\(t.turn?.prefix(10) ?? "-") \(t.verb ?? "") \(t.text.prefix(60).replacingOccurrences(of: "\n", with: " ")) round=\(t.round.map(String.init) ?? "-") done=\(t.done.map { "\($0)" } ?? "-")") }
            guard !tools.isEmpty else { fail("no tool steps recorded") }
            guard tools.allSatisfy({ $0.toolId != nil && $0.round != nil && $0.done == true }) else { fail("a step is missing its id, round or finished flag") }
            ok("tool steps carry id, round, and finish (\(tools.count) steps)")
            let rows = Transcript.build(b.messages[juno.id] ?? [], run: nil, draft: nil, pending: []).rows
            if case .agent(let t)? = rows.last {
                let (o, w, tl) = TurnFlow.split(TurnFlow.pieces(steps: t.steps, raw: t.raw, shown: Int.max))
                print("     opening=\(o.count) work=\(w.count) tail=\(tl.count) plan=\(PlanTag.parse(t.raw)?.items ?? []) summary=\(StepWords.summary(t.steps))")
                ok("the real turn folds into opening, work and answer")
            }
        }
        // A channel, for real: tag Juno in #engineering; it answers there, as itself, and nothing lands in its DM.
        if CommandLine.arguments.contains("--chat") {
            let ws = b.workspaces.first { $0.id == w.id }!, conv = ws.conv("eng")
            let dm = (b.messages[juno.id] ?? []).count
            b.sendToChannel(ws, "eng", "@Juno 2 reply with just the word: pong")
            wait(5) { b.runs["agent:\(juno.id)"] != nil }
            guard b.runs["agent:\(juno.id)"]?.conv == conv, b.runs["agent:\(juno.id)"]?.by == juno.id else { fail("tagged agent didn't start in the channel") }
            wait(120) { b.runs["agent:\(juno.id)"] == nil }
            wait(2) { false }
            run { await b.loadMessages(conv) }; run { await b.loadMessages(juno.id) }
            let lines = b.messages[conv] ?? []
            guard let reply = lines.last(where: { $0.role == "assistant" }), reply.by == juno.id else { fail("no reply in the channel: \(lines.last?.text ?? "nothing")") }
            guard (b.messages[juno.id] ?? []).count == dm else { fail("the channel reply went into the DM") }
            let rows = b.rows(for: conv)
            guard case .agent(let t)? = rows.last, t.by == juno.id else { fail("channel turn not named for its agent") }
            ok("tagged in #engineering, answered there: \(reply.text.prefix(30))")
        }
        // Remove workspace: its agents go back to Personal; delete an agent
        run { await b.removeWorkspace(w.id) }
        run { await b.load() }
        guard !b.workspaces.contains(where: { $0.id == w.id }), b.agents.contains(where: { $0.id == juno.id }) else { fail("remove workspace") }
        ok("remove workspace: its agents stay")
        run { await b.deleteAgent(inWs.id) }
        guard !b.agents.contains(where: { $0.id == inWs.id }) else { fail("delete") }
        ok("delete agent")
        b.engine.stop(); wait(0.4) { false }
        print("PASS"); exit(0)
    }
}

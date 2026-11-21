// Renders chat rows from fixed turns to a PNG (no window, no engine), to look at the layout of every turn state.
//   build/chatrender out.png
import SwiftUI
import AppKit

@main
struct ChatRender {
    @MainActor static func main() {
        F.register(); SnapshotMode.on = true
        if let t = ProcessInfo.processInfo.environment["SNAP_THEME"], let p = Palettes.named(t) { themeNow = p }
        let store = Store()
        let agent = Agent(id: "a1", name: "Juno", job: "", look: nil, operator: "claude-code", model: "sonnet", permission: "ask", cwd: "/Users/you/app", workspace: nil, pinned: nil, createdAt: 0, worktree: nil, branch: nil, last: nil, origin: nil)
        store.agents = [agent]
        let now = Date().timeIntervalSince1970 * 1000
        func m(_ id: String, _ role: String, _ text: String, turn: String? = nil, verb: String? = nil, round: Int? = nil, done: Bool = true) -> Message {
            Message(id: id, role: role, text: text, verb: verb, at: now - 60_000, turn: turn, ch: nil, toolId: id, round: round, done: done, failed: nil)
        }
        let msgs = [
            m("u1", "user", "The checkout test fails on main. Can you fix it?"),
            m("a1", "assistant", "I'll find the failing test, then fix it. ⟦plan: Find the failing test | Fix the cause | Run the tests | Sum it up⟧", turn: "u1"),
            m("t1", "tool", "checkout.test.js", turn: "u1", verb: "Read", round: 1),
            m("t2", "tool", "npm test -- checkout", turn: "u1", verb: "Run", round: 2),
            m("a2", "assistant", "⟦done: 1⟧ It's a null total when the cart is empty.", turn: "u1"),
            m("t3", "tool", "src/cart.js", turn: "u1", verb: "Edit", round: 3),
            m("a3", "assistant", "⟦done: 2⟧ ⟦done: 3⟧ Fixed: an empty cart now totals 0 instead of null, and the checkout tests pass. Want me to add a test for the empty cart?", turn: "u1"),
            m("u2", "user", "Audit the payments folder for risky code."),
            m("a4", "assistant", "I'll go through the payments folder. ⟦plan: Read the payment code | Check error handling | Write it up⟧", turn: "u2"),
            m("t4", "tool", "src/payments/stripe.js", turn: "u2", verb: "Read", round: 1),
            m("t5", "tool", "src/payments/refund.js", turn: "u2", verb: "Read", round: 2, done: false),
        ]
        store.messages["a1"] = msgs
        store.runs["agent:a1"] = Run(key: "agent:a1", agentId: "a1", startedAt: now - 14_000, activity: "Read refund.js", turn: "u2")
        store.approvals = [Approval(id: "ap1", agentId: "a1", verb: "Run", line: "cd ~; ls -A | head -80", detail: nil, canAlways: false, tool: "Bash", risk: "host",
                                    command: "cd ~; ls -A | head -80; for d in \"Desktop/Agent Lab\"; do echo \"=== $d\"; ls -lA \"$d\"; done")]
        let rows = store.rows(for: "a1")
        let stopped: [ChatRow] = Transcript.build([m("u3", "user", "Rename every component"), m("a5", "assistant", "I'll start with the buttons.", turn: "u3"), m("e1", "error", "Stopped.", turn: "u3")], run: nil, draft: nil, pending: []).rows
        let pend = Transcript.build([], run: nil, draft: nil, pending: [PendingSend(id: "p", agentId: "a1", text: "And the dark theme too?", at: now, queued: false, channel: nil)]).rows
        // `chatrender out.png organized`: one finished turn whose answer uses every kind of structure.
        let organized = Transcript.build([
            m("o1", "user", "Why did the prospects run fail?"),
            m("o2", "assistant", "I'll check the run log and the network. ⟦plan: Read the run log | Check the network | Sum it up⟧", turn: "o1"),
            m("o3", "tool", "runs/today.log", turn: "o1", verb: "Read", round: 1),
            m("o4", "tool", "curl -I https://x.com", turn: "o1", verb: "Run", round: 2),
            m("o5", "assistant", "⟦done: 1⟧ ⟦done: 2⟧ ⟦done: 3⟧ The run failed: no prospects were found today because X can't be reached from this machine.\n\n- **Cause:** the X tab reports `ERR_INTERNET_DISCONNECTED`, and curl to `x.com` times out.\n- **Not checked:** I never reached the search or the DM history check, so no handles were screened.\n- **Results:** none. Nothing was sent, followed, liked or posted.\n\n## What can run on its own\n1. Reading your repo and releases.\n2. Drafting and tagging links.\n3. The weekly review.\n\n| Workflow | Autonomy |\n|---|---|\n| Release posts | Veto window |\n| Cold DMs | Always asks |\n\nThe next run will retry. If X is still unreachable, check this Mac's network.", turn: "o1"),
        ], run: nil, draft: nil, pending: []).rows
        let shown = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "organized" ? organized : rows + stopped + pend
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, r in ChatRowView(agent: agent, row: r, prev: nil) }
        }
        .padding(16).frame(width: 760).background(C.v1).environmentObject(store).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view); r.scale = 2
        guard let cg = r.cgImage else { print("render failed"); exit(1) }
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("wrote \(cg.width)x\(cg.height)")
    }
}

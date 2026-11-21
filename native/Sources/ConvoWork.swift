// The hand-off picker (the agent's ⋯ menu, or /handoff): pass the chat to another agent, with a note on where it stands.
import SwiftUI
import AppKit

/// Who to pass the chat to: every other agent, the ones you use most first. The chosen one gets a note on where things
/// stand as your first message in its DM, and starts on it.
struct HandOffMenu: View {
    @EnvironmentObject var s: Store
    let agent: Agent
    @Binding var open: Bool
    var body: some View {
        let others = s.agents.filter { $0.id != agent.id }
            .sorted { ($0.pinned == true ? 1 : 0, $0.last?.at ?? $0.createdAt ?? 0) > ($1.pinned == true ? 1 : 0, $1.last?.at ?? $1.createdAt ?? 0) }
            .prefix(10)
        ActionMenu(open: $open, width: 280, items: others.isEmpty
            ? [.init(symbol: "person.crop.circle.badge.plus", title: "No other agents yet", detail: "Make one, then hand this chat to it") { s.newAgentOpen = true }]
            : others.map { a in
                let busy = s.runs["agent:\(a.id)"] != nil
                return .init(symbol: "arrow.turn.up.right", title: "Hand off to \(a.name)", detail: busy ? "Working now" : (a.job?.isEmpty == false ? Words.line(a.job!, 40) : "Gets a note on where this stands")) {
                    s.handOff(agent.id, to: a.id)
                }
            })
    }
}

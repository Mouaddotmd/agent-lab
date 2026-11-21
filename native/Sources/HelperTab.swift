// A helper's own transcript (a Task / Agent call Claude made): what it was asked, its steps (each opening as the chat's
// do) and words in order, under a status bar (Running with the time / Done / Failed / Stopped). Live while it works;
// saved with the chat, so it opens again after a relaunch.
import SwiftUI
import AppKit

struct HelperTab: View {
    @ObservedObject var panel: SidePanel
    let helperId: String
    var body: some View {
        HelperView(model: ConvoHub.shared.helper(panel.agentId, helperId))
            .environment(\.chatAgentId, panel.agentId)
    }
}

private struct HelperView: View {
    @ObservedObject var model: HelperModel
    @State private var askOpen = false
    var body: some View {
        VStack(spacing: 0) {
            if let h = model.doc {
                bar(h)
                Rectangle().fill(C.divider).frame(height: 1)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let p = h.prompt, !p.isEmpty { asked(p) }
                        let t = h.turn
                        let pieces = TurnFlow.pieces(steps: t.steps, raw: t.raw, shown: Int.max)
                        ForEach(pieces) { piece in
                            switch piece {
                            case .steps(_, let steps): StepCardView(steps: steps)
                            case .words(_, let text): MarkdownText(text: text, color: Color.white(0.82))
                            }
                        }
                        if pieces.isEmpty && h.running {
                            Text("Getting started…").font(F.font(13, .regular)).foregroundStyle(C.i9)
                        }
                        if let e = h.error, h.status == "failed" {
                            Text(e).font(F.font(13, .regular)).foregroundStyle(FAIL_TEXT).fixedSize(horizontal: false, vertical: true)
                        }
                        if !h.running, pieces.isEmpty {
                            Text(h.status == "stopped" ? "It was stopped before it did anything." : "It finished without saying anything.")
                                .font(F.font(13, .regular)).foregroundStyle(C.i9)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.never)
            } else if model.missing {
                VStack(spacing: 6) {
                    Line("This helper's work wasn't kept", 14, .medium, C.i12)
                    Text("Helpers are kept from now on. This one ran before that, or its chat was cleared.").font(F.font(12, .regular)).foregroundStyle(C.i10)
                        .multilineTextAlignment(.center).frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if model.doc?.running != false { model.load() } }
    }

    /// Running with the time, or how it ended and how long it took; Stop while it runs.
    private func bar(_ h: HelperDoc) -> some View {
        HStack(spacing: 8) {
            Group {
                switch h.status {
                case "running": WorkSpinner()
                case "failed": StepMark(state: "failed")
                case "stopped": RoundedRectangle(cornerRadius: 1.5).fill(C.i10).frame(width: 7, height: 7).frame(width: 14, height: 14)
                default: StepMark(state: "done")
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let end = h.endedAt.map { $0 / 1000 } ?? Date().timeIntervalSince1970
                let took = h.startedAt.map { StepWords.clock(max(0, end - $0 / 1000)) }
                let word = ["running": "Running", "failed": "Failed", "stopped": "Stopped"][h.status] ?? "Done"
                Text([word, took].compactMap { $0 }.joined(separator: " · ")).font(F.font(12, .medium)).foregroundStyle(h.status == "failed" ? FAIL_TEXT : C.i12).monospacedDigit()
            }
            if h.running, let a = h.activity, !a.isEmpty {
                Text(a).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1).truncationMode(.middle)
            } else if let k = h.kind, !k.isEmpty {
                Text(k).font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1)
            }
            Spacer(minLength: 8)
            if h.running {
                ToolText(title: "Stop") { model.stop() }.tip("Stop this helper")
            }
        }
        .padding(.leading, 12).padding(.trailing, Box.pad).frame(height: Bar.height)
    }

    /// What it was asked, folded to three lines (click for all of it).
    private func asked(_ p: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Asked").font(F.font(11, .medium)).foregroundStyle(C.i9)
            Button { askOpen.toggle() } label: {
                Text(p).font(F.font(13, .regular)).foregroundStyle(C.i10).lineLimit(askOpen ? nil : 3)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
    }
}

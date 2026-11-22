// New agent (web: drawAgentForm / saveAgentForm). Add agent creates it in the engine. The same form edits an agent
// (its ⋯ menu: Edit agent): filled with what it has, Save changes it; what it runs on and where it works stay as they
// were made (its conversation and folder belong to them).
import SwiftUI

struct NewAgentForm: View {
    @EnvironmentObject var s: Store
    var editing: Agent? = nil
    @State private var name = ""
    @State private var job = ""
    @State private var op = "claude-code"
    @State private var look = Look.random()
    @State private var model = "Claude Code default"
    @State private var access = Mode.ask.title
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var nameFocused: Bool
    let ops: [(String, String)] = [("claude-code", "Claude Code"), ("codex", "Codex")]
    let models = ["Claude Code default", "Opus", "Sonnet", "Haiku"]
    let accessLevels = Mode.allCases.map(\.title)

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).contentShape(Rectangle()).onTapGesture { close() }
            VStack(spacing: 0) {
                // Head: its picture (the tool it runs on, follows "Runs on"), title (24 top, 16 bottom)
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Avatar.radius(80), style: .continuous).fill(C.v3).frame(width: 80, height: 80)
                        .overlay { OpLogo(op: op, size: 48) }
                    Line(editing == nil ? "New agent" : "Edit \(editing!.name)", 20, .semibold)
                }
                .padding(.top, 24).padding(.bottom, 16)
                // Body: fields 24 in, 12 apart
                VStack(alignment: .leading, spacing: 12) {
                    field("Name") { TextBox(text: $name, placeholder: "Juno", focused: $nameFocused).onSubmit { save() } }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 0) { Line("Its job", 12, .semibold, C.i10); Line(" optional", 12, .semibold, C.i10) }
                        TextArea(text: $job, placeholder: "Reviews every pull request in this repo before I do")
                        Line("Left empty, it behaves exactly like Claude Code normally does.", 12, .regular, C.i10)
                    }
                    field("Runs on") {
                        HStack(spacing: 8) {
                            ForEach(ops, id: \.0) { k, label in
                                Button { if editing == nil { op = k } } label: {
                                    HStack(spacing: 8) { OpLogo(op: k, size: 16); Line(label, 14, .medium, op == k ? C.v2 : C.i10) }
                                        .padding(.leading, 10).padding(.trailing, 12).frame(height: 32)
                                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(op == k ? C.i12 : C.v3)).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(op == k ? .isSelected : [])
                                .opacity(editing != nil && op != k ? 0.4 : 1)
                            }
                        }
                    }
                    field("Model") { SelectBox(value: $model, options: models) }
                    field("Works in") {
                        HStack(spacing: 8) {
                            Icon("folder", 16).foregroundStyle(C.i12)
                            Text(editing?.cwd ?? s.currentWorkspace?.path ?? s.home).font(.system(size: 12, design: .monospaced)).foregroundStyle(C.i12).frame(height: 16)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v1))
                        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.25), lineWidth: 1)).frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Line("Its own branch and folder", 14, .regular)
                            Line("Needs a git repository with at least one commit.", 12, .regular, C.i10)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(0.6)
                    field("What it may do") { SelectBox(value: $access, options: accessLevels) }
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
                // Footer: black, 16 in
                HStack {
                    SecondaryButton(title: "Cancel") { close() }
                    if let problem { Line(problem, 12, .regular, Color(0xff6166)).lineLimit(1).padding(.leading, 12) }
                    Spacer()
                    PrimaryButton(title: saving ? "Saving…" : editing == nil ? "Add agent" : "Save") { save() }.disabled(saving)
                }
                .padding(.horizontal, 16).frame(height: 64).background(C.v0)
            }
            .frame(width: 464)
            .background(C.v1)
            .clipShape(RoundedRectangle(cornerRadius: R.card))
            .overlay(RoundedRectangle(cornerRadius: R.card).stroke(C.edgeControl, lineWidth: 1).padding(-0.5))
            .floatShadow()
        }
        .onAppear { fill(); nameFocused = true }
        .onExitCommand { close() }
    }

    private func close() { if editing == nil { s.newAgentOpen = false } else { s.editingAgent = nil } }
    /// Editing: the form starts with what the agent has.
    private func fill() {
        guard let a = editing else { return }
        name = a.name; job = a.job ?? ""; op = a.operator ?? "claude-code"
        model = ["opus": "Opus", "sonnet": "Sonnet", "haiku": "Haiku"][a.model ?? ""] ?? "Claude Code default"
        access = Mode.of(a.permission).title
    }

    /// web: saveAgentForm. Name is required; everything else has a default.
    func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { problem = "Give it a name first."; nameFocused = true; return }
        let modelId: String? = ["Opus": "opus", "Sonnet": "sonnet", "Haiku": "haiku"][model]
        let perm = Mode.allCases.first { $0.title == access }?.rawValue ?? Mode.ask.rawValue
        saving = true; problem = nil
        if let a = editing {
            Task {
                do {
                    let patch: [String: Any] = ["name": n, "job": job, "permission": perm, "model": (op == "claude-code" ? modelId : nil) as Any? ?? NSNull()]
                    try await s.updateAgent(a.id, patch)
                    s.editingAgent = nil
                } catch { problem = error.localizedDescription }
                saving = false
            }
            return
        }
        Task {
            do {
                let ws = s.currentWorkspace
                let a = try await s.createAgent(name: n, job: job, look: look, operator: op, model: op == "claude-code" ? modelId : nil, permission: perm, cwd: ws?.path ?? s.home, workspace: ws?.id)
                s.newAgentOpen = false
                if ws != nil { s.openAgent = a.id } else { s.openChat(a.id) }   // web: go({ kind: 'dm', id })
            } catch { problem = error.localizedDescription }
            saving = false
        }
    }

    func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Line(label, 12, .semibold, C.i10); content() }
    }
}

/// Text input: 40 tall, 12 sides, 16/24; focus = black fill + 2px #878787 ring (web: .field input).
struct TextBox: View {
    @Binding var text: String; let placeholder: String; var focused: FocusState<Bool>.Binding
    var body: some View {
        let on = focused.wrappedValue || SnapshotMode.on
        ZStack(alignment: .leading) {
            if text.isEmpty { Line(placeholder, 16, .regular, C.i9) }
            if !SnapshotMode.on { TextField("", text: $text).textFieldStyle(.plain).font(F.font(16, .regular)).foregroundStyle(C.i12).focused(focused) }
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: R.ctl).fill(on ? C.v0 : C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: R.ctl + 2).stroke(on ? C.i9 : .clear, lineWidth: 2).padding(-1))
    }
}
struct TextArea: View {
    @Binding var text: String; let placeholder: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty { Para(text: placeholder, size: 16, weight: .regular, color: C.i9) }
            if !SnapshotMode.on { TextEditor(text: $text).font(F.font(16, .regular)).foregroundStyle(C.i12).scrollContentBackground(.hidden) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
    }
}
/// A select drawn like Chrome's: value on the left, a small chevron on the right.
struct SelectBox: View {
    @Binding var value: String; let options: [String]
    var face: some View {
        HStack(spacing: 0) {
            Line(value, 16, .regular)
            Spacer(minLength: 0)
            Icon("chev", 12).foregroundStyle(C.i12)
        }
        .padding(.leading, 16).padding(.trailing, 1).frame(maxWidth: .infinity).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1))
        .contentShape(Rectangle())
    }
    var body: some View {
        if SnapshotMode.on { face }
        else {
            Menu { ForEach(options, id: \.self) { o in Button(o) { value = o } } } label: { face }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: .infinity)
        }
    }
}

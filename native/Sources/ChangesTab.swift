// The Changes tab: what changed in the agent's folder, three ways:
// Uncommitted (against the last commit, new files too), Against base (since the branch left its base branch) and This
// chat (the files this chat's steps changed). Each file opens to its diff with line numbers; lines can go into the
// message box; a file can be opened or put back. Commit keeps what's there, with a message Claude can write.
// Engine: changes.js (changes:list, :diff, :discard, :commit, :message, :init) and git.js (git:merge for own branches).
import SwiftUI
import AppKit

// MARK: What the engine sends

struct ChangeFile: Codable, Hashable {
    var path: String; var abs: String; var status: String; var add: Int; var del: Int
    var binary: Bool?; var untracked: Bool?; var from: String?; var source: String?; var settled: Bool?; var ref: String?; var big: Bool?
    var name: String { (path as NSString).lastPathComponent }
    /// The one-letter mark, as the Files tree shows it.
    var mark: String {
        if untracked == true { return "U" }
        switch status { case "added": return "A"; case "deleted": return "D"; case "renamed": return "R"; default: return "M" }
    }
    var words: String {
        if untracked == true { return "New, not in git yet" }
        switch status { case "added": return "Added"; case "deleted": return "Deleted"; case "renamed": return "Renamed from \(from ?? "")"; default: return "Changed" }
    }
    /// As a dictionary, to hand back to the engine.
    var json: [String: Any] {
        guard let d = try? JSONEncoder().encode(self), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ["path": path] }
        return o
    }
}
struct ChangeListing: Codable {
    var folder: String?; var ownBranch: Bool?; var branch: String?; var repo: Bool; var root: String?; var mode: String?
    var base: String?; var files: [ChangeFile]; var note: String?
}
struct DiffRow: Codable, Hashable {
    var k: String; var t: String; var o: Int?; var n: Int?
}
struct ChangeDiff: Codable {
    var rows: [DiffRow]; var binary: Bool?; var cut: Bool?; var recorded: Bool?; var big: Bool?; var gone: Bool?
}

// MARK: State

/// The commit box's state, on its own so typing a message doesn't redraw the diffs.
@MainActor final class CommitState: ObservableObject {
    @Published var message = ""
    @Published var writing = false
    @Published var committing = false
    @Published var error: String?
    @Published var done: String?
}

@MainActor final class ChangesModel: ObservableObject {
    enum Mode: String, CaseIterable { case uncommitted, base, chat }
    struct DiffState { var rows: [DiffRow] = []; var loading = true; var error: String?; var info: ChangeDiff? }
    struct Selection: Equatable { var file: String; var from: Int; var to: Int }
    struct Confirm { var title: String; var detail: String; var label: String; var action: () -> Void }

    let agentId: String
    @Published var mode: Mode = .uncommitted { didSet { if mode != oldValue { selection = nil; refresh() } } }
    @Published private(set) var listings: [Mode: ChangeListing] = [:]
    @Published private(set) var loading = false
    @Published var error: String?
    /// Files open to their diff (full paths), per view.
    @Published var open: [Mode: Set<String>] = [:]
    @Published private(set) var diffs: [String: DiffState] = [:]
    /// Diffs shown whole (long ones show their first lines until you ask).
    @Published var whole: Set<String> = []
    @Published var selection: Selection?
    @Published var confirm: Confirm?
    @Published var busy: String?
    let commit = CommitState()
    private weak var engine: Engine?
    private var seen = false
    private var pending: Task<Void, Never>?
    private var generation = 0
    init(agentId: String) { self.agentId = agentId }

    var listing: ChangeListing? { listings[mode] }
    func key(_ file: ChangeFile) -> String { "\(mode.rawValue)|\(file.abs)" }
    func isOpen(_ file: ChangeFile) -> Bool { open[mode]?.contains(file.abs) == true }

    func appeared(_ engine: Engine) {
        self.engine = engine
        if !seen { seen = true; refresh() }
    }
    /// Files changed somewhere (a turn ended, git changed): load again, once the tab was seen.
    func changed() {
        guard seen else { return }
        pending?.cancel()
        pending = Task { try? await Task.sleep(for: .milliseconds(250)); if !Task.isCancelled { refresh() } }
    }

    func refresh() {
        guard let engine else { return }
        let mode = mode
        generation += 1
        let gen = generation
        loading = listings[mode] == nil
        Task {
            do {
                let l = try await engine.call("changes:list", [agentId, mode.rawValue], as: ChangeListing.self)
                guard gen == generation else { return }
                listings[mode] = l; error = nil
                // Open diffs are loaded again; files that are gone close.
                let have = Set(l.files.map(\.abs))
                open[mode] = (open[mode] ?? []).intersection(have)
                for k in diffs.keys where k.hasPrefix(mode.rawValue + "|") { diffs[k] = nil }
                if let sel = selection, !have.contains(sel.file) { selection = nil }
                for f in l.files where open[mode]?.contains(f.abs) == true { loadDiff(f) }
            } catch {
                guard gen == generation else { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    func toggle(_ file: ChangeFile) {
        var set = open[mode] ?? []
        if set.contains(file.abs) { set.remove(file.abs); if selection?.file == file.abs { selection = nil } }
        else { set.insert(file.abs); if diffs[key(file)] == nil { loadDiff(file) } }
        open[mode] = set
    }

    private func loadDiff(_ file: ChangeFile) {
        guard let engine else { return }
        let k = key(file), mode = mode
        diffs[k] = DiffState()
        Task {
            do {
                let d = try await engine.call("changes:diff", [agentId, mode.rawValue, file.json], as: ChangeDiff.self)
                diffs[k] = DiffState(rows: d.rows, loading: false, info: d)
            } catch {
                diffs[k] = DiffState(loading: false, error: error.localizedDescription)
            }
        }
    }

    /// A click on a diff line selects it; with Shift, everything from the selected line to it.
    func select(_ file: ChangeFile, _ i: Int, extend: Bool) {
        if extend, let s = selection, s.file == file.abs { selection = Selection(file: file.abs, from: min(s.from, i), to: max(s.to, i)) }
        else if selection == Selection(file: file.abs, from: i, to: i) { selection = nil }
        else { selection = Selection(file: file.abs, from: i, to: i) }
    }

    /// The selected lines (or `only`) into the agent's box: `path:12-14` and the lines as a diff.
    func addToMessage(relative: (String) -> String, only: (ChangeFile, Int)? = nil) {
        let target: (ChangeFile, Int, Int)?
        if let (f, i) = only { target = (f, i, i) }
        else if let s = selection, let f = listing?.files.first(where: { $0.abs == s.file }) { target = (f, s.from, s.to) }
        else { target = nil }
        guard let (file, from, to) = target, let rows = diffs[key(file)]?.rows, rows.indices.contains(from) else { return }
        let picked = rows[from...min(to, rows.count - 1)].filter { $0.k != "@" }
        guard !picked.isEmpty else { return }
        let numbers = picked.compactMap { $0.n ?? $0.o }
        let rel = relative(file.abs)
        let at: String
        if let a = numbers.first, let b = numbers.last { at = a == b ? "\(rel):\(a)" : "\(rel):\(a)-\(b)" } else { at = rel }
        let body = picked.map { ($0.k == "+" ? "+" : $0.k == "-" ? "-" : " ") + $0.t }.joined(separator: "\n")
        AddToMessage.send(agentId, Fence.wrap(at: at, body: body, language: "diff"))
        selection = nil
    }

    func askDiscard(_ file: ChangeFile) {
        let new = file.untracked == true
        confirm = Confirm(
            title: new ? "Delete \(file.name)?" : "Discard changes to \(file.name)?",
            detail: new ? "It's a new file git doesn't have yet, so discarding it deletes it for good."
                        : file.status == "renamed" ? "It goes back to \(file.from ?? "its old name") as it was at the last commit. This can't be undone."
                        : "It goes back to how it was at the last commit. This can't be undone.",
            label: new ? "Delete" : "Discard") { [weak self] in self?.discard(file) }
    }
    private func discard(_ file: ChangeFile) {
        guard let engine else { return }
        confirm = nil
        Task {
            do { _ = try await engine.call("changes:discard", [agentId, file.abs]) } catch { self.error = error.localizedDescription }
            refresh()
        }
    }

    func write() {
        guard let engine, !commit.writing else { return }
        commit.writing = true; commit.error = nil
        Task {
            do {
                let m = try await engine.call("changes:message", [agentId]) as? String ?? ""
                if !m.isEmpty { commit.message = m }
            } catch { commit.error = error.localizedDescription }
            commit.writing = false
        }
    }
    func doCommit() {
        let msg = commit.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let engine, !commit.committing else { return }
        guard !msg.isEmpty else { commit.error = "Write a message for the commit first."; return }
        commit.committing = true; commit.error = nil; commit.done = nil
        Task {
            do {
                let v = try await engine.call("changes:commit", [agentId, msg]) as? [String: Any]
                let n = v?["files"] as? Int ?? 0, sha = v?["sha"] as? String ?? "", branch = v?["branch"] as? String ?? ""
                commit.message = ""
                commit.done = "Committed \(n == 1 ? "1 file" : "\(n) files") to \(branch) (\(sha))"
            } catch { commit.error = error.localizedDescription }
            commit.committing = false
            refresh()
        }
    }
    func askMerge() {
        guard let base = listing?.base else { return }
        let n = listing?.files.count ?? 0
        confirm = Confirm(title: "Merge into \(base)?", detail: "Its \(n == 1 ? "1 changed file goes" : "\(n) changed files go") into \(base), uncommitted work included. The agent keeps working from there.", label: "Merge") { [weak self] in self?.merge() }
    }
    private func merge() {
        guard let engine else { return }
        confirm = nil; busy = "Merging…"
        Task {
            do {
                let v = try await engine.call("git:merge", [agentId]) as? [String: Any]
                let n = v?["merged"] as? Int ?? 0
                commit.done = "Merged \(n == 1 ? "1 file" : "\(n) files") into \(listing?.base ?? "the base branch")"
            } catch { self.error = error.localizedDescription }
            busy = nil
            refresh()
        }
    }
    func makeRepo() {
        guard let engine else { return }
        Task {
            do { _ = try await engine.call("changes:init", [agentId]) } catch { self.error = error.localizedDescription }
            refresh()
        }
    }
}

// MARK: The tab

struct ChangesTab: View {
    @ObservedObject var panel: SidePanel
    var body: some View { ChangesView(panel: panel, model: panel.changes) }
}

private struct ChangesView: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    @ObservedObject var model: ChangesModel
    /// Long diffs show this many lines until "Show all".
    static let firstLines = 1500

    enum Item: Identifiable {
        case file(ChangeFile)
        case row(ChangeFile, Int, DiffRow)
        case note(ChangeFile, String)
        case more(ChangeFile, Int)
        var id: String {
            switch self {
            case .file(let f): "f|" + f.abs
            case .row(let f, let i, _): "r|\(f.abs)|\(i)"
            case .note(let f, _): "n|" + f.abs
            case .more(let f, _): "m|" + f.abs
            }
        }
    }

    var body: some View {
        let on = panel.isFront("changes")
        VStack(spacing: 0) {
            modes
            Rectangle().fill(C.divider).frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.selection != nil { selectionBar }
            if let l = model.listing, l.repo {
                if model.mode == .base, l.ownBranch == true, l.base != nil, !l.files.isEmpty { mergeBar }
                if model.mode != .base { CommitBox(model: model, commit: model.commit, show: hasUncommitted(l)) }
            }
        }
        .overlay {
            if let c = model.confirm {
                PanelConfirm(title: c.title, detail: c.detail, confirm: c.label, onConfirm: c.action, onCancel: { model.confirm = nil })
            }
        }
        .background {
            Button("") { model.addToMessage(relative: panel.relative) }.keyboardShortcut("l", modifiers: .command).opacity(0).allowsHitTesting(false)
        }
        .onAppear { model.appeared(s.engine) }
        .onChange(of: on) { _, now in if now { model.appeared(s.engine); model.refresh() } }
    }

    /// Whether Commit has anything to take: uncommitted files (on the Uncommitted view, or as git sees the chat's).
    private func hasUncommitted(_ l: ChangeListing) -> Bool {
        switch model.mode {
        case .uncommitted: !l.files.isEmpty
        case .chat: l.files.contains { $0.source == "git" }
        case .base: false
        }
    }

    // MARK: Top

    private var modes: some View {
        HStack(spacing: 2) {
            chip(.uncommitted, "Uncommitted")
            chip(.base, model.listings[.base]?.base.map { "Against \($0)" } ?? "Against base")
            chip(.chat, "This chat")
            Spacer(minLength: 4)
            if model.loading || model.busy != nil { ProgressView().controlSize(.small).padding(.trailing, 4) }
            ToolIcon(symbol: "arrow.clockwise", label: "Refresh") { model.refresh() }
        }
        .padding(.horizontal, Box.pad).frame(height: Bar.height)
    }
    private func chip(_ m: ChangesModel.Mode, _ title: String) -> some View {
        let on = model.mode == m
        return ToolText(title: title, on: on) { model.mode = m }
    }

    // MARK: The list

    @ViewBuilder private var content: some View {
        if let e = model.error, model.listing == nil {
            empty("Couldn't load changes", e) { SmallSecondaryButton(title: "Try again") { model.refresh() } }
        } else if let l = model.listing {
            if !l.repo && model.mode != .chat {
                empty("This folder isn't a git repository", "Git keeps track of changes, so you can review, commit and undo them.") {
                    SmallSecondaryButton(title: "Create a git repository") { model.makeRepo() }
                }
            } else if l.files.isEmpty {
                empty(emptyTitle(l), l.note ?? emptyDetail(l)) { EmptyView() }
            } else {
                list(l)
            }
        } else {
            Line("Loading changes…", 13, .regular, C.i9).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func emptyTitle(_ l: ChangeListing) -> String {
        switch model.mode {
        case .uncommitted: "No uncommitted changes"
        case .base: l.base.map { "No changes against \($0)" } ?? "No base branch"
        case .chat: "This chat hasn't changed any files"
        }
    }
    private func emptyDetail(_ l: ChangeListing) -> String {
        switch model.mode {
        case .uncommitted: "Everything here is committed."
        case .base: "This branch has nothing \(l.base ?? "its base") doesn't."
        case .chat: "Files it edits show here."
        }
    }
    private func empty<A: View>(_ title: String, _ detail: String, @ViewBuilder action: () -> A) -> some View {
        VStack(spacing: 8) {
            Line(title, 14, .medium, C.i10)
            Text(detail).font(F.font(12, .regular)).foregroundStyle(C.i9).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            action().padding(.top, 6)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ l: ChangeListing) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(l.files.count == 1 ? "1 file" : "\(l.files.count) files").font(F.font(12, .medium)).foregroundStyle(C.i10)
                let add = l.files.reduce(0) { $0 + $1.add }, del = l.files.reduce(0) { $0 + $1.del }
                if add + del > 0 { Counts(add: add, del: del) }
                if let b = l.branch { Text("on \(b)").font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1) }
                Spacer(minLength: 0)
                if let e = model.error { Text(e).font(F.font(11, .regular)).foregroundStyle(FAIL_TEXT).lineLimit(2) }
            }
            .padding(.horizontal, 14).frame(height: 30)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items(l)) { item in
                        switch item {
                        case .file(let f):
                            ChangeRow(file: f, open: model.isOpen(f), canDiscard: canDiscard(f), relative: panel.relative(f.abs),
                                      toggle: { model.toggle(f) }, openFile: { panel.openFile(f.abs) }, discard: { model.askDiscard(f) })
                        case .row(let f, let i, let row):
                            DiffLineRow(row: row, selected: isSelected(f, i),
                                        tap: { shift in model.select(f, i, extend: shift) },
                                        add: { model.addToMessage(relative: panel.relative, only: (f, i)) },
                                        openFile: { panel.openFile(f.abs) })
                        case .note(_, let words):
                            Text(words).font(F.font(12, .regular)).foregroundStyle(C.i9).padding(.horizontal, 14).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .more(let f, let n):
                            Button { model.whole.insert(model.key(f)) } label: {
                                Text("Show all \(n) lines").font(F.font(12, .medium)).foregroundStyle(C.i10).padding(.horizontal, 14).frame(height: 30)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    /// The files and, under each open one, its diff's lines: one lazy run, so a long diff costs only what's on screen.
    private func items(_ l: ChangeListing) -> [Item] {
        var out: [Item] = []
        for f in l.files {
            out.append(.file(f))
            guard model.isOpen(f) else { continue }
            let k = model.key(f)
            guard let d = model.diffs[k], !d.loading else { out.append(.note(f, "Loading…")); continue }
            if let e = d.error { out.append(.note(f, "Couldn't show this diff: \(e)")); continue }
            if d.info?.binary == true || f.binary == true { out.append(.note(f, "A binary file: there's no text to show.")); continue }
            if d.info?.big == true || f.big == true { out.append(.note(f, "Too big to show here. Open it to see it.")); continue }
            if d.info?.recorded == true {
                out.append(.note(f, f.settled == true ? "What the chat changed. Git has no uncommitted change for it now (committed or put back)." : "What the chat changed."))
            }
            if d.rows.isEmpty {
                out.append(.note(f, f.status == "renamed" ? "Renamed from \(f.from ?? "its old name"), nothing else changed." : f.status == "deleted" ? "Deleted (it was empty)." : "No changes to its text."))
                continue
            }
            let shown = model.whole.contains(k) ? d.rows.count : min(d.rows.count, Self.firstLines)
            for i in 0..<shown { out.append(.row(f, i, d.rows[i])) }
            if shown < d.rows.count { out.append(.more(f, d.rows.count)) }
            if d.info?.cut == true && shown == d.rows.count { out.append(.note(f, "The rest of this diff is too long to show here.")) }
        }
        return out
    }
    private func canDiscard(_ f: ChangeFile) -> Bool {
        model.mode == .uncommitted || (model.mode == .chat && f.source == "git")
    }
    private func isSelected(_ f: ChangeFile, _ i: Int) -> Bool {
        guard let s = model.selection, s.file == f.abs else { return false }
        return i >= s.from && i <= s.to
    }

    // MARK: Bottom

    private var selectionBar: some View {
        let n = model.selection.map { $0.to - $0.from + 1 } ?? 0
        return HStack(spacing: 8) {
            Text(n == 1 ? "1 line selected" : "\(n) lines selected").font(F.font(12, .medium)).foregroundStyle(C.i10)
            Spacer(minLength: 0)
            SmallSecondaryButton(title: "Clear") { model.selection = nil }
            SmallSecondaryButton(title: "Add to message") { model.addToMessage(relative: panel.relative) }.tip("Put these lines in the message", "⌘L")
        }
        .padding(.leading, 12).padding(.trailing, Box.pad).frame(height: Bar.height)
        .overlay(alignment: .top) { Rectangle().fill(C.divider).frame(height: 1) }
    }
    private var mergeBar: some View {
        HStack(spacing: 8) {
            Text("Its own branch: \(model.listing?.branch ?? "")").font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            MergeDone(commit: model.commit)
            SmallSecondaryButton(title: "Merge into \(model.listing?.base ?? "base")") { model.askMerge() }
        }
        .padding(.leading, 12).padding(.trailing, Box.pad).frame(height: Bar.height)
        .overlay(alignment: .top) { Rectangle().fill(C.divider).frame(height: 1) }
    }
}

private struct MergeDone: View {
    @ObservedObject var commit: CommitState
    var body: some View { if let d = commit.done { Text(d).font(F.font(12, .regular)).foregroundStyle(C.i10).lineLimit(1) } }
}

/// +12 −3, as the chat's "Changed N files" shows it.
private struct Counts: View {
    let add: Int; let del: Int
    var body: some View {
        (Text("+\(add)").foregroundStyle(MV.on ? MV.Accent.added : C.i10) + Text(" −\(del)").foregroundStyle(MV.on ? MV.Accent.removed : C.i9)).font(F.font(12, .medium)).monospacedDigit()
    }
}

/// A changed file: its mark, name and folder, +/−; Open and Discard on hover; a click opens its diff.
private struct ChangeRow: View {
    let file: ChangeFile; let open: Bool; let canDiscard: Bool; let relative: String
    let toggle: () -> Void; let openFile: () -> Void; let discard: () -> Void
    @State private var hover = false
    var body: some View {
        let dir = (relative as NSString).deletingLastPathComponent
        HStack(spacing: 6) {
            Icon("chev", 10).foregroundStyle(C.i9).rotationEffect(.degrees(open ? 0 : -90)).frame(width: 12)
            Text(file.mark).font(F.font(11, .semibold)).foregroundStyle(C.i10).frame(width: 12).help(file.words)
            Text(file.name).font(F.font(13, .regular)).foregroundStyle(file.status == "deleted" ? C.i10 : C.i12)
                .strikethrough(file.status == "deleted", color: C.i9).lineLimit(1)
            if !dir.isEmpty { Text(dir).font(F.font(11, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.head) }
            Spacer(minLength: 4)
            if hover {
                if file.status != "deleted", FileManager.default.fileExists(atPath: file.abs) { action("Open", openFile) }
                if canDiscard { action(file.untracked == true ? "Delete" : "Discard", discard) }
            }
            if file.add + file.del > 0 { Counts(add: file.add, del: file.del) }
        }
        .padding(.leading, 8).padding(.trailing, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: R.xs).fill(hover ? C.v3 : .clear)).contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button(open ? "Hide changes" : "Show changes", action: toggle)
            if file.status != "deleted" { Button("Open", action: openFile) }
            if canDiscard { Divider(); Button(file.untracked == true ? "Delete…" : "Discard changes…", action: discard) }
        }
        .accessibilityAddTraits(.isButton).accessibilityLabel("\(file.name), \(file.words)")
    }
    private func action(_ title: String, _ act: @escaping () -> Void) -> some View {
        Hover { h in
            Button(action: act) {
                Text(title).font(F.font(11, .medium)).foregroundStyle(h ? C.i12 : C.i10).padding(.horizontal, 6).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: R.xs).fill(h ? C.v4 : .clear))
            }.buttonStyle(.plain)
        }
    }
}

/// One line of a diff: old and new line numbers, the sign, the words (wrapped). In and out as the chat's diffs show
/// them. Click selects (Shift-click selects up to it); + on hover puts just this line in the message.
private struct DiffLineRow: View {
    let row: DiffRow; let selected: Bool
    let tap: (Bool) -> Void; let add: () -> Void; let openFile: () -> Void
    @State private var hover = false
    var body: some View {
        if row.k == "@" {
            HStack(spacing: 6) {
                Text("⋯").foregroundStyle(C.i9)
                if !row.t.isEmpty { Text(row.t).foregroundStyle(C.i9).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.leading, 10).frame(height: 22)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(row.o.map(String.init) ?? "").frame(width: 34, alignment: .trailing).foregroundStyle(C.i9.opacity(0.7))
                Text(row.n.map(String.init) ?? "").frame(width: 34, alignment: .trailing).foregroundStyle(C.i9.opacity(0.7))
                Text(row.k == "+" ? "+" : row.k == "-" ? "−" : " ").foregroundStyle(row.k == "+" ? C.i10 : C.i9).frame(width: 18)
                Text(row.t.isEmpty ? " " : row.t).foregroundStyle(row.k == "+" ? C.i12 : row.k == "-" ? C.i9 : C.i10)
                    .strikethrough(row.k == "-", color: C.i9.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5, design: .monospaced))
            .padding(.vertical, 1).padding(.trailing, 26).frame(minHeight: 18, alignment: .leading)
            .background(selected ? C.sel : row.k == "+" ? Color.white(0.05) : .clear)
            .overlay(alignment: .topTrailing) {
                if hover {
                    Button(action: add) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(C.i12)
                            .frame(width: 18, height: 16).background(RoundedRectangle(cornerRadius: R.xs).fill(C.v4))
                    }
                    .buttonStyle(.plain).padding(.trailing, 4).padding(.top, 1).help("Add this line to the message")
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { tap(NSEvent.modifierFlags.contains(.shift)) }
            .contextMenu {
                Button("Add to message", action: add)
                Button("Open file", action: openFile)
            }
        }
    }
}

/// The message and Commit (and Claude writing the message). Commits everything uncommitted in the agent's folder (on
/// its own branch, for an agent that has one).
private struct CommitBox: View {
    @ObservedObject var model: ChangesModel
    @ObservedObject var commit: CommitState
    let show: Bool
    var body: some View {
        if show || commit.done != nil || commit.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if show {
                    TextField("", text: $commit.message, prompt: Text("Commit message").foregroundStyle(C.i9), axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain).font(F.font(13, .regular)).foregroundStyle(C.i12)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v2))
                        .overlay(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
                        .onSubmit { model.doCommit() }
                        .disabled(commit.committing)
                }
                if let e = commit.error {
                    Text(e).font(F.font(12, .regular)).foregroundStyle(FAIL_TEXT).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else if let d = commit.done {
                    Text(d).font(F.font(12, .regular)).foregroundStyle(C.i10)
                }
                if show {
                    HStack(spacing: 8) {
                        SmallSecondaryButton(title: commit.writing ? "Writing…" : "Write it for me") { model.write() }
                            .disabled(commit.writing).tip("Claude writes a one-line message from the changes")
                        Spacer(minLength: 0)
                        let ready = !commit.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !commit.committing
                        Hover { h in
                            Button { model.doCommit() } label: {
                                Line(commit.committing ? "Committing…" : "Commit", 14, .medium, C.v1).padding(.horizontal, 14).frame(height: 28)
                                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(ready ? (h ? C.primaryHover : C.i12) : C.i10.opacity(0.5)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!ready)
                        }
                        .tip("Commit every change in this folder")
                    }
                }
            }
            .padding(12)
            .overlay(alignment: .top) { Rectangle().fill(C.divider).frame(height: 1) }
        }
    }
}

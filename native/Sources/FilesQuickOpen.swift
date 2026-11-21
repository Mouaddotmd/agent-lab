// ⌘P in a chat: open a file of the agent's folder by name. The list comes from the engine (files:list: git's own list
// in a repository, so .gitignore is respected and big folders are quick); matching runs off the main thread, letters in
// order with the file's name counting most. ↑↓ choose, Return opens, Esc closes.
import SwiftUI
import AppKit

/// A folder's files, with their lowercased bytes ready for matching.
final class QuickList: @unchecked Sendable {
    let files: [String]
    let lower: [[UInt8]]
    init(_ files: [String]) {
        let sorted = files.sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
        self.files = sorted
        lower = sorted.map { Array($0.lowercased().utf8) }
    }
}

@MainActor final class QuickOpenModel: ObservableObject {
    let folder: String
    @Published var query = "" { didSet { if query != oldValue { search() } } }
    @Published private(set) var results: [String] = []
    @Published var index = 0
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    private var list: QuickList?
    private var listedAt = Date.distantPast
    private var fetching = false
    private var task: Task<Void, Never>?
    /// Files opened from here, most recent first: what an empty search shows on top.
    private var recent: [String] = []
    init(folder: String) { self.folder = folder }

    /// Each time ⌘P opens: a fresh search, and the list again if it's more than a few seconds old.
    func prepare(_ engine: Engine) {
        query = ""; index = 0
        search()
        guard Date().timeIntervalSince(listedAt) > 5, !fetching else { return }
        fetching = true
        loading = list == nil
        Task {
            defer { fetching = false }
            do {
                let v = try await engine.call("files:list", [folder]) as? [String: Any]
                let files = v?["files"] as? [String] ?? []
                let made = await Task.detached(priority: .userInitiated) { QuickList(files) }.value
                list = made; listedAt = Date(); problem = nil
            } catch { problem = error.localizedDescription }
            loading = false
            search()
        }
    }
    func opened(_ rel: String) { recent.removeAll { $0 == rel }; recent.insert(rel, at: 0); if recent.count > 20 { recent.removeLast() } }

    private func search() {
        task?.cancel()
        guard let list else { results = []; return }
        let q = Array(query.lowercased().filter { !$0.isWhitespace }.utf8)
        if q.isEmpty {
            let have = Set(list.files)
            let top = recent.filter { have.contains($0) }
            results = top + list.files.prefix(60).filter { !top.contains($0) }
            index = 0
            return
        }
        task = Task {
            let found = await Task.detached(priority: .userInitiated) { QuickOpenModel.match(q, in: list) }.value
            guard !Task.isCancelled else { return }
            results = found; index = 0
        }
    }

    /// The best 60 files for `q`: its letters in order in the path; matches in the file's name, at word starts and in
    /// runs score higher, short paths break ties.
    nonisolated static func match(_ q: [UInt8], in list: QuickList) -> [String] {
        var scored: [(Int, Int)] = []
        scored.reserveCapacity(256)
        for (i, p) in list.lower.enumerated() {
            if i & 1023 == 0, Task.isCancelled { return [] }
            if let s = score(q, p) { scored.append((s, i)) }
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        return scored.prefix(60).map { list.files[$0.1] }
    }
    nonisolated static func score(_ q: [UInt8], _ p: [UInt8]) -> Int? {
        guard q.count <= p.count else { return nil }
        let slash = UInt8(ascii: "/")
        let nameStart = (p.lastIndex(of: slash) ?? -1) + 1
        func isStart(_ j: Int) -> Bool {
            if j == 0 { return true }
            let b = p[j - 1]
            return b == slash || b == UInt8(ascii: "_") || b == UInt8(ascii: "-") || b == UInt8(ascii: ".") || b == UInt8(ascii: " ")
        }
        // In the name alone first: that's what you most often type.
        func walk(from start: Int) -> Int? {
            var j = start, total = 0, run = 0, last = -2
            for c in q {
                while j < p.count, p[j] != c { j += 1 }
                guard j < p.count else { return nil }
                var s = 1
                if isStart(j) { s += 8 }
                if j == last + 1 { run += 1; s += 4 + run } else { run = 0 }
                if j >= nameStart { s += 3 }
                total += s; last = j; j += 1
            }
            return total
        }
        if let s = walk(from: nameStart) {
            let exact = p.count - nameStart == q.count ? 40 : 0
            return 1000 + s + exact - (p.count - nameStart) / 2 - p.count / 8      // shorter names first
        }
        guard let s = walk(from: 0) else { return nil }
        return s - p.count / 8
    }
}

/// The ⌘P box over the panel.
struct QuickOpenView: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    @ObservedObject var model: QuickOpenModel
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .top) {
            // A click outside closes it.
            Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { panel.quickOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Icon("search", 14).foregroundStyle(C.i10)
                    TextField("", text: $model.query, prompt: Text("Open a file by name").foregroundStyle(C.i9))
                        .textFieldStyle(.plain).font(F.font(14, .regular)).foregroundStyle(C.i12)
                        .focused($focused)
                        .onKeyPress(.upArrow) { model.index = max(0, model.index - 1); return .handled }
                        .onKeyPress(.downArrow) { model.index = min(model.results.count - 1, model.index + 1); return .handled }
                        .onKeyPress(.escape) { panel.quickOpen = false; return .handled }
                        .onSubmit { open(model.index) }
                    if model.loading { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 12).frame(height: 40)
                Rectangle().fill(C.divider).frame(height: 1)
                if let problem = model.problem, model.results.isEmpty {
                    Line(problem, 13, .regular, C.i10).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                } else if model.results.isEmpty {
                    Line(model.loading ? "Listing files…" : model.query.isEmpty ? "No files here" : "No file matches", 13, .regular, C.i9)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.results.enumerated()), id: \.element) { i, rel in
                                    row(rel, on: i == model.index).id(i)
                                        .onTapGesture { open(i) }
                                        .onHover { if $0 { model.index = i } }
                                }
                            }
                            .padding(4)
                        }
                        .scrollIndicators(.never)
                        .frame(maxHeight: 360)
                        .fixedSize(horizontal: false, vertical: true)
                        .onChange(of: model.index) { _, i in proxy.scrollTo(i) }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: R.card, style: .continuous).fill(C.v1))
            .overlay(RoundedRectangle(cornerRadius: R.card, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: R.card, style: .continuous))
            .floatShadow()
            .padding(.horizontal, 12).padding(.top, 8)
        }
        .onAppear { model.prepare(s.engine); DispatchQueue.main.async { focused = true } }
    }
    private func row(_ rel: String, on: Bool) -> some View {
        let dir = (rel as NSString).deletingLastPathComponent
        return HStack(spacing: 8) {
            Icon("file", 13).foregroundStyle(C.i9)
            Text((rel as NSString).lastPathComponent).font(F.font(13, .regular)).foregroundStyle(C.i12).lineLimit(1)
            if !dir.isEmpty { Text(dir).font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.head) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: R.inset(R.card, by: 4), style: .continuous).fill(on ? C.v3 : .clear))
        .contentShape(Rectangle())
    }
    private func open(_ i: Int) {
        guard model.results.indices.contains(i) else { return }
        let rel = model.results[i]
        model.opened(rel)
        panel.quickOpen = false
        panel.openFile(rel)
    }
}

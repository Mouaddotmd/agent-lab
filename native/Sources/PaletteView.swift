// The command palette (⌘K, or the top bar's search): a card over the window with a field on top and what it found
// below, in groups. ↑ ↓ choose, Return opens, ⌘1–9 opens the first nine, Esc closes. Opens and closes at once.
import SwiftUI
import AppKit

struct CommandPalette: View {
    @EnvironmentObject var s: Store
    @StateObject private var model = PaletteModel()
    @FocusState private var focused: Bool
    static let width: CGFloat = 640
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                Color.black.opacity(0.7).contentShape(Rectangle()).onTapGesture { close() }
                VStack(spacing: 0) {
                    field
                    Rectangle().fill(C.divider).frame(height: 1)
                    list(maxHeight: max(160, min(440, g.size.height * 0.6)))
                    Rectangle().fill(C.divider).frame(height: 1)
                    footer
                }
                .frame(width: min(Self.width, g.size.width - 32))
                .background(RoundedRectangle(cornerRadius: R.card, style: .continuous).fill(C.v1))
                .clipShape(RoundedRectangle(cornerRadius: R.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: R.card, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
                .floatShadow()
                .padding(.top, 0.12 * (g.size.height + 48) - 24)   // web: 12vh from the top of a 48px-taller page
            }
        }
        .onAppear { model.build(s); focused = true; FindKeys.paletteOpen = true }
        .onDisappear { FindKeys.paletteOpen = false }
        .onExitCommand { close() }
    }

    // MARK: Field

    var field: some View {
        HStack(spacing: 12) {
            Icon("search", 18).foregroundStyle(C.i10)
            ZStack(alignment: .leading) {
                if model.query.isEmpty { Line("Search agents, chats, files, messages or commands", 16, .regular, C.i9).allowsHitTesting(false) }
                if !SnapshotMode.on {
                    TextField("", text: $model.query).textFieldStyle(.plain).font(F.font(16, .regular)).foregroundStyle(C.i12)
                        .focused($focused)
                        .onSubmit { run(nil) }
                        .onKeyPress(.upArrow) { model.move(-1); return .handled }
                        .onKeyPress(.downArrow) { model.move(1); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                        .onKeyPress(phases: .down) { press in
                            // ⌘1–9: the first nine rows.
                            guard press.modifiers == .command, let n = Int(press.characters), (1...9).contains(n) else { return .ignored }
                            run(n - 1); return .handled
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.filesLoading || model.messagesLoading { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16) }
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    // MARK: Results

    func list(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.flat.isEmpty { empty }
                    let place = Dictionary(model.flat.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
                    ForEach(model.groups, id: \.group) { group in
                        Line(group.group.title, 12, .medium, C.i9).padding(.horizontal, 12).frame(height: 28).padding(.top, 4)
                        ForEach(group.rows) { row in
                            let i = place[row.id] ?? 0
                            PaletteRowView(row: row, on: i == model.selected, number: i < 9 ? i + 1 : nil, typed: !model.query.isEmpty) { run(i) }
                                .id(row.id)
                        }
                    }
                    if model.messageProblem != nil {
                        Line("Couldn’t search messages", 12, .regular, FAIL_TEXT).padding(.horizontal, 12).frame(height: 28)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.automatic)
            .frame(height: min(maxHeight, contentHeight))
            .onChange(of: model.selected) { _, i in
                guard model.flat.indices.contains(i) else { return }
                proxy.scrollTo(model.flat[i].id)
            }
            .onChange(of: model.query) { _, _ in if let f = model.flat.first { proxy.scrollTo(f.id, anchor: .top) } }
        }
    }
    /// The list's height from what's in it (rows are a fixed height), up to `maxHeight`: no measuring pass.
    var contentHeight: CGFloat {
        if model.flat.isEmpty { return 136 + (model.messageProblem != nil ? 28 : 0) }
        let rows = model.flat.reduce(CGFloat(0)) { $0 + ($1.item.snippet == nil ? 36 : 48) }
        return 8 + CGFloat(model.groups.count) * 32 + rows + (model.messageProblem != nil ? 28 : 0)
    }
    @ViewBuilder var empty: some View {
        let typed = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(spacing: 4) {
            if typed && (model.messagesLoading || model.filesLoading) {
                Line("Searching…", 14, .medium, C.i10)
            } else if typed {
                Line("Nothing matches", 14, .medium, C.i10)
                Line("Try fewer letters, or other words", 14, .regular, C.i9)
            } else {
                Line("No agents yet", 14, .medium, C.i10)
                Line("Press ⌘N to make one", 14, .regular, C.i9)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    var footer: some View {
        HStack(spacing: 16) {
            hint(["↵"], "open"); hint(["↑", "↓"], "choose"); hint(["⌘", "1–9"], "open one"); hint(["esc"], "close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 32)
    }
    func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { k in
                    Text(k).font(F.font(12, .medium)).foregroundStyle(C.i10).padding(.horizontal, 4).frame(height: 15)
                        .background(RoundedRectangle(cornerRadius: R.xs).fill(C.v3))
                }
            }
            Line(" " + label, 12, .regular, C.i10)
        }
    }

    // MARK: Acting

    func close() { s.searchOpen = false }
    /// Closes the palette, then does the thing (on the next pass, once the palette has let go of the keyboard).
    func run(_ i: Int?) {
        guard let item = model.pick(i) else { return }
        close()
        DispatchQueue.main.async { item.run() }
    }
}

/// One row: its picture, its title (typed letters lit), what it is, its shortcut on the right. A message shows the
/// piece of its line that matched under the title.
struct PaletteRowView: View {
    let row: PaletteRow; let on: Bool; let number: Int?; let typed: Bool
    let action: () -> Void
    var item: PaletteItem { row.item }
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 10) {
                    look.frame(width: 20, height: 20)
                    if let snip = item.snippet {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title).font(F.font(13, .medium)).foregroundStyle(C.i12).lineLimit(1)
                                if let d = item.detail { Text(d).font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1) }
                            }
                            Text(Self.lit(snip.text, Array(snip.start..<max(snip.start, snip.start + snip.length)), size: 12, base: C.i10, weight: .regular))
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 8) {
                            Text(typed ? Self.lit(item.title, row.marks, size: 14, base: C.i12, weight: .medium) : AttributedString(item.title))
                                .font(F.font(14, .medium)).foregroundStyle(C.i12).lineLimit(1).layoutPriority(1)
                            if let d = item.detail { Text(d).font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.head) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let k = item.shortcut { Text(k).font(F.font(12, .medium)).foregroundStyle(C.i9).fixedSize() }
                    else if on, let number { Text("⌘\(number)").font(F.font(12, .medium)).foregroundStyle(C.i9).fixedSize() }
                }
                .padding(.horizontal, 8).frame(height: item.snippet == nil ? 36 : 48)
                .background(RoundedRectangle(cornerRadius: R.inset(R.card, by: 4), style: .continuous).fill(on ? C.sel : h ? C.rowHover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(item.title)
    }
    @ViewBuilder var look: some View {
        switch item.look {
        case .icon(let n): Icon(n, 18).foregroundStyle(on ? C.i12 : C.i10)
        case .symbol(let n): Image(systemName: n).font(.system(size: 14)).foregroundStyle(on ? C.i12 : C.i10)
        case .agent(let a): Avatar(agent: a, size: 20, status: false)
        case .workspace(let w): WsPic(name: w.name, color: w.color, image: w.image, size: 20, radius: R.xs - 1)
        }
    }
    /// The text with the letters at `marks` (UTF-16 offsets) brighter and heavier, the rest quieter.
    static func lit(_ text: String, _ marks: [Int], size: CGFloat, base: Color, weight: F.W) -> AttributedString {
        var a = AttributedString(text)
        guard !marks.isEmpty else { return a }
        a.foregroundColor = base == C.i12 ? C.i10 : base
        a.font = F.font(size, weight)
        let u = text.utf16
        for m in Set(marks) where m >= 0 && m < u.count {
            let lo = u.index(u.startIndex, offsetBy: m)
            guard let start = lo.samePosition(in: text.unicodeScalars) else { continue }
            let end = text.unicodeScalars.index(after: start)
            guard let r = Range(start..<end, in: a) else { continue }
            a[r].foregroundColor = C.i12
            a[r].font = F.font(size, .semibold)
        }
        return a
    }
}

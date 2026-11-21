// Find in a chat (⌘F): a small bar at the chat's top right, a field, "3 of 12", previous and next (↑ ↓, ⌘G ⇧⌘G,
// Return ⇧Return), Esc to close. The transcript does the finding: the bar posts what to look for and which match to
// show, the chat answers with how many it found (contract below, kept by the chat views).
import SwiftUI
import AppKit

/// The notifications between the find bar, the palette and the chat views.
///   find:        ["agentId": conversation id, "query": String, "index": Int]  (index 0-based; an empty query clears)
///   findResult:  ["agentId": conversation id, "count": Int]
///   jump:        ["agentId": conversation id, "messageId": String]
/// A DM's conversation id is its agent's id; a channel's is `c_<workspace>_<channel>`.
enum ChatFindNote {
    static let find = Notification.Name("agentlab.findInChat")
    static let findResult = Notification.Name("agentlab.findInChatResult")
    static let jump = Notification.Name("agentlab.jumpToMessage")
}

/// One conversation's find: open or not, what's typed, which match is shown, how many there are.
@MainActor final class ChatFind: ObservableObject {
    let conv: String
    @Published var open = false
    @Published var query = ""
    @Published var index = 0
    /// What the chat last said it found; nil until it answers.
    @Published var count: Int?
    /// Bumped to put the cursor back in the field (⌘F again while it's open).
    @Published var focusTick = 0
    /// The chat column on screen, for knowing whether it's the chat in front and whether you're in it.
    weak var anchor: NSView?
    private var observer: Any?
    private var pending: Task<Void, Never>?

    private static var all: [String: ChatFind] = [:]
    static func of(_ conv: String) -> ChatFind {
        if let f = all[conv] { return f }
        let f = ChatFind(conv: conv); all[conv] = f; return f
    }
    private init(conv: String) {
        self.conv = conv
        observer = NotificationCenter.default.addObserver(forName: ChatFindNote.findResult, object: nil, queue: .main) { [weak self] n in
            guard let info = n.userInfo, info["agentId"] as? String == conv, let c = info["count"] as? Int else { return }
            MainActor.assumeIsolated {
                guard let self, self.open, !self.query.isEmpty else { return }
                self.count = c
                if self.index >= c { self.index = max(0, c - 1) }
            }
        }
    }

    func show() {
        open = true; focusTick += 1
        if !query.isEmpty { post() }
    }
    func close() {
        pending?.cancel()
        open = false; count = nil; index = 0
        post(query: "")
    }
    /// The words changed: look again from the first match, a moment after typing stops.
    func changed() {
        index = 0; count = nil
        pending?.cancel()
        if query.isEmpty { post(); return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            self?.post()
        }
    }
    func step(_ d: Int) {
        guard let c = count, c > 0 else { return }
        index = (index + d + c) % c
        post()
    }
    private func post(query q: String? = nil) {
        NotificationCenter.default.post(name: ChatFindNote.find, object: nil, userInfo: ["agentId": conv, "query": q ?? query, "index": index])
    }

    /// The find of the chat in front in a window: its column is in the window and not parked (ChatHost hides the chats
    /// it keeps).
    static func active(in window: NSWindow?) -> ChatFind? {
        guard let window else { return nil }
        return all.values.first { f in
            guard let a = f.anchor, a.window === window, !a.isHiddenOrHasHiddenAncestor else { return false }
            return a.visibleRect.width > 1 && a.visibleRect.height > 1
        }
    }
}

// MARK: The bar

struct FindBar: View {
    @ObservedObject var find: ChatFind
    @FocusState private var focused: Bool
    var label: String? {
        guard !find.query.isEmpty, let c = find.count else { return nil }
        return c == 0 ? "No results" : "\(find.index + 1) of \(c)"
    }
    var body: some View {
        HStack(spacing: 6) {
            Icon("search", 14).foregroundStyle(C.i10)
            TextField("", text: $find.query, prompt: Text("Find in chat").foregroundStyle(C.i9))
                .textFieldStyle(.plain).font(F.font(13, .regular)).foregroundStyle(C.i12)
                .frame(width: 170)
                .focused($focused)
                .onSubmit { find.step(NSEvent.modifierFlags.contains(.shift) ? -1 : 1); focused = true }
                .onKeyPress(.upArrow) { find.step(-1); return .handled }
                .onKeyPress(.downArrow) { find.step(1); return .handled }
                .onKeyPress(.escape) { find.close(); return .handled }
            if let label { Text(label).font(F.font(12, .regular)).foregroundStyle(C.i9).monospacedDigit().lineLimit(1).fixedSize() }
            HStack(spacing: 0) {
                button("chevron.up", "Previous match", "⇧⌘G") { find.step(-1) }
                button("chevron.down", "Next match", "⌘G") { find.step(1) }
                button("xmark", "Close", "Esc") { find.close() }
            }
        }
        .padding(.leading, 10).padding(.trailing, 4).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
        .modifier(MenuDrop(soft: false))
        .onChange(of: find.query) { _, _ in find.changed() }
        .onChange(of: find.focusTick) { _, _ in focused = true }
        .onAppear { focused = true }
    }
    private func button(_ symbol: String, _ title: String, _ keys: String, _ action: @escaping () -> Void) -> some View {
        Hover { h in
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(h ? C.i12 : C.i10)
                    .frame(width: 26, height: 28)
                    .background(RoundedRectangle(cornerRadius: R.inset(R.ctl, by: 4), style: .continuous).fill(h ? C.v3 : .clear))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .tip(title, keys).accessibilityLabel(title)
    }
}

/// Puts the find bar on a chat column: `.findInChat(conversationId)`. The bar sits at the top right, under the 56 pt
/// header.
struct FindInChat: ViewModifier {
    @ObservedObject var find: ChatFind
    func body(content: Content) -> some View {
        content
            .background(FindAnchor(find: find))
            .overlay(alignment: .topTrailing) {
                if find.open { FindBar(find: find).padding(.top, 56 + 8).padding(.trailing, 16) }
            }
            .onAppear { FindKeys.install() }
    }
}
extension View {
    @MainActor func findInChat(_ conv: String) -> some View { modifier(FindInChat(find: ChatFind.of(conv))) }
}

/// An empty view the size of the chat column: where the chat is in the window. Takes no clicks.
private struct FindAnchor: NSViewRepresentable {
    let find: ChatFind
    final class Mark: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    func makeNSView(context: Context) -> Mark { let v = Mark(); find.anchor = v; return v }
    func updateNSView(_ v: Mark, context: Context) { if find.anchor !== v { find.anchor = v } }
}

// MARK: The keys

/// ⌘F, ⌘G and ⇧⌘G for the chat in front, read before anything else sees them. ⌘F goes to the chat only when you're in
/// the chat: when you're in the side panel (to the chat's right; a file tab's own ⌘F finds in the file) it's left
/// alone.
@MainActor enum FindKeys {
    private static var monitor: Any?
    /// Where you last clicked, for when nothing in particular has the keyboard.
    private static var lastClick: (window: NSWindow?, point: NSPoint)?
    /// The palette is open (it has the keyboard; ⌘F there does nothing).
    static var paletteOpen = false

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { e in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let ev = e
            return MainActor.assumeIsolated { handle(ev) } ? e : nil
        }
    }
    /// False when the key was used here (nothing else sees it).
    private static func handle(_ e: NSEvent) -> Bool {
        if e.type == .leftMouseDown { lastClick = (e.window, e.locationInWindow); return true }
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods.contains(.command), !paletteOpen, let key = e.charactersIgnoringModifiers?.lowercased() else { return true }
        switch (key, mods) {
        case ("f", [.command]):
            guard let f = ChatFind.active(in: e.window), let w = e.window, inChat(f, w) else { return true }
            f.show(); return false
        case ("g", [.command]), ("g", [.command, .shift]):
            guard let f = ChatFind.active(in: e.window), f.open else { return true }
            f.step(mods.contains(.shift) ? -1 : 1); return false
        default: return true
        }
    }
    /// Opens the find of the chat in front (the palette's "Find in chat").
    static func openActive() {
        guard let f = ChatFind.active(in: NSApp.keyWindow ?? NSApp.mainWindow) else { return }
        f.show()
    }
    /// Whether the keyboard is in the chat rather than in the side panel to its right. The view that has the keyboard
    /// says where you are when it's a small one (a field, a text view); when it's the whole window, your last click does.
    static func inChat(_ f: ChatFind, _ w: NSWindow) -> Bool {
        guard let a = f.anchor else { return false }
        let chat = a.convert(a.bounds, to: nil)
        var responder: NSResponder? = w.firstResponder
        if let t = responder as? NSTextView, t.isFieldEditor, let owner = t.delegate as? NSView { responder = owner }
        if let v = responder as? NSView, v.window === w {
            let r = v.convert(v.bounds, to: nil)
            if r.width < chat.width + 1 { return r.minX < chat.maxX - 1 }
        }
        if let c = lastClick, c.window === w { return c.point.x < chat.maxX - 1 }
        return true
    }
}

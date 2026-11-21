// A web page in a tab beside the chat. Back, forward, reload; its address, which opens the one box that goes to a page,
// searches or asks the agent (Omnibox.swift); "Add page to the chat" (its title, address and text into the agent's box)
// and "Point at something" (click an element on the page; what it is goes into the box). One page per tab, kept while
// the tab is open; pages you visit feed the box's suggestions.
import SwiftUI
import AppKit
import WebKit
import Combine

// MARK: The tab

struct BrowserTab: View {
    @ObservedObject var panel: SidePanel
    let pageId: String
    var body: some View { BrowserBody(panel: panel, page: BrowserPage.of(panel, pageId)) }

    /// Opens `url` in `panel`'s Browser tab (opening the tab if it isn't open). Addresses a web view can't show
    /// (mail, other apps) go to the app that handles them.
    @MainActor static func open(_ url: URL, in panel: SidePanel) {
        guard BrowserPage.canShow(url) else { NSWorkspace.shared.open(url); return }
        panel.openWeb(url)
    }
}

private struct BrowserBody: View {
    @EnvironmentObject var s: Store
    @ObservedObject var panel: SidePanel
    @ObservedObject var page: BrowserPage
    @State private var moreOpen = false
    /// The address bar is being typed in (a click on it, ⌘L): its rows hang under it, over the page.
    @State private var omni: OmniModel?
    /// Where the address bar is, so its rows hang from it.
    @State private var bar: CGRect = .zero
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .top) {
                BrowserHost(page: page, showing: panel.isFront("web:" + page.id)).frame(maxWidth: .infinity, maxHeight: .infinity)
                if let problem = page.problem {
                    VStack(spacing: 8) {
                        Line("Couldn't open this page", 14, .medium, C.i12)
                        Text(problem.reason).font(F.font(13, .regular)).foregroundStyle(C.i10).multilineTextAlignment(.center)
                        Text(problem.url.absoluteString).font(F.font(12, .regular)).foregroundStyle(C.i9).lineLimit(1).truncationMode(.middle)
                        SmallSecondaryButton(title: "Try again") { page.load(problem.url) }.padding(.top, 4)
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(C.v1)
                }
                if page.picking {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Text("Click something on the page").font(F.font(13, .medium)).foregroundStyle(C.i10)
                            Spacer(minLength: 8)
                            SmallSecondaryButton(title: "Cancel") { page.stopPicking() }
                        }
                        .padding(.leading, 14).padding(.trailing, Box.pad).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).fill(C.v2))
                        .overlay(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
                        .floatShadow()
                        .padding(12)
                    }
                }
                if let m = omni {
                    // The page takes no clicks while you type; a click on it lets go of the bar.
                    Color.clear.contentShape(Rectangle()).onTapGesture { closeOmni() }
                    OmniDrop(model: m, bar: bar) { pick($0) }
                }
            }
        }
        .coordinateSpace(.named("browser"))
        .onChange(of: page.focusAddress) { _, _ in openOmni() }
        .onChange(of: omni == nil) { _, closed in page.web.blocked = !closed; page.addressOpen = !closed }
        .onChange(of: page.dismissAddress) { _, _ in if omni != nil { closeOmni() } }
    }

    private func openOmni() {
        guard omni == nil else { return }
        let name = ConvoHub.shared.store?.agents.first { $0.id == panel.agentId }?.name ?? "the agent"
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { omni = OmniModel(agentName: name, start: page.url?.absoluteString ?? "") }
    }
    private func closeOmni() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { omni = nil }
        page.focusPage()
    }
    private func take(_ m: OmniModel, _ kind: OmniModel.Row.Kind?) {
        if let r = kind.flatMap({ m.row($0) }) ?? m.current { pick(r.pick) }
        else if let u = BrowserPage.address(m.text) { pick(.open(u)) }
    }
    private func pick(_ p: OmniPick) {
        closeOmni()
        switch p {
        case .open(let u): page.load(u)
        case .ask(let q):
            guard let a = s.agents.first(where: { $0.id == panel.agentId }) else { return }
            let about = page.url.map { "\n\n(I'm looking at \($0.absoluteString))" } ?? ""
            s.openSideChat(a, question: q + about)
        }
    }

    /// Back, forward, reload; the page's address (a click opens the box over the page); point at something.
    @ViewBuilder private var toolbar: some View {
        if MV.on { mavisToolbar } else { classicToolbar }
    }
    /// MAVIS (prototype .btool): 44 tall, padding 0 6, 2 apart: back, forward, reload (28 round, 18 icons, 45% when
    /// they can't act), the address (34 pill on omni, the lock in a 26 circle, 13.5 text, 6 either side), then the
    /// blue take-over button (pointing at the page: the hand, a check while it's on).
    private var mavisToolbar: some View {
        HStack(spacing: MV.Space.rowGap) {
            MVIconButton(icon: "mvBack", label: "Back") { page.web.goBack() }.opacity(page.canGoBack ? 1 : MV.Browser.disabled).disabled(!page.canGoBack)
            MVIconButton(icon: "mvFwd", label: "Forward") { page.web.goForward() }.opacity(page.canGoForward ? 1 : MV.Browser.disabled).disabled(!page.canGoForward)
            MVIconButton(icon: page.loading ? "mvClose" : "mvReload", label: page.loading ? "Stop" : "Reload") {
                page.loading ? page.web.stopLoading() : page.reload()
            }
            .opacity(page.url != nil ? 1 : MV.Browser.disabled).disabled(page.url == nil)
            Group {
                if let m = omni { AddressEditor(model: m, onReturn: { take(m, $0) }, onCancel: { closeOmni() }) }
                else { MVAddressPill(page: page) { openOmni() } }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("browser")) } action: { bar = $0 }
            .padding(.horizontal, MV.Space.sm)
            Button { page.picking ? page.stopPicking() : page.startPicking() } label: {
                Icon(page.picking ? "mvDone" : "mvGrab", MV.Size.icon).foregroundStyle(Color.white)
                    .frame(width: MV.Size.iconButton, height: MV.Size.iconButton)
                    .background(Circle().fill(MV.Browser.takeOver)).contentShape(Circle())
            }
            .buttonStyle(MVStates(shape: Circle()))
            .disabled(page.url == nil)
            .tip(page.picking ? "Done" : "Take over", edge: .bottom)
            .accessibilityLabel(page.picking ? "Done, hand the page back" : "Take over this page")
        }
        // The header's 8 from the edge, so the take-over button sits right under the collapse button.
        .padding(.horizontal, MV.Space.headerEdge).frame(height: MV.Size.header)
        .background(MV.Tone.toolbar)
        .overlay(alignment: .bottom) {
            if page.loading {
                GeometryReader { g in Rectangle().fill(MV.Accent.blue).frame(width: max(MV.Space.gutter, g.size.width * page.progress)) }
                    .frame(height: MV.Space.rowGap)
            }
        }
    }
    private var classicToolbar: some View {
        HStack(spacing: Box.pair) {
            tool("chevron.left", "Back", "⌘[", enabled: page.canGoBack) { page.web.goBack() }
            tool("chevron.right", "Forward", "⌘]", enabled: page.canGoForward) { page.web.goForward() }
            tool(page.loading ? "xmark" : "arrow.clockwise", page.loading ? "Stop" : "Reload", page.loading ? nil : "⌘R", enabled: page.url != nil) {
                page.loading ? page.web.stopLoading() : page.reload()
            }
            Group {
                if let m = omni { AddressEditor(model: m, onReturn: { take(m, $0) }, onCancel: { closeOmni() }) }
                else { AddressPill(page: page) { openOmni() } }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("browser")) } action: { bar = $0 }
            .padding(.horizontal, 4)
            tool("cursorarrow.rays", page.picking ? "Stop pointing" : "Point at something", nil, enabled: page.url != nil, on: page.picking) {
                page.picking ? page.stopPicking() : page.startPicking()
            }
        }
        .padding(.horizontal, Box.pad).frame(height: Bar.height)
        // The tab in front and this bar are one surface (as Chrome's): the same fill, no line between them.
        .background(C.v2)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .leading) {
                Rectangle().fill(C.divider)
                // The page's loading line, drawn over the bar's own line while it loads.
                if page.loading {
                    GeometryReader { g in Rectangle().fill(C.i10).frame(width: max(8, g.size.width * page.progress)) }
                }
            }
            .frame(height: page.loading ? 2 : 1)
        }
    }

    private var more: some View {
        ActionMenu(open: $moreOpen, width: 240, items: [
            .init(symbol: "plus.magnifyingglass", title: "Zoom in", detail: "⌘+") { page.zoom(by: 0.1) },
            .init(symbol: "minus.magnifyingglass", title: "Zoom out", detail: "⌘−") { page.zoom(by: -0.1) },
            .init(symbol: "1.magnifyingglass", title: "Actual size", detail: page.zoomWords) { page.zoomReset() },
            .divider,
            .init(symbol: "link", title: "Copy address") { page.copyAddress() },
            .init(symbol: "safari", title: "Open in your browser") { page.openOutside() },
        ])
    }

    private func tool(_ symbol: String, _ title: String, _ key: String?, enabled: Bool, on: Bool = false, action: @escaping () -> Void) -> some View {
        ToolIcon(symbol: symbol, label: title, keys: key, enabled: enabled, on: on, action: action)
    }
}

/// MAVIS address pill (prototype .omni): 34 tall, full pill on omni, padding 0 4, 8 apart; the lock in a 26 circle
/// (box2, t2); the address 13.5 in t1 (its path in t3). A click opens the box over the page, as before.
private struct MVAddressPill: View {
    @ObservedObject var page: BrowserPage
    let action: () -> Void
    var body: some View {
        let shape = Capsule()
        Button(action: action) {
            HStack(spacing: MV.Space.labelGap) {
                Icon(page.secure ? "mvLock" : "mvGlobe", MV.Size.iconSmall - MV.Space.rowGap).foregroundStyle(MV.Ink.t2)
                    .frame(width: MV.Browser.site, height: MV.Browser.site).background(Circle().fill(MV.Tone.box2))
                if let u = page.url, let host = u.host() {
                    let rest = u.path + (u.query.map { "?" + $0 } ?? "")
                    (Text(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host).foregroundStyle(MV.Ink.t1)
                     + Text(rest == "/" ? "" : rest).foregroundStyle(MV.Ink.t3))
                        .font(F.font(MV.Browser.address, .regular)).lineLimit(1).truncationMode(.tail)
                } else {
                    Text("Search or type an address").font(F.font(MV.Browser.address, .regular)).foregroundStyle(MV.Ink.t3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MV.Space.xs).frame(height: MV.Size.addressBar)
            .background(shape.fill(MV.Tone.omni)).contentShape(shape)
        }
        .buttonStyle(MVStates(shape: shape))
        .tip("Search, ask or go somewhere", "⌘L")
    }
}

/// The page's address, quiet: its site bright, the rest faint. A click opens the box over the page (⌘L too).
private struct AddressPill: View {
    @ObservedObject var page: BrowserPage
    let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: page.secure ? "lock.fill" : "globe").font(.system(size: 11)).foregroundStyle(C.i9).frame(width: 14)
                    if let u = page.url, let host = u.host() {
                        let rest = u.path + (u.query.map { "?" + $0 } ?? "")
                        (Text(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host).foregroundStyle(C.i12)
                         + Text(rest == "/" ? "" : rest).foregroundStyle(C.i9))
                            .font(F.font(13, .regular)).lineLimit(1).truncationMode(.tail)
                    } else {
                        Text("Search, ask or type an address").font(F.font(13, .regular)).foregroundStyle(C.i9).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(height: Bar.control)
                .background(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).fill(C.v1))
                .overlay(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous).strokeBorder(h ? C.edgeControl : .clear, lineWidth: 1))
                .contentShape(Rectangle())
            }.buttonStyle(Press())
        }
        .tip("Search, ask or go somewhere", "⌘L")
    }
}

/// The rows hanging from the address bar, as wide as it, flat along the top where they meet it.
private struct OmniDrop: View {
    @ObservedObject var model: OmniModel
    let bar: CGRect
    let onPick: (OmniPick) -> Void
    @State private var hover: Int?
    var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS (Chrome's omnibox): the rows hang from the bar as one piece with it: the same fill, flat where they meet,
    /// rounded at the foot (the bar's radius), the 4 / 8% outline. No shadow.
    @ViewBuilder private var mavis: some View {
        if !model.rows.isEmpty {
            let shape = UnevenRoundedRectangle(bottomLeadingRadius: MV.Browser.addressRadius, bottomTrailingRadius: MV.Browser.addressRadius, style: .continuous)
            VStack(spacing: MV.Space.rowGap) {
                // Under the bar's own icon and words (Chrome): 4 in + 4 lead puts the 18 icon on the 26 circle's centre
                // (17) and, 12 after it, the words at the field's 38.
                ForEach(model.rows) { r in MVOmniRow(row: r, on: r.id == model.selected, lead: MV.Space.xs, hover: $hover, onPick: onPick) }
            }
            .padding(.horizontal, MV.Space.xs).padding(.vertical, MV.Space.sm)
            .background(shape.fill(MV.Browser.editing))
            .frame(width: bar.width)
            .offset(x: bar.minX, y: bar.maxY - MV.Size.header)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .transaction { $0.animation = nil }
        }
    }
    @ViewBuilder private var classic: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Bar.radius + 4, bottomTrailingRadius: Bar.radius + 4, style: .continuous)
        if !model.rows.isEmpty {
            OmniRows(model: model, onPick: onPick)
                .padding(4)
                .background(shape.fill(C.v2))
                .overlay(shape.strokeBorder(C.edgeControl, lineWidth: 1).padding(.top, -1).clipped())
                .floatShadow()
                .frame(width: bar.width)
                .offset(x: bar.minX, y: bar.maxY - Bar.height)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transaction { $0.animation = nil }
        }
    }
}

/// The address bar while you type in it: the same place and size, the address selected; flat along the bottom while
/// rows hang under it, so the two read as one piece.
private struct AddressEditor: View {
    @ObservedObject var model: OmniModel
    let onReturn: (OmniModel.Row.Kind?) -> Void
    let onCancel: () -> Void
    var body: some View {
        if MV.on { mavis } else { classic }
    }
    /// MAVIS (Chrome): the bar keeps its place, size and look while you type: 34 tall, the 26 circle on the left (now the
    /// lit row's icon), the words at 13.5. With rows under it, it lifts to the rows' fill and loses its bottom corners,
    /// so the two read as one piece.
    private var mavis: some View {
        let joined = !model.rows.isEmpty
        let r = MV.Browser.addressRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: joined ? 0 : r, bottomTrailingRadius: joined ? 0 : r, topTrailingRadius: r, style: .continuous)
        return HStack(spacing: MV.Space.labelGap) {
            Group {
                if let row = model.current { MVOmniIcon(row: row, lit: true) } else { Icon("mvSearch", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2) }
            }
            .frame(width: MV.Browser.site, height: MV.Browser.site).background(Circle().fill(MV.Tone.box2))
            OmniField(model: model, selectAll: true, prompt: "Search, ask or type an address", size: MV.Browser.address, onReturn: onReturn, onCancel: onCancel)
                .frame(height: MV.Browser.addressLine)
        }
        .padding(.horizontal, MV.Space.xs).frame(height: MV.Size.addressBar)
        .background(shape.fill(joined ? MV.Browser.editing : MV.Tone.omni))
        .transaction { $0.animation = nil }
    }
    private var classic: some View {
        let joined = !model.rows.isEmpty
        let r = Bar.radius
        return HStack(spacing: 8) {
            Image(systemName: model.current?.symbol ?? "magnifyingglass").font(.system(size: 11)).foregroundStyle(C.i10).frame(width: 14)
            OmniField(model: model, selectAll: true, prompt: "Search, ask or type an address", size: 13, onReturn: onReturn, onCancel: onCancel)
                .frame(height: 18)
        }
        .padding(.horizontal, 10).frame(height: Bar.control)
        .background(UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: joined ? 0 : r, bottomTrailingRadius: joined ? 0 : r, topTrailingRadius: r, style: .continuous).fill(C.v1))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: joined ? 0 : r, bottomTrailingRadius: joined ? 0 : r, topTrailingRadius: r, style: .continuous)
            .strokeBorder(C.edgeControl, lineWidth: 1))
        .transaction { $0.animation = nil }
    }
}

/// Puts the page's web view (kept by the page) in the tab.
private struct BrowserHost: NSViewRepresentable {
    let page: BrowserPage
    let showing: Bool
    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        page.attach(to: box)
        return box
    }
    func updateNSView(_ box: NSView, context: Context) {
        if page.web.superview !== box { page.attach(to: box) }
        page.setShowing(showing)
    }
    /// Leaving the page (another page, Home): the web view waits in the window, out of sight, so it keeps its picture
    /// and shows at once when it comes back (taken out of the window, WebKit painted a blank frame or two first).
    static func dismantleNSView(_ box: NSView, coordinator: ()) {
        for v in box.subviews { if let w = v as? BrowserWebView { BrowserPage.park(w, from: box) } }
    }
}

// MARK: The page

@MainActor final class BrowserPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    struct Problem: Equatable { let url: URL; let reason: String }
    @Published var address = ""
    @Published private(set) var url: URL?
    @Published fileprivate(set) var title = ""
    /// The site's icon, for its tab (read from the page once it has loaded).
    @Published private(set) var favicon: NSImage?
    private var faviconHost: String?
    @Published private(set) var loading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var problem: Problem?
    @Published private(set) var picking = false
    /// Bumped to put the keyboard in the address bar.
    @Published private(set) var focusAddress = 0
    /// The address bar has the keyboard (it then keeps what you type instead of following the page).
    var editing = false
    /// You're typing in the address bar (its box is open): + then closes it instead of opening another box.
    var addressOpen = false
    /// Bumped to close the address bar's box.
    @Published private(set) var dismissAddress = 0
    func dismissAddressBar() { dismissAddress += 1 }
    let web: BrowserWebView
    private let panel: SidePanel
    private var observers: [NSKeyValueObservation] = []
    private var watch: AnyCancellable?
    private var showing = false
    private var themeWatch: NSObjectProtocol?

    private static var pages: [String: BrowserPage] = [:]
    /// The page of the web tab `id` (made with the tab, ended when it closes).
    static func of(_ panel: SidePanel, _ id: String) -> BrowserPage {
        if let p = pages[id] { return p }
        let p = BrowserPage(panel: panel, id: id)
        pages[id] = p
        // A tab kept from before (SidePanel.saveBrowser): its page opens where it was.
        if let u = panel.restored.removeValue(forKey: id) {
            if let t = panel.restoredTitles.removeValue(forKey: id) { p.title = t }
            p.load(u)
        }
        return p
    }
    /// The page of tab `id`, if it has been made.
    static func existing(_ id: String) -> BrowserPage? { pages[id] }
    let id: String

    private init(panel: SidePanel, id: String) {
        self.panel = panel; self.id = id
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        // It's Safari's engine, so it says so as Safari does ("Version/27.0 Safari/605.1.15"). A bare web view's name tells
        // sites it's an unknown browser: Google sent its old basic page and asked "are you a robot" far more often.
        config.applicationNameForUserAgent = Self.safariName
        // The page's console and errors, kept for the agent (browser_console in AgentHands.swift).
        config.userContentController.addUserScript(WKUserScript(source: Self.consoleKeeper, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = BrowserWebView(frame: .zero, configuration: config)
        super.init()
        web.configuration.userContentController.add(WeakHandler(self), contentWorld: .defaultClient, name: "browser")
        web.page = self
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsMagnification = true
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = NSColor(red: 0x0a / 255, green: 0x0a / 255, blue: 0x0a / 255, alpha: 1)
        // Pages in their dark look (prefers-color-scheme), as your browser in dark mode shows them.
        web.appearance = NSAppearance(named: themeNow.dark ? .darkAqua : .aqua)
        themeWatch = NotificationCenter.default.addObserver(forName: Themes.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.web.appearance = NSAppearance(named: themeNow.dark ? .darkAqua : .aqua) }
        }
        observers = [
            web.observe(\.estimatedProgress) { [weak self] w, _ in let v = w.estimatedProgress; Task { @MainActor in self?.progress = v } },
            web.observe(\.isLoading) { [weak self] w, _ in let v = w.isLoading; Task { @MainActor in self?.loading = v } },
            web.observe(\.canGoBack) { [weak self] w, _ in let v = w.canGoBack; Task { @MainActor in self?.canGoBack = v } },
            web.observe(\.canGoForward) { [weak self] w, _ in let v = w.canGoForward; Task { @MainActor in self?.canGoForward = v } },
            web.observe(\.title) { [weak self] w, _ in
                let v = w.title ?? "", u = w.url
                Task { @MainActor in guard let self else { return }; if !v.isEmpty || self.title.isEmpty { self.title = v }; if let u, !v.isEmpty { BrowserHistory.shared.visit(u, title: v) }; self.panel.saveBrowser() }
            },
            web.observe(\.url) { [weak self] w, _ in let v = w.url; Task { @MainActor in self?.moved(to: v) } },
        ]
        // The page lives as long as its tab.
        watch = panel.$tabs.sink { [weak self] tabs in
            guard let self else { return }
            let mine = "web:" + self.id
            if !tabs.contains(where: { $0.id == mine }) { Task { @MainActor in self.end() } }
        }
    }

    var secure: Bool { url?.scheme == "https" }
    var zoomWords: String { "\(Int((web.pageZoom * 100).rounded()))%" }

    func attach(to box: NSView) {
        self.box = box
        web.removeFromSuperview()
        web.frame = box.bounds
        web.autoresizingMask = [.width, .height]
        if showing { box.addSubview(web) }
    }
    private weak var box: NSView?
    /// A web view whose pane went away with its page: kept in the window, past its left edge, still drawing.
    static func park(_ web: NSView, from box: NSView) {
        guard let content = box.window?.contentView else { return }
        let size = web.frame.size
        web.removeFromSuperview()
        web.frame = NSRect(origin: NSPoint(x: -size.width - MV.Space.section, y: 0), size: size)
        web.autoresizingMask = []
        content.addSubview(web)
    }

    func setShowing(_ on: Bool) {
        if on, web.superview !== box, let box { web.removeFromSuperview(); web.frame = box.bounds; web.autoresizingMask = [.width, .height]; box.addSubview(web) }
        web.isHidden = !on
        guard on != showing else { return }
        showing = on
        if !on {
            let size = web.frame.size
            web.removeFromSuperview()
            web.frame.size = size              // still laid out at its size, for the agent's reading and pictures
            if picking { stopPicking() }
            if let w = web.window, let r = w.firstResponder as? NSView, r === web || r.isDescendant(of: web) { w.makeFirstResponder(nil) }
        }
    }

    // MARK: Going places

    func load(_ u: URL) {
        problem = nil
        if picking { stopPicking() }
        if u.isFileURL { web.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent()) }
        else { web.load(URLRequest(url: u)) }
        url = url ?? u
        if !editing { address = u.absoluteString }
    }

    func reload() {
        if let p = problem { load(p.url) } else { web.reload() }
    }

    /// What you typed: an address (https unless it says otherwise; local servers on http) or else a search.
    func go(_ typed: String) {
        guard let u = Self.address(typed) else { showCurrentAddress(); return }
        load(u)
        focusPage()
    }

    nonisolated static func address(_ typed: String) -> URL? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()
        if lower.range(of: #"^[a-z][a-z0-9+.\-]*://"#, options: .regularExpression) != nil || lower.hasPrefix("about:") || lower.hasPrefix("mailto:") || lower.hasPrefix("data:") {
            return URL(string: t) ?? URL(string: t.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? t)
        }
        if t.hasPrefix("/") || t.hasPrefix("~/") { return URL(fileURLWithPath: (t as NSString).expandingTildeInPath) }
        if !t.contains(" ") {
            // Local servers and bare addresses on this network speak plain http.
            let host = lower.split(whereSeparator: { "/:?#".contains($0) }).first.map(String.init) ?? lower
            let local = ["localhost", "127.0.0.1", "0.0.0.0", "[::1]"].contains(host) || host.hasSuffix(".localhost") || host.hasSuffix(".local")
                || host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            if local { return URL(string: "http://" + t) }
            let hasPort = lower.range(of: #"^[a-z0-9.\-]+:\d+"#, options: .regularExpression) != nil
            if hasPort || host.range(of: #"^([a-z0-9\-]+\.)+[a-z][a-z0-9\-]{1,}$"#, options: .regularExpression) != nil {
                return URL(string: "https://" + t)
            }
        }
        var q = URLComponents(string: "https://www.google.com/search")!
        q.queryItems = [URLQueryItem(name: "q", value: t)]
        return q.url
    }

    nonisolated static func canShow(_ u: URL) -> Bool { ["http", "https", "file", "about", "data"].contains(u.scheme?.lowercased() ?? "") }

    private func moved(to u: URL?) {
        guard let u, u.absoluteString != "about:blank" || url == nil else { return }
        url = u
        panel.saveBrowser()
        if u.scheme == "http" || u.scheme == "https" { BrowserHistory.shared.visit(u, title: title) }
        if !editing { address = u.absoluteString }
    }

    func showCurrentAddress() { address = url?.absoluteString ?? "" }
    func focusPage() { DispatchQueue.main.async { [self] in web.window?.makeFirstResponder(web) } }
    func focusAddressBar() { focusAddress += 1 }

    // MARK: Zoom

    func zoom(by step: CGFloat) { web.pageZoom = min(3, max(0.3, ((web.pageZoom + step) * 10).rounded() / 10)) }
    func zoomReset() { web.pageZoom = 1 }

    func copyAddress() {
        guard let u = url else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(u.absoluteString, forType: .string)
    }
    func openOutside() { if let u = url { NSWorkspace.shared.open(u) } }

    // MARK: Into the message

    /// The page's title, address and readable text (its article or main part when it has one), into the agent's box.
    func addPage() {
        guard url != nil else { return }
        web.evaluateJavaScript(Self.readable, in: nil, in: .defaultClient) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard case .success(let v) = result, let d = v as? [String: Any] else { return }
                let title = (d["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let href = d["url"] as? String ?? self.url?.absoluteString ?? ""
                var text = (d["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > Self.pageMax { text = String(text.prefix(Self.pageMax)) + "\n…" }
                var out = "Page: \(title.isEmpty ? href : title)\n\(href)"
                if !text.isEmpty { out += "\n\n" + text }
                AddToMessage.send(self.panel.agentId, out)
            }
        }
    }
    private static let pageMax = 12_000

    /// Point at something: outlines what's under the pointer; a click picks it, Esc stops.
    func startPicking() {
        guard url != nil, problem == nil else { return }
        picking = true
        web.window?.makeFirstResponder(web)
        web.evaluateJavaScript(Self.picker, in: nil, in: .defaultClient) { [weak self] result in
            if case .failure = result { MainActor.assumeIsolated { self?.picking = false } }
        }
    }
    func stopPicking() {
        picking = false
        web.evaluateJavaScript("window.__alPick && window.__alPick.stop()", in: nil, in: .defaultClient, completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let t = m["t"] as? String else { return }
        switch t {
        case "picked":
            picking = false
            let selector = m["selector"] as? String ?? ""
            let tag = m["tag"] as? String ?? ""
            let text = (m["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let html = m["html"] as? String ?? ""
            var out = "Element on \(url?.absoluteString ?? "the page")\nSelector: \(selector)\n<\(tag)>"
            if !text.isEmpty { out += " \u{201C}\(text)\u{201D}" }
            if !html.isEmpty { out += "\n```html\n\(html)\n```" }
            AddToMessage.send(panel.agentId, out)
        case "pickEnd":
            picking = false
        default: break
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.shouldPerformDownload { if let u = action.request.url { NSWorkspace.shared.open(u) }; return .cancel }
        guard let u = action.request.url else { return .allow }
        if !Self.canShow(u) && u.scheme != "blob" {
            // mailto:, app links and the like go to the app that handles them.
            NSWorkspace.shared.open(u)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        // Files the page can't show (downloads) are handed to your browser to fetch.
        if !response.canShowMIMEType, response.isForMainFrame, let u = response.response.url {
            NSWorkspace.shared.open(u)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { problem = nil; if picking { stopPicking() } }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loadFavicon() }

    /// The page's own icon (its <link rel=icon>, else /favicon.ico), fetched once per site.
    private func loadFavicon() {
        guard let host = web.url?.host(), host != faviconHost else { return }
        let js = "(() => { const l = [...document.querySelectorAll('link[rel~=icon], link[rel=apple-touch-icon]')].map(x => x.href).filter(Boolean); return l[0] || (location.origin + '/favicon.ico'); })()"
        web.evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] result in
            MainActor.assumeIsolated {
                let origin = self?.web.url.flatMap { u in u.scheme.map { "\($0)://\(host)" } }
                let first = (try? result.get()) as? String
                let tries = [first, origin.map { $0 + "/favicon.ico" }].compactMap { $0 }.compactMap(URL.init(string:)).filter { $0.scheme?.hasPrefix("http") == true }
                // The page's own icon, else the site's /favicon.ico (as Chrome falls back), the first that's a picture.
                Task { [weak self] in
                    for u in tries {
                        guard let (data, _) = try? await URLSession.shared.data(from: u), let img = NSImage(data: data), img.size.width > 0 else { continue }
                        self?.favicon = img; self?.faviconHost = host
                        Favicons.shared.keep(host, img)
                        return
                    }
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let u = url { problem = Problem(url: u, reason: "The page stopped working.") }
    }

    private func failed(_ error: Error) {
        let e = error as NSError
        // Stopped by you or replaced by another load, or a download handed off: not a problem.
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 204) { return }
        let failing = (e.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url ?? URL(string: "about:blank")!
        problem = Problem(url: failing, reason: Self.words(e))
        if !editing { address = failing.absoluteString }
    }

    private static func words(_ e: NSError) -> String {
        guard e.domain == NSURLErrorDomain else { return e.localizedDescription }
        switch e.code {
        case NSURLErrorCannotConnectToHost: return "Nothing answered at this address. If it's a local server, check that it's running."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "There's no site at this address."
        case NSURLErrorNotConnectedToInternet: return "This Mac isn't connected to the internet."
        case NSURLErrorTimedOut: return "The site took too long to answer."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorServerCertificateHasUnknownRoot: return "The site's secure connection couldn't be trusted."
        default: return e.localizedDescription
        }
    }

    // Links that open a new window (target=_blank, window.open) open here instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url { if Self.canShow(u) { webView.load(action.request) } else { NSWorkspace.shared.open(u) } }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK")
        if let w = webView.window { await a.beginSheetModal(for: w) } else { a.runModal() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        let r = webView.window != nil ? await a.beginSheetModal(for: webView.window!) : a.runModal()
        return r == .alertFirstButtonReturn
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let p = NSOpenPanel(); p.allowsMultipleSelection = parameters.allowsMultipleSelection; p.canChooseDirectories = parameters.allowsDirectories
        return p.runModal() == .OK ? p.urls : nil
    }

    private func end() {
        guard let p = Self.pages[id], p === self else { return }
        Self.pages[id] = nil
        watch = nil; observers = []
        web.stopLoading()
        web.navigationDelegate = nil; web.uiDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: "browser", contentWorld: .defaultClient)
        web.removeFromSuperview()
    }

    // MARK: Scripts (run in their own world, out of the page's way)

    /// Safari's own name for this Mac's version (read from Safari, so it stays true as macOS updates).
    static let safariName: String = {
        let v = (NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")?["CFBundleShortVersionString"] as? String) ?? "27.0"
        return "Version/\(v) Safari/605.1.15"
    }()
    static let consoleKeeper = #"""
    (() => {
      if (window.__alLogs) return;
      const logs = window.__alLogs = [];
      const keep = (level, args) => {
        let t; try { t = args.map((a) => typeof a === 'string' ? a : a instanceof Error ? (a.stack || a.message) : JSON.stringify(a)).join(' '); } catch (e) { t = String(args[0]); }
        logs.push(level + ': ' + String(t).slice(0, 1000)); if (logs.length > 200) logs.shift();
      };
      for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        const was = console[level];
        console[level] = function (...args) { keep(level, args); return was.apply(this, args); };
      }
      addEventListener('error', (e) => keep('error', [e.message + (e.filename ? ' (' + e.filename + ':' + e.lineno + ')' : '')]));
      addEventListener('unhandledrejection', (e) => keep('error', ['Unhandled rejection: ' + (e.reason && (e.reason.stack || e.reason.message) || e.reason)]));
    })();
    """#

    static let readable = #"""
    (() => {
      const root = document.querySelector('article') || document.querySelector('main') || document.querySelector('[role=main]') || document.body;
      let text = root ? root.innerText : '';
      if (root !== document.body && text.trim().length < 200 && document.body) text = document.body.innerText;
      text = text.replace(/[ \t ]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
      return { title: document.title || '', url: location.href, text: text.slice(0, 20000) };
    })()
    """#

    static let picker = #"""
    (() => {
      if (window.__alPick) window.__alPick.stop(true);
      const post = (m) => window.webkit.messageHandlers.browser.postMessage(m);
      const box = document.createElement('div');
      Object.assign(box.style, { position: 'fixed', zIndex: 2147483647, pointerEvents: 'none', boxSizing: 'border-box',
        border: '1.5px solid rgba(237,237,237,0.9)', boxShadow: '0 0 0 1px rgba(0,0,0,0.45)', background: 'rgba(255,255,255,0.10)',
        borderRadius: '6px', display: 'none' });
      const tag = document.createElement('div');
      Object.assign(tag.style, { position: 'fixed', zIndex: 2147483647, pointerEvents: 'none', background: '#1a1a1a', color: '#ededed',
        font: '500 11px -apple-system, system-ui, sans-serif', padding: '3px 7px', borderRadius: '6px', display: 'none',
        border: '1px solid rgba(255,255,255,0.055)', whiteSpace: 'nowrap', maxWidth: '60vw', overflow: 'hidden', textOverflow: 'ellipsis' });
      document.documentElement.append(box, tag);
      let target = null;
      const name = (el) => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.classList.length ? '.' + [...el.classList].slice(0, 2).join('.') : '');
      const draw = () => {
        if (!target) { box.style.display = tag.style.display = 'none'; return; }
        const r = target.getBoundingClientRect();
        Object.assign(box.style, { display: 'block', left: r.left - 2 + 'px', top: r.top - 2 + 'px', width: r.width + 4 + 'px', height: r.height + 4 + 'px' });
        tag.textContent = name(target) + '  ' + Math.round(r.width) + '×' + Math.round(r.height);
        const y = r.top > 26 ? r.top - 26 : Math.min(r.bottom + 6, innerHeight - 24);
        Object.assign(tag.style, { display: 'block', left: Math.max(4, r.left - 2) + 'px', top: y + 'px' });
      };
      const unique = (sel) => { try { return document.querySelectorAll(sel).length === 1; } catch (e) { return false; } };
      const selector = (el) => {
        if (el.id && unique('#' + CSS.escape(el.id))) return '#' + CSS.escape(el.id);
        const parts = [];
        for (let n = el; n && n.nodeType === 1 && n !== document.documentElement; n = n.parentElement) {
          if (n.id && unique('#' + CSS.escape(n.id))) { parts.unshift('#' + CSS.escape(n.id)); break; }
          let p = n.tagName.toLowerCase();
          const sibs = n.parentElement ? [...n.parentElement.children].filter((c) => c.tagName === n.tagName) : [];
          if (sibs.length > 1) p += ':nth-of-type(' + (sibs.indexOf(n) + 1) + ')';
          parts.unshift(p);
          if (unique(parts.join(' > '))) break;
        }
        return parts.join(' > ');
      };
      const over = (e) => { const t = e.target; if (t && t !== box && t !== tag && t.nodeType === 1) { target = t; draw(); } };
      const block = (e) => { e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); };
      const click = (e) => {
        block(e);
        const el = target || e.target;
        if (!el || el.nodeType !== 1) return;
        let html = el.outerHTML || '';
        if (html.length > 2000) html = html.slice(0, 2000) + '…';
        let text = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
        if (text.length > 240) text = text.slice(0, 240) + '…';
        stop(true);
        post({ t: 'picked', selector: selector(el), tag: el.tagName.toLowerCase(), text, html });
      };
      const key = (e) => { if (e.key === 'Escape') { block(e); stop(); } };
      const events = [['mouseover', over], ['mousedown', block], ['mouseup', block], ['click', click], ['pointerdown', block], ['keydown', key]];
      for (const [n, f] of events) window.addEventListener(n, f, true);
      addEventListener('scroll', draw, true);
      document.documentElement.style.cursor = 'crosshair';
      function stop(quiet) {
        for (const [n, f] of events) window.removeEventListener(n, f, true);
        removeEventListener('scroll', draw, true);
        box.remove(); tag.remove();
        document.documentElement.style.cursor = '';
        window.__alPick = null;
        if (!quiet) post({ t: 'pickEnd' });
      }
      window.__alPick = { stop };
      return true;
    })()
    """#
}

/// The browser's web view: ⌘+ ⌘− ⌘0 zoom, ⌘L the address bar, ⌘R reload, ⌘[ ⌘] back and forward, while the page has
/// the keyboard; Esc stops pointing.
final class BrowserWebView: WKWebView {
    weak var page: BrowserPage?
    /// Something is over the page (the box): it takes no clicks, so they reach what's over it.
    var blocked = false
    override func hitTest(_ point: NSPoint) -> NSView? { blocked ? nil : super.hitTest(point) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let page, let r = window?.firstResponder as? NSView, r === self || r.isDescendant(of: self) else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "=", "+": page.zoom(by: 0.1); return true
        case "-", "_": page.zoom(by: -0.1); return true
        case "0": page.zoomReset(); return true
        case "l", "L": page.focusAddressBar(); return true
        case "r", "R": page.reload(); return true
        case "[": goBack(); return true
        case "]": goForward(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let page, page.picking { page.stopPicking(); return }
        super.keyDown(with: event)
    }
}


/// Sites' icons by host, for everything that shows a site without its page open (the omnibox's rows): the ones pages
/// found (kept on disk under Caches), else the site's /favicon.ico, fetched once.
@MainActor final class Favicons: ObservableObject {
    static let shared = Favicons()
    @Published private(set) var icons: [String: NSImage] = [:]
    private var asked: Set<String> = []
    private let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab/favicons")
    static func key(_ host: String) -> String { host.lowercased().replacingOccurrences(of: "www.", with: "") }
    func keep(_ host: String, _ img: NSImage) {
        let k = Self.key(host)
        icons[k] = img
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent(k + ".png"))
        }
    }
    func icon(_ host: String) -> NSImage? {
        let k = Self.key(host)
        if let i = icons[k] { return i }
        guard !asked.contains(k) else { return nil }
        asked.insert(k)
        if let img = NSImage(contentsOf: dir.appendingPathComponent(k + ".png")), img.size.width > 0 {
            DispatchQueue.main.async { self.icons[k] = img }
            return img
        }
        Task { [weak self] in
            for u in ["https://\(host)/favicon.ico", "https://www.\(k)/favicon.ico"].compactMap(URL.init(string:)) {
                guard let (data, _) = try? await URLSession.shared.data(from: u), let img = NSImage(data: data), img.size.width > 0 else { continue }
                self?.keep(host, img); return
            }
        }
        return nil
    }
}

/// A site's icon at `size` (its favicon, as on its tab), else the globe.
struct SiteIcon: View {
    let host: String?; let size: CGFloat; var ink: Color = MV.Ink.t3
    @ObservedObject private var icons = Favicons.shared
    var body: some View {
        if let host, let img = icons.icon(host) {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: MV.Size.siteIconRadius, style: .continuous))
        } else {
            Icon("mvGlobe", size).foregroundStyle(ink)
        }
    }
}

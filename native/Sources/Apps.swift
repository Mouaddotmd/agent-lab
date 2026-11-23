// Connected apps (Mavis final launch's Connectors.swift, ported): what the engine knows (engine/apps.js), connecting,
// disconnecting, the apps' own logos, and the note that goes with a message when you pick one.
import SwiftUI
import AppKit

@MainActor final class Apps: ObservableObject {
    static let shared = Apps()
    weak var store: Store?

    struct App: Identifiable, Equatable, Decodable {
        let slug: String
        let label: String
        var description = ""
        var categories: [String] = []
        var tools = 0
        var site: String? = nil
        var logo: String? = nil
        var id: String { slug }
    }
    struct Account: Identifiable, Equatable, Decodable { let id: String; var alias: String?; var status: String }
    struct Service: Equatable, Decodable { var connected: Bool; var pending: Bool; var accounts: [Account] }
    private struct Services: Decodable { let configured: Bool; let own: Bool?; let consumer: Bool?; let services: [String: Service] }
    private struct Catalog: Decodable { let cards: [App] }
    private struct SignIn: Decodable { let url: String?; let connected: Bool? }

    /// Apps can be connected on this Mac. Own: with a Composio key of yours. Consumer: a Connect key, whose apps are
    /// connected on composio.dev too.
    @Published private(set) var available = true
    @Published private(set) var own = false
    @Published private(set) var consumer = false
    /// Every app there is, most used first.
    @Published private(set) var catalog: [App] = []
    @Published private(set) var services: [String: Service] = [:]
    /// Connected, by name; and waiting for you to finish signing in.
    @Published private(set) var connected: [String] = []
    @Published private(set) var pending: Set<String> = []
    /// The app being connected or disconnected right now.
    @Published private(set) var working: String?
    @Published private(set) var loading = false
    @Published var error: String?
    private var watches: [String: Task<Void, Never>] = [:]
    /// Sign-in pages opened this session: opening one again goes to the same page.
    private var pages: [String: URL] = [:]
    private var refreshing: Task<Void, Never>?

    /// The apps people reach for first: shown before the full list has loaded, and as Popular after.
    static let starter: [App] = [
        ("gmail", "Gmail", "Read, search, draft and send your email."), ("googlecalendar", "Google Calendar", "See your day, find time and book meetings."),
        ("youtube", "YouTube", "Your channel, videos, comments and analytics."), ("slack", "Slack", "Read channels, catch up and post messages."),
        ("notion", "Notion", "Search, write and update pages and databases."), ("github", "GitHub", "Issues, pull requests, code and releases."),
        ("googledrive", "Google Drive", "Find, read and organise your files."), ("googledocs", "Google Docs", "Write and edit documents."),
        ("googlesheets", "Google Sheets", "Read and fill in spreadsheets."), ("linear", "Linear", "Triage, create and update issues."),
        ("figma", "Figma", "Read files, comments and components."), ("linkedin", "LinkedIn", "Write posts and read your profile."),
        ("discord", "Discord", "Your servers, channels and messages."), ("outlook", "Outlook", "Email and calendar from Microsoft."),
        ("stripe", "Stripe", "Payments, customers and invoices."), ("shopify", "Shopify", "Products, orders and customers."),
        ("reddit", "Reddit", "Search, read and post in communities."), ("airtable", "Airtable", "Read and update your bases."),
        ("googleslides", "Google Slides", ""), ("googlemeet", "Google Meet", ""), ("whatsapp", "WhatsApp", ""), ("zoom", "Zoom", ""), ("dropbox", "Dropbox", ""),
        ("trello", "Trello", ""), ("asana", "Asana", ""), ("jira", "Jira", ""), ("hubspot", "HubSpot", ""), ("canva", "Canva", ""),
    ].map { App(slug: $0.0, label: $0.1, description: $0.2, logo: "https://logos.composio.dev/api/\($0.0)") }
    var offered: [App] { catalog.isEmpty ? Self.starter : catalog }

    func app(_ slug: String) -> App {
        catalog.first { $0.slug == slug } ?? Self.starter.first { $0.slug == slug }
            ?? App(slug: slug, label: slug.split(separator: "_").map { $0.capitalized }.joined(separator: " "), logo: "https://logos.composio.dev/api/\(slug)")
    }
    /// Its line on a card: ours for the apps people reach for first, else its own.
    func line(_ app: App) -> String {
        let ours = Self.starter.first { $0.slug == app.slug }?.description ?? ""
        return ours.isEmpty ? app.description : ours
    }

    /// Where an app's logo comes from: its makers' own current asset when they publish one we can reach (Google's
    /// product icons, GitHub's mark from Primer Octicons, pinned), otherwise the catalogue's.
    static func logo(for app: App) -> URL? {
        let google = ["gmail": "gmail", "googlecalendar": "calendar", "googledrive": "drive", "googledocs": "docs",
                      "googlesheets": "sheets", "googleslides": "slides", "googlemeet": "meet", "googlekeep": "keep"]
        if let name = google[app.slug] { return URL(string: "https://ssl.gstatic.com/images/branding/product/2x/\(name)_2020q4_48dp.png") }
        if app.slug == "github" { return URL(string: "https://cdn.jsdelivr.net/npm/@primer/octicons@19.15.1/build/svg/mark-github-24.svg") }
        return app.logo.flatMap(URL.init(string:))
    }

    /// Reads what the engine has: your connections, and the list of apps (once). One at a time.
    func refresh() async {
        if SnapshotMode.on { return }
        if let refreshing { return await refreshing.value }
        let t = Task { await self.load() }
        refreshing = t
        await t.value
        refreshing = nil
    }
    private func load() async {
        guard let engine = store?.engine else { return }
        loading = true; defer { loading = false }
        do {
            let r = try await engine.call("apps:services", as: Services.self)
            available = r.configured; own = r.own ?? false; consumer = r.consumer ?? false
            if services != r.services { services = r.services }
            let mine = r.services.filter { $0.value.connected && (consumer || !$0.value.accounts.isEmpty) }.keys
            let now = mine.sorted { app($0).label.localizedCaseInsensitiveCompare(app($1).label) == .orderedAscending }
            if connected != now { connected = now }
            let waiting = Set(r.services.filter { !$0.value.connected && $0.value.pending }.keys)
            if pending != waiting { pending = waiting }
            if available, catalog.isEmpty, let c = try? await engine.call("apps:catalog", as: Catalog.self) { catalog = c.cards }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Opens the app's own sign-in page in your browser, then watches until it's connected (up to three minutes).
    /// `alias` names a second account, so the one you have isn't replaced.
    @discardableResult func connect(_ slug: String, alias: String? = nil) async -> Bool {
        guard let engine = store?.engine, working == nil else { return false }
        if alias == nil, pending.contains(slug), let page = pages[slug] { NSWorkspace.shared.open(page); watch(slug, accounts: 0); return true }
        working = slug; defer { working = nil }
        error = nil
        let had = services[slug]?.accounts.filter { $0.status.uppercased() == "ACTIVE" }.count ?? 0
        do {
            let r = try await engine.call("apps:connect", [slug, alias ?? NSNull()] as [Any], as: SignIn.self)
            if r.connected == true { await refresh(); return true }      // already signed in: nothing to open
            guard let link = r.url, let url = URL(string: link), url.scheme == "https" else { throw EngineError(message: "Couldn\u{2019}t open \(app(slug).label)\u{2019}s sign-in page. Try again in a moment.") }
            NSWorkspace.shared.open(url)
            if alias == nil { pages[slug] = url; pending.insert(slug) }
            watch(slug, accounts: alias == nil ? 0 : had)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func watch(_ slug: String, accounts had: Int) {
        watches[slug]?.cancel()
        watches[slug] = Task { @MainActor [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
                let active = self.services[slug]?.accounts.filter { $0.status.uppercased() == "ACTIVE" }.count ?? 0
                if self.connected.contains(slug), self.consumer || active > had { self.pages[slug] = nil; return }
            }
        }
    }
    func disconnect(_ slug: String) async {
        guard let engine = store?.engine, working == nil else { return }
        working = slug; defer { working = nil }
        watches[slug]?.cancel(); pages[slug] = nil
        do {
            _ = try await engine.call("apps:disconnect", [slug])
            NotificationCenter.default.post(name: .appGone, object: nil, userInfo: ["slug": slug])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ slug: String, account: String) async {
        guard let engine = store?.engine, working == nil else { return }
        working = slug; defer { working = nil }
        do { _ = try await engine.call("apps:remove-account", [slug, account]); await refresh() } catch { self.error = error.localizedDescription }
    }
    /// Your own Composio key; empty goes back to the built-in connection. nil when kept, else what's wrong.
    func setKey(_ key: String) async -> String? {
        guard let engine = store?.engine else { return nil }
        do {
            _ = try await engine.call("apps:key", [key])
            catalog = []; services = [:]; connected = []; pending = []; pages = [:]
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }
    /// Puts an app on your next message to the agent you last talked to, its chat open (with words to start from).
    func use(_ slug: String, words: String = "") {
        guard let s = store else { return }
        guard let a = s.agents.first(where: { $0.id == s.messagesAgent }) ?? s.agents.max(by: { (lastAt($0)) < (lastAt($1)) }) else { s.newAgentOpen = true; return }
        s.restore[a.id] = DraftStore.Draft(text: words, apps: [slug])
        s.openChat(a.id)
    }
}
extension Notification.Name { static let appGone = Notification.Name("appGone") }

// MARK: The note that goes with a message

/// A picked app travels as a note after your words, which the engine reads ("(connected-app:<slug>)"); the chat shows it
/// as the app's logo and name instead (Mavis: ComposerMode.connector).
enum SentApps {
    @MainActor static func append(_ words: String, _ picks: [String]) -> String {
        guard !picks.isEmpty else { return words }
        let notes = picks.map { slug in
            let name = Apps.shared.app(slug).label
            return "[\(name)]\nUse my connected \(name) account for this, through its connector tools (connected-app:\(slug))."
        }
        return ([words] + notes).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    private static let note = try! NSRegularExpression(pattern: #"(?:^|\n+)\[[^\n\]]+\]\nUse my connected [^\n]+ account for this, through its connector tools \(connected-app:([\w-]+)\)\.\s*$"#)
    static func split(_ text: String) -> (words: String, apps: [String]) {
        var rest = text, apps: [String] = []
        while rest.contains("(connected-app:"), let m = note.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
              let slug = Range(m.range(at: 1), in: rest), let whole = Range(m.range, in: rest) {
            apps.insert(String(rest[slug]), at: 0)
            rest = String(rest[..<whole.lowerBound])
        }
        return (rest.trimmingCharacters(in: .whitespacesAndNewlines), apps)
    }
}

// MARK: Logos

/// An app's logo as its makers drew it, trimmed to its drawing. A dark mark with no colour (GitHub) is drawn in the text
/// colour; one that mixes ink with white (Notion) sits on paper; colour logos are as they are. `solid` fills its square.
struct AppLogoImage { enum Look { case asIs, mark, paper }; let image: NSImage; let look: Look; let solid: Bool }

/// One logo, read once, off the main thread, and kept (on disk too): a card redraws only when its own logo arrives.
@MainActor final class AppLogoBox: ObservableObject {
    @Published private(set) var logo: AppLogoImage?
    private static var all: [URL: AppLogoBox] = [:]
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab/App Logos", isDirectory: true)
        c.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 64 << 20, directory: folder)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: c)
    }()
    static func of(_ url: URL) -> AppLogoBox {
        if let b = all[url] { return b }
        let b = AppLogoBox(); all[url] = b
        b.load(url, tries: 2)
        return b
    }
    private func load(_ url: URL, tries: Int) {
        Task {
            guard let (data, response) = try? await Self.session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 else {
                if tries > 0 { try? await Task.sleep(for: .seconds(4)); load(url, tries: tries - 1) }
                return
            }
            logo = await Task.detached(priority: .utility) { Self.read(data) }.value
        }
    }
    /// Drawn once into pixels (an SVG is drawn large enough for every size), then read: its drawn part and its colours.
    nonisolated private static func read(_ data: Data) -> AppLogoImage? {
        guard let source = NSImage(data: data), source.size.width > 0, source.size.height > 0 else { return nil }
        let side = 192
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let k = min(CGFloat(side) / source.size.width, CGFloat(side) / source.size.height)
        let w = source.size.width * k, h = source.size.height * k
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        source.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let whole = ctx.makeImage(), let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = side, minY = side, maxX = -1, maxY = -1, filled = 0, opaque = 0, dark = 0, light = 0, colour = 0
        for y in 0..<side { for x in 0..<side {
            let p = (y * side + x) * 4, a = Double(bytes[p + 3]) / 255
            guard a > 0.08 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y); filled += 1
            guard a > 0.5 else { continue }
            let c = [Double(bytes[p]), Double(bytes[p + 1]), Double(bytes[p + 2])].map { $0 / 255 / a }
            let hi = c.max()!, lo = c.min()!
            opaque += 1
            if hi - lo > 0.18 { colour += 1 } else if hi < 0.35 { dark += 1 } else if lo > 0.8 { light += 1 }
        } }
        guard maxX >= minX, opaque > 0 else { return nil }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        guard let cut = whole.cropping(to: CGRect(x: minX, y: minY, width: bw, height: bh)) else { return nil }
        let d = Double(dark) / Double(opaque), l = Double(light) / Double(opaque), c = Double(colour) / Double(opaque)
        let look: AppLogoImage.Look = c < 0.05 && d > 0.85 && l < 0.02 ? .mark : c < 0.05 && d > 0.25 && d < 0.85 && l > 0.1 ? .paper : .asIs
        let solid = Double(filled) / Double(bw * bh) > 0.8 && abs(bw - bh) <= 6
        return AppLogoImage(image: NSImage(cgImage: cut, size: NSSize(width: bw, height: bh)), look: look, solid: solid)
    }
}

/// An app's logo at one size, centred in a square of that size, so every logo lines up and carries the same weight.
struct AppLogo: View {
    let app: Apps.App
    let size: CGFloat
    var body: some View {
        if let url = Apps.logo(for: app), !SnapshotMode.on { Drawn(box: AppLogoBox.of(url), app: app, size: size) } else { AppInitial(app: app, size: size) }
    }
    private struct Drawn: View {
        @ObservedObject var box: AppLogoBox
        let app: Apps.App
        let size: CGFloat
        var body: some View {
            Group {
                if let logo = box.logo {
                    let s = size * (logo.solid || logo.look == .paper ? MV.Apps.solid : 1)
                    Group {
                        switch logo.look {
                        case .asIs: Image(nsImage: logo.image).resizable().interpolation(.high).scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: logo.solid ? s * MV.Apps.corner : 0, style: .continuous))
                        case .mark: Image(nsImage: logo.image).renderingMode(.template).resizable().interpolation(.high).scaledToFit().foregroundStyle(MV.Ink.t1)
                        case .paper: Image(nsImage: logo.image).resizable().interpolation(.high).scaledToFit().padding(size * MV.Apps.paperPad)
                            .background(RoundedRectangle(cornerRadius: size * MV.Apps.corner, style: .continuous).fill(MV.Apps.paper))
                        }
                    }
                    .frame(width: s, height: s)
                } else { AppInitial(app: app, size: size) }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}
/// Until a logo is here (or if it never comes): its first letter, the same size, so nothing shifts.
private struct AppInitial: View {
    let app: Apps.App; let size: CGFloat
    var body: some View {
        Text(app.label.prefix(1).uppercased()).font(F.font(size / 2, .medium)).foregroundStyle(MV.Ink.t3).frame(width: size, height: size).accessibilityHidden(true)
    }
}
/// The logo on its tile (page tone inside a card, box on the page).
struct AppTile: View {
    let app: Apps.App
    var size = MV.Apps.tile, logo = MV.Apps.logo, radius = MV.Radius.tile, fill = MV.Tone.page
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill).frame(width: size, height: size).overlay(AppLogo(app: app, size: logo))
    }
}

// MARK: In the chat

/// The apps on your next message, at the top of the box: logo and name in blue. Pointing turns the logo into ✕.
struct AppPicks: View {
    @ObservedObject var model: ComposerModel
    @ObservedObject private var apps = Apps.shared
    var body: some View {
        HStack(spacing: MV.Space.headerLead) {
            ForEach(model.picks, id: \.self) { slug in
                let app = apps.app(slug)
                Hover { h in
                    Button { model.togglePick(slug) } label: {
                        HStack(spacing: MV.Space.sm) {
                            ZStack {
                                if h { Icon("mvClose", MV.Apps.pickLogo - MV.Space.xs).foregroundStyle(MV.Ink.t2) } else { AppLogo(app: app, size: MV.Apps.pickLogo) }
                            }
                            .frame(width: MV.Apps.pickLogo, height: MV.Apps.pickLogo)
                            Text(app.label).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Accent.blue).lineLimit(1)
                        }
                        .frame(height: MV.Size.chip).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .tip("Remove \(app.label)", edge: .top).accessibilityLabel("\(app.label), remove")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MV.Space.inset).padding(.top, MV.Space.sm)
        .onReceive(NotificationCenter.default.publisher(for: .appGone)) { n in
            if let slug = n.userInfo?["slug"] as? String, model.picks.contains(slug) { model.picks.removeAll { $0 == slug }; model.save() }
        }
    }
}
/// The apps a message went with, above its bubble.
struct MVSentApps: View {
    let slugs: [String]
    @ObservedObject private var apps = Apps.shared
    var body: some View {
        HStack(spacing: MV.Space.sm) {
            ForEach(slugs, id: \.self) { slug in
                HStack(spacing: MV.Space.sm) {
                    AppLogo(app: apps.app(slug), size: MV.Apps.pickLogo)
                    Text(apps.app(slug).label).font(F.font(MV.Text.control, .medium)).foregroundStyle(MV.Ink.t2).lineLimit(1)
                }
                .padding(.horizontal, MV.Space.gridGap).frame(height: MV.Size.pill)
                .background(Capsule().fill(MV.Tone.box))
                .accessibilityElement().accessibilityLabel("With \(apps.app(slug).label)")
            }
        }
    }
}
/// Apps, opened inside the + menu: whether this agent may use them, yours to put on the next message, and the page.
struct AppsMenu: View {
    @EnvironmentObject var s: Store
    @ObservedObject var model: ComposerModel
    @ObservedObject private var apps = Apps.shared
    var body: some View {
        VStack(alignment: .leading, spacing: MV.Space.rowGap) {
            Button { model.appsRow = nil } label: {
                HStack(spacing: MV.Space.sm) {
                    Icon("mvBack", MV.Size.iconSmall); Text("Apps").font(F.font(MV.Menu.headerText, .medium)); Spacer(minLength: 0)
                }
                .foregroundStyle(MV.Ink.t3).padding(.horizontal, MV.Space.gridGap).frame(height: MV.Size.pill).contentShape(Rectangle())
            }.buttonStyle(.plain).tip("Back", "\u{2190}", edge: .leading)
            if let agent = model.speaker {
                row(0, action: { model.toggleApps() }) {
                    Text("\(agent.name) can use my apps").lineLimit(1)
                    Spacer(minLength: MV.Space.labelGap)
                    Switch(on: agent.apps != false)
                }
                .accessibilityAddTraits(agent.apps != false ? .isSelected : [])
                Rectangle().fill(MV.Menu.divider).frame(height: MV.Stroke.list).padding(.vertical, MV.Space.xs)
            }
            ScrollView(.vertical) {
                VStack(spacing: MV.Space.rowGap) {
                    ForEach(Array(apps.connected.enumerated()), id: \.element) { i, slug in
                        row(i + 1, action: { model.togglePick(slug); model.closeMenu() }) {
                            AppLogo(app: apps.app(slug), size: MV.Apps.rowLogo)
                            Text(apps.app(slug).label).lineLimit(1)
                            Spacer(minLength: 0)
                            if model.picks.contains(slug) { Icon("mvDone", MV.Size.iconSmall).foregroundStyle(MV.Accent.blue) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: CGFloat(MV.Apps.menuLogos) * MV.Menu.item).fixedSize(horizontal: false, vertical: true)
            .opacity(model.speaker?.apps == false ? MV.Browser.disabled : 1).allowsHitTesting(model.speaker?.apps != false)
            row(apps.connected.count + 1, action: { model.closeMenu(); s.go(.apps) }) {
                Icon("mvPlus", MV.Apps.rowLogo).foregroundStyle(MV.Ink.t2)
                Text(apps.connected.isEmpty ? "Connect your first app" : "Browse apps").lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
    private func row<V: View>(_ i: Int, action: @escaping () -> Void, @ViewBuilder _ content: () -> V) -> some View {
        Button(action: action) {
            HStack(spacing: MV.Space.inset) { content() }
                .font(F.font(MV.Menu.itemText, .medium)).foregroundStyle(MV.Ink.t1)
                .padding(.horizontal, MV.Space.gridGap).frame(height: MV.Menu.item)
                .background(RoundedRectangle(cornerRadius: MV.Space.gridGap, style: .continuous).fill(model.appsRow == i ? MV.Menu.itemHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { if case .active = $0 { model.appsRow = i } }
    }
}

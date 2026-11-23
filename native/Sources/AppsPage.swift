// Apps: the marketplace of services your agents can work in. Connecting is one click (Apps.swift); the logos are the
// page's only colour. Layout: a fixed head (title, search, categories) over one scrolling column (the wall of logos, yours,
// collections, then shelves by category).
import SwiftUI

/// The page's categories, and which of the catalogue's own words belong to each (the first that fits wins).
enum AppGroup: String, CaseIterable, Identifiable {
    case communication = "Communication", productivity = "Productivity", creator = "Video & social", design = "Design", developer = "Developer"
    case sales = "Sales", marketing = "Marketing", money = "Money", ai = "AI", data = "Data"
    var id: String { rawValue }
    private var words: [String] {
        switch self {
        case .communication: ["email", "team chat", "phone & sms", "communication", "notifications", "team collaboration", "video conferencing", "call tracking"]
        case .productivity: ["productivity", "task management", "project management", "calendar", "scheduling & booking", "documents", "spreadsheets", "file management & storage",
                             "time tracking software", "forms & surveys", "signatures", "bookmark managers", "content & files", "notes", "human resources", "hr talent & recruitment"]
        case .creator: ["video & audio", "social media accounts", "social media marketing", "audio & speech", "transcription", "media generation", "lifestyle & entertainment", "news & lifestyle"]
        case .design: ["images & design", "website builders", "website & app building"]
        case .developer: ["developer tools", "databases", "server monitoring", "it operations", "app builder", "security & identity tools", "product management", "internet of things"]
        case .sales: ["crm", "sales & crm", "contact management", "customer support", "people & contact data", "company data", "ai sales tools", "proposal & invoice management"]
        case .marketing: ["marketing automation", "marketing", "email newsletters", "ads & conversion", "seo & ai visibility", "transactional email"]
        case .money: ["accounting", "payment processing", "ecommerce", "commerce", "taxes", "fundraising"]
        case .ai: ["artificial intelligence", "ai agents", "ai models", "ai chatbots", "ai content generation", "ai meeting assistants", "ai document extraction", "model context protocol"]
        case .data: ["analytics", "business intelligence", "ai web scraping", "web scraping & browser", "web search & research", "dashboards", "places & weather"]
        }
    }
    static func of(_ app: Apps.App) -> AppGroup? {
        for c in app.categories { if let g = allCases.first(where: { $0.words.contains(c) }) { return g } }
        return nil
    }
}

/// A few apps that belong to one job, with what you'd ask for.
struct AppSet: Identifiable {
    let title: String, ask: String, slugs: [String]
    var id: String { title }
    static let all: [AppSet] = [
        .init(title: "Run your inbox", ask: "Who\u{2019}s waiting on a reply from me? Draft the answers.", slugs: ["gmail", "googlecalendar", "outlook", "slack", "calendly"]),
        .init(title: "Grow your channel", ask: "What did people ask for in the comments this week?", slugs: ["youtube", "linkedin", "reddit", "instagram", "discord", "twitch", "facebook", "heygen", "elevenlabs"]),
        .init(title: "Ship with your team", ask: "Turn these bug reports into issues and assign them.", slugs: ["github", "linear", "figma", "notion", "jira", "supabase", "sentry", "vercel"]),
    ]
}

/// What you could ask an agent once an app is connected.
enum AppAsks {
    static func of(_ app: Apps.App) -> [String] {
        switch app.slug {
        case "gmail", "outlook": ["Who\u{2019}s waiting on a reply from me?", "Draft a reply to my last unread email", "Summarise this week\u{2019}s newsletters"]
        case "googlecalendar": ["What does my week look like?", "Find an hour for deep work tomorrow", "Move my Friday meetings to Monday"]
        case "youtube": ["How did my last three videos do?", "What are people asking for in the comments?", "Draft a title and description for my next video"]
        case "slack", "discord": ["Catch me up on what I missed today", "What\u{2019}s still waiting on me?", "Draft an update for the team"]
        case "notion": ["Find my notes about the launch", "Turn this into a clean page", "What\u{2019}s overdue in my tasks?"]
        case "github": ["What needs my review?", "Turn this into an issue", "Write the release notes since the last tag"]
        case "linear", "jira", "asana", "trello": ["What\u{2019}s on me this week?", "Turn these notes into tasks", "What\u{2019}s blocked, and by whom?"]
        case "googledrive", "dropbox": ["Find the latest version of my contract", "What changed in my files this week?"]
        case "googledocs": ["Write up these notes as a document", "Tighten the document I edited last"]
        case "googlesheets", "airtable": ["Add these rows to my sheet", "What stands out in this month\u{2019}s numbers?"]
        case "stripe": ["How much came in this month?", "Which payments failed?"]
        case "shopify": ["Which orders still need shipping?", "What sold best this week?"]
        case "linkedin": ["Draft a post about what I shipped", "Rewrite my headline"]
        case "figma": ["What did people comment on my file?", "List the components in this file"]
        case "reddit": ["What are people saying about my product?", "Find threads worth answering"]
        default: ["What can you do with my \(app.label)?"]
        }
    }
}

struct AppsPage: View {
    @EnvironmentObject var s: Store
    @ObservedObject private var apps = Apps.shared
    enum Filter: Hashable { case all, connected, group(AppGroup), set(String) }
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var opened: String?
    @State private var keyOpen = false
    @FocusState private var searching: Bool

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    /// Yours first, then the most used; a search matches the name first, then what it's about.
    private var found: [Apps.App] {
        let list: [Apps.App]
        switch filter {
        case .all: list = apps.offered
        case .connected: list = apps.connected.map(apps.app)
        case .group(let g): list = apps.offered.filter { AppGroup.of($0) == g }
        case .set(let id):
            let slugs = AppSet.all.first { $0.id == id }?.slugs ?? []
            list = slugs.filter { slug in apps.catalog.isEmpty || apps.catalog.contains { $0.slug == slug } }.map(apps.app)
        }
        guard !q.isEmpty else { return list }
        let all = apps.offered + apps.connected.filter { slug in !apps.offered.contains { $0.slug == slug } }.map(apps.app)
        func rank(_ a: Apps.App) -> Int? {
            let name = a.label.lowercased()
            if name.hasPrefix(q) || a.slug.hasPrefix(q) { return 0 }
            if name.contains(q) || a.slug.contains(q) { return 1 }
            return q.count > 2 && a.categories.contains { $0.contains(q) } ? 2 : nil
        }
        return all.enumerated().compactMap { i, a in rank(a).map { ($0, i, a) } }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            scroll
        }
        .overlay { if let slug = opened { AppDetail(app: apps.app(slug)) { opened = nil }.id(slug) } }
        .overlay { if keyOpen { AppsKeyDialog { keyOpen = false } } }
        .task { apps.error = nil; await apps.refresh() }
    }

    // MARK: Head: title, search, categories

    private var head: some View {
        VStack(alignment: .leading, spacing: MV.Space.headerLead) {
            HStack(spacing: MV.Space.inset) {
                Text("Apps").font(F.font(MV.Text.listTitle, .medium)).foregroundStyle(MV.Ink.t1)
                Spacer(minLength: MV.Space.inset)
                search
                MVIconButton(icon: "mvKey", label: apps.own ? "Using your Composio key" : "Use your own Composio key", on: apps.own) { keyOpen = true }
            }
            ScrollView(.horizontal) {
                HStack(spacing: MV.Space.sm) {
                    chip("All", .all)
                    if !apps.connected.isEmpty { chip("Connected", .connected, count: apps.connected.count) }
                    ForEach(AppGroup.allCases) { g in chip(g.rawValue, .group(g)) }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: MV.Apps.column)
        .padding(.horizontal, MV.Apps.sides).padding(.top, MV.Apps.head).padding(.bottom, MV.Space.headerLead)
        .frame(maxWidth: .infinity)
    }
    private var search: some View {
        HStack(spacing: MV.Space.labelGap) {
            Icon("mvSearch", MV.Size.iconSmall).foregroundStyle(MV.Ink.t3)
            ZStack(alignment: .leading) {
                if query.isEmpty { Text(apps.catalog.isEmpty ? "Search apps" : "Search \(apps.catalog.count) apps").foregroundStyle(MV.Ink.t3).lineLimit(1).allowsHitTesting(false) }
                if !SnapshotMode.on {
                    TextField("", text: $query).textFieldStyle(.plain).foregroundStyle(MV.Ink.t1).focused($searching)
                        .onExitCommand { if query.isEmpty { searching = false } else { query = "" } }
                        .accessibilityLabel("Search apps")
                }
            }
            .font(F.font(MV.Text.title, .regular))
            if !query.isEmpty {
                Button { query = "" } label: { Icon("mvClose", MV.Space.inset).foregroundStyle(MV.Ink.t3).frame(width: MV.Size.iconSmall, height: MV.Size.iconSmall).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, MV.Space.inset)
        .frame(width: MV.Apps.search.width, height: MV.Apps.search.height)
        .background(Capsule().fill(MV.Tone.box))
        .overlay(Capsule().strokeBorder(searching ? MV.Stroke.boxTyping : MV.Stroke.boxRest, lineWidth: searching ? MV.Stroke.boxTypingWidth : MV.Stroke.boxRestWidth))
        .contentShape(Capsule()).onTapGesture { searching = true }
    }
    private func chip(_ title: String, _ f: Filter, count: Int? = nil) -> some View {
        let on = filter == f && q.isEmpty
        return Button { query = ""; filter = f } label: {
            HStack(spacing: MV.Space.sm) {
                Text(title).foregroundStyle(on ? MV.Ink.onWhite : MV.Ink.t2)
                if let count { Text("\(count)").monospacedDigit().foregroundStyle(on ? MV.Ink.onWhite : MV.Ink.t3) }
            }
            .font(F.font(MV.Text.control, .medium)).lineLimit(1).fixedSize()
            .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.pill)
            .background(Capsule().fill(on ? Color.white : MV.Tone.box)).contentShape(Capsule())
        }
        .buttonStyle(MVStates(shape: Capsule())).accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: The column

    private var scroll: some View {
        let column = VStack(alignment: .leading, spacing: MV.Apps.sides) {
            if let e = apps.error { problem(e) }
            if q.isEmpty && filter == .all { storefront } else { results }
        }
        .frame(maxWidth: MV.Apps.column, alignment: .leading)
        .padding(.horizontal, MV.Apps.sides).padding(.bottom, MV.Apps.foot)
        .frame(maxWidth: .infinity)
        return Group {
            if SnapshotMode.on { GeometryReader { g in column.frame(width: g.size.width).fixedSize(horizontal: false, vertical: true).frame(height: g.size.height, alignment: .top).clipped() } }
            else { ScrollView(.vertical) { column }.scrollIndicators(.never).id(filter) }
        }
    }
    @ViewBuilder private var storefront: some View {
        AppsHero(count: apps.catalog.count) { opened = $0 }
        if !apps.connected.isEmpty {
            shelf("Your apps", apps.connected.prefix(6).map(apps.app), total: apps.connected.count, filter: .connected)
        }
        VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            SectionTitle(text: "Put them to work")
            HStack(alignment: .top, spacing: MV.Space.gridGap) {
                ForEach(AppSet.all) { set in AppSetCard(set: set) { filter = .set(set.id) } }
            }
        }
        let popular = Apps.starter.prefix(12).map { apps.app($0.slug) }.filter { !apps.connected.contains($0.slug) }
        shelf("Popular", Array(popular.prefix(9)), total: 0, filter: .all)
        // Each category's first six that aren't already above.
        let shown = Set(popular.prefix(9).map(\.slug) + apps.connected)
        if !apps.catalog.isEmpty {
            LazyVStack(alignment: .leading, spacing: MV.Apps.sides) {
                ForEach(AppGroup.allCases) { g in
                    let all = apps.catalog.filter { AppGroup.of($0) == g }
                    shelf(g.rawValue, Array(all.filter { !shown.contains($0.slug) }.prefix(6)), total: all.count, filter: .group(g))
                }
            }
        }
    }
    private func shelf(_ title: String, _ list: [Apps.App], total: Int, filter f: Filter) -> some View {
        VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            HStack(spacing: 0) {
                SectionTitle(text: title)
                Spacer(minLength: 0)
                if total > list.count {
                    Hover { h in
                        Button { filter = f } label: { Text("See all \(total)").font(F.font(MV.Text.body, .regular)).foregroundStyle(h ? MV.Ink.t1 : MV.Ink.t3) }.buttonStyle(.plain)
                    }
                }
            }
            grid(list)
        }
    }
    private func grid(_ list: [Apps.App]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: MV.Apps.cardMin), spacing: MV.Space.gridGap, alignment: .top)], spacing: MV.Space.gridGap) {
            ForEach(list) { app in AppCard(app: app) { opened = app.slug } }
        }
    }
    @ViewBuilder private var results: some View {
        let list = found
        if list.isEmpty {
            VStack(spacing: MV.Space.xs) {
                Text(filter == .connected && q.isEmpty ? "Nothing connected yet" : "No app called \u{201C}\(query)\u{201D}").font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1)
                Text(filter == .connected && q.isEmpty ? "Connect one and your agents can work in it." : "An agent can still use its website in the Browser pane.")
                    .font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3)
            }
            .frame(maxWidth: .infinity).padding(.vertical, MV.Apps.foot)
        } else {
            VStack(alignment: .leading, spacing: MV.Space.labelGap) {
                SectionTitle(text: resultTitle(list.count))
                grid(list)
            }
        }
    }
    private func resultTitle(_ n: Int) -> String {
        if !q.isEmpty { return "\(n) \(n == 1 ? "app" : "apps")" }
        switch filter { case .set(let t): return t; case .connected: return "Your apps"; case .group(let g): return "\(g.rawValue) \u{00B7} \(n)"; case .all: return "All" }
    }
    private func problem(_ text: String) -> some View {
        HStack(spacing: MV.Space.inset) {
            Text(text).font(F.font(MV.Text.title, .regular)).foregroundStyle(MV.Ink.t1).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            MVPill(title: apps.loading ? "Trying\u{2026}" : "Try again", primary: false, filled: true) { Task { await apps.refresh() } }
        }
        .padding(MV.Space.inset)
        .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(MV.Tone.box))
    }
}

// MARK: The wall

/// What it is in two lines, and the apps themselves: a wall of their logos running off the card's right edge.
private struct AppsHero: View {
    @ObservedObject private var apps = Apps.shared
    let count: Int
    let open: (String) -> Void
    private static let wall = ["gmail", "youtube", "notion", "googlecalendar", "figma", "googledrive", "stripe", "slack", "github", "linkedin", "googledocs", "linear", "discord", "shopify",
                               "googlesheets", "dropbox", "reddit", "airtable", "canva", "zoom", "trello", "outlook", "asana", "jira", "hubspot", "whatsapp", "googlemeet", "googleslides"]
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MV.Radius.homeBox, style: .continuous)
        let first = Apps.starter.first { !apps.connected.contains($0.slug) } ?? Apps.starter[0]
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your agents, inside").foregroundStyle(MV.Ink.t1)
                    Text("the apps you already use.").foregroundStyle(MV.Ink.t2)
                }
                .font(F.font(MV.Text.greeting, .medium)).tracking(MV.Text.greetingTracking).lineLimit(1).minimumScaleFactor(MV.Chat.dropDim)
                Text("\(count > 0 ? "\(count) apps. " : "")Click one, sign in on its own page, and every agent can work in it. Nothing to paste, nothing to set up.")
                    .font(F.font(MV.Text.preview, .regular)).foregroundStyle(MV.Ink.t3).lineSpacing(MV.Text.previewLine - MV.Text.preview)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, MV.Space.labelGap)
                MVCardPill(label: "Connect \(first.label)", primary: true) { open(first.slug) }.padding(.top, MV.Space.section)
            }
            .frame(width: MV.Apps.heroText, alignment: .leading)
            .padding(.leading, MV.Apps.heroPad)
            Spacer(minLength: 0)
        }
        .frame(height: MV.Apps.hero)
        .background(alignment: .leading) {
            wall.padding(.leading, MV.Apps.heroPad + MV.Apps.heroText + MV.Space.section).frame(height: MV.Apps.hero)
        }
        .background(shape.fill(MV.Tone.box))
        .clipShape(shape)
    }
    /// Columns of tiles, every other one half a step lower, cut by the card's top, bottom and right edges.
    private var wall: some View {
        HStack(alignment: .center, spacing: MV.Apps.wallGap) {
            ForEach(0..<MV.Apps.wallColumns, id: \.self) { c in
                VStack(spacing: MV.Apps.wallGap) {
                    ForEach(0..<MV.Apps.wallRows, id: \.self) { r in
                        // The best known ones sit in the middle rows, which are never cut.
                        let i = [2, 0, 1, 3][r] * MV.Apps.wallColumns + c
                        let app = apps.app(Self.wall[i])
                        Button { open(app.slug) } label: {
                            AppTile(app: app, size: MV.Apps.wallTile, logo: MV.Apps.wallLogo, radius: MV.Apps.wallRadius)
                                .contentShape(RoundedRectangle(cornerRadius: MV.Apps.wallRadius, style: .continuous))
                        }
                        .buttonStyle(MVStates(shape: RoundedRectangle(cornerRadius: MV.Apps.wallRadius, style: .continuous)))
                        .accessibilityLabel(app.label)
                    }
                }
                .offset(y: MV.Apps.drop(c))
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A collection: its apps, its name, and what you'd ask.
private struct AppSetCard: View {
    @ObservedObject private var apps = Apps.shared
    let set: AppSet
    let open: () -> Void
    var body: some View {
        Hover { h in
            Button(action: open) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: MV.Space.sm) {
                        ForEach(set.slugs.prefix(5), id: \.self) { AppTile(app: apps.app($0), size: MV.Apps.set, logo: MV.Apps.setLogo) }
                    }
                    Text(set.title).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).padding(.top, MV.Space.headerLead)
                    Text("\u{201C}\(set.ask)\u{201D}").font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3)
                        .lineSpacing(MV.Text.bodyLine - MV.Text.body).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).padding(.top, MV.Space.xs)
                }
                .padding(MV.Space.headerLead)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(h ? MV.Tone.box2 : MV.Tone.box))
                .clipShape(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// One app: its logo, name and what it's for; its state on the right (Connect, finish signing in, connected).
private struct AppCard: View {
    @ObservedObject private var apps = Apps.shared
    let app: Apps.App
    let open: () -> Void
    var body: some View {
        Hover { h in
            Button(action: open) {
                VStack(alignment: .leading, spacing: MV.Space.gridGap) {
                    HStack(spacing: MV.Space.inset) {
                        AppTile(app: app)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(app.label).font(F.font(MV.Text.title, .medium)).foregroundStyle(MV.Ink.t1).lineLimit(1)
                            Text(app.tools > 0 ? "\(app.tools) actions" : AppGroup.of(app)?.rawValue ?? "App").font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3).lineLimit(1)
                        }
                        Spacer(minLength: MV.Space.labelGap)
                        AppState(app: app)
                    }
                    Text(apps.line(app)).font(F.font(MV.Text.body, .regular)).foregroundStyle(MV.Ink.t3).lineSpacing(MV.Text.bodyLine - MV.Text.body)
                        .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: MV.Text.bodyLine * 2 + MV.Space.xs, alignment: .topLeading)
                }
                .padding(MV.Space.inset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: MV.Radius.card, style: .continuous).fill(h ? MV.Tone.box2 : MV.Tone.box))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .contextMenu {
            if apps.connected.contains(app.slug) {
                Button("Use in a chat") { apps.use(app.slug) }
                Button("Disconnect \(app.label)") { Task { await apps.disconnect(app.slug) } }
            } else {
                Button("Connect \(app.label)") { Task { await apps.connect(app.slug) } }
                if apps.pending.contains(app.slug) { Button("Cancel sign-in") { Task { await apps.disconnect(app.slug) } } }
            }
        }
        .accessibilityLabel(app.label + (apps.connected.contains(app.slug) ? ", connected" : ""))
    }
}
/// A card's trailing state, and its button.
private struct AppState: View {
    @ObservedObject private var apps = Apps.shared
    let app: Apps.App
    var body: some View {
        if apps.working == app.slug { ProgressView().controlSize(.small).frame(height: MV.Size.pill) }
        else if apps.connected.contains(app.slug) { MVChip(text: "Connected", done: true) }
        else {
            MVPill(title: apps.pending.contains(app.slug) ? "Finish" : "Connect", primary: false, filled: true) { Task { await apps.connect(app.slug) } }
                .fixedSize()
        }
    }
}

// MARK: One app, opened

struct AppDetail: View {
    @EnvironmentObject var s: Store
    @ObservedObject private var apps = Apps.shared
    let app: Apps.App
    let close: () -> Void
    @State private var adding = false
    @State private var alias = ""
    @State private var leaving = false
    @FocusState private var naming: Bool
    private var on: Bool { apps.connected.contains(app.slug) }
    private var waiting: Bool { apps.pending.contains(app.slug) }
    private var busy: Bool { apps.working == app.slug }
    private var accounts: [Apps.Account] { (apps.services[app.slug]?.accounts ?? []).filter { $0.status.uppercased() == "ACTIVE" } }
    var body: some View {
        let card = RoundedRectangle(cornerRadius: MV.Radius.homeBox, style: .continuous)
        ZStack {
            Color.black.opacity(MV.Launcher.dim).contentShape(Rectangle()).onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: MV.Space.section) {
                HStack(alignment: .top, spacing: MV.Space.headerLead) {
                    AppTile(app: app, size: MV.Apps.detailTile, logo: MV.Apps.detailLogo, radius: MV.Apps.detailRadius)
                    VStack(alignment: .leading, spacing: MV.Space.xs) {
                        Text(app.label).font(F.font(MV.Text.listTitle, .medium)).foregroundStyle(MV.Ink.t1)
                        Text(facts).font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Ink.t3)
                    }
                    .frame(minHeight: MV.Apps.detailTile)
                    Spacer(minLength: 0)
                    Button(action: close) { Icon("mvClose", MV.Size.iconSmall).foregroundStyle(MV.Ink.t2).frame(width: MV.Size.iconButton, height: MV.Size.iconButton).contentShape(Circle()) }
                        .buttonStyle(MVStates(shape: Circle())).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
                }
                Text(app.description.isEmpty ? apps.line(app) : app.description).font(F.font(MV.Text.preview, .regular)).foregroundStyle(MV.Ink.t2)
                    .lineSpacing(MV.Text.previewLine - MV.Text.preview).fixedSize(horizontal: false, vertical: true)
                asks
                if on && !accounts.isEmpty { accountList }
                VStack(alignment: .leading, spacing: MV.Space.inset) {
                    if let e = apps.error { Text(e).font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Accent.red).fixedSize(horizontal: false, vertical: true) }
                    else if !on {
                        Text(waiting ? "Finish signing in on \(app.label)\u{2019}s page in your browser. This updates by itself."
                                     : "You sign in on \(app.label)\u{2019}s own page. What an agent may do there without asking follows its mode.")
                            .font(F.font(MV.Text.meta, .regular)).foregroundStyle(MV.Ink.t3).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: MV.Space.labelGap) {
                        if let site = app.site.flatMap(URL.init(string:)) {
                            MVIconButton(icon: "mvOut", label: "Open \(app.label)\u{2019}s site") { NSWorkspace.shared.open(site) }
                        }
                        Spacer(minLength: 0)
                        if busy { ProgressView().controlSize(.small) }
                        if on {
                            MVCardPill(label: "Disconnect") { leaving = true }
                            MVCardPill(label: "Use in a chat", primary: true) { apps.use(app.slug); close() }
                        } else {
                            if waiting { MVCardPill(label: "Cancel") { Task { await apps.disconnect(app.slug) } } }
                            MVCardPill(label: waiting ? "Open sign-in page" : "Connect", primary: true) { Task { await apps.connect(app.slug) } }
                        }
                    }
                    .allowsHitTesting(!busy)
                }
            }
            .padding(MV.Space.section)
            .frame(width: MV.Apps.detail)
            .background(card.fill(MV.Tone.box))
            .overlay(card.strokeBorder(MV.Stroke.boxRest, lineWidth: MV.Stroke.boxRestWidth).allowsHitTesting(false))
        }
        .onAppear { apps.error = nil }
        .confirmationDialog("Disconnect \(app.label)?", isPresented: $leaving) {
            Button("Disconnect", role: .destructive) { Task { await apps.disconnect(app.slug) } }
        } message: { Text("Your agents lose access to it. You can connect it again any time.") }
    }
    private var facts: String {
        [AppGroup.of(app)?.rawValue, app.tools > 0 ? "\(app.tools) actions" : nil, on ? "Connected" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
    private var asks: some View {
        VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            SectionTitle(text: on ? "Try asking" : "Once it\u{2019}s connected, ask")
            VStack(spacing: 0) {
                let list = AppAsks.of(app)
                ForEach(Array(list.enumerated()), id: \.offset) { i, ask in
                    if i > 0 { Rectangle().fill(MV.Workspace.divider).frame(height: MV.Stroke.list) }
                    Hover { h in
                        Button { apps.use(app.slug, words: ask); close() } label: {
                            HStack(spacing: MV.Space.labelGap) {
                                Text(ask).font(F.font(MV.Text.title, .regular)).foregroundStyle(MV.Ink.t1).lineLimit(1)
                                Spacer(minLength: 0)
                                if on { Icon("mvFwd", MV.Size.iconSmall).foregroundStyle(h ? MV.Ink.t1 : MV.Ink.t3) }
                            }
                            .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.chatButton)
                            .background(on && h ? MV.Wash.hover : .clear).contentShape(Rectangle())
                        }.buttonStyle(.plain).allowsHitTesting(on)
                    }
                }
            }
            .background(MV.Tone.page)
            .clipShape(RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous))
        }
    }
    private var accountList: some View {
        let field = RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
        return VStack(alignment: .leading, spacing: MV.Space.labelGap) {
            SectionTitle(text: accounts.count == 1 ? "Your account" : "Your accounts")
            ForEach(Array(accounts.enumerated()), id: \.element.id) { i, a in
                HStack(spacing: MV.Space.inset) {
                    AppLogo(app: app, size: MV.Apps.rowLogo)
                    Text(a.alias ?? (accounts.count == 1 ? "Signed in" : "Account \(i + 1)")).font(F.font(MV.Text.title, .regular)).foregroundStyle(MV.Ink.t1)
                    Spacer(minLength: 0)
                    if accounts.count > 1 { MVPill(title: "Remove", primary: false) { Task { await apps.remove(app.slug, account: a.id) } } }
                }
                .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.chatButton).background(field.fill(MV.Tone.page))
            }
            if adding {
                HStack(spacing: MV.Space.labelGap) {
                    TextField("", text: $alias, prompt: Text("Name it, like Work").foregroundStyle(MV.Ink.t3)).textFieldStyle(.plain)
                        .font(F.font(MV.Text.title, .regular)).foregroundStyle(MV.Ink.t1).focused($naming).onSubmit(add)
                    MVPill(title: "Sign in", primary: true, action: add)
                }
                .padding(.leading, MV.Space.inset).padding(.trailing, MV.Space.sm).frame(height: MV.Size.chatButton).background(field.fill(MV.Tone.page))
                .onAppear { naming = true }
            } else if accounts.count < 5, !apps.consumer {
                Hover { h in
                    Button { adding = true } label: { Text("Add another account").font(F.font(MV.Text.body, .regular)).foregroundStyle(h ? MV.Ink.t1 : MV.Ink.t3) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func add() {
        let name = alias.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { if await apps.connect(app.slug, alias: name) { adding = false; alias = "" } }
    }
}

// MARK: Your own key

/// Optional: connect through a Composio account of your own instead of the built-in one.
struct AppsKeyDialog: View {
    @ObservedObject private var apps = Apps.shared
    let close: () -> Void
    @State private var key = ""
    @State private var problem: String?
    @State private var saving = false
    @FocusState private var typing: Bool
    var body: some View {
        let card = RoundedRectangle(cornerRadius: MV.Radius.homeBox, style: .continuous)
        let field = RoundedRectangle(cornerRadius: MV.Radius.tile, style: .continuous)
        ZStack {
            Color.black.opacity(MV.Launcher.dim).contentShape(Rectangle()).onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: MV.Space.headerLead) {
                VStack(alignment: .leading, spacing: MV.Space.xs) {
                    Text("Your own Composio key").font(F.font(MV.Text.panelTitle, .medium)).foregroundStyle(MV.Ink.t1)
                    Text(apps.own ? "Your apps connect through your own Composio account. Removing the key goes back to the built-in connection."
                                  : "You don\u{2019}t need one: connecting already works. With your own key, apps connect through your Composio account, and it\u{2019}s kept on this Mac only.")
                        .font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Ink.t3).fixedSize(horizontal: false, vertical: true)
                }
                SecureField("", text: $key, prompt: Text(apps.own ? "Paste a different key" : "ak_\u{2026} or ck_\u{2026}").foregroundStyle(MV.Ink.t3)).textFieldStyle(.plain)
                    .font(F.font(MV.Text.chatInput, .regular)).foregroundStyle(MV.Ink.t1).focused($typing).onSubmit { save(key) }
                    .padding(.horizontal, MV.Space.inset).frame(height: MV.Size.chatBox - MV.Space.labelGap)
                    .background(field.fill(MV.Tone.page))
                    .overlay(field.strokeBorder(typing ? MV.Chat.talking : MV.Stroke.boxRest, lineWidth: typing ? MV.Stroke.boxTypingWidth : MV.Stroke.boxRestWidth))
                if let problem { Text(problem).font(F.font(MV.Text.footer, .regular)).foregroundStyle(MV.Accent.red).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: MV.Space.labelGap) {
                    if apps.own { MVCardPill(label: "Remove key") { save("") } }
                    Spacer(minLength: 0)
                    if saving { ProgressView().controlSize(.small) }
                    Button(action: close) { EmptyView() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).frame(width: 0, height: 0).accessibilityHidden(true)
                    MVCardPill(label: "Cancel", action: close)
                    MVCardPill(label: "Save", primary: true) { save(key) }.opacity(key.isEmpty ? MV.Browser.disabled : 1).allowsHitTesting(!key.isEmpty && !saving)
                }
            }
            .padding(MV.Space.section)
            .frame(width: MV.Apps.detail)
            .background(card.fill(MV.Tone.box))
            .overlay(card.strokeBorder(MV.Stroke.boxRest, lineWidth: MV.Stroke.boxRestWidth).allowsHitTesting(false))
        }
        .onAppear { typing = true }
    }
    private func save(_ value: String) {
        guard !saving else { return }
        saving = true; problem = nil
        Task { problem = await apps.setKey(value); saving = false; if problem == nil { key = ""; close() } }
    }
}

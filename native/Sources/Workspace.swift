// Workspaces: a place for a team of agents, like a Discord server (web: drawCreateWs, wsSection, projectView, channelView).
import SwiftUI
import AppKit
import UniformTypeIdentifiers

let PROJ_COLORS: [UInt32] = [0x4073d4, 0x17866b, 0x8b5ade, 0xcf4079, 0xcc4d29, 0xac6612, 0x5f7a4d, 0x4a4e57]

/// The workspace's picture: the uploaded image, or its colour with two initials (web: wsPic / wsInitials).
struct WsPic: View {
    let name: String; let color: String?; var image: String? = nil; var size: CGFloat = 48; var radius: CGFloat = R.ctl
    var initials: String {
        let s = String(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(2).map(Character.init))
        return s.isEmpty ? "··" : s.prefix(1).uppercased() + s.dropFirst()
    }
    var body: some View {
        Group {
            if let img = WsPic.decode(image) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Color(Look.hex(color ?? "") ?? 0x5D6B8C)
                    .overlay(Text(initials).font(F.font(size >= 64 ? 24 : size >= 48 ? 16 : 12, .semibold)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
    nonisolated(unsafe) static var cache: [Int: NSImage] = [:]
    static func decode(_ s: String?) -> NSImage? {
        guard let s, let comma = s.firstIndex(of: ","), s.hasPrefix("data:image/") else { return nil }
        if let hit = cache[s.hashValue] { return hit }
        guard let data = Data(base64Encoded: String(s[s.index(after: comma)...])), let img = NSImage(data: data) else { return nil }
        cache[s.hashValue] = img
        return img
    }
    /// A picked image as the engine wants it: square, 256 px, PNG or JPEG data URL under 400 KB.
    static func encode(_ url: URL) -> String? {
        guard let src = NSImage(contentsOf: url), let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = min(cg.width, cg.height), out = 256
        guard let crop = cg.cropping(to: CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)),
              let ctx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: out, height: out))
        guard let small = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: small)
        if let png = rep.representation(using: .png, properties: [:]), png.count * 4 / 3 < 380_000 { return "data:image/png;base64," + png.base64EncodedString() }
        if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]), jpg.count * 4 / 3 < 380_000 { return "data:image/jpeg;base64," + jpg.base64EncodedString() }
        return nil
    }
}

// MARK: Sidebar row (web: wsSection)

struct WsRow: View {
    @EnvironmentObject var s: Store
    let w: Workspace
    @Binding var menuOpen: Bool
    static let corner: CGFloat = R.ctl, inset: CGFloat = 6
    var body: some View {
        let pool = s.members(of: w)
        let working = pool.filter { s.state(of: $0) == "working" }.count
        let waiting = s.approvals.filter { p in pool.contains { $0.id == p.agentId } }.count
        let about = (w.about?.isEmpty == false ? w.about : w.path.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }) ?? ""
        let on = s.openWorkspace == w.id
        Hover { h in
            Button { s.openSpace(w.id) } label: {
                HStack(spacing: 12) {
                    WsPic(name: w.name, color: w.color, image: w.image)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(w.name).font(F.font(16, s.unread(w) ? .semibold : .medium)).foregroundStyle(on || h || s.unread(w) ? C.i12 : Color.white(0.82)).lineLimit(1)
                            if w.muted == true { Image(systemName: "bell.slash").font(.system(size: 11)).foregroundStyle(C.i9).accessibilityLabel("Muted") }
                            if s.unread(w) { Circle().fill(C.i12).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                            if waiting > 0 && w.muted != true { Text("\(waiting)").font(F.font(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(WAIT)) }
                        }
                        if !about.isEmpty { Text(about).font(F.font(14, .regular)).foregroundStyle(C.i10).lineLimit(1) }
                        if !pool.isEmpty {
                            HStack(spacing: 8) {
                                HStack(spacing: -8) { ForEach(pool.prefix(4)) { a in Avatar(agent: a, size: 24, status: false).background(RoundedRectangle(cornerRadius: Avatar.radius(28), style: .continuous).fill(on ? C.v4 : C.v0).padding(-2)) } }
                                Text("\(pool.count) \(pool.count == 1 ? "agent" : "agents")\(working > 0 ? " · \(working) working" : "")").font(F.font(12, .regular)).foregroundStyle(C.i10)
                            }
                            .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(on ? C.v4 : h || menuOpen ? C.v3 : .clear))
                .opacity(w.muted == true && !on ? 0.6 : 1)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            // ⋯ on hover, top right, concentric with the row (the container shape below); the menu floats from it.
            .overlay(alignment: .topTrailing) {
                ZStack {
                    if h || menuOpen { MoreButton(open: menuOpen, corner: Self.corner, inset: Self.inset) { menuOpen.toggle() } }
                }
                .frame(width: MoreButton.size, height: MoreButton.size)
                .floatingMenu($menuOpen) { WorkspaceActions(w: w, open: $menuOpen) }
                .padding(.top, Self.inset).padding(.trailing, Self.inset)
            }
            .containerShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        }
        .onRightClick { menuOpen = true }
        .accessibilityLabel(w.name)
    }
}

// MARK: Create and edit (web: drawCreateWs, drawProjectForm)

struct WorkspaceForm: View {
    @EnvironmentObject var s: Store
    var editing: Workspace? = nil
    @State private var name = ""
    @State private var about = ""
    @State private var path: String?
    @State private var color = PROJ_COLORS.randomElement()!
    @State private var image: String?
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var nameFocused: Bool
    func close() { if editing == nil { s.createWorkspaceOpen = false } else { s.editingWorkspace = nil } }
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).contentShape(Rectangle()).onTapGesture { close() }
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    // The picture: click it to upload one (web: .pic-drop)
                    Hover { h in
                        Button { pickImage() } label: {
                            WsPic(name: name.isEmpty ? "?" : name, color: Look.str(color), image: image, size: 88, radius: R.card)
                                .overlay(RoundedRectangle(cornerRadius: R.card).fill(Color.black.opacity(h ? 0.45 : 0)))
                                .overlay { if h { VStack(spacing: 4) { Icon("plus", 22); Line(image == nil ? "Upload" : "Change", 12, .semibold, .white) }.foregroundStyle(.white) } }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Upload a picture").accessibilityLabel("Upload a picture")
                    }
                    HStack(spacing: 8) {
                        SmallSecondaryButton(title: image == nil ? "Upload picture" : "Change picture") { pickImage() }
                        if image != nil { SmallSecondaryButton(title: "Remove") { image = nil } }
                    }
                    .padding(.top, 4)
                    Line(editing == nil ? "Make your workspace" : "Edit workspace", 24, .semibold, C.i12, tracking: -0.36).padding(.top, 8)
                    if editing == nil {
                        Para(text: "Give it a name and a picture. Agents you add here live in it. You can change both later.", size: 14, weight: .regular, color: C.i10, align: .center)
                            .frame(width: 360)
                    }
                }
                .padding(.top, 24).padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 12) {
                    field("Workspace name") { TextBox(text: $name, placeholder: "Workspace name", focused: $nameFocused).onSubmit { save() } }
                    field("Description", optional: true) { PlainBox(text: $about, placeholder: "What this team of agents works on").onSubmit { save() } }
                    if image == nil {
                        field("Colour") {
                            HStack(spacing: 8) {
                                ForEach(PROJ_COLORS, id: \.self) { c in
                                    Button { color = c } label: {
                                        Circle().fill(Color(c)).frame(width: 24, height: 24)
                                            .overlay(Circle().strokeBorder(C.i12, lineWidth: color == c ? 2 : 0).padding(-4))
                                            .frame(width: 32, height: 32).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityLabel(Look.str(c)).accessibilityAddTraits(color == c ? .isSelected : [])
                                }
                            }
                        }
                    }
                    field("Folder", optional: true) {
                        if editing != nil {
                            Line(path ?? "None. Agents choose their own folders.", 14, .regular, C.i10)
                        } else {
                            Hover { h in
                                Button { pickFolder() } label: {
                                    HStack(spacing: 8) {
                                        Icon("folder", 16).foregroundStyle(C.i10)
                                        Text(path ?? "None. Agents choose their own folders.").font(F.font(14, .regular)).foregroundStyle(path == nil ? C.i10 : C.i12).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                        if path != nil { Button { path = nil } label: { Icon("x", 12).foregroundStyle(C.i10).frame(width: 24, height: 24) }.buttonStyle(.plain).tip("No folder") }
                                    }
                                    .padding(.horizontal, 12).frame(height: 40)
                                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(h ? C.v3 : C.v1))
                                    .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edgeControl, lineWidth: 1)).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
                HStack(spacing: 8) {
                    if let w = editing {
                        DangerButton(title: "Remove workspace") { s.editingWorkspace = nil; s.removingWorkspace = w.id }
                    } else {
                        SecondaryButton(title: "Back") { close() }
                    }
                    if let problem { Line(problem, 12, .regular, FAIL_TEXT).padding(.leading, 4) }
                    Spacer()
                    if editing != nil { SecondaryButton(title: "Cancel") { close() } }
                    PrimaryButton(title: saving ? (editing == nil ? "Creating…" : "Saving…") : (editing == nil ? "Create" : "Save")) { save() }.disabled(saving)
                }
                .padding(.horizontal, 16).frame(height: 64).background(C.v0)
            }
            .frame(width: 464)
            .background(C.v1)
            .clipShape(RoundedRectangle(cornerRadius: R.card))
            .overlay(RoundedRectangle(cornerRadius: R.card).stroke(C.edgeControl, lineWidth: 1).padding(-0.5))
            .floatShadow()
        }
        .onAppear {
            if let w = editing { name = w.name; about = w.about ?? ""; path = w.path; image = w.image; color = Look.hex(w.color ?? "") ?? PROJ_COLORS[2] }
            else { name = "\(s.handle)’s workspace" }
            nameFocused = true
        }
        .onExitCommand { close() }
    }
    func field<Content: View>(_ label: String, optional: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) { Line(label, 12, .semibold, C.i10); if optional { Line(" optional", 12, .regular, C.i9) } }
            content()
        }
    }
    func pickImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .webP, .heic]; p.prompt = "Use this picture"
        guard p.runModal() == .OK, let u = p.url else { return }
        if let d = WsPic.encode(u) { image = d; problem = nil } else { problem = "That picture couldn't be used. Try a PNG or JPEG." }
    }
    func pickFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Use this folder"
        p.directoryURL = URL(fileURLWithPath: s.home)
        if p.runModal() == .OK, let u = p.url { path = u.path; if name.hasSuffix("’s workspace") { name = u.lastPathComponent } }
    }
    func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { problem = "Give it a name first."; nameFocused = true; return }
        saving = true; problem = nil
        Task {
            do {
                if let w = editing {
                    try await s.updateWorkspace(w.id, ["name": n, "about": about, "color": Look.str(color), "image": (image as Any?) ?? NSNull()])
                } else {
                    let w = try await s.createWorkspace(name: n, about: about, color: Look.str(color), path: path, image: image)
                    s.openSpace(w.id)
                }
                close()
            } catch { problem = error.localizedDescription }
            saving = false
        }
    }
}
/// A plain text field with the form's look (no focus ring of its own).
struct PlainBox: View {
    @Binding var text: String; let placeholder: String
    @FocusState private var on: Bool
    var body: some View { TextBox(text: $text, placeholder: placeholder, focused: $on) }
}

// MARK: The workspace (web: projectView): channels on the left, then its members; a channel or a member's DM on the right

struct WorkspacePage: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var panes: Panes
    let w: Workspace
    @State private var inviting = false
    @State private var headMenu = ProcessInfo.processInfo.environment["AL_TEST_MENU"] == "head"
    /// Naming a channel: a new one (in a category) or a rename. One sheet for both.
    @State private var naming: (category: String, channel: String?)?
    @State private var newName = ""
    /// The agents a new channel starts with (none: the assistant).
    @State private var newAgents: [String] = []
    /// Naming a category: its id, or "" for a new one.
    @State private var catNaming: String?
    @State private var catName = ""
    var body: some View {
        let members = s.members(of: w)
        let open = s.openAgent.flatMap { id in members.first { $0.id == id } }
        let channel = w.channels.first { $0.id == s.openChannel } ?? w.channels.first
        HStack(spacing: 0) {
            if MV.on {
                MavisWorkspaceSidebar(w: w, members: members, open: open, channel: channel, headMenu: $headMenu, inviting: $inviting,
                                      newChannel: { naming = ($0, nil); newName = ""; newAgents = [] },
                                      rename: { c, ch in naming = (c, ch.id); newName = ch.name },
                                      delete: { delete($0) },
                                      newCategory: { catNaming = ""; catName = "" },
                                      renameCategory: { c in catNaming = c.id; catName = c.name },
                                      recolor: { id, hex in editCategories { cats in if let i = cats.firstIndex(where: { $0.id == id }) { cats[i].color = hex } } },
                                      deleteCategory: { id in editCategories { $0.removeAll { $0.id == id && $0.channels.isEmpty } } })
                MVListGap()
                Group {
                    if let a = open { ChatHost(key: "ws:\(w.id):dm:\(a.id)", token: a) { ChatPane(agent: a) } }
                    else if let channel { ChatHost(key: "ch:\(w.conv(channel.id))", token: ChannelToken(w: w, channel: channel, members: members)) { ChannelPane(w: w, channel: channel, members: members) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            Group {
                if SnapshotMode.on { VStack(spacing: 0) { sidebar(members: members, open: open, channel: channel); Spacer(minLength: 0) } }   // ImageRenderer draws no scroll views
                else { ScrollView { sidebar(members: members, open: open, channel: channel) }.scrollIndicators(.never) }
            }
            .frame(width: panes.list)
            .overlay(alignment: .trailing) { SplitHandle(pane: PaneID.list).offset(x: 5.5) }
            .padding(.trailing, 1)
            .zIndex(1)                                  // the handle's half over the chat stays on top of it
            Group {
                if let a = open { ChatHost(key: "ws:\(w.id):dm:\(a.id)", token: a) { ChatPane(agent: a) } }
                else if let channel { ChatHost(key: "ch:\(w.conv(channel.id))", token: ChannelToken(w: w, channel: channel, members: members)) { ChannelPane(w: w, channel: channel, members: members) } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: s.invitingWorkspace) { _, id in if id == w.id { inviting = true; s.invitingWorkspace = nil } }
        .onAppear { if s.invitingWorkspace == w.id { inviting = true; s.invitingWorkspace = nil } }
        .task(id: w.id) { if let channel { await s.loadMessages(w.conv(channel.id)) } }
        .alert(catNaming == "" ? "New category" : "Rename category", isPresented: Binding(get: { catNaming != nil }, set: { if !$0 { catNaming = nil } })) {
            TextField("Category name", text: $catName)
            Button("Cancel", role: .cancel) { catNaming = nil }
            Button(catNaming == "" ? "Create" : "Rename") { saveCategory() }
        }
        // MAVIS: the app's own dialog (name, category, who answers); classic keeps the system alert.
        .overlay {
            if MV.on, let n = naming {
                MVChannelDialog(title: n.channel == nil ? "New channel" : "Rename channel",
                                category: (w.categories ?? []).first { $0.id == n.category }?.name ?? w.name,
                                confirm: n.channel == nil ? "Create channel" : "Rename",
                                name: $newName, agents: $newAgents, asksAgents: n.channel == nil,
                                cancel: { naming = nil }, create: { saveName() })
            }
        }
        .alert(naming?.channel == nil ? "New channel" : "Rename channel", isPresented: Binding(get: { !MV.on && naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("channel-name", text: $newName)
            Button("Cancel", role: .cancel) { naming = nil }
            Button(naming?.channel == nil ? "Create" : "Rename") { saveName() }
        }
    }
    /// Channels by category, then the members.
    func sidebar(members: [Agent], open: Agent?, channel: Workspace.Channel?) -> some View {
                VStack(alignment: .leading, spacing: 0) {
                    head
                    ForEach(w.categories ?? []) { c in
                        sectionHead(c.name.uppercased(), help: "New channel in \(c.name)") { naming = (c.id, nil); newName = "" }
                        VStack(spacing: 2) {
                            ForEach(c.channels) { ch in
                                let on = open == nil && channel?.id == ch.id
                                SideRow(selected: on, hover: true) { s.openAgent = nil; s.openChannel = ch.id; Task { await s.loadMessages(w.conv(ch.id)) } } label: {
                                    Icon("hash", 20); Line(ch.name, 16, .medium, on ? C.i12 : C.i10)
                                }
                                .contextMenu {
                                    Button("Rename #\(ch.name)…") { naming = (c.id, ch.id); newName = ch.name }
                                    if w.channels.count > 1 { Button("Delete #\(ch.name)", role: .destructive) { delete(ch.id) } }
                                }
                            }
                        }
                    }
                    sectionHead("MEMBERS", help: "Invite an agent") { if Date().timeIntervalSince(PickMenu.closedAt) > 0.3 { inviting.toggle() } }
                        .overlay(alignment: .topTrailing) {
                            if inviting {
                                PickMenu(scope: s.agents.filter { !(w.members ?? []).contains($0.id) }, chosen: "", open: $inviting,
                                         extra: ("plus", "New agent", { s.newAgentOpen = true })) { id in Task { await s.setMember(id, w.id, true) } }
                                    .offset(y: 32)
                            }
                        }
                        .zIndex(1)
                    if members.isEmpty {
                        Para(text: "Nobody here yet. Invite one of your agents with +: it brings its own memory.", size: 14, weight: .regular, color: C.i10)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    VStack(spacing: 2) {
                        ForEach(members) { a in
                            SideRow(selected: open?.id == a.id, hover: true) { s.openAgent = a.id; Task { await s.loadMessages(a.id) } } label: {
                                Avatar(agent: a, size: 20, status: false)
                                Line(a.name, 16, .medium, open?.id == a.id ? C.i12 : C.i10)
                                Spacer(minLength: 0)
                                let st = s.state(of: a)
                                if st == "needs" { Text("\(s.approvalsFor(a.id).count)").font(F.font(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(WAIT)) }
                                else if st == "working" { Circle().fill(Color(0xe0a100)).frame(width: 8, height: 8) }
                                else if st == "failed" { Circle().fill(FAIL_TEXT).frame(width: 8, height: 8) }
                            }
                            .help("Message \(a.name)")
                            .contextMenu { Button("Remove \(a.name) from \(w.name)") { if s.openAgent == a.id { s.openAgent = nil }; Task { await s.setMember(a.id, w.id, false) } } }
                        }
                    }
                }
                .padding(.top, 8).padding(.horizontal, 10).padding(.bottom, 16)
    }
    var head: some View {
        HStack(spacing: 8) {
            Hover { h in
                Button { headMenu.toggle() } label: {
                    HStack(spacing: 8) {
                        Text(w.name).font(F.font(20, .semibold)).foregroundStyle(C.i12).lineLimit(1)
                        Icon("chev", 16).foregroundStyle(h || headMenu ? C.i12 : C.i10).rotationEffect(.degrees(headMenu ? 180 : 0))
                    }
                    .padding(.horizontal, 8).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(h || headMenu ? C.v3 : .clear)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .fixedSize()
            .floatingMenu($headMenu, placement: .below(trailing: false, gap: 6)) { WorkspaceActions(w: w, open: $headMenu) }
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .zIndex(2)
    }
    /// A small section title with a + at its end (Discord's "TEXT CHANNELS  +").
    func sectionHead(_ title: String, help: String, add: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Line(title, 12, .semibold, C.i10)
            Spacer(minLength: 0)
            Hover { h in
                Button(action: add) {
                    Icon("plus", 16).foregroundStyle(h ? C.i12 : C.i10).frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: R.xs).fill(h ? C.v3 : .clear)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.tip(help).accessibilityLabel(help)
        }
        .padding(.leading, 12).padding(.trailing, 0).frame(height: 24).padding(.top, 16).padding(.bottom, 4)
    }
    /// Channel names as Discord writes them: lower case, dashes for spaces.
    static func channelName(_ raw: String) -> String {
        let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let dashed = t.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? String($0) : "-" }.joined()
        return String(dashed.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-").prefix(40))
    }
    func saveName() {
        guard let n = naming else { return }
        naming = nil
        let name = Self.channelName(newName); guard !name.isEmpty else { return }
        var cats = w.categories ?? []
        guard let ci = cats.firstIndex(where: { $0.id == n.category }) else { return }
        if let id = n.channel, let i = cats[ci].channels.firstIndex(where: { $0.id == id }) { cats[ci].channels[i].name = name }
        else {
            let id = "c" + UUID().uuidString.prefix(8).lowercased()
            cats[ci].channels.append(.init(id: id, name: name, agents: newAgents.isEmpty ? nil : newAgents))
            for a in newAgents where !(w.members ?? []).contains(a) { Task { await s.setMember(a, w.id, true) } }
            s.openAgent = nil; s.openChannel = id
        }
        Task { await s.saveChannels(w, cats) }
    }
    /// Changes the categories and saves them.
    func editCategories(_ change: (inout [Workspace.Category]) -> Void) {
        var cats = w.categories ?? []
        change(&cats)
        Task { await s.saveChannels(w, cats) }
    }
    /// A new category takes the next colour in the set; a rename keeps its colour.
    func saveCategory() {
        guard let id = catNaming else { return }
        catNaming = nil
        let name = catName.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }
        editCategories { cats in
            if id.isEmpty {
                let color = MV.Workspace.tagColors[cats.count % MV.Workspace.tagColors.count].hex
                cats.append(.init(id: "k" + UUID().uuidString.prefix(8).lowercased(), name: name, open: true, channels: [], color: color))
            } else if let i = cats.firstIndex(where: { $0.id == id }) { cats[i].name = name }
        }
    }
    func delete(_ id: String) {
        let cats = (w.categories ?? []).map { c in var c = c; c.channels = c.channels.filter { $0.id != id }; return c }
        if s.openChannel == id { s.openChannel = w.channels.first { $0.id != id }?.id ?? "general" }
        Task { await s.saveChannels(w, cats) }
    }
}

/// A 40-tall sidebar row (web: .snav).
struct SideRow<L: View>: View {
    let selected: Bool; var hover = true; let action: () -> Void; @ViewBuilder let label: () -> L
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 12) { label() }
                    .foregroundStyle(selected || h ? C.i12 : C.i10)
                    .padding(.leading, 12).padding(.trailing, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: R.ctl).fill(selected ? C.sel : h ? C.rowHover : .clear)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// A channel: one shared conversation. You post; every member you @tag answers here, in the same rows, cards and
/// streaming as a DM. Nobody tagged: the message is just posted.
struct ChannelPane: View {
    @EnvironmentObject var s: Store
    let w: Workspace; let channel: Workspace.Channel; let members: [Agent]
    var body: some View {
        let conv = w.conv(channel.id)
        let rows = s.rows(for: conv)
        // Everyone who ever spoke here keeps their face, even after leaving the workspace.
        let cast = Dictionary(s.agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let idx = (w.categories ?? []).firstIndex { $0.channels.contains { $0.id == channel.id } } ?? 0
        let cat = (w.categories ?? []).indices.contains(idx) ? w.categories![idx].name : w.name
        let panel = s.channelPanel(w, channel.id)
        if MV.on {
            // A channel has the same tools as a chat with an agent (browser, terminal, files) plus Changes, which only
            // a workspace has.
            ChatWithPanel(panel: panel, chat: column(conv: conv, rows: rows, cast: cast, cat: cat, idx: idx, panel: panel).modifier(MVDropZone(key: "ch:\(conv)")))
                .environment(\.chatConv, conv)
        } else {
            column(conv: conv, rows: rows, cast: cast, cat: cat, idx: idx, panel: panel)
        }
    }
    @ViewBuilder func column(conv: String, rows: [ChatRow], cast: [String: Agent], cat: String, idx: Int, panel: SidePanel) -> some View {
        VStack(spacing: 0) {
            if MV.on {
                MavisChannelHead(category: cat, color: MV.Workspace.color((w.categories ?? []).indices.contains(idx) ? w.categories![idx] : nil, at: idx),
                                 name: channel.name, members: members, panel: panel,
                                 given: w.granted(channel, among: s.agents),
                                 state: s.channelState(conv),
                                 set: { ids in
                                     // Given a channel: a member of its workspace too.
                                     for id in ids where !(w.members ?? []).contains(id) { Task { await s.setMember(id, w.id, true) } }
                                     var cats = w.categories ?? []
                                     for ci in cats.indices {
                                         if let i = cats[ci].channels.firstIndex(where: { $0.id == channel.id }) { cats[ci].channels[i].agents = ids }
                                     }
                                     Task { await s.saveChannels(w, cats) }
                                 })
                if s.messages[conv] == nil || rows.isEmpty {
                    MavisChannelStart(title: channel.name,
                                      lede: "A chat in \(cat). Every agent here can see \(((w.path ?? s.home) as NSString).lastPathComponent) and its notes; only what you allow can change anything.",
                                      chips: [("mvFolder", ((w.path ?? s.home) as NSString).abbreviatingWithTildeInPath), ("mvPen", "Project notes")])
                        .task { if s.messages[conv] == nil { await s.loadMessages(conv) } }
                } else {
                    ChatTranscript(agent: nil, cast: cast, rows: rows, intro: AnyView(EmptyView()))
                }
                ChannelComposer(w: w, channel: channel, members: members)
            } else {
            HStack(spacing: 8) {
                Icon("hash", 20).foregroundStyle(C.i10)
                Line(channel.name, 16, .semibold)
                Line(members.isEmpty ? "Invite agents to \(w.name) to talk to them here" : "Tag @\(members[0].name) to ask, or @everyone", 14, .regular, C.i10)
                Spacer(minLength: 0)
                HStack(spacing: -8) { ForEach(members.prefix(5)) { a in Avatar(agent: a, size: 24, status: false).background(RoundedRectangle(cornerRadius: Avatar.radius(28), style: .continuous).fill(C.v1).padding(-2)) } }
            }
            .padding(.horizontal, 16).frame(height: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(C.divider).frame(height: 1) }
            if s.messages[conv] != nil {
                ChatTranscript(agent: nil, cast: cast, rows: rows, intro: AnyView(ChannelIntro(w: w, channel: channel, members: members)))
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).task { await s.loadMessages(conv) }
            }
            ChannelComposer(w: w, channel: channel, members: members)
            }
        }
        .background(C.v1)
        .findInChat(conv)
        .onAppear { LiveWords.shared.update(rows) }
        .onChange(of: rows) { _, r in LiveWords.shared.update(r) }
    }
}

/// The start of a channel (Discord: "Welcome to #general").
struct ChannelIntro: View {
    let w: Workspace; let channel: Workspace.Channel; let members: [Agent]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Icon("hash", 32).foregroundStyle(C.i10).frame(width: 64, height: 64).background(Circle().fill(C.v3))
            Line("Welcome to #\(channel.name)", 24, .semibold, C.i12, tracking: -0.36).padding(.top, 12)
            Para(text: members.isEmpty
                 ? "This is the start of #\(channel.name). Invite agents to \(w.name) from Members, then tag them here."
                 : "This is the start of #\(channel.name). Tag an agent with @ to ask it something; everyone here sees the whole conversation.",
                 size: 16, weight: .regular, color: C.i10)
                .frame(maxWidth: 640, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 8)
    }
}

/// The channel's box (the same box as a DM's): @ lists the members to tag (and @everyone), then folders and files;
/// + adds files, photos or a folder; ↵ posts.
struct ChannelComposer: View {
    @EnvironmentObject var s: Store
    let w: Workspace; let channel: Workspace.Channel; let members: [Agent]
    @StateObject private var model = ComposerModel()
    @StateObject private var dictation = Dictation()
    @State private var before = ""
    var body: some View {
        Group { if MV.on { mavis } else { classic } }
            .onAppear { connect() }
            .onChange(of: channel.id) { _, _ in connect() }
            .onChange(of: members.map(\.id)) { _, _ in connect() }
            .onChange(of: channel.agents ?? []) { _, _ in connect() }
            .onDisappear { model.save() }
    }
    /// MAVIS: the same chat box as a chat with an agent (MVChatBox): its Mode is the channel agent's, talking works
    /// the same way, and there's no @ button (the channel's agent answers without a tag).
    var mavis: some View {
        let agent = w.answerer(channel, among: s.agents) ?? s.assistants.first
        // This channel's own runs (ch:<conv>:<agent>): an agent's DM never counts here, nor this there.
        let mine = s.runs.keys.filter { $0.hasPrefix("ch:\(w.conv(channel.id)):") }
        return MVChatBox(model: model, dictation: dictation,
                         placeholder: "Message #\(channel.name)",
                         busy: !mine.isEmpty, modeAgent: agent, stop: { for k in mine { s.stop(k) } }, talk: { talk() },
                         talkSend: { dictation.finish { heard in model.set(ChatComposer.join(before, heard), caretAtEnd: true); model.submit() } },
                         dropKey: "ch:\(w.conv(channel.id))")
        .onChange(of: dictation.transcript) { _, heard in if dictation.active { model.set(ChatComposer.join(before, heard), caretAtEnd: true) } }
        .onChange(of: dictation.failure) { _, f in if let f { s.toast = f } }
    }
    func talk() {
        if dictation.active { dictation.finish { heard in model.set(ChatComposer.join(before, heard), caretAtEnd: true) } }
        else { before = model.text; dictation.start() }
    }
    var classic: some View {
        HStack(alignment: .bottom, spacing: Box.gap) {
            ComposerButton(icon: "paperclip", label: "Add files or a folder") { model.toggleMenu() }
            VStack(alignment: .leading, spacing: 6) {
                if !model.images.isEmpty || !model.files.isEmpty { AttachmentStrip(model: model).padding(.top, 6) }
                ZStack(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text(members.isEmpty ? "Message #\(channel.name)" : "Message #\(channel.name), tag @\(members[0].name) to ask")
                            .font(F.font(16, .regular)).foregroundStyle(C.i9).lineLimit(1).allowsHitTesting(false)
                    }
                    ComposerField(model: model).frame(height: model.height).padding(.horizontal, -Chip.room)
                }
                .padding(.vertical, 8)
            }
            .frame(minHeight: 40)
        }
        .padding(Box.pad)
        .background(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).strokeBorder(C.edge, lineWidth: 1))
        .shadow(color: .black.opacity(themeNow.dark ? 0.5 : 0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(themeNow.dark ? 0.35 : 0.06), radius: 12, y: 6)
        .modifier(ComposerOverlays(model: model))
        .zIndex(1)
        .padding(.horizontal, 16).padding(.bottom, Box.lift)
    }
    func connect() {
        model.attach(.channel(conv: w.conv(channel.id), members: members.map(\.id), folder: w.path), store: s)
        model.commandsFor = (w.answerer(channel, among: s.agents) ?? s.assistants.first)?.id
        if let id = model.commandsFor { s.loadCatalog(id) }
        model.sidePanel = { [s, w, channel] in s.channelPanel(w, channel.id) }
        model.send = { [s, w, channel] text, images, files in s.sendToChannel(w, channel.id, text, images: images, files: files) }
        // Esc as in a chat: stop listening, else stop this channel's reply.
        model.escape = { [s, w, channel, dictation] in
            if dictation.active { dictation.cancel(); return }
            for k in s.runs.keys where k.hasPrefix("ch:\(w.conv(channel.id)):") { s.stop(k) }
        }
    }
}

/// What you can do to a workspace (Discord's server menu, in the app's style): open it, mark it read, invite an agent,
/// mute it, edit it, open its folder, copy its path, remove it.
struct WorkspaceActions: View {
    @EnvironmentObject var s: Store
    let w: Workspace; @Binding var open: Bool
    var body: some View {
        var items: [ActionMenu.Item] = []
        if s.openWorkspace != w.id { items.append(.init(symbol: "arrow.up.right.square", title: "Open") { s.openSpace(w.id) }) }
        items.append(.init(symbol: "checkmark.circle", title: "Mark as read") { s.markRead(w) })
        items.append(.divider)
        items.append(.init(symbol: "person.badge.plus", title: "Invite an agent") { s.openSpace(w.id); s.invitingWorkspace = w.id })
        items.append(.init(symbol: w.muted == true ? "bell" : "bell.slash", title: w.muted == true ? "Unmute workspace" : "Mute workspace",
                           detail: w.muted == true ? nil : "No badge or unread dot") { s.setMuted(w, w.muted != true) })
        items.append(.divider)
        items.append(.init(symbol: "pencil", title: "Edit workspace") { s.editingWorkspace = w.id })
        if let p = w.path {
            items.append(.init(symbol: "folder", title: "Open folder") { NSWorkspace.shared.open(URL(fileURLWithPath: p)) })
            items.append(.init(symbol: "doc.on.doc", title: "Copy path") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(p, forType: .string)
            })
        }
        items.append(.divider)
        items.append(.init(symbol: "trash", title: "Remove workspace", danger: true) { s.removingWorkspace = w.id })
        return ActionMenu(open: $open, width: 240, items: items)
    }
}

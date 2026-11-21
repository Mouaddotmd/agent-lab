// The welcome, the first time Agent Lab opens on a Mac (ported from Mavis final launch's Welcome.swift; same steps,
// Agent Lab's look, inside the main window): sign in with Google (Account), connect Claude (only while it's missing),
// done. Until it's finished nothing else of Agent Lab runs (the engine starts after it). Signed out later: only the
// sign-in page comes back.
//   AgentLabNative --welcome     shows the whole welcome again
import SwiftUI
import AppKit

@MainActor final class Welcome: ObservableObject {
    static let shared = Welcome()
    private static let doneKey = "welcomeDone"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    /// Setup is once per Mac. Someone who used Agent Lab before the welcome existed already has agents here: for them
    /// setup counts as done, and only signing in is asked for. Run once at launch, before deciding to show it.
    static func adoptExistingUser() {
        guard !isDone else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if FileManager.default.fileExists(atPath: support.appendingPathComponent("Agent Lab/state.json").path) {
            UserDefaults.standard.set(true, forKey: doneKey)
        }
    }

    enum Page: Int, CaseIterable { case account, claude, ready }
    @Published var page: Page = .account
    /// Shown instead of the app (decided at launch; again if access is lost).
    @Published private(set) var showing: Bool
    /// Bumped every second while showing, so Claude installed or signed in from Terminal shows here at once.
    @Published private(set) var tick = 0
    /// --welcome: the whole setup, even when it's been done (to look at it).
    private var full = CommandLine.arguments.contains("--welcome")
    private var timer: Timer?

    private init() {
        Self.adoptExistingUser()
        showing = CommandLine.arguments.contains("--welcome") || !(Self.isDone && Account.shared.allowed)
        page = Self.firstPage(full: CommandLine.arguments.contains("--welcome"))
        if showing { startTicking() }
    }
    private static func firstPage(full: Bool) -> Page { Account.configured || full ? .account : .claude }

    /// Only signing in is missing (set up before, signed out since).
    var signInOnly: Bool { Self.isDone && !full }
    /// The pages actually shown: the account only when accounts are set up for this build, Claude's only while it isn't
    /// installed and signed in.
    var pages: [Page] {
        if signInOnly && Account.configured { return [.account] }
        return Page.allCases.filter {
            switch $0 {
            case .account: Account.configured
            case .claude: page == .claude || full || !ClaudeAccount.ready
            case .ready: true
            }
        }
    }
    /// Continue waits for what this page sets up: access to Agent Lab, then Claude installed and signed in.
    var canContinue: Bool {
        _ = tick
        switch page {
        case .account: return Account.shared.allowed
        case .claude: return ClaudeAccount.ready
        case .ready: return true
        }
    }
    func next() {
        guard canContinue else { return }
        if page == .account, signInOnly { finish(); return }
        let p = pages
        if let i = p.firstIndex(of: page), i + 1 < p.count { page = p[i + 1] } else { finish() }
    }
    func back() {
        let p = pages
        if let i = p.firstIndex(of: page), i > 0 { page = p[i - 1] }
    }
    func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        full = false
        timer?.invalidate(); timer = nil
        showing = false
    }
    /// Access lost while open (signed out, or the account turned off): back to the sign-in page.
    func reopen() {
        page = Self.firstPage(full: false)
        showing = true
        startTicking()
    }
    func bringForward() { NSApp.activate() }
    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick += 1 } }
    }
}

/// The welcome, in the window: a picture spot, the title and line, the page, then page dots and Back / Continue.
struct WelcomeView: View {
    @ObservedObject var model = Welcome.shared
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Line(title, 24, .semibold, C.i12, tracking: -0.36)
                Para(text: detail, size: 14, weight: .regular, color: C.i10).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 24)
            Group {
                switch model.page {
                case .account: WelcomeAccountPage()
                case .claude: WelcomeClaudePage()
                case .ready: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(model.pages, id: \.self) { p in Circle().fill(p == model.page ? C.i12 : C.v5).frame(width: 6, height: 6) }
                }
                .accessibilityElement().accessibilityLabel("Page \((model.pages.firstIndex(of: model.page) ?? 0) + 1) of \(model.pages.count)")
                Spacer(minLength: 0)
                if model.page != model.pages.first { SecondaryButton(title: "Back") { model.back() } }
                PrimaryButton(title: model.signInOnly && model.page == .account ? "Open Agent Lab" : model.page == .ready ? "Start" : "Continue") { model.next() }
                    .disabled(!model.canContinue).opacity(model.canContinue ? 1 : 0.4)
                    .help(model.canContinue ? "" : model.page == .account ? "Sign in first" : "Install Claude Code and sign in first")
            }
        }
        .padding(32)
        .frame(width: 520, height: 480)
        .background(RoundedRectangle(cornerRadius: R.card).fill(C.v1))
        .overlay(RoundedRectangle(cornerRadius: R.card).strokeBorder(C.edge, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.v0)
    }
    private var title: String {
        switch model.page {
        case .account: "Sign in to Agent Lab"
        case .claude: "Connect Claude"
        case .ready: "You're ready"
        }
    }
    private var detail: String {
        switch model.page {
        case .account: "Agent Lab is in beta. Sign in with Google to get access; your account keeps your place."
        case .claude: "Your agents think with Claude, on your own Claude plan. No API key needed."
        case .ready: "Make an agent, give it a job and a folder, then invite it into your workspaces. Ask it anything in plain words; it shows you what it's doing and checks with you before anything risky."
        }
    }
}

/// One setting: what it is, a line on it, and its control at the end.
private struct WelcomeRow<Trailing: View>: View {
    let title: String; var detail: String? = nil; @ViewBuilder let trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(F.font(14, .medium)).foregroundStyle(C.i12)
                if let detail { Text(detail).font(F.font(12, .regular)).foregroundStyle(C.i10).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: R.ctl).fill(C.v2))
        .overlay(RoundedRectangle(cornerRadius: R.ctl).strokeBorder(C.edge, lineWidth: 1))
    }
}
private struct DoneMark: View {
    var title = "Done"
    var body: some View {
        HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)); Text(title).font(F.font(13, .medium)) }.foregroundStyle(C.i10)
    }
}

private struct WelcomeAccountPage: View {
    @ObservedObject private var account = Account.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = account.session {
                WelcomeRow(title: session.name ?? session.email, detail: session.name == nil ? nil : session.email) {
                    switch session.status {
                    case "approved": DoneMark(title: "Signed in")
                    case "waitlist": SmallSecondaryButton(title: "Check again") { Task { await account.recheck() } }
                    default: EmptyView()
                    }
                }
                if session.status == "waitlist" { note("You're on the waitlist. You'll get in as soon as a spot opens; Agent Lab checks each time it opens.") }
                else if session.status == "blocked" { note("This account doesn't have access to Agent Lab.") }
                else if session.status == "unknown" { note("Checking your access…") }
                SmallSecondaryButton(title: "Use another account") { account.signOut() }
            } else {
                switch account.phase {
                case .signingIn:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Finish signing in in your browser, then come back here.").font(F.font(13, .regular)).foregroundStyle(C.i10)
                        SmallSecondaryButton(title: "Cancel") { account.cancelSignIn() }
                    }
                case .checking:
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Checking your access…").font(F.font(13, .regular)).foregroundStyle(C.i10) }
                default:
                    GoogleButton { account.signIn() }
                    if case .failed(let why) = account.phase {
                        Text(why).font(F.font(12, .regular)).foregroundStyle(FAIL_TEXT).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let url = Account.privacyURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text("What Agent Lab keeps about your account").font(F.font(12, .regular)).foregroundStyle(C.i10).underline()
                }.buttonStyle(.plain)
            }
        }
    }
    private func note(_ text: String) -> some View {
        Text(text).font(F.font(12, .regular)).foregroundStyle(C.i10).fixedSize(horizontal: false, vertical: true)
    }
}

/// Google's own button: white, its "G", "Continue with Google".
private struct GoogleButton: View {
    let action: () -> Void
    var body: some View {
        Hover { h in
            Button(action: action) {
                HStack(spacing: 10) {
                    Text("G").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(0x4285f4))
                    Text("Continue with Google").font(F.font(14, .medium)).foregroundStyle(Color.black.opacity(0.87))
                }
                .padding(.horizontal, 16).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: R.ctl).fill(Color.white.opacity(h ? 0.9 : 1)))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .accessibilityLabel("Continue with Google")
    }
}

private struct WelcomeClaudePage: View {
    @ObservedObject private var model = Welcome.shared
    var body: some View {
        let _ = model.tick
        let installed = ClaudeAccount.installed, signedIn = ClaudeAccount.signedIn
        VStack(spacing: 8) {
            WelcomeRow(title: "Install Claude Code", detail: "Opens Terminal and runs Claude's installer.") {
                if installed { DoneMark() } else { PrimaryButton(title: "Install") { ClaudeAccount.install() } }
            }
            WelcomeRow(title: "Sign in to Claude", detail: "Opens Claude Code. Follow its sign-in, then come back.") {
                if signedIn { DoneMark() } else { PrimaryButton(title: "Sign in") { ClaudeAccount.signIn() }.disabled(!installed).opacity(installed ? 1 : 0.4) }
            }
        }
    }
}

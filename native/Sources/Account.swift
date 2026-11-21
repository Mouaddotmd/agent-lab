import AppKit
import CryptoKit
import Network
import Security

// The Agent Lab account (ported from Agent Lab final launch's Account.swift; same flow, its own project and keys): sign
// in with Google, through the accounts service (Supabase Auth). Agent Lab only works signed in,
// with an account that's been let in (status "approved"); the welcome window does the signing in.
//
// How it works, the way desktop apps sign in with Google (VS Code, the Google Cloud CLI):
//   1. Your own browser opens Google's sign-in for Agent Lab's Google key (Info.plist Agent LabGoogleClientID, a "Desktop app"
//      key), with a PKCE challenge. You're usually signed in to Google there already, so it's one click.
//   2. Google sends the browser back to this Mac — http://127.0.0.1:<port>, where Agent Lab listens for that one answer
//      (SignInReceiver) and shows a "You're signed in" page — never leaving the Mac.
//   3. The code is exchanged with Google for an ID token, and Supabase signs in with that token (it accepts Agent Lab's
//      Google keys, listed under Authentication → Sign In / Providers → Google → Client IDs).
//   4. mavis_check_in (a database function) records this Mac's version and returns the account's status:
//      approved, waitlist or blocked. Who gets in is decided there (Supabase dashboard: profiles, allowlist, settings).
// The session is kept in Agent Lab's data folder, readable only by you (the Keychain asks for your password whenever the
// signing changes, so Agent Lab keeps its secrets out of it). Offline, a recent approved check-in still counts.
//
// Configuration (Info.plist): Agent LabAuthURL, the project's address; Agent LabAuthKey, its publishable key — public by
// design: every row is guarded by row-level security; Agent LabGoogleClientID and Agent LabGoogleClientSecret, the Google key.

@MainActor final class Account: NSObject, ObservableObject {
    static let shared = Account()

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String
        var name: String?
        var avatar: URL?
        /// approved, waitlist or blocked, as of `checkedAt`.
        var status: String
        var checkedAt: Date
    }

    enum Phase: Equatable { case idle, signingIn, checking, failed(String) }

    @Published private(set) var session: Session?
    @Published private(set) var phase: Phase = .idle

    /// How long an approved check-in still counts without reaching the service (offline, or the service down).
    static let grace: TimeInterval = 14 * 24 * 3600

    private static var base: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "AgentLabAuthURL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
    private static var key: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AgentLabAuthKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    /// Agent Lab's Google key, of the "Desktop app" kind: its secret isn't a secret (Google says so for installed apps);
    /// the proof is PKCE, and the answer only ever comes back to this Mac.
    private static var googleID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AgentLabGoogleClientID") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    private static var googleSecret: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AgentLabGoogleClientSecret") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    static var privacyURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "AgentLabPrivacyURL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
    /// Accounts are switched on for this build (a development build without the settings simply skips them).
    static var configured: Bool { base != nil && key != nil && googleID != nil }

    /// Let in: signed in, approved, and checked recently enough.
    var allowed: Bool {
        guard Self.configured else { return true }
        guard let session, session.status == "approved" else { return false }
        return Date().timeIntervalSince(session.checkedAt) < Self.grace
    }

    /// Called once access is granted by a sign-in (the welcome window moves on).
    var onSignedIn: (() -> Void)?

    override init() {
        super.init()
        session = Self.load()
    }

    // MARK: Signing in

    private var receiver: SignInReceiver?

    /// Opens Google's sign-in in your browser; the answer comes back to this Mac only (SignInReceiver).
    func signIn() {
        guard let googleID = Self.googleID else { return }
        receiver?.stop()
        let verifier = Self.randomURLSafe(32), state = Self.randomURLSafe(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        phase = .signingIn
        let receiver = SignInReceiver(state: state) { [weak self] result in
            Task { @MainActor in self?.received(result, verifier: verifier) }
        }
        self.receiver = receiver
        receiver.start { [weak self] port in
            Task { @MainActor in
                guard let self else { return }
                guard let port else { self.phase = .failed("Agent Lab couldn't start signing in. Try again."); return }
                var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                parts.queryItems = [.init(name: "client_id", value: googleID), .init(name: "redirect_uri", value: "http://127.0.0.1:\(port)"),
                                    .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
                                    .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                                    .init(name: "state", value: state), .init(name: "prompt", value: "select_account")]
                self.redirect = "http://127.0.0.1:\(port)"
                if !NSWorkspace.shared.open(parts.url!) { self.phase = .failed("Your browser didn't open. Try again.") }
            }
        }
    }

    private var redirect = ""

    func cancelSignIn() {
        receiver?.stop(); receiver = nil
        if phase == .signingIn { phase = .idle }
    }

    private func received(_ result: Result<String, AccountError>, verifier: String) {
        NSApp.activate()
        Welcome.shared.bringForward()
        switch result {
        case .failure(let error): receiver = nil; phase = .failed(error.message)
        case .success(let code): Task { await exchange(code: code, verifier: verifier) }
        }
    }

    /// Google's code → Google's ID token → a Agent Lab session (Supabase signs in with the ID token, checking it was made
    /// for one of Agent Lab's Google keys).
    private func exchange(code: String, verifier: String) async {
        guard let base = Self.base, let key = Self.key, let googleID = Self.googleID else { return }
        phase = .checking
        do {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [.init(name: "code", value: code), .init(name: "client_id", value: googleID),
                               .init(name: "client_secret", value: Self.googleSecret ?? ""), .init(name: "code_verifier", value: verifier),
                               .init(name: "grant_type", value: "authorization_code"), .init(name: "redirect_uri", value: redirect)]
            request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            let (data, response) = try await URLSession.shared.data(for: request)
            let google = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (response as? HTTPURLResponse)?.statusCode == 200, let idToken = google["id_token"] as? String else {
                throw AccountError("Google didn't finish the sign-in (\((google["error_description"] ?? google["error"]) as? String ?? "no answer")). Try again.")
            }
            var body: [String: Any] = ["provider": "google", "id_token": idToken]
            if let access = google["access_token"] as? String { body["access_token"] = access }
            let reply = try await Self.post(base.appendingPathComponent("auth/v1/token"), query: ["grant_type": "id_token"], body: body, key: key)
            guard var fresh = Self.session(from: reply) else { throw AccountError("Google sign-in didn't return an account.") }
            fresh.status = "unknown"
            session = fresh
            try await checkIn()
            phase = .idle
            switch session?.status {
            case "approved": tellBrowser(ok: true, nil)
            case "waitlist": tellBrowser(ok: true, "You're on the Agent Lab waitlist. Agent Lab lets you in as soon as a spot opens.")
            default: tellBrowser(ok: false, "This account doesn't have access to Agent Lab.")
            }
            if allowed { onSignedIn?() }
        } catch {
            let message = (error as? AccountError)?.message ?? "Couldn't reach Agent Lab's account service. Check your connection and try again."
            phase = .failed(message)
            tellBrowser(ok: false, message)
        }
    }

    private func tellBrowser(ok: Bool, _ detail: String?) {
        receiver?.answer(ok: ok, detail: detail)
        receiver = nil
    }

    // MARK: Staying signed in

    /// Records this Mac's version and reads the account's status. Throws when the service can't be reached.
    func checkIn() async throws {
        guard let base = Self.base, let key = Self.key, session != nil else { return }
        try await refreshIfNeeded()
        guard var current = session else { return }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let reply = try await Self.post(base.appendingPathComponent("rest/v1/rpc/agentlab_check_in"), query: [:],
                                        body: ["p_app_version": AppVersion.text,
                                               "p_os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"],
                                        key: key, token: current.accessToken)
        guard let status = reply["status"] as? String else { throw AccountError("Agent Lab's account service answered oddly. Try again.") }
        current.status = status
        if let name = reply["name"] as? String, !name.isEmpty { current.name = name }
        current.checkedAt = Date()
        save(current)
    }

    /// At launch and every few hours: an account turned off is noticed, and the session stays fresh. Offline it's left
    /// as it was (the grace period covers it). Signed out by the service (the refresh token revoked): signed out here.
    func recheck() async {
        do { try await checkIn() } catch let error as AccountError where error.signedOut { forget() } catch {}
    }

    private func refreshIfNeeded() async throws {
        guard let base = Self.base, let key = Self.key, let current = session, current.expiresAt.timeIntervalSinceNow < 120 else { return }
        do {
            let reply = try await Self.post(base.appendingPathComponent("auth/v1/token"), query: ["grant_type": "refresh_token"],
                                            body: ["refresh_token": current.refreshToken], key: key)
            guard var fresh = Self.session(from: reply) else { throw AccountError("Couldn't renew your sign-in.") }
            fresh.status = current.status; fresh.checkedAt = current.checkedAt
            if fresh.name == nil { fresh.name = current.name }
            save(fresh)
        } catch let error as AccountError where error.status == 400 || error.status == 401 {
            throw AccountError("You've been signed out. Sign in again.", status: error.status, signedOut: true)
        }
    }

    // MARK: Signing out

    func signOut() {
        if let base = Self.base, let key = Self.key, let token = session?.accessToken {
            Task { _ = try? await Self.post(base.appendingPathComponent("auth/v1/logout"), query: [:], body: [:], key: key, token: token) }
        }
        forget()
    }

    /// Sends a tester's feedback to the accounts service (stored there, and emailed to the maker). `kind` is
    /// "feedback", "bug" or "idea". Throws if it couldn't be sent, so the sheet can show it didn't go.
    func submitFeedback(kind: String, message: String) async throws {
        guard let base = Self.base, let key = Self.key, session != nil else {
            throw AccountError("Sign in first to send feedback.")
        }
        try await refreshIfNeeded()
        guard let token = session?.accessToken else { throw AccountError("Sign in first to send feedback.") }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        _ = try await Self.post(base.appendingPathComponent("rest/v1/rpc/agentlab_submit_feedback"), query: [:],
                                body: ["p_kind": kind, "p_message": message,
                                       "p_app_version": AppVersion.text,
                                       "p_os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"],
                                key: key, token: token)
    }

    /// Deletes the account on the service (its sign-in and profile), then signs out here. Throws if it couldn't.
    func deleteAccount() async throws {
        guard let base = Self.base, let key = Self.key, session != nil else { return }
        try await refreshIfNeeded()
        guard let token = session?.accessToken else { return }
        _ = try await Self.post(base.appendingPathComponent("rest/v1/rpc/agentlab_delete_account"), query: [:], body: [:], key: key, token: token)
        forget()
    }

    private func forget() {
        session = nil
        phase = .idle
        try? FileManager.default.removeItem(at: Self.file)
    }

    // MARK: Storage

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agent Lab", isDirectory: true)
    }
    private static var file: URL { folder.appendingPathComponent("account.json") }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    private static func load() -> Session? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private func save(_ next: Session) {
        session = next
        Self.write(next, to: Self.file)
    }

    // MARK: The service

    private static func post(_ url: URL, query: [String: String], body: [String: Any], key: String, token: String? = nil) async throws -> [String: Any] {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: parts.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let said = (json["error_description"] ?? json["msg"] ?? json["message"]) as? String
            throw AccountError(said.map { "Sign-in failed: \($0)" } ?? "Agent Lab's account service said no (\(status)). Try again.", status: status)
        }
        return json
    }

    private static func session(from reply: [String: Any]) -> Session? {
        guard let access = reply["access_token"] as? String, let refresh = reply["refresh_token"] as? String,
              let user = reply["user"] as? [String: Any], let id = user["id"] as? String else { return nil }
        let meta = user["user_metadata"] as? [String: Any] ?? [:]
        let expires = (reply["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(reply["expires_in"] as? Double ?? 3600)
        return Session(accessToken: access, refreshToken: refresh, expiresAt: expires, userID: id,
                       email: user["email"] as? String ?? "", name: (meta["full_name"] ?? meta["name"]) as? String,
                       avatar: (meta["avatar_url"] as? String).flatMap(URL.init(string:)), status: "unknown", checkedAt: .distantPast)
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL
    }
}

struct AccountError: Error {
    let message: String
    var status = 0
    var signedOut = false
    init(_ message: String, status: Int = 0, signedOut: Bool = false) { self.message = message; self.status = status; self.signedOut = signedOut }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Access gone while Agent Lab is open (signed out by the service, or the account turned off): say so plainly, then reopen
/// Agent Lab, which lands in the welcome window's sign-in page.
@MainActor enum AccountGate {
    private static var shown = false
    static func lost() {
        guard !shown else { return }
        shown = true
        let alert = NSAlert()
        if Account.shared.session == nil {
            alert.messageText = "You've been signed out of Agent Lab"
            alert.informativeText = "Sign in again with Google to keep using Agent Lab."
        } else {
            alert.messageText = "Your Agent Lab access has changed"
            alert.informativeText = Account.shared.session?.status == "waitlist"
                ? "Your account is on the waitlist for now. Agent Lab will let you in as soon as a spot opens."
                : "This account no longer has access to Agent Lab. You can sign in with another one."
        }
        alert.addButton(withTitle: "Continue")
        NSApp.activate()
        alert.runModal()
        shown = false
        Welcome.shared.reopen()                      // back to the sign-in page, in the same window
    }

    /// Quits and opens Agent Lab again.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Catches Google's answer to one sign-in: a tiny web server on 127.0.0.1 (this Mac only, a port picked by macOS),
/// open only while you sign in. It takes the first request that carries the sign-in's state and keeps the browser
/// waiting until Agent Lab has finished signing in (`answer`), so the page says what really happened, then stops.
/// Gives up after ten minutes.
final class SignInReceiver: @unchecked Sendable {
    private let state: String
    private let done: @Sendable (Result<String, AccountError>) -> Void
    private let queue = DispatchQueue(label: "dev.agentlab.native.sign-in")
    private var listener: NWListener?
    private var finished = false
    /// The browser's request, held open until `answer`.
    private var waiting: NWConnection?

    init(state: String, done: @escaping @Sendable (Result<String, AccountError>) -> Void) {
        self.state = state
        self.done = done
    }

    /// Starts listening; `ready` gets the port (nil if it couldn't start).
    func start(ready: @escaping @Sendable (UInt16?) -> Void) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else { ready(nil); return }
        self.listener = listener
        var told = false
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: if !told { told = true; ready(listener.port?.rawValue) }
            case .failed: if !told { told = true; ready(nil) }; self?.stop()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 600) { [weak self] in self?.finish(.failure(AccountError("Signing in took too long. Try again."))) }
    }

    func stop() {
        queue.async { [weak self] in self?.listener?.cancel(); self?.listener = nil }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let head = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
            let parts = head.split(separator: " ")
            let target = parts.count > 1 ? String(parts[1]) : ""
            let items = URLComponents(string: "http://127.0.0.1" + target)?.queryItems ?? []
            let value = { (name: String) in items.first(where: { $0.name == name })?.value }
            // Anything else the browser asks for (a favicon) isn't the answer.
            guard value("state") == self.state, !self.finished else {
                self.reply(connection, status: "404 Not Found", page: nil)
                return
            }
            if let code = value("code") {
                self.waiting = connection
                self.finish(.success(code))
                // Never leave the browser hanging, whatever happens in Agent Lab.
                self.queue.asyncAfter(deadline: .now() + 45) { [weak self] in self?.respond(ok: false, detail: "Agent Lab took too long to finish. Go back to Agent Lab and try again.") }
            } else {
                self.reply(connection, status: "200 OK", page: Self.page(ok: false, detail: nil))
                self.finish(.failure(AccountError(value("error") == "access_denied" ? "Sign-in was cancelled." : "Google sign-in didn't finish. Try again.")))
                self.close()
            }
        }
    }

    private func finish(_ result: Result<String, AccountError>) {
        guard !finished else { return }
        finished = true
        done(result)
    }

    /// Tells the waiting browser how it ended, then stops listening.
    func answer(ok: Bool, detail: String?) {
        queue.async { self.respond(ok: ok, detail: detail) }   // strong: this keeps the receiver alive until it's answered
    }

    private func respond(ok: Bool, detail: String?) {
        guard let connection = waiting else { return }
        waiting = nil
        reply(connection, status: "200 OK", page: Self.page(ok: ok, detail: detail))
        close()
    }

    private func close() {
        queue.asyncAfter(deadline: .now() + 1) { self.listener?.cancel(); self.listener = nil }
    }

    private func reply(_ connection: NWConnection, status: String, page: String?) {
        let body = Data((page ?? "").utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// The page the browser lands on: Agent Lab's own colours (DESIGN.md: chat, ink, ink-meta, in both themes).
    private static func page(ok: Bool, detail: String?) -> String {
        let title = ok ? "You're signed in to Agent Lab" : "Sign-in didn't finish"
        let line = (ok ? (detail ?? "You can close this tab and go back to Agent Lab.") : (detail ?? "Go back to Agent Lab and try again."))
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title><style>
        :root{--chat:#ffffff;--ink:#1b1e22;--ink-meta:#565a60}
        @media (prefers-color-scheme:dark){:root{--chat:#141517;--ink:#ececee;--ink-meta:#b2b6bc}}
        html,body{margin:0;height:100%;background:var(--chat);color:var(--ink);font:400 14px/20px "Helvetica Neue",Helvetica,Arial,sans-serif}
        main{height:100%;display:grid;place-content:center;text-align:center;padding:0 16px}
        p{margin:4px 0 0;color:var(--ink-meta)}
        </style></head><body><main><div>\(title)</div><p>\(line)</p></main></body></html>
        """
    }
}

/// The version this Mac runs, as the check-in records it ("0.1.0 (1)").
enum AppVersion {
    static var text: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }
}

// Claude Code on this Mac (ported from Mavis final launch's ClaudeAccount.swift): agents think with Claude, on your own
// Claude plan, through the Claude Code installed here. Installing and signing in each happen in a Terminal window.
import AppKit
import Security

/// Whether Claude Code is installed and signed in on this Mac: its credentials are in the login Keychain (only their
/// presence is checked — nothing is read), or in its config folder.
enum ClaudeAccount {
    static var signedIn: Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/.credentials.json").path)
    }
    static var installed: Bool { executable() != nil }
    /// Ready for agents: installed and signed in.
    static var ready: Bool { installed && signedIn }

    /// Where Claude Code lives. Apps opened from the Dock get a bare PATH, so look where the installers put it.
    static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func install() {
        Terminal.run("curl -fsSL https://claude.ai/install.sh | bash && echo && echo 'Claude Code is installed. Head back to Agent Lab.'")
    }
    static func signIn() {
        guard let exe = executable() else { install(); return }
        Terminal.run("'\(exe.path)'")
    }
}

/// A line run in a new Terminal window (installing or signing in to Claude Code needs one).
enum Terminal {
    static func run(_ line: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agentlab-\(UUID().uuidString.prefix(8)).command")
        let script = "#!/bin/zsh\nclear\n\(line)\n"
        guard (try? script.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}

import SwiftUI
import AppKit

/// End-to-end walk through the real app, used by `scripts/app-test.sh`.
/// Only runs when AGENT_LAB_SNAPSHOT is set (a folder for screenshots); it always uses a throwaway data folder.
@MainActor
enum TestDriver {
    static let env = ProcessInfo.processInfo.environment
    static var enabled: Bool { env["AGENT_LAB_SNAPSHOT"] != nil && env["AGENT_LAB_DATA"] != nil }

    static func log(_ s: String) { FileHandle.standardError.write("[app-test] \(s)\n".data(using: .utf8)!) }
    static func fail(_ s: String) -> Never { log("FAILED: \(s)"); exit(1) }

    static func wait(_ label: String, seconds: Double = 120, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if cond() { return }; try? await Task.sleep(for: .milliseconds(300)) }
        snap("timeout-\(label.replacingOccurrences(of: " ", with: "-"))")
        fail("timed out waiting for \(label)")
    }

    static func snap(_ name: String) {
        let dir = env["AGENT_LAB_SNAPSHOT"]!
        for (i, w) in NSApp.windows.filter({ $0.isVisible }).enumerated() {
            guard let v = w.contentView?.superview ?? w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)\(i == 0 ? "" : "-\(i)").png"))
        }
        log("shot \(name)")
    }

    static func settle() async { try? await Task.sleep(for: .milliseconds(900)) }

    static func run(_ lab: Lab) async {
        await wait("start", seconds: 20) { lab.loaded }
        NSApp.windows.first?.setContentSize(NSSize(width: 1380, height: 860))
        await settle(); snap("01-start")

        guard let repo = env["AGENT_LAB_TEST_REPO"] else { exit(0) }
        await lab.addWorkspace(repo)
        guard let juno = await lab.createAgent(["name": "Juno", "job": "", "color": 2, "operator": "claude-code", "model": "claude-haiku-5-5", "permission": "ask", "cwd": repo, "ownBranch": true]) else { fail("create agent") }
        log("ok agent on \(juno.branch ?? "?")")
        lab.open(juno)
        await settle()
        await lab.send(to: juno.id, "Create a file named hello.txt in the current folder containing exactly: hi from Juno. Then reply with one short sentence.")
        await wait("approval or reply", seconds: 180) { !lab.approvals(for: juno.id).isEmpty || (lab.runs["agent:\(juno.id)"] == nil && (lab.messages[juno.id] ?? []).contains { $0.role == "assistant" }) }
        if !lab.approvals(for: juno.id).isEmpty { await settle(); snap("02-approval") }
        var asked = 0
        while lab.runs["agent:\(juno.id)"] != nil || !lab.approvals(for: juno.id).isEmpty {
            if let p = lab.approvals(for: juno.id).first { asked += 1; lab.answer(p, "allow") }
            try? await Task.sleep(for: .milliseconds(500))
            if asked > 8 { fail("too many approvals") }
        }
        await wait("reply saved", seconds: 30) { (lab.messages[juno.id] ?? []).contains { $0.role == "assistant" } }
        log("ok asked before acting (\(asked))")
        guard FileManager.default.fileExists(atPath: "\(juno.worktree ?? "")/hello.txt") else { fail("file not written in its folder") }
        log("ok wrote hello.txt in its own folder")
        await settle(); snap("03-reply")

        lab.nav = .review(juno.id)
        try? await Task.sleep(for: .seconds(3)); snap("04-review")

        lab.scope = nil
        lab.nav = .chats("claude-code")
        await wait("chats", seconds: 60) { lab.chats["claude-code"] != nil }
        try? await Task.sleep(for: .seconds(3)); snap("05-chats")

        _ = await lab.addDecision("Never merge to main without tests passing", workspace: nil)
        lab.nav = .memory
        await settle(); snap("06-memory")

        lab.nav = .connections
        try? await Task.sleep(for: .seconds(3)); snap("07-connections")

        lab.nav = .agents
        lab.sheet = .newAgent(nil)
        try? await Task.sleep(for: .seconds(1.5)); snap("08-new-agent")
        lab.sheet = nil
        try? await Task.sleep(for: .seconds(1))
        lab.sheet = .search
        try? await Task.sleep(for: .seconds(1.5)); snap("09-search")
        lab.sheet = nil
        try? await Task.sleep(for: .seconds(1))
        lab.nav = .agents
        await settle(); snap("10-agents")
        log("PASS")
        lab.engine.stop()
        try? await Task.sleep(for: .milliseconds(500))
        exit(0)
    }
}

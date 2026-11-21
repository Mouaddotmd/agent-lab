import Foundation

/// Runs the engine (`node engine/server.js`) and talks to it one JSON line at a time.
/// Calls are async and throw the engine's own sentence when something goes wrong.
final class EngineClient {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private let lock = NSLock()
    var onEvent: ((EngineEvent) -> Void)?
    var onExit: ((String) -> Void)?
    private var stderrTail = ""

    /// The engine folder: written into Info.plist at build time, overridable for development.
    static var engineDir: String? {
        if let env = ProcessInfo.processInfo.environment["AGENT_LAB_ENGINE"] { return env }
        // A built app carries its own copy, so it never reaches into the folder it was built from.
        if let res = Bundle.main.resourcePath, FileManager.default.fileExists(atPath: "\(res)/engine/server.js") { return "\(res)/engine" }
        return Bundle.main.object(forInfoDictionaryKey: "AgentLabEngine") as? String
    }

    static func findNode() -> String? {
        let home = NSHomeDirectory()
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.volta/bin", "/usr/bin"]
        if let nvm = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            dirs += nvm.sorted().reversed().map { "\(home)/.nvm/versions/node/\($0)/bin" }
        }
        return dirs.map { "\($0)/node" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func start() throws {
        guard let dir = Self.engineDir, FileManager.default.fileExists(atPath: "\(dir)/server.js") else {
            throw Failure(message: "Agent Lab can’t find its engine. Rebuild the app from the Agent Lab folder.")
        }
        guard let node = Self.findNode() else {
            throw Failure(message: "Agent Lab needs Node.js, and it isn’t installed on this Mac.")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = ["\(dir)/server.js"]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        // A GUI app starts with a short PATH; give the engine the places tools usually live.
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", (node as NSString).deletingLastPathComponent, env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        p.environment = env
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            self?.receive(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let s = String(data: h.availableData, encoding: .utf8), !s.isEmpty else { return }
            FileHandle.standardError.write(s.data(using: .utf8)!)
            self?.lock.withLock { self?.stderrTail = String(((self?.stderrTail ?? "") + s).suffix(2000)) }
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let tail = self.lock.withLock { self.stderrTail }
            let waiting = self.lock.withLock { () -> [CheckedContinuation<Data, Error>] in let w = Array(self.pending.values); self.pending.removeAll(); return w }
            waiting.forEach { $0.resume(throwing: Failure(message: "The engine stopped.")) }
            self.onExit?(proc.terminationStatus == 0 ? "" : tail)
        }
        try p.run()
        process = p
        input = stdin.fileHandleForWriting
    }

    func stop() {
        try? input?.close()
        process?.terminate()
    }

    private func receive(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines { handle(line) }
    }

    private func handle(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let event = obj["event"], let data = try? JSONSerialization.data(withJSONObject: event),
           let ev = try? JSONDecoder().decode(EngineEvent.self, from: data) {
            DispatchQueue.main.async { self.onEvent?(ev) }
            return
        }
        guard let id = obj["id"] as? Int else { return }
        let cont = lock.withLock { pending.removeValue(forKey: id) }
        if obj["ok"] as? Bool == true {
            let value = obj["value"] ?? NSNull()
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            cont?.resume(returning: data)
        } else {
            cont?.resume(throwing: Failure(message: obj["error"] as? String ?? "Something went wrong."))
        }
    }

    func call<T: Decodable>(_ method: String, _ params: Any?..., as: T.Type = T.self) async throws -> T {
        let data = try await raw(method, params.map { $0 ?? NSNull() })
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Failure(message: "The engine sent something unexpected for \(method).") }
    }

    func send(_ method: String, _ params: Any?...) async throws {
        _ = try await raw(method, params.map { $0 ?? NSNull() })
    }

    private func raw(_ method: String, _ params: [Any]) async throws -> Data {
        guard let input else { throw Failure(message: "The engine isn’t running.") }
        return try await withCheckedThrowingContinuation { cont in
            let id: Int = lock.withLock { let i = nextId; nextId += 1; pending[i] = cont; return i }
            do {
                var line = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
                line.append(0x0A)
                try input.write(contentsOf: line)
            } catch {
                _ = lock.withLock { pending.removeValue(forKey: id) }
                cont.resume(throwing: Failure(message: "Couldn’t reach the engine."))
            }
        }
    }
}

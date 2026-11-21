// A pseudo-terminal running a shell, done natively (forkpty), so the terminal tab needs no native Node module.
// Output is read on a background queue into a buffer the screen drains at its own pace: when the screen falls behind
// (a flood like `yes`), reading pauses and the shell simply waits, so nothing piles up and the app never stalls.
import Foundation
import Darwin

final class TermPTY: @unchecked Sendable {
    let pid: pid_t
    private let master: Int32
    private let queue = DispatchQueue(label: "agentlab.pty.read")
    private let writes = DispatchQueue(label: "agentlab.pty.write")
    private var reader: DispatchSourceRead?
    private var watcher: DispatchSourceProcess?
    private let lock = NSLock()
    private var pending = Data()
    private var paused = false
    private var closed = false
    private var ended = false
    /// Called (on a background queue) when output arrives while the buffer was empty: time to drain it.
    var onOutput: (@Sendable () -> Void)?
    /// Called once (on a background queue) with the shell's exit status when it ends.
    var onExit: (@Sendable (Int32) -> Void)?

    /// Most output held before reading pauses, and the point under which it carries on.
    private static let high = 2 << 20, low = 256 << 10

    struct Failure: Error, LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Starts `shell` (with `args`) in `folder` on a new pseudo-terminal of `cols` × `rows`.
    init(shell: String, args: [String], folder: String, cols: Int, rows: Int, env: [String: String]) throws {
        // Everything the child needs is made before fork: after it, only plain system calls are safe.
        let argv = ([shell] + args).map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let dir = strdup(folder), path = strdup(shell)
        defer { argv.forEach { free($0) }; envp.forEach { free($0) }; free(dir); free(path) }
        var size = winsize(ws_row: UInt16(max(rows, 2)), ws_col: UInt16(max(cols, 2)), ws_xpixel: 0, ws_ypixel: 0)
        var term = Self.defaultTermios()
        var fd: Int32 = -1
        let maxFd = min(getdtablesize(), 65536)
        let child = forkpty(&fd, nil, &term, &size)
        if child < 0 { throw Failure(message: "Couldn't start a terminal (\(String(cString: strerror(errno))))") }
        if child == 0 {
            // The child: plain signals, nothing of the app's left open, then the shell.
            for s in [SIGPIPE, SIGINT, SIGQUIT, SIGTSTP, SIGTTIN, SIGTTOU, SIGCHLD, SIGHUP, SIGTERM, SIGWINCH] { signal(s, SIG_DFL) }
            var none = sigset_t(); sigemptyset(&none); sigprocmask(SIG_SETMASK, &none, nil)
            var i: Int32 = 3
            while i < maxFd { close(i); i += 1 }
            if chdir(dir) != 0 { _ = chdir(getenv("HOME")) }
            execve(path, argv, envp)
            _exit(127)
        }
        pid = child
        master = fd
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        start()
    }

    /// The usual cooked mode a terminal app opens with (UTF-8 input on).
    private static func defaultTermios() -> termios {
        var t = termios()
        t.c_iflag = tcflag_t(ICRNL | IXON | IXANY | IMAXBEL | BRKINT | IUTF8)
        t.c_oflag = tcflag_t(OPOST | ONLCR)
        t.c_cflag = tcflag_t(CREAD | CS8 | HUPCL)
        t.c_lflag = tcflag_t(ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL)
        let cc: [(Int32, UInt8)] = [(VEOF, 4), (VEOL, 255), (VEOL2, 255), (VERASE, 0x7f), (VWERASE, 23), (VKILL, 21), (VREPRINT, 18),
                                    (VINTR, 3), (VQUIT, 0x1c), (VSUSP, 26), (VDSUSP, 25), (VSTART, 17), (VSTOP, 19), (VLNEXT, 22),
                                    (VDISCARD, 15), (VMIN, 1), (VTIME, 0), (VSTATUS, 20)]
        withUnsafeMutableBytes(of: &t.c_cc) { raw in for (i, v) in cc { raw[Int(i)] = v } }
        t.c_ispeed = speed_t(B38400); t.c_ospeed = speed_t(B38400)
        return t
    }

    private func start() {
        let r = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        r.setEventHandler { [weak self] in self?.readSome() }
        reader = r
        r.resume()
        let w = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        w.setEventHandler { [weak self] in self?.reap() }
        watcher = w
        w.resume()
    }

    private func readSome() {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = buf.withUnsafeMutableBytes { read(master, $0.baseAddress, 65536) }
        if n > 0 {
            lock.lock()
            let wasEmpty = pending.isEmpty
            pending.append(contentsOf: buf[0..<n])
            let full = pending.count > Self.high && !paused
            if full { paused = true }
            lock.unlock()
            if full { reader?.suspend() }
            if wasEmpty { onOutput?() }
        } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
            // The other side is gone (the shell and everything it started have closed it).
            reader?.cancel(); reader = nil
            reap()
        }
    }

    private func reap() {
        var status: Int32 = 0
        let r = waitpid(pid, &status, WNOHANG)
        guard r == pid else { return }
        watcher?.cancel(); watcher = nil
        lock.lock(); let first = !ended; ended = true; lock.unlock()
        // What's still on its way out is read before saying it ended.
        if first {
            if let reader { reader.cancel(); self.reader = nil; drainRest() }
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            onExit?(code)
        }
    }

    private func drainRest() {
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = buf.withUnsafeMutableBytes { read(master, $0.baseAddress, 65536) }
            guard n > 0 else { break }
            lock.lock(); let wasEmpty = pending.isEmpty; pending.append(contentsOf: buf[0..<n]); lock.unlock()
            if wasEmpty { onOutput?() }
        }
    }

    /// Takes up to `max` bytes of output for the screen; reading picks up again once the screen has caught up.
    func take(_ max: Int) -> Data {
        lock.lock()
        let n = min(max, pending.count)
        let out = pending.prefix(n)
        pending.removeFirst(n)
        let resume = paused && pending.count < Self.low
        if resume { paused = false }
        lock.unlock()
        if resume { queue.async { [weak self] in self?.reader?.resume() } }
        return Data(out)
    }

    var hasOutput: Bool { lock.lock(); defer { lock.unlock() }; return !pending.isEmpty }

    /// Types `data` into the shell (on its own queue: a big paste waits for room without holding anything up).
    func write(_ data: Data) {
        writes.async { [self] in
            var rest = data[...]
            var tries = 0
            while !rest.isEmpty {
                lock.lock(); let gone = closed; lock.unlock()
                if gone { return }
                let n = rest.withUnsafeBytes { Darwin.write(master, $0.baseAddress, rest.count) }
                if n > 0 { rest = rest.dropFirst(n); tries = 0 }
                else if errno == EAGAIN || errno == EINTR { tries += 1; if tries > 5000 { return }; usleep(1000) }
                else { return }
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        lock.lock(); let gone = closed; lock.unlock()
        guard !gone, cols > 1, rows > 1 else { return }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &size)
    }

    /// The tab closed: the shell and its jobs get a hang-up, as when a terminal window closes.
    func hangUp() {
        lock.lock(); if closed { lock.unlock(); return }; closed = true; lock.unlock()
        kill(-pid, SIGHUP); kill(pid, SIGHUP)
        let pid = pid
        let fd = master
        queue.async { [self] in
            // The descriptor closes once reading has properly stopped (a paused reader is let go first).
            if let r = reader {
                r.setCancelHandler { close(fd) }
                lock.lock(); let wasPaused = paused; paused = false; lock.unlock()
                if wasPaused { r.resume() }
                r.cancel(); reader = nil
            } else { close(fd) }
            // A shell that ignores the hang-up is ended a moment later, so none is left behind.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if kill(pid, 0) == 0 { kill(-pid, SIGKILL); kill(pid, SIGKILL) }
                var s: Int32 = 0; _ = waitpid(pid, &s, WNOHANG)
            }
        }
    }
}

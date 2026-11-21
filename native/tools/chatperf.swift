// Times the chat the way you feel it: opening a conversation (build + first layout + draw) and dragging the window
// wider and narrower (relayout + draw per frame). Real messages from disk, an offscreen window, no engine.
// Built by build.sh. Run: build/chatperf "~/Library/Application Support/Agent Lab/messages/<agent>.json" [copies]
// (copies repeats the chat, to check nothing grows with history). Budget: 16.7 ms a frame for 60 fps.
// Loop counts for profiling with `sample`: OPENS, SWITCHES, RESIZES, WRESIZES; CHATONLY=1 skips page switches.
import SwiftUI
import AppKit
import QuartzCore

@main
struct ChatPerf {
    @MainActor static func main() {
        _ = NSApplication.shared; F.register()
        let args = CommandLine.arguments
        let path = args.count > 1 ? args[1] : NSHomeDirectory() + "/Library/Application Support/Agent Lab/messages/a_dcdd5ea4.json"
        let copies = args.count > 2 ? Int(args[2]) ?? 1 : 1
        let one = try! JSONDecoder().decode([Message].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        // Bigger chats: the same conversation repeated with fresh ids, to see whether cost grows with history.
        var msgs: [Message] = []
        for c in 0..<copies { for m in one { msgs.append(Message(id: "\(c)_\(m.id)", role: m.role, text: m.text, verb: m.verb, at: m.at, turn: m.turn.map { "\(c)_\($0)" }, ch: m.ch, by: m.by, toolId: m.toolId, round: m.round, done: m.done, failed: m.failed)) } }
        let store = Store()
        let agent = Agent(id: "a1", name: "mavis v2", job: "", look: nil, operator: "claude-code", model: nil, permission: "ask", cwd: NSHomeDirectory(), workspace: nil, pinned: nil, createdAt: 0, worktree: nil, branch: nil, last: nil, origin: nil)
        store.agents = [agent]; store.messages["a1"] = msgs
        print("messages \(msgs.count), chars \(msgs.reduce(0) { $0 + $1.text.count }), rows \(store.rows(for: "a1").count)")

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        win.setFrameOrigin(NSPoint(x: -4000, y: 0)); win.orderFrontRegardless()
        func ms(_ t: CFTimeInterval) -> String { String(format: "%.1f ms", t * 1000) }
        func settle() { for _ in 0..<3 { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) } }
        func draw(_ v: NSView) { v.layoutSubtreeIfNeeded(); v.displayIfNeeded(); CATransaction.flush() }

        // Open: what switching to the chat costs, five times (first one includes font and cache warm-up).
        var opens: [CFTimeInterval] = []
        for _ in 0..<(ProcessInfo.processInfo.environment["OPENS"].flatMap { Int($0) } ?? 6) {
            let t0 = CACurrentMediaTime()
            let host = NSHostingView(rootView: ChatPane(agent: agent).environmentObject(store).environmentObject(Panes()))
            win.contentView = host
            draw(host)
            opens.append(CACurrentMediaTime() - t0)
            settle()
            win.contentView = NSView()
            settle()
        }
        print("open   first \(ms(opens[0]))  then \(opens.dropFirst().map(ms).joined(separator: ", "))")

        // Correctness: a chat opens at its end with its last rows drawn (a lazy list once opened onto black).
        for label in ["open"] {
            let h2 = NSHostingView(rootView: ChatPane(agent: agent).environmentObject(store).environmentObject(store.panes))
            win.contentView = h2; draw(h2)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6)); draw(h2)
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            guard let scroll = all(h2).compactMap({ $0 as? NSScrollView }).first(where: { $0.documentView != nil && $0.hasVerticalScroller || $0.contentView.bounds.height > 300 }), let doc = scroll.documentView else { print("CHECK no scroll view"); break }
            let clip = scroll.contentView, gap = doc.frame.height - clip.bounds.maxY
            let texts = all(h2).compactMap { $0 as? NSTextView }.filter { !$0.isHiddenOrHasHiddenAncestor && $0.window != nil }
            let shown = texts.filter { clip.bounds.intersects($0.convert($0.bounds, to: clip)) && $0.bounds.height > 0 }
            let lastText = msgs.last { $0.role == "assistant" }?.text ?? ""
            let tail = String(lastText.suffix(30)).trimmingCharacters(in: .whitespacesAndNewlines)
            let hasLast = shown.contains { $0.string.contains(tail.prefix(12)) }
            print("CHECK \(label): gap to end \(Int(gap)) pt, text views on screen \(shown.count) of \(texts.count) built, last reply on screen: \(hasLast)")
        }
        // Scroll: a trackpad flick up through the whole chat and back down, one step per frame, each frame laid out and
        // drawn (what you feel as smooth or stuttery). SCROLLONLY=1 stops after this.
        do {
            let h3 = NSHostingView(rootView: ChatPane(agent: agent).environmentObject(store).environmentObject(store.panes))
            win.contentView = h3; draw(h3)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6)); draw(h3)
            // As on a Mac with an accessibility app attached (voice tools, window managers): SwiftUI then keeps its
            // accessibility tree current, which an app with none never pays for. AX=1.
            if ProcessInfo.processInfo.environment["AX"] != nil {
                func walk(_ e: Any, _ d: Int) { guard d < 6, let el = e as? NSAccessibilityElementProtocol else { return }; for c in ((el as AnyObject).accessibilityChildren?() ?? []) ?? [] { walk(c, d + 1) } }
                walk(h3, 0)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3)); draw(h3)
            }
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            if let scroll = all(h3).compactMap({ $0 as? NSScrollView }).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) {
                let clip = scroll.contentView
                var f: [CFTimeInterval] = []
                let step = CGFloat(ProcessInfo.processInfo.environment["STEP"].flatMap { Double($0) } ?? 45)
                for dir in [-1.0, 1.0] {
                    for _ in 0..<(ProcessInfo.processInfo.environment["SCROLLS"].flatMap { Int($0) } ?? 240) {
                        let y = clip.bounds.origin.y + step * dir
                        let t0 = CACurrentMediaTime()
                        clip.scroll(to: CGPoint(x: 0, y: max(0, y))); scroll.reflectScrolledClipView(clip)
                        RunLoop.main.run(until: Date())       // SwiftUI's own work for the move (lazy rows coming in)
                        draw(h3)
                        f.append(CACurrentMediaTime() - t0)
                    }
                }
                // What each trackpad event costs before AppKit even scrolls: the app's own wheel handling (SmoothScroll's
                // monitor), measured on real precise-delta events with a phase, as a trackpad sends ~120 a second.
                var ev: [CFTimeInterval] = []
                for i in 0..<240 {
                    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(i % 2 == 0 ? -6 : 6), wheel2: 0, wheel3: 0) else { break }
                    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)   // changed: a finger on the pad
                    let mid = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
                    cg.location = CGPoint(x: mid.x, y: mid.y)
                    guard let e = NSEvent(cgEvent: cg) else { break }
                    let t0 = CACurrentMediaTime()
                    _ = SmoothScroll.shared.wheel(e, window: scroll.window)
                    ev.append(CACurrentMediaTime() - t0)
                }
                ev.sort()
                if !ev.isEmpty { print("trackpad event handling median \(ms(ev[ev.count / 2]))  p90 \(ms(ev[ev.count * 9 / 10]))  worst \(ms(ev.last!))") }
                f.sort()
                let over = f.filter { $0 > 1.0 / 60 }.count
                print("scroll median \(ms(f[f.count / 2]))  p90 \(ms(f[f.count * 9 / 10]))  p99 \(ms(f[f.count * 99 / 100]))  worst \(ms(f.last!))  frames over 16.7 ms: \(over) of \(f.count)  (doc \(Int(scroll.documentView?.frame.height ?? 0)) pt)")
            }
            if ProcessInfo.processInfo.environment["SCROLLONLY"] != nil { exit(0) }
        }
        // Resize: 60 width steps, as a window drag delivers them.
        let host = NSHostingView(rootView: ChatPane(agent: agent).environmentObject(store).environmentObject(Panes()))
        win.contentView = host; draw(host); settle()
        var frames: [CFTimeInterval] = []
        for i in 0..<(ProcessInfo.processInfo.environment["RESIZES"].flatMap { Int($0) } ?? 60) {
            let w = 700 + CGFloat(abs((i % 30) - 15)) * 30
            let t0 = CACurrentMediaTime()
            win.setContentSize(NSSize(width: w, height: 900))
            draw(host)
            frames.append(CACurrentMediaTime() - t0)
        }
        frames.sort()
        print("resize median \(ms(frames[frames.count / 2]))  p90 \(ms(frames[frames.count * 9 / 10]))  worst \(ms(frames.last!))  (16.7 ms = 60 fps)")
        // Switching inside one window, as the app does: chat A -> blank page (Review) -> chat A -> chat B -> chat A.
        let other = Agent(id: "a2", name: "other", job: "", look: nil, operator: "claude-code", model: nil, permission: "ask", cwd: NSHomeDirectory(), workspace: nil, pinned: nil, createdAt: 0, worktree: nil, branch: nil, last: nil, origin: nil)
        store.agents = [agent, other]; store.messages["a2"] = msgs
        store.openAgent = "a1"
        store.view = .messages
        let sw = NSHostingView(rootView: Page().environmentObject(store).environmentObject(store.panes).environmentObject(store.railTip))
        win.contentView = sw; draw(sw); settle()
        var toPage: [CFTimeInterval] = [], toChat: [CFTimeInterval] = []
        for i in 0..<(ProcessInfo.processInfo.environment["SWITCHES"].flatMap { Int($0) } ?? 12) {
            var t0 = CACurrentMediaTime()
            if ProcessInfo.processInfo.environment["CHATONLY"] == nil {
                store.view = .reviews; draw(sw); settle()
                t0 = CACurrentMediaTime(); store.view = .messages; draw(sw); toPage.append(CACurrentMediaTime() - t0); settle()
            } else { toPage.append(0) }
            t0 = CACurrentMediaTime(); store.openAgent = i % 2 == 0 ? "a2" : "a1"; draw(sw); toChat.append(CACurrentMediaTime() - t0); settle()
        }
        toPage.sort(); toChat.sort()
        print("switch Review->Messages median \(ms(toPage[6]))  worst \(ms(toPage.last!))   chat->chat median \(ms(toChat[6]))  worst \(ms(toChat.last!))")
        // The whole window (sidebar, top bar, page), dragged wider and narrower, on Home and on Messages.
        for page in [Kind.reviews, .messages, .agents] {
            store.view = page
            let shell = NSHostingView(rootView: Shell().environmentObject(store).environmentObject(store.panes).environmentObject(store.railTip))
            win.contentView = shell; win.setContentSize(NSSize(width: 1300, height: 900)); draw(shell); settle()
            if page == .agents { store.view = .messages; draw(shell); settle(); store.view = .agents; draw(shell); settle() }   // Messages kept behind
            var f: [CFTimeInterval] = []
            for i in 0..<(ProcessInfo.processInfo.environment["WRESIZES"].flatMap { Int($0) } ?? 80) {
                let w = 900 + CGFloat(abs((i % 40) - 20)) * 25
                let t0 = CACurrentMediaTime(); win.setContentSize(NSSize(width: w, height: 900)); draw(shell); f.append(CACurrentMediaTime() - t0)
            }
            f.sort(); print("window resize (\(page)) median \(ms(f[f.count / 2]))  p90 \(ms(f[f.count * 9 / 10]))  worst \(ms(f.last!))")
            // A change somewhere else in the app (a toast, another agent's run): what it costs this page.
            var pubs: [CFTimeInterval] = []
            for i in 0..<20 { let t0 = CACurrentMediaTime(); store.toast = i % 2 == 0 ? "x" : nil; settle(); draw(shell); pubs.append(CACurrentMediaTime() - t0) }
            pubs.sort(); print("   unrelated store change on (\(page)) median \(ms(pubs[pubs.count / 2]))")
        }
        exit(0)
    }
}

/// The Messages page's chat side exactly as Pages.swift has it, plus the blank page you switch from.
struct SwitchRoot: View {
    @EnvironmentObject var s: Store
    var body: some View {
        if s.view == .messages, let id = s.openAgent, let a = s.agents.first(where: { $0.id == id }) {
            ChatHost(key: "dm:\(a.id)", token: a) { ChatPane(agent: a) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { Color.clear }
    }
}

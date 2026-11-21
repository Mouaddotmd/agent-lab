// Draws approval card options with the app's own fonts and tokens, for picking one: build/cardshot <folder>
import SwiftUI
import AppKit

private let cmd = "for t in A AAAA CNAME NS; do echo \"$t: $(dig +short mouad.work $t | tr '\\n' ' ')\"; done; echo \"www CNAME: $(dig +short www.mouad.work CNAME)\""
private let title = "Check mouad.work\u{2019}s DNS records"

/// A white primary or a quiet secondary, 32 tall (Bar.control), R.ctl corners.
private struct Btn: View {
    let label: String; var key: String? = nil; var primary = false; var chevron = false
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(F.font(13, .medium))
            if let key { Text(key).font(F.font(12, .medium)).opacity(0.55) }
            if chevron { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6) }
        }
        .foregroundStyle(primary ? C.v1 : C.i12)
        .padding(.horizontal, 12).frame(height: Bar.control)
        .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(primary ? C.i12 : C.v4))
        .overlay(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).strokeBorder(primary ? .clear : C.edgeControl, lineWidth: 1))
    }
}

private struct Well: View {
    let text: String
    var body: some View {
        Text(ApprovalWords.tidy(text)).font(.system(size: 12, design: .monospaced)).foregroundStyle(C.i10)
            .lineLimit(2).truncationMode(.tail).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v1))
    }
}

private extension View {
    /// The chat box's shell: v2, its edge, Box.corner.
    func shell() -> some View {
        background(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).fill(C.v2))
            .overlay(RoundedRectangle(cornerRadius: Box.corner, style: .continuous).strokeBorder(C.edgeControl, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
    }
}

/// A: the same card, on the system. Numbered rows stay; no blue, no ✕, the agent's own words as the title.
private struct OptionA: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(F.font(14, .medium)).foregroundStyle(C.i12)
                Well(text: cmd)
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            VStack(spacing: 2) {
                row(1, "Allow", "For the rest of this request", hover: true)
                row(2, "Just this step", nil)
                row(3, "Don\u{2019}t allow", nil)
            }
            HStack {
                Text("Or tell it what to do instead").font(F.font(13, .regular)).foregroundStyle(C.i9)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v1))
            .padding(.top, 4)
        }
        .padding(Box.pad).frame(width: 420).shell()
    }
    func row(_ n: Int, _ label: String, _ detail: String?, hover: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(F.font(12, .medium)).monospacedDigit().foregroundStyle(C.i10)
                .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: R.xs, style: .continuous).fill(C.v4))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(F.font(14, .regular)).foregroundStyle(C.i12).frame(minHeight: 20)
                if let detail { Text(detail).font(F.font(12, .regular)).foregroundStyle(C.i9) }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(hover ? C.v3 : .clear))
    }
}

/// B: what it wants, then one row of answers: your words on the left, Don't allow and Allow (the one white button) on
/// the right. Allow's arrow picks "just this step".
private struct OptionB: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(F.font(14, .medium)).foregroundStyle(C.i12)
                Well(text: cmd)
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 10)
            HStack(spacing: Box.pair * 2) {
                Text("Tell it what to do instead").font(F.font(13, .regular)).foregroundStyle(C.i9)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: Bar.control, alignment: .leading)
                Btn(label: "Don\u{2019}t allow")
                Btn(label: "Allow", primary: true, chevron: true)
            }
        }
        .padding(Box.pad + 2).frame(width: 420).shell()
    }
}

/// C: no card. The message box itself asks: what it wants sits on top of the box, your typing tells it what to do
/// instead, and the send circle's place holds Don't allow and Allow.
private struct OptionC: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("mavis v2 wants to").font(F.font(13, .regular)).foregroundStyle(C.i9)
                    Spacer()
                    Text("fn 1  Allow \u{00B7} fn 2  Don\u{2019}t").font(F.font(12, .regular)).foregroundStyle(C.i9)
                }
                Text(title).font(F.font(14, .medium)).foregroundStyle(C.i12)
                Well(text: cmd)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: R.ctl, style: .continuous).fill(C.v3))
            HStack(alignment: .bottom, spacing: Box.gap) {
                Text("Or tell it what to do instead").font(F.font(16, .regular)).foregroundStyle(C.i9)
                    .padding(.leading, 8).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                Btn(label: "Don\u{2019}t allow")
                Btn(label: "Allow", primary: true, chevron: true)
            }
            .padding(.top, Box.pad)
        }
        .padding(Box.pad).frame(width: 560).shell()
    }
}

/// Today's card, for comparison.
private struct Today: View {
    let s = Store()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ApprovalCard(p: { var a = Approval(id: "x", verb: "Run", line: cmd, tool: "Bash", risk: "host", command: cmd); a.about = "Check mouad.work\u{2019}s DNS records"; return a }(), primary: false)
            ApprovalCard(p: { var a = Approval(id: "y", verb: "Run", line: "rm -rf node_modules", tool: "Bash", risk: "delete", command: "rm -rf node_modules"); return a }(), primary: false)
        }.environmentObject(s)
    }
}

@main struct CardShot {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/cardshot"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = NSApplication.shared; F.register()
        func save<V: View>(_ name: String, _ v: V) {
            let r = ImageRenderer(content: v.padding(28).background(C.v1).environment(\.colorScheme, .dark))
            r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
            }
        }
        save("0-today", Today())
        save("A-refine", OptionA())
        save("B-recompose", OptionB())
        save("C-rethink", OptionC())
        // Chat words with names in them, drawn by the chat's own text view.
        let para = NSMutableParagraphStyle(); para.lineSpacing = 5
        RichText.roots = [NSHomeDirectory() + "/Desktop/desktop", NSHomeDirectory(), NSHomeDirectory() + "/Desktop"]
        CommandTokens.names = CommandTokens.own.union(["design-audit", "stageshow", "advisor"])
        FileNames.shared.refresh(roots: RichText.roots)
        let t0 = Date(); while FileNames.shared.version == 0 && Date().timeIntervalSince(t0) < 60 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        print("index built in \(Int(Date().timeIntervalSince(t0)))s")
        for (w, url) in [("ShellChat.swift", "Mavis final launch"), ("App/Sources/DockWidget.swift", ""), ("Browser/", "Mavis final launch"), ("MavisPeek.html", "Mavis final launch"), ("Composer.swift", "Mavis final launch"), ("mouad.work", ""), ("Mavis final launch", ""), ("Extras/dist/", "Mavis final launch"), ("~/Desktop/mouad-work-resume/index.html", ""), ("~/Desktop", "")] {
            print("resolve \(w) -> \(RichText.fileLink(w, context: url)?.path ?? "none")")
        }
        let txt = NSMutableAttributedString(); txt.append(RichText.inline("Mavis final launch is in decent shape. The largest source file is App/Sources/DockWidget.swift at 2,911 lines; ShellChat.swift (2,503) and `Composer.swift` are next. README points to Browser/, Extras/dist/ and MavisPeek.html. Release 0.1.15, see https://mouad.work.", size: 16, base: NSColor(Color.white(0.82)), weight: .regular, style: para))
        let you = RichText.inline("/design-audit the portfolio page, then use /stageshow for a demo", size: 16, base: NSColor(C.i12), weight: .regular, style: para)
        txt.append(NSAttributedString(string: "\n\n")); txt.append(you)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 260)); tv.drawsBackground = true; tv.backgroundColor = NSColor(C.v1)
        tv.textContainer?.replaceLayoutManager(ChipLayoutManager()); tv.textContainerInset = NSSize(width: 20, height: 20); tv.textStorage?.setAttributedString(txt)
        tv.linkTextAttributes = [.foregroundColor: NSColor(MARK_BLUE), .underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: NSColor(MARK_BLUE.opacity(0.3))]
        let win = NSWindow(contentRect: tv.frame, styleMask: [.borderless], backing: .buffered, defer: false); win.contentView = tv
        if let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) { tv.cacheDisplay(in: tv.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/prose.png")) }
        // The work fold, opened, in a real hosting view.
        let steps1 = [Step(id: "a", verb: "Read", line: "README.md", round: 1, done: true, failed: false, offset: 0, detail: "/Users/me/Desktop/Mavis final launch/README.md"),
                      Step(id: "b", verb: "Run", line: "cd ~/Desktop/\"Mavis final launch\"; git log -1 --format='%h %s (%cd)'", round: 2, done: true, failed: false, offset: 0, detail: "cd ~/Desktop/\"Mavis final launch\"; git log -1 --format='%h %s (%cd)'", output: "a1b2c3 Release 0.1.15 (Wed Nov 19)"),
                      Step(id: "c", verb: "Run", line: "find App/Sources -name '*.swift' | wc -l", round: 3, done: true, failed: false, offset: 0, detail: "find App/Sources -name '*.swift' | wc -l", output: "99"),
                      Step(id: "d", verb: "Run", line: "find App/Sources -name '*.swift' | wc -l", round: 4, done: true, failed: false, offset: 0, detail: "find App/Sources -name '*.swift' | wc -l", output: "99"),
                      Step(id: "e", verb: "Write", line: "mavis-final-launch-health-check.md", round: 5, done: true, failed: false, offset: 0, detail: "/tmp/x.md")]
        let pieces: [Piece] = [.words(id: "w", text: "Running the health check you asked for earlier, on Mavis final launch, since it's the project with a release pending."), .steps(id: "s", steps: steps1)]
        let fold = VStack(alignment: .leading, spacing: 8) {
            Text("Made a change and looked at a file").font(F.font(14, .regular)).foregroundStyle(StepInk.lit)
            WorkList(pieces: pieces)
            Text(MarkdownText.inline("Mavis final launch is in decent shape, but **532 uncommitted changes** will block the next release. The largest file is `App/Sources/DockWidget.swift` at 2,911 lines; see [mouad.work](https://mouad.work).", size: 16, base: Color.white(0.82), weight: .regular)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 640).background(C.v1).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: fold); host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        let w2 = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); w2.contentView = host
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/fold.png")) }
        print("saved to \(out)")
    }
}

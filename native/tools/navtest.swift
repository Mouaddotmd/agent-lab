// Back and forward walk every place you opened (page, workspace, channel, chat), one step each, with no engine.
import SwiftUI
import AppKit

@main
struct NavTest {
    @MainActor static func main() {
        var failed = 0
        func check(_ n: String, _ ok: Bool, _ d: @autoclosure () -> String = "") { print(ok ? "ok   \(n)" : "FAIL \(n) \(d())"); if !ok { failed += 1 } }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let s = Store()
        s.workspaces = [Workspace(id: "w1", name: "Acme")]
        s.agents = [try! JSONDecoder().decode(Agent.self, from: #"{"id":"a1","name":"Nova"}"#.data(using: .utf8)!)]
        func at() -> String { "\(s.view.rawValue) ws=\(s.openWorkspace ?? "-") ch=\(s.openChannel) dm=\(s.openAgent ?? "-")" }
        s.go(.discover); settle()
        s.openSpace("w1"); settle()                                   // three fields change: one step
        s.openChannel = "eng"; settle()
        s.openAgent = "a1"; settle()                                  // a member's DM inside the workspace
        s.openChat("a1"); settle()                                    // the chat in Messages
        check("each place is one step", s.stack.count == 6, "\(s.stack.map(\.place))")
        let walk = ["agents ws=- ch=general dm=-", "discover ws=- ch=general dm=-", "discover ws=w1 ch=general dm=-", "discover ws=w1 ch=eng dm=-", "discover ws=w1 ch=eng dm=a1", "messages ws=- ch=eng dm=a1"]
        var seen: [String] = [at()]
        for _ in 0..<5 { s.step(-1); settle(); seen.append(at()) }
        check("back walks every place, newest first", seen == walk.reversed(), "\(seen)")
        check("back at the start does nothing", { s.step(-1); settle(); return s.index == 0 && !s.canBack }())
        var fwd: [String] = []
        for _ in 0..<5 { s.step(1); settle(); fwd.append(at()) }
        check("forward walks them again", fwd == Array(walk.dropFirst()), "\(fwd)")
        check("going back and forward adds no steps", s.stack.count == 6)
        s.step(-2); settle(); s.go(.memory); settle()
        check("a new place after going back drops the forward steps", s.stack.count == 5 && !s.canForward && s.view == .memory)
        s.agents = []; s.step(-1); settle()
        check("a deleted chat is skipped over, its page still opens", s.openAgent == nil && s.view == .discover, at())
        paneChecks(check)
        // Rail labels: a pause before the first, at once when moving between tiles, gone at once on leaving.
        let tip = RailTip(), a = RailTip.Tip(id: "a", title: "Home", detail: nil, frame: .zero), b = RailTip.Tip(id: "b", title: "Team", detail: nil, frame: .zero)
        tip.enter(a); settle()
        check("no label right away (a quick sweep shows nothing)", tip.tip == nil)
        RunLoop.main.run(until: Date().addingTimeInterval(RailTip.delay + 0.1))
        check("the label shows after the pause", tip.tip?.id == "a")
        tip.leave("a"); tip.enter(b)
        check("moving to the next tile swaps at once", tip.tip?.id == "b")
        tip.leave("b")
        check("leaving hides it at once", tip.tip == nil)
        tip.enter(a); tip.leave("a"); RunLoop.main.run(until: Date().addingTimeInterval(RailTip.delay + 0.1))
        check("passing over a tile without resting shows nothing", tip.tip == nil)
        print(failed == 0 ? "PASS" : "\(failed) FAILED"); exit(failed == 0 ? 0 : 1)
    }
}

// Panes: widths, the rail, and how a drag follows the pointer and settles.
@MainActor func paneChecks(_ check: (String, Bool, @autoclosure () -> String) -> Void) {
    for k in ["sidebar", "list", "now"] { UserDefaults.standard.removeObject(forKey: "pane." + k) }
    UserDefaults.standard.removeObject(forKey: "pane.sidebar.folded")
    let p = Panes(), S = PaneID.sidebar, L = PaneID.list
    p.resized(1392)
    check("standard widths", p.sidebar == 280 && p.width(L) == 319 && p.width(PaneID.now) == 360 && !p.rail && p.showsNow, "\(p.sidebar)")
    // Dragging follows the pointer exactly inside the range, everywhere from the rail to the maximum
    for w: CGFloat in [390, 300, 200, 120, 80] { p.drag(S, to: w); check("the sidebar follows the pointer to \(Int(w))", p.sidebar == w, "\(p.sidebar)") }
    check("mid-drag, narrow shows as the rail", p.rail, "")
    p.drag(S, to: 20); check("past the rail it stretches, less than the pointer moved", p.sidebar < Panes.rail && p.sidebar >= Panes.rail - 12, "\(p.sidebar)")
    p.drag(S, to: 520); check("past the maximum it stretches too", p.sidebar > 400 && p.sidebar <= 412, "\(p.sidebar)")
    p.dragEnd(S); check("let go past the maximum: back to the maximum", p.sidebar == 400 && !p.sidebarFolded, "\(p.sidebar)")
    p.drag(S, to: 190); p.dragEnd(S); check("let go between the rail and the minimum: opens at the minimum", p.sidebar == 220 && !p.sidebarFolded, "\(p.sidebar)")
    p.drag(S, to: 140); p.dragEnd(S); check("let go narrow: folds into the rail", p.sidebarFolded && p.sidebar == Panes.rail, "\(p.sidebar)")
    check("folding keeps your open width for later", p.saved(S) == 220, "")
    p.drag(S, to: 300); p.dragEnd(S); check("drag the rail out: opens where you let go", !p.sidebarFolded && p.sidebar == 300, "\(p.sidebar)")
    check("a width is kept for next launch", Panes().saved(S) == 300, "")
    p.resized(Panes.windowMin); check("a small window never folds or shrinks the sidebar", !p.rail && p.sidebar == 300, "\(p.sidebar)")
    check("and Right now steps aside", !p.showsNow, "")
    p.resized(1392); check("a big window shows Right now again", p.showsNow, "")
    p.drag(L, to: 100); check("a list stretches below its minimum while dragged", p.width(L) < 240 && p.width(L) >= 228, "\(p.width(L))")
    p.dragEnd(L); check("and springs back to it", p.width(L) == 240, "\(p.width(L))")
    p.reset(S); check("double-click resets: open, standard width", !p.rail && p.sidebar == 280, "\(p.sidebar)")
    check("the open sidebar is fully there at its minimum width", Panes.openOpacity(PaneID.sidebar.min) == 1 && Panes.openOpacity(400) == 1, "")
    check("the rail is fully there folded", Panes.railOpacity(Panes.rail) == 1, "")
    check("folding fades out to nothing before the rail fades in", Panes.openOpacity(165) == 0 && Panes.railOpacity(165) == 0, "")
    check("never both at once", stride(from: 40.0, through: 440.0, by: 1).allSatisfy { Panes.openOpacity(CGFloat($0)) == 0 || Panes.railOpacity(CGFloat($0)) == 0 }, "")
    p.resized(Panes.windowMin); check("at the smallest window the panel still has room", p.window - PaneID.sidebar.max >= 320, "")
}

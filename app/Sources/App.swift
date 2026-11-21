import SwiftUI

@main
struct AgentLabApp: App {
    @State private var lab = Lab()
    init() { T.registerFonts() }

    var body: some Scene {
        Window("Agent Lab", id: "main") {
            RootView()
                .environment(lab)
                .frame(minWidth: 1000, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent") { lab.sheet = .newAgent(nil) }.keyboardShortcut("n")
            }
            CommandMenu("Go") {
                Button("Search Everything…") { lab.sheet = .search }.keyboardShortcut("k")
                Divider()
                Button("Agents") { lab.nav = .agents }.keyboardShortcut("0")
                ForEach(Array(lab.team.prefix(6).enumerated()), id: \.element.id) { i, a in
                    Button(a.name) { lab.open(a) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("Memory") { lab.nav = .memory }
                Button("Connections") { lab.nav = .connections }
            }
            CommandGroup(after: .sidebar) {
                Button(lab.showRightNow ? "Hide Right Now" : "Show Right Now") { lab.showRightNow.toggle() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
    }
}

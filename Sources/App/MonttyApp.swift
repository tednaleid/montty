import AppKit
import SwiftUI

@main
struct MonttyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindow(tabStore: appDelegate.tabStore)
                .environmentObject(appDelegate.ghostty)
                .environmentObject(appDelegate)
        }
        .commands {
            CommandMenu("Navigate") {
                Button("Jump to Surface") {
                    appDelegate.enterJumpMode()
                }
                .keyboardShortcut(";", modifiers: .command)

                Divider()

                Button("Toggle Sidebar") {
                    appDelegate.sidebarVisible.toggle()
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Toggle("Surface Tint", isOn: Binding(
                    get: { appDelegate.surfaceTintEnabled },
                    set: { appDelegate.surfaceTintEnabled = $0 }
                ))
            }

            CommandGroup(replacing: .appSettings) {
                Button("Open Ghostty Config...") {
                    openGhosttyConfig()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func openGhosttyConfig() {
        let configPath = NSString("~/.config/ghostty/config")
            .expandingTildeInPath
        let url = URL(fileURLWithPath: configPath)

        // Create the file with a comment header if it doesn't exist
        let mgr = FileManager.default
        if !mgr.fileExists(atPath: configPath) {
            let dir = (configPath as NSString).deletingLastPathComponent
            try? mgr.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            mgr.createFile(
                atPath: configPath, contents: Data(
                    "# Ghostty configuration\n# See https://ghostty.org/docs/config\n\n".utf8
                ))
        }

        NSWorkspace.shared.open(url)
    }
}

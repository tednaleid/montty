// ABOUTME: One window's model state, holding the tabs it owns and the chrome
// ABOUTME: settings that belong to it rather than to the application.

import Foundation

@Observable
final class WindowModel: Identifiable {
    let id: UUID
    let tabStore: TabStore
    /// Each window carries its own sidebar, so its width belongs here.
    var sidebarWidth: Double
    var frame: WindowFrame

    init(
        id: UUID = UUID(),
        tabStore: TabStore = TabStore(),
        sidebarWidth: Double = 200,
        frame: WindowFrame = WindowFrame(x: 0, y: 0, width: 0, height: 0)
    ) {
        self.id = id
        self.tabStore = tabStore
        self.sidebarWidth = sidebarWidth
        self.frame = frame
    }
}
